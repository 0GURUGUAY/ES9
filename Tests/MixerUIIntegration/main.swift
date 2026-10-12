import AppKit
import AudioToolbox
import CoreMIDI
import SwiftUI
import MixerCore
import GateState

final class ButtonProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MixerUITestButtonProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> ButtonProbeView {
        let view = ButtonProbeView()
        view.setAccessibilityIdentifier(identifier)
        return view
    }

    func updateNSView(_ view: ButtonProbeView, context: Context) {}
}

@MainActor
func runTests() throws {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ES9Mixer-UI-\(UUID().uuidString)")
    defer {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            fputs("FAIL UI test cleanup: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    let store = MixerStore(sessionURL: directory.appendingPathComponent("session.json"))
    store.esInput = 0
    store.esOutput = 0
    store.session = Session()
    let first = LiveSubscene(name: "First", inputs: Array(
        repeating: LiveInputCue(level: 0.4, transitionSeconds: 0), count: 14))
    let second = LiveSubscene(name: "Second", inputs: Array(
        repeating: LiveInputCue(level: 0.8, transitionSeconds: 0), count: 14))
    let third = LiveSubscene(name: "Fade", inputs: Array(
        repeating: LiveInputCue(level: 0.1, transitionSeconds: 2), count: 14))
    let scene = LiveScene(name: "UI test", subscenes: [first, second, third])
    store.session.liveScenes = [scene]
    store.selectLiveScene(scene.id)
    store.displayMode = .live
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 1000, height: 590),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: ContentView().environmentObject(store))
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }

    func settle(_ seconds: TimeInterval = 0.1) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        hosting.layoutSubtreeIfNeeded()
    }

    func finishTransition() throws {
        let deadline = Date().addingTimeInterval(3)
        while store.sceneTransitioning && Date() < deadline { settle(0.05) }
        try require(!store.sceneTransitioning, "Scene transition did not finish before the deadline")
    }

    func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for child in view.subviews {
            if let found = find(identifier, in: child) { return found }
        }
        return nil
    }

    func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "MixerUIIntegration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func click(_ identifier: String) throws {
        settle()
        guard let button = find(identifier, in: hosting) else {
            throw NSError(domain: "MixerUIIntegration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Button not found: \(identifier)"])
        }
        let frame = button.convert(button.bounds, to: nil)
        try require(frame.width > 0 && frame.height > 0, "Empty button frame: \(identifier)")
        let visibleFrame = hosting.convert(frame, from: nil)
        try require(hosting.bounds.contains(visibleFrame), "Button outside the window: \(identifier)")
        let point = NSPoint(x: frame.midX, y: frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ) else { fatalError("Could not create mouse event") }
            window.sendEvent(event)
        }
        settle()
    }

    func moveFader(_ identifier: String, to position: Double) throws {
        settle()
        guard let view = find(identifier, in: hosting) else {
            throw NSError(domain: "MixerUIIntegration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Fader not found: \(identifier)"])
        }
        let frame = view.convert(view.bounds, to: nil)
        try require(hosting.bounds.contains(hosting.convert(frame, from: nil)),
                    "Fader outside the window: \(identifier)")
        let start = NSPoint(x: frame.midX, y: frame.midY)
        let end = NSPoint(x: frame.minX + 8 + (frame.width - 16) * position, y: frame.midY)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start),
                              (.leftMouseDragged, end), (.leftMouseUp, end)] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
            ) else { fatalError("Could not create fader mouse event") }
            window.sendEvent(event)
        }
        settle()
    }

    for size in [NSSize(width: 1000, height: 590), NSSize(width: 1400, height: 1050)] {
        window.setContentSize(size)
        store.selectLiveScene(scene.id)
        settle()
        try require(!store.liveSceneActive, "Loading must not start playback")
        let initialPlan = try RoutingPlan(store.session)
        try moveFader("live-input-0-level", to: 0.9)
        try require(store.session.channels[0].level != 0.4, "Scene fader did not change the mix before GO")
        try require(store.session.channels[0].level == store.session.liveScenes[0].subscenes[0].inputs[0].level,
                    "Scene fader must update both the audible level and the programmed target")
        try require(try RoutingPlan(store.session) != initialPlan, "Scene fader did not change audio coefficients")
        try click("live-input-0-solo")
        try require(store.session.channels[0].soloed && !store.session.inputIsAudible(1),
                    "SOLO button did not isolate the input before GO")
        try click("live-input-0-mute")
        try require(!store.session.inputIsAudible(0), "MUTE must take priority over SOLO")
        try click("live-input-0-mute")
        try click("live-input-0-solo")
        store.setLiveInputLevel(0.4, sceneID: scene.id, subsceneID: first.id, input: 0)
        try click("live-mute-all")
        try require(store.session.muteAll, "MUTE GÉNÉRAL button did not mute")
        try click("live-go")
        try require(!store.session.muteAll, "GO from stopped state did not release MUTE GÉNÉRAL")
        try require(store.liveSubsceneID == first.id, "Mouse click on GO did not start the first cue at \(size)")
        try require(store.session.channels.allSatisfy { $0.level == 0.4 }, "GO did not apply target levels")
        try click("live-mute-all")
        try require(store.session.muteAll, "MUTE GÉNÉRAL button did not mute during the set")
        try click("live-next")
        try require(store.session.muteAll, "NEXT must respect MUTE GÉNÉRAL during the set")
        try require(store.liveSubsceneID == second.id, "Mouse click on NEXT did not advance at \(size)")
        try click("live-mute-all")
        try require(!store.session.muteAll, "MUTE GÉNÉRAL button did not unmute")
        try require(store.session.channels.allSatisfy { $0.level == 0.8 }, "NEXT did not apply target levels")
        try click("live-next")
        try require(store.sceneTransitioning, "Transition did not start")
        try click("live-stop")
        let stopped = store.session.channels
        try require(!store.liveSceneActive && !store.sceneTransitioning, "ARRÊT did not stop playback")
        try require(store.selectedLiveSceneID == scene.id && store.selectedLiveSubsceneID == first.id,
                    "ARRÊT must select the first scene and its first cue")
        settle(0.5)
        try require(store.session.channels == stopped, "Levels changed after ARRÊT")
        print("PASS Scene mouse clicks: GO, NEXT, transition and ARRÊT at \(size)")
    }

    let laterScene = LiveScene(name: "Later scene", subscenes: [second, third])
    store.session.liveScenes = [scene, laterScene]
    store.selectLiveScene(laterScene.id)
    store.selectLiveSubscene(third.id)
    store.goLive()
    settle(0.1)
    try click("live-stop")
    let stoppedMix = store.session.channels
    try require(store.selectedLiveSceneID == scene.id && store.selectedLiveSubsceneID == first.id,
                "STOP from a later scene must return to the start of the set")
    try require(!store.liveSceneActive && !store.sceneTransitioning && !store.clockGateHigh,
                "Returning to the first scene must not restart playback or GATE")
    settle(0.3)
    try require(store.session.channels == stoppedMix, "Returning to the first scene must preserve the mix")
    try click("live-go")
    try require(store.liveSceneID == scene.id && store.liveSubsceneID == first.id,
                "GO after STOP must start the first scene and its first cue")
    store.stopLive()
    try require(store.session.channels.allSatisfy { $0.level == 0.4 },
                "GO must apply the first cue")
    store.nextLiveSubscene()
    try require(store.liveSceneID == scene.id && store.liveSubsceneID == first.id,
                "NEXT after STOP must also start the first cue")
    store.stopLive()
    print("PASS STOP returns to the first scene/cue without changing the mix; GO/NEXT restart at the beginning")

    let manualCue = LiveSubscene(name: "Manual control", inputs: Array(
        repeating: LiveInputCue(level: 0.8, transitionSeconds: 0.6), count: 14))
    let manualScene = LiveScene(name: "Manual test", subscenes: [manualCue])
    store.session.liveScenes = [manualScene]
    store.selectLiveScene(manualScene.id)
    store.goLive()
    settle(0.1)
    store.setLiveInputLevel(0.25, sceneID: manualScene.id, subsceneID: manualCue.id, input: 0)
    store.changeChannel(1) { $0.muted = true }
    store.changeChannel(2) { $0.soloed = true }
    store.changeChannel(3) { $0.soloed = true }
    try require(store.session.inputIsAudible(2) && store.session.inputIsAudible(3),
                "Input SOLO must be cumulative during playback")
    try finishTransition()
    try require(store.session.channels[0].level == 0.25 && store.liveTargetLevel(for: 0) == 0.25,
                "Fade overwrote a manual level or its displayed target")
    try require(store.session.channels[1].muted, "Fade overwrote manual MUTE")
    try require(store.session.channels[2].level == 0.8 && store.session.channels[3].level == 0.8,
                "SOLO must not interrupt other transitions")
    store.changeChannel(0) { $0.muted = true }
    store.setLiveInputLevel(0.6, sceneID: manualScene.id, subsceneID: manualCue.id, input: 0)
    try require(store.session.channels[0].muted && store.session.channels[0].level == 0.6,
                "Moving a muted fader must not unmute it")
    let beforeInvalidLevel = store.session
    store.setLiveInputLevel(1.5, sceneID: manualScene.id, subsceneID: manualCue.id, input: 0)
    try require(store.error != nil && store.session == beforeInvalidLevel,
                "Invalid manual level must be reported without changing the session")
    store.error = nil
    store.goLive()
    try finishTransition()
    try require(store.session.channels[0].level == 0.6 && !store.session.channels[0].muted,
                "GO must recall the edited target and programmed activation: level=\(store.session.channels[0].level), muted=\(store.session.channels[0].muted), transitioning=\(store.sceneTransitioning), cue=\(store.session.liveScenes[0].subscenes[0].inputs[0])")
    try require(store.session.channels.allSatisfy { !$0.soloed }, "GO must clear live solos")
    store.stopLive()
    store.updateLiveInput(sceneID: manualScene.id, subsceneID: manualCue.id, input: 0) { $0.enabled = false }
    try moveFader("live-input-0-level", to: 0.3)
    try require(store.session.channels[0].level != 0.6,
                "Fader must remain usable for an input disabled in the cue")
    print("PASS Scene live controls: real fader, cumulative SOLO, MUTE priority, manual fade overrides and GO recall")

    // Verify MUTE GÉNÉRAL replication across views (Console, Strip, Matrix)
    store.displayMode = .live
    settle()
    try click("live-mute-all")
    try require(store.session.muteAll, "MUTE GÉNÉRAL from scenes must activate muteAll")

    store.displayMode = .console
    settle()
    try require(find("workspace-mute-all", in: hosting) != nil, "MUTE GÉNÉRAL button must be present in Console view header")
    try click("workspace-mute-all")
    try require(!store.session.muteAll, "Clicking MUTE GÉNÉRAL from Console view must release muteAll")
    try click("workspace-mute-all")
    try require(store.session.muteAll, "Clicking MUTE GÉNÉRAL from Console view must re-engage muteAll")

    store.displayMode = .strip
    settle()
    try require(find("workspace-mute-all", in: hosting) != nil, "MUTE GÉNÉRAL button must be present in Strip view header")
    try click("workspace-mute-all")
    try require(!store.session.muteAll, "Clicking MUTE GÉNÉRAL from Strip view must release muteAll")

    store.displayMode = .matrix
    settle()
    try require(find("workspace-mute-all", in: hosting) != nil, "MUTE GÉNÉRAL button must be present in Matrix view header")
    try click("workspace-mute-all")
    try require(store.session.muteAll, "Clicking MUTE GÉNÉRAL from Matrix view must re-engage muteAll")
    try click("workspace-mute-all")
    try require(!store.session.muteAll, "Clicking MUTE GÉNÉRAL from Matrix view must release muteAll")

    store.displayMode = .live
    settle()
    print("PASS MUTE GÉNÉRAL replication across views: header button in Console, Strip, Matrix")

    store.session.liveScenes = [scene]
    store.selectLiveScene(scene.id)
    store.addLiveSubscene(to: scene.id)
    if let added = store.session.liveScenes.first?.subscenes.last, let previous = store.session.liveScenes.first?.subscenes.dropLast().last {
        try require(added.id != previous.id && added.inputs.map(\.level) == previous.inputs.map(\.level)
                    && added.inputs.allSatisfy { $0.transitionSeconds == 0 },
                    "New subscene must copy previous levels with no transitions")
        print("PASS New subscene copies previous levels without transitions")
    }

    let bitboxTarget = (60 - 9.2) / 60
    var introInputs = Array(repeating: LiveInputCue(level: 0.3, transitionSeconds: 0), count: 14)
    introInputs[0] = LiveInputCue(level: bitboxTarget, transitionSeconds: 6)
    introInputs[2] = LiveInputCue(enabled: false, level: 0.7, transitionSeconds: 0)
    let intro = LiveSubscene(name: "Intro", inputs: introInputs)
    let bitboxScene = LiveScene(name: "BITBOX test", subscenes: [intro])
    store.session.liveScenes = [bitboxScene]
    store.session.channels[0].name = "BITBOX"
    store.session.channels[0].level = bitboxTarget
    store.session.channels[0].muted = false
    store.selectLiveScene(bitboxScene.id)
    store.goLive()
    try require(store.session.channels[0].level == 0, "BITBOX must start at silence despite its current level")
    try require(store.liveTargetLevel(for: 0) == bitboxTarget, "BITBOX fader must display the target")
    try require(store.session.channels[1].level == 0.3, "Zero-duration input must apply immediately")
    try require(store.session.channels[2].muted, "Zero-duration mute must apply immediately")
    settle(1)
    try require(store.session.channels[0].level > 0 && store.session.channels[0].level < bitboxTarget,
                "BITBOX must rise gradually during the six-second transition")
    store.goLive()
    try require(store.session.channels[0].level == 0, "Repeated GO must restart BITBOX at silence")
    settle(6.2)
    try require(!store.sceneTransitioning, "BITBOX transition must finish after six seconds")
    try require(store.session.channels[0].level == bitboxTarget, "BITBOX must reach -9.2 dB")
    try require(store.session.channels[2].level == 0.7 && store.session.channels[2].muted,
                "Immediate muted input must retain its stored level")
    store.stopLive()
    store.goLive()
    try require(store.session.channels[0].level == 0, "ARRÊT then GO must reset BITBOX to silence")
    try require(store.session.channels[1].level == 0.3, "ARRÊT then GO must reapply immediate targets")
    try require(store.session.channels[0].level == 0,
                "Volumes must be initialized to silence before or when GATE is raised")
    store.stopLive()
    print("PASS BITBOX: silence to -9.2 dB in six seconds, repeated GO and mixed zero-duration inputs")

    var midiClient: MIDIClientRef = 0
    var midiSource: MIDIEndpointRef = 0
    var midiDestination: MIDIEndpointRef = 0
    try require(MIDIClientCreateWithBlock("Scene control test" as CFString, &midiClient, { _ in }) == noErr,
                "Could not create the scene MIDI test client")
    defer { MIDIClientDispose(midiClient) }
    try require(MIDISourceCreate(midiClient, "Scene test source" as CFString, &midiSource) == noErr,
                "Could not create the scene MIDI test source")
    defer { MIDIEndpointDispose(midiSource) }
    try require(MIDIDestinationCreateWithBlock(
        midiClient, "Scene test destination" as CFString, &midiDestination
    ) { list, _ in
        if MIDIReceived(midiSource, list) != noErr {
            fputs("FAIL Scene test MIDI loopback\n", stderr)
            exit(1)
        }
    } == noErr, "Could not create the scene MIDI test destination")
    defer {
        store.suspend()
        MIDIEndpointDispose(midiDestination)
    }
    let midiReceiver = try MIDITransport()
    var receivedMessages: [[UInt8]] = []
    var midiParser = MIDIParser()
    midiReceiver.onBytes = { _, bytes in
        receivedMessages += midiParser.feed(bytes).filter {
            $0.starts(with: ES9.header) && $0 != ES9.dspUsageRequest
        }
    }
    try midiReceiver.subscribe(to: [MIDIEndpoint(id: midiSource, name: "Scene test")])
    settle()
    store.esInput = midiSource
    store.esOutput = midiDestination
    store.controllerInput = midiSource
    store.controllerOutput = 0
    store.refresh()
    store.controllerOutput = 0
    store.session = Session()
    let midiCue = LiveSubscene(name: "MIDI", inputs: Array(
        repeating: LiveInputCue(level: 0.7, transitionSeconds: 0), count: 14))
    let midiScene = LiveScene(name: "MIDI", subscenes: [midiCue])
    store.session.liveScenes = [midiScene]
    store.session.mappings = [
        ControlMapping(action: "fader0", status: 0xB0, number: 13),
        ControlMapping(action: "mute0", status: 0xB0, number: 14),
        ControlMapping(action: "solo0", status: 0xB0, number: 15)
    ]
    store.selectLiveScene(midiScene.id)
    store.goLive()
    store.active = true
    store.setLiveInputLevel(0.45, sceneID: midiScene.id, subsceneID: midiCue.id, input: 0)

    func requireMIDIMessages(_ expected: [[UInt8]]) throws {
        let deadline = Date().addingTimeInterval(3)
        while receivedMessages.count < expected.count && Date() < deadline { settle(0.05) }
        try require(receivedMessages == expected,
                    "Live MIDI mismatch: received \(receivedMessages.count)/\(expected.count), error \(store.error ?? "none"), status \(store.status)")
        receivedMessages.removeAll()
    }

    var sentPlan = try RoutingPlan(store.session)
    try requireMIDIMessages(sentPlan.messages(from: nil))
    try click("live-input-0-mute")
    var nextPlan = try RoutingPlan(store.session)
    try requireMIDIMessages(nextPlan.messages(from: sentPlan))
    sentPlan = nextPlan
    try click("live-input-0-mute")
    nextPlan = try RoutingPlan(store.session)
    try requireMIDIMessages(nextPlan.messages(from: sentPlan))
    sentPlan = nextPlan
    try click("live-input-0-solo")
    nextPlan = try RoutingPlan(store.session)
    try requireMIDIMessages(nextPlan.messages(from: sentPlan))
    try click("live-input-0-solo")
    settle(0.5)
    receivedMessages.removeAll()
    store.changeBank(.inputs1)
    let pickupValue = UInt8((ControllerFader.position(for: store.session.channels[0].level) * 127).rounded())
    try midiReceiver.send([0xB0, 13, pickupValue], to: midiDestination)
    settle(0.3)
    try midiReceiver.send([0xB0, 13, 100], to: midiDestination)
    settle(0.3)
    try require(store.session.channels[0].level == ControllerFader.level(at: 100.0 / 127),
                "MIDI fader must keep pickup acquired and change the live input")
    try require(store.liveTargetLevel(for: 0) == store.session.channels[0].level,
                "MIDI live fader must update the displayed target")
    try midiReceiver.send([0xB0, 14, 127, 0xB0, 14, 0, 0xB0, 15, 127], to: midiDestination)
    settle(0.3)
    try require(store.session.channels[0].muted && store.session.channels[0].soloed,
                "MIDI MUTE/SOLO must remain usable during a scene")
    try require(store.error == nil, "Virtual MIDI scene controls reported an error")
    store.suspend()
    print("PASS Scene real-time MIDI: exact fader/MUTE/SOLO coefficients and controller pickup during playback")

    store.stopLive()
    let timedCue = LiveSubscene(name: "Timed", inputs: Array(repeating: LiveInputCue(), count: 14))
    let followingCue = LiveSubscene(name: "Following", durationSeconds: 2,
                                    inputs: Array(repeating: LiveInputCue(), count: 14))
    let timedScene = LiveScene(name: "Timer test", subscenes: [timedCue, followingCue])
    store.session = Session()
    store.session.liveScenes = [timedScene]
    store.selectLiveScene(timedScene.id)
    store.setLiveSubsceneDuration("00:01", sceneID: timedScene.id, subsceneID: timedCue.id)
    try require(store.session.liveScenes[0].subscenes[0].durationSeconds == 1,
                "MM:SS duration was not saved as seconds")
    store.goLive()
    let timerDeadline = Date().addingTimeInterval(3)
    while store.liveSubsceneID == timedCue.id && Date() < timerDeadline { settle(0.05) }
    try require(store.liveSubsceneID == followingCue.id,
                "Subscene timer did not automatically advance to the following cue")
    store.stopLive()
    settle(1.1)
    try require(!store.liveSceneActive && store.liveTimerRemainingSeconds == nil,
                "STOP did not cancel the active subscene timer")
    print("PASS Subscene timer: MM:SS duration advances automatically and STOP cancels the timer")

    let buffers = AudioBufferList.allocate(maximumBuffers: 16)
    buffers.unsafeMutablePointer.pointee.mNumberBuffers = 16
    defer {
        for buffer in buffers { buffer.mData?.deallocate() }
        buffers.unsafeMutablePointer.deallocate()
    }
    for channel in 0..<16 {
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        samples.initialize(repeating: -1, count: 64)
        buffers[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 256, mData: samples)
    }
    guard let state = ES9GateStateCreate() else {
        throw ClockGateError.operation("allocation du test", kAudio_MemFullError)
    }
    defer { ES9GateStateDestroy(state) }
    var flags = AudioUnitRenderActionFlags()
    var timestamp = AudioTimeStamp()
    ES9GateStateSet(state, true)
    let highStatus = ClockGate.render(UnsafeMutableRawPointer(state), &flags, &timestamp,
                                     0, 64, buffers.unsafeMutablePointer)
    try require(highStatus == noErr, "GATE callback failed")
    for channel in 0..<16 {
        let samples = buffers[channel].mData!.assumingMemoryBound(to: Float.self)
        for sample in 0..<64 {
            try require(samples[sample] == (channel == 15 ? 0.5 : 0),
                        "GATE must generate constant high on USB 16 only")
        }
    }
    ES9GateStateSet(state, false)
    let lowStatus = ClockGate.render(UnsafeMutableRawPointer(state), &flags, &timestamp,
                                    0, 64, buffers.unsafeMutablePointer)
    try require(lowStatus == noErr && ES9GateStateLowRendered(state), "GATE low must be acknowledged")
    for buffer in buffers {
        let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
        for sample in 0..<64 { try require(samples[sample] == 0, "ARRÊT must render zero on USB 16") }
    }
    print("PASS Pamela gate renderer: USB 16 high on GO and zero on ARRÊT, other channels silent")
}

do {
    try MainActor.assumeIsolated { try runTests() }
} catch {
    fputs("FAIL \(error.localizedDescription)\n", stderr)
    exit(1)
}

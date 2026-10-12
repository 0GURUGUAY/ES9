import Foundation
import MixerCore

private extension Channel {
    mutating func routeExclusively(to destination: Int) {
        mainEnabled = destination == 0
        jackSends = (1...8).map { JackSend(enabled: $0 == destination) }
    }
}

final class MixerCoreTests {
    func testMasterMuteIsIndependent() throws {
        var session = Session()
        session.headphonesEnabled = true
        for index in session.channels.indices {
            session.channels[index].jackSends[index < 7 ? 0 : 1].enabled = true
        }
        session.channels[0].muted = true
        session.channels[1].soloed = true
        session.channels[8].soloed = true
        let previous = session
        let audible = try RoutingPlan(session)
        session.masterMuted = true
        let muted = try RoutingPlan(session)
        XCTAssertEqual(muted.inputs, audible.inputs)
        XCTAssertEqual(muted.outputs, audible.outputs)
        for block in 0..<2 {
            for row in 0..<8 {
                let index = block * 8 + row
                if [UInt8(6), 7].contains(muted.outputs[block][row]) {
                    XCTAssertTrue(muted.coefficients[index].allSatisfy { $0 == 0 })
                    XCTAssertTrue(audible.coefficients[index].contains { $0 > 0 })
                } else {
                    XCTAssertEqual(muted.coefficients[index], audible.coefficients[index])
                }
            }
        }
        for input in session.channels.indices {
            XCTAssertEqual(session.inputIsAudible(input), previous.inputIsAudible(input))
        }
        XCTAssertEqual(session.master, previous.master)
        XCTAssertEqual(session.channels, previous.channels)
        XCTAssertEqual(session.outputs, previous.outputs)
        XCTAssertTrue(muted.messages(from: audible).allSatisfy { (0x60...0x6F).contains($0[5]) })
        let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored, session)
        XCTAssertEqual(try RoutingPlan(restored), muted)
        session.muteAll = true
        XCTAssertTrue(try RoutingPlan(session).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        session.masterMuted = false
        XCTAssertTrue(try RoutingPlan(session).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        session.muteAll = false
        XCTAssertEqual(session, previous)
        XCTAssertEqual(try RoutingPlan(session), audible)
        guard var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any] else {
            throw MixerError.invalidSession
        }
        legacy.removeValue(forKey: "masterMuted")
        let migrated = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(migrated.masterMuted)
        XCTAssertEqual(try RoutingPlan(migrated), audible)
    }

    func testMuteAllPreservesIndividualStateAndRouting() throws {
        var session = Session()
        session.headphonesEnabled = true
        for index in session.channels.indices {
            session.channels[index].jackSends[index < 7 ? 0 : 1].enabled = true
        }
        session.channels[0].muted = true
        session.channels[1].soloed = true
        session.channels[8].soloed = true
        session.outputs[1].muted = true
        let previous = session
        let audible = try RoutingPlan(session)
        XCTAssertTrue(audible.coefficients.flatMap { $0 }.contains { $0 > 0 })
        session.muteAll = true
        let muted = try RoutingPlan(session)
        XCTAssertEqual(muted.inputs, audible.inputs)
        XCTAssertEqual(muted.outputs, audible.outputs)
        XCTAssertTrue(muted.coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        XCTAssertTrue(session.channels.indices.allSatisfy { !session.inputIsAudible($0) })
        XCTAssertEqual(session.channels, previous.channels)
        XCTAssertEqual(session.outputs, previous.outputs)
        XCTAssertTrue(muted.messages(from: audible).allSatisfy {
            (0x60...0x6F).contains($0[5]) && Array($0.suffix(4)) == [0, 0, 0, 0xF7]
        })
        let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored, session)
        XCTAssertTrue(try RoutingPlan(restored).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        session.muteAll = false
        XCTAssertEqual(session, previous)
        XCTAssertEqual(try RoutingPlan(session), audible)
        session.muteAll = true
        session.channels[2].muted = true
        session.channels[2].soloed = true
        XCTAssertFalse(session.inputIsAudible(2))
        session.muteAll = false
        XCTAssertFalse(session.inputIsAudible(2))
        XCTAssertTrue(session.channels[2].soloed)

        guard var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any] else {
            throw MixerError.invalidSession
        }
        legacy.removeValue(forKey: "muteAll")
        let migrated = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(migrated.muteAll)
        XCTAssertEqual(try RoutingPlan(migrated), audible)
    }

    func testLiveSceneValidationAndPersistence() throws {
        var session = Session()
        let inputCues = (0..<14).map { LiveInputCue(enabled: $0 < 3, level: Double($0) / 14, transitionSeconds: Double($0)) }
        let first = LiveSubscene(name: "Intro", durationSeconds: 90, inputs: inputCues)
        let second = LiveSubscene(name: "Tension", durationSeconds: 45, inputs: inputCues)
        session.liveScenes = [LiveScene(name: "Set", subscenes: [first, second])]
        try session.validate()
        XCTAssertEqual(session.liveScenes[0].totalDurationSeconds, 135)

        let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored, session)
        XCTAssertEqual(restored.liveScenes[0].subscenes[0].inputs, inputCues)
        XCTAssertEqual(restored.liveScenes[0].subscenes[0].durationSeconds, 90)

        guard var legacySubscene = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(first)) as? [String: Any] else {
            throw MixerError.invalidSession
        }
        legacySubscene.removeValue(forKey: "durationSeconds")
        let restoredLegacySubscene = try JSONDecoder().decode(
            LiveSubscene.self, from: JSONSerialization.data(withJSONObject: legacySubscene))
        XCTAssertEqual(restoredLegacySubscene.durationSeconds, 0)

        guard var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Session())) as? [String: Any] else {
            throw MixerError.invalidSession
        }
        legacy.removeValue(forKey: "liveScenes")
        let migrated = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(migrated.liveScenes.isEmpty)

        for duration in [0.0, 30.0] {
            var boundary = session
            boundary.liveScenes[0].subscenes[0].inputs[0].transitionSeconds = duration
            try boundary.validate()
            XCTAssertEqual(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(boundary)), boundary)
        }
        for duration in [30.1, 600.0] {
            var oldSession = session
            oldSession.liveScenes[0].subscenes[0].inputs[0].transitionSeconds = duration
            let migrated = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(oldSession))
            XCTAssertEqual(migrated.liveScenes[0].subscenes[0].inputs[0].transitionSeconds, 30)
            try migrated.validate()
        }
        for invalidDuration in [-0.1, 30.1, 600.1, .nan, .infinity] {
            var invalid = session
            invalid.liveScenes[0].subscenes[0].inputs[0].transitionSeconds = invalidDuration
            XCTAssertThrowsError(try invalid.validate())
        }
        for invalidLevel in [-0.1, 1.1, .nan] {
            var invalid = session
            invalid.liveScenes[0].subscenes[0].inputs[0].level = invalidLevel
            XCTAssertThrowsError(try invalid.validate())
        }
        var invalid = session
        invalid.liveScenes[0].subscenes[0].inputs.removeLast()
        XCTAssertThrowsError(try invalid.validate())
        invalid = session
        invalid.liveScenes[0].subscenes[0].name = "  "
        XCTAssertThrowsError(try invalid.validate())
        invalid = session
        invalid.liveScenes[0].subscenes[0].durationSeconds = -1
        XCTAssertThrowsError(try invalid.validate())
        invalid = session
        invalid.liveScenes[0].subscenes.append(first)
        XCTAssertThrowsError(try invalid.validate())
    }

    func testLiveRoutingRecallAndMigration() throws {
        var session = Session()
        session.channels[0].jackSends[4] = JackSend(enabled: true, level: 0.6)
        let original = session
        var cues = session.channels.map {
            LiveInputCue(enabled: !$0.muted, level: $0.level,
                         jackSends: Array($0.jackSends.prefix(4)))
        }
        cues[0].jackSends = [JackSend(enabled: true, level: 0.8),
                            JackSend(enabled: false, level: 0.2), JackSend(), JackSend()]
        let cue = LiveSubscene(name: "Intro", inputs: cues)
        let recalled = try session.applyingLiveRouting(cue)
        XCTAssertTrue(recalled.routingLocked)
        XCTAssertEqual(Array(recalled.channels[0].jackSends.prefix(4)), cues[0].jackSends)
        XCTAssertEqual(Array(recalled.channels[0].jackSends.suffix(4)),
                       Array(original.channels[0].jackSends.suffix(4)))
        XCTAssertEqual(recalled.channels[0].level, original.channels[0].level)
        XCTAssertEqual(recalled.channels[0].mainEnabled, original.channels[0].mainEnabled)
        session.liveScenes = [LiveScene(name: "Set", subscenes: [cue])]
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)), session)

        let legacy = Data("{\"enabled\":true,\"level\":0.7,\"transitionSeconds\":3}".utf8)
        let legacyCue = try JSONDecoder().decode(LiveInputCue.self, from: legacy)
        XCTAssertEqual(legacyCue.jackSends, nil)
        XCTAssertEqual(try original.applyingLiveRouting(
            LiveSubscene(name: "Ancienne", inputs: Array(repeating: legacyCue, count: 14))), original)
        for sends in [[], [JackSend()], Array(repeating: JackSend(), count: 5),
                      [JackSend(level: .nan), JackSend(), JackSend(), JackSend()],
                      [JackSend(level: 1.1), JackSend(), JackSend(), JackSend()]] {
            var invalid = session
            invalid.liveScenes[0].subscenes[0].inputs[0].jackSends = sends
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertThrowsError(try original.applyingLiveRouting(invalid.liveScenes[0].subscenes[0]))
        }
        var overloaded = original
        for input in overloaded.channels.indices {
            overloaded.channels[input].mainEnabled = false
            overloaded.channels[input].jackSends = Array(repeating: JackSend(enabled: true), count: 8)
        }
        _ = try RoutingPlan(overloaded)
        // Preserving outputs 5–8 while adding four sends and the stereo main exceeds capacity.
        for input in overloaded.channels.indices { overloaded.channels[input].mainEnabled = true }
        let allSends = LiveSubscene(name: "Trop de sorties", inputs: Array(
            repeating: LiveInputCue(jackSends: Array(repeating: JackSend(enabled: true), count: 4)), count: 14))
        XCTAssertThrowsError(try overloaded.applyingLiveRouting(allSends))
    }

    func testLiveInputFadeInAndFadeOut() {
        let fadeIn = LiveInputCue(enabled: true, level: 0.8, transitionSeconds: 4)
        XCTAssertEqual(fadeIn.transitionStartLevel(currentLevel: 0.6, currentlyMuted: true), 0)
        XCTAssertEqual(fadeIn.transitionStartLevel(currentLevel: 0.6, currentlyMuted: false), 0)
        XCTAssertEqual(Channel.gain(fadeIn.transitionLevel(from: 0, after: 2)), Channel.gain(0.8) * pow(0.5, 1.6), accuracy: 0.000001)
        XCTAssertEqual(fadeIn.transitionLevel(from: 0, after: 4), 0.8, accuracy: 0.000001)

        let fadeOut = LiveInputCue(enabled: false, level: 0.65, transitionSeconds: 2)
        XCTAssertEqual(fadeOut.transitionStartLevel(currentLevel: 0.8, currentlyMuted: false), 0.8)
        XCTAssertEqual(fadeOut.transitionStartLevel(currentLevel: 0.8, currentlyMuted: true), 0)
        XCTAssertEqual(Channel.gain(fadeOut.transitionLevel(from: 0.8, after: 1)), Channel.gain(0.8) * pow(0.5, 1.6), accuracy: 0.000001)
        XCTAssertEqual(fadeOut.transitionLevel(from: 0.8, after: 2), 0, accuracy: 0.000001)
        XCTAssertEqual(fadeOut.transitionLevel(from: 0.8, after: 3), 0, accuracy: 0.000001)
        XCTAssertEqual(LiveInputCue(enabled: true, level: 0.3, transitionSeconds: 0)
            .transitionLevel(from: 0, after: 0), 0.3, accuracy: 0.000001)
        let immediate = LiveInputCue(enabled: true, level: 0.3, transitionSeconds: 0)
        XCTAssertEqual(immediate.transitionStartLevel(currentLevel: 0.9, currentlyMuted: false), 0.3)
        XCTAssertEqual(immediate.transitionStartLevel(currentLevel: 0.9, currentlyMuted: true), 0.3)

        let bitbox = LiveInputCue(level: (60 - 9.2) / 60, transitionSeconds: 6)
        let start = bitbox.transitionStartLevel(currentLevel: bitbox.level, currentlyMuted: false)
        XCTAssertEqual(start, 0)
        XCTAssertEqual(Channel.gain(start), 0)
        XCTAssertEqual(bitbox.transitionLevel(from: start, after: 0), 0)
        XCTAssertEqual(Channel.gain(bitbox.transitionLevel(from: start, after: 3)), Channel.gain(bitbox.level) * pow(0.5, 1.6),
                       accuracy: 0.000001)
        XCTAssertTrue(bitbox.transitionLevel(from: start, after: 0.3) > 0.1)
        XCTAssertEqual(bitbox.transitionLevel(from: start, after: 6), bitbox.level, accuracy: 0.000001)
        XCTAssertEqual(Channel.decibels(bitbox.transitionLevel(from: start, after: 6)), "-9.2 dB")
        XCTAssertEqual(bitbox.transitionStartLevel(currentLevel: 1, currentlyMuted: false), 0)
    }

    func testLiveSequenceAdvancesAndHoldsAtEnd() {
        let cues = Array(repeating: LiveInputCue(), count: 14)
        let first = LiveSubscene(name: "Intro", inputs: cues)
        let second = LiveSubscene(name: "Tension", inputs: cues)
        let third = LiveSubscene(name: "Drop", inputs: cues)
        let sceneA = LiveScene(name: "A", subscenes: [first, second])
        let sceneB = LiveScene(name: "B", subscenes: [third])
        let scenes = [sceneA, sceneB]

        XCTAssertEqual(LiveSequence.next(in: [], after: nil, subsceneID: nil), .empty)
        XCTAssertEqual(LiveSequence.next(in: scenes, after: nil, subsceneID: nil),
                       .cue(sceneID: sceneA.id, subsceneID: first.id))
        XCTAssertEqual(LiveSequence.next(in: scenes, after: sceneA.id, subsceneID: first.id),
                       .cue(sceneID: sceneA.id, subsceneID: second.id))
        XCTAssertEqual(LiveSequence.next(in: scenes, after: sceneA.id, subsceneID: second.id),
                       .cue(sceneID: sceneB.id, subsceneID: third.id))
        XCTAssertEqual(LiveSequence.next(in: scenes, after: sceneB.id, subsceneID: third.id), .finished)
        XCTAssertEqual(LiveSequence.next(in: scenes, after: UUID(), subsceneID: UUID()),
                       .cue(sceneID: sceneA.id, subsceneID: first.id))
    }

    func testDSPUsageProtocol() throws {
        func response(_ counters: [Int]) -> [UInt8] {
            ES9.message(0x12, counters.flatMap { [UInt8($0 >> 7), UInt8($0 & 0x7F)] })
        }
        XCTAssertEqual(ES9.dspUsageRequest, [0xF0, 0, 0x21, 0x27, 0x19, 0x2B, 0xF7])
        let packet = response([1024, 2560, 2048, 2560])
        let usage = try DSPUsage(packet: packet)
        XCTAssertEqual(usage.first, 50, accuracy: 0.000001)
        XCTAssertEqual(usage.second, 25)
        XCTAssertEqual(try DSPUsage(packet: response([1024, 1024, 0, 0])).first, 0)
        XCTAssertEqual(try DSPUsage(packet: response([1024, 4096, 0, 0])).first, 100)
        XCTAssertEqual(try DSPUsage(packet: response([1024, 4096, 0, 0])).second, nil)
        XCTAssertTrue(try DSPUsage(packet: response([1024, 4200, 0, 0])).first > 100)
        XCTAssertThrowsError(try DSPUsage(packet: response([4096, 4096, 0, 0])))
        XCTAssertThrowsError(try DSPUsage(packet: response([1024, 1000, 0, 0])))
        XCTAssertThrowsError(try DSPUsage(packet: response([1024, 2560, 4096, 4096])))
        XCTAssertThrowsError(try DSPUsage(packet: response([1024, 2560, 2048, 2000])))
        XCTAssertThrowsError(try DSPUsage(packet: Array(packet.dropLast())))
        XCTAssertThrowsError(try DSPUsage(packet: packet + [0]))
        var invalid = packet
        invalid[5] = 0x14
        XCTAssertThrowsError(try DSPUsage(packet: invalid))
        invalid = packet
        invalid[6] = 0x80
        XCTAssertThrowsError(try DSPUsage(packet: invalid))
        invalid = packet
        invalid[1] = 1
        XCTAssertThrowsError(try DSPUsage(packet: invalid))
        var parser = MIDIParser()
        XCTAssertEqual(parser.feed(Array(packet.prefix(9))), [])
        let parsed = parser.feed(Array(packet.dropFirst(9)))
        XCTAssertEqual(parsed, [packet])
        XCTAssertEqual(try DSPUsage(packet: parsed[0]), usage)
    }

    private func coefficient(_ plan: RoutingPlan, input: Int, output: UInt8) -> Int {
        for block in 0..<2 {
            if let column = plan.inputs[block].firstIndex(of: ES9.analogInputs[input]),
               let row = plan.outputs[block].firstIndex(of: output) {
                return plan.coefficients[block * 8 + row][column]
            }
        }
        return 0
    }

    private func dump(version: Int = 3) -> [UInt8] {
        var words = Array(repeating: 0, count: 719)
        words[0] = version
        words[450] = 2
        for filter in 0..<64 {
            let offset = 462 + filter * 4
            words[offset] = 3
            words[offset + 1] = 1000
            words[offset + 2] = 707
            words[offset + 3] = 32768
        }
        return ES9.message(0x08, [0, 0] + words.flatMap(ES9.word))
    }

    func testDefaultStereoMixAndMaster() throws {
        var session = Session()
        session.master = 1
        session.channels = (0..<14).map {
            var channel = Channel(id: $0)
            channel.level = 1
            return channel
        }
        let plan = try RoutingPlan(session)
        XCTAssertEqual(plan.outputs[0], [6, 7, 31, 31, 31, 31, 31, 31])
        XCTAssertEqual(plan.outputs[1], plan.outputs[0])
        for row in [0, 1] {
            XCTAssertEqual(Array(plan.coefficients[row].prefix(7)), Array(repeating: 5793, count: 7))
            XCTAssertEqual(plan.coefficients[row][7], 0)
        }
        for row in [8, 9] {
            XCTAssertEqual(Array(plan.coefficients[row].prefix(7)), Array(repeating: 5793, count: 6) + [0])
            XCTAssertEqual(plan.coefficients[row][7], 0)
        }
        XCTAssertEqual(Channel.gain(0), 0)
        XCTAssertEqual(Channel.gain(1), 1)
        XCTAssertEqual(Channel.gain(0.7), pow(10, -18.0 / 20), accuracy: 0.000001)
    }

    func testSevenInputsCoverStereoAndSixMonoOutputs() throws {
        var session = Session()
        for index in 0..<7 { session.channels[index].routeExclusively(to: index) }
        let plan = try RoutingPlan(session)
        XCTAssertEqual(plan.outputs[0], [6, 7, 8, 9, 4, 5, 2, 3])
    }

    func testEveryPossibleDestinationSubsetFits() throws {
        // All 9^7 ordered assignments reduce to these 9-choose-at-most-7 subsets.
        for mask in 1..<256 {
            let destinations = (0...7).filter { mask & (1 << $0) != 0 }
            guard destinations.count <= 7 else { continue }
            var session = Session()
            for index in 0..<14 {
                session.channels[index].routeExclusively(to: destinations[index % destinations.count])
            }
            let plan = try RoutingPlan(session)
            XCTAssertEqual(plan.outputs.count, 2)
            XCTAssertTrue(plan.outputs.allSatisfy { $0.count == 8 })
        }
    }

    func testJackMappingAndExclusiveDestinations() throws {
        XCTAssertEqual(ES9.jackOutputs, [8, 9, 4, 5, 2, 3, 11, 10])
        for destination in 1...7 {
            var session = Session()
            session.channels[0].routeExclusively(to: destination)
            session.channels[0].level = 1
            session.master = 0
            let plan = try RoutingPlan(session)
            XCTAssertEqual(plan.outputs[0][2], ES9.jackOutputs[destination - 1])
            XCTAssertEqual(plan.coefficients[2][0], 8192)
            XCTAssertEqual(plan.coefficients[0][0], 0)
            XCTAssertEqual(plan.coefficients[1][0], 0)
        }
    }

    func testInputOneToOutputOneHardwareRoute() throws {
        var session = Session()
        session.channels[0].routeExclusively(to: 1)
        session.channels[0].level = 1
        let plan = try RoutingPlan(session)
        XCTAssertEqual(ES9.analogInputs[0], 0x78)
        XCTAssertEqual(plan.outputs[0], [6, 7, 8, 31, 31, 31, 31, 31])
        XCTAssertEqual(plan.coefficients[2][0], 8192)
        XCTAssertTrue(plan.messages(from: nil).contains(
            [0xF0, 0, 0x21, 0x27, 0x19, 0x62, 0, 0, 64, 0, 0xF7]
        ))
        session.channels[0].level = 0.33599537037037036
        let attenuated = try RoutingPlan(session)
        XCTAssertEqual(attenuated.outputs, plan.outputs)
        XCTAssertEqual(attenuated.coefficients[2][0], 83)
    }

    func testMuteAndPanExtremes() throws {
        var session = Session()
        session.master = 1
        session.channels[0].level = 1
        session.channels[0].pan = -1
        var plan = try RoutingPlan(session)
        XCTAssertEqual(plan.coefficients[0][0], 8192)
        XCTAssertEqual(plan.coefficients[1][0], 0)
        session.channels[0].pan = 1
        plan = try RoutingPlan(session)
        XCTAssertEqual(plan.coefficients[0][0], 0)
        XCTAssertEqual(plan.coefficients[1][0], 8192)
        session.channels[0].muted = true
        plan = try RoutingPlan(session)
        XCTAssertEqual(plan.coefficients[1][0], 0)
    }

    func testHeadphoneMixAndIndependentLevel() throws {
        var session = Session()
        session.headphonesEnabled = true
        session.headphonesLevel = 60.0 / 72.0
        session.master = 0
        for index in 0..<14 { session.channels[index].muted = true }
        session.channels[0].muted = false
        session.channels[0].level = 1
        var plan = try RoutingPlan(session)
        XCTAssertEqual(plan.outputs[0], [6, 7, 12, 13, 31, 31, 31, 31])
        XCTAssertEqual(plan.coefficients[0][0], 0)
        XCTAssertEqual(plan.coefficients[1][0], 0)
        XCTAssertEqual(plan.coefficients[2][0], 5793)
        XCTAssertEqual(plan.coefficients[3][0], 5793)
        let old = plan
        session.headphonesLevel = 1
        session.channels[0].pan = -1
        plan = try RoutingPlan(session)
        XCTAssertEqual(plan.coefficients[2][0], 32767)
        XCTAssertEqual(plan.coefficients[3][0], 0)
        XCTAssertTrue(plan.messages(from: old).allSatisfy { [0x62, 0x63].contains($0[5]) })
        session.channels[0].pan = 1
        plan = try RoutingPlan(session)
        XCTAssertEqual(plan.coefficients[2][0], 0)
        XCTAssertEqual(plan.coefficients[3][0], 32767)
        session.headphonesLevel = 0
        XCTAssertTrue(try RoutingPlan(session).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        session.headphonesLevel = 1
        session.channels[0].muted = true
        XCTAssertTrue(try RoutingPlan(session).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        session.channels[0].muted = false
        session.channels[0].routeExclusively(to: 1)
        plan = try RoutingPlan(session)
        XCTAssertEqual(plan.coefficients[2][0], 8192)
        XCTAssertEqual(plan.coefficients[3][0], 0)
        XCTAssertEqual(plan.coefficients[4][0], 0)
        XCTAssertEqual(Session.headphonesGain(60.0 / 72.0), 1, accuracy: 0.000001)
        XCTAssertEqual(Session.headphonesDecibels(1), "+12.0 dB")
    }

    func testHeadphoneAllocationAndRerouting() throws {
        for mask in 1..<256 {
            let destinations = (0...7).filter { mask & (1 << $0) != 0 }
            var session = Session()
            session.headphonesEnabled = true
            for index in 0..<14 {
                session.channels[index].routeExclusively(to: destinations[index % destinations.count])
                session.channels[index].level = 1
                session.channels[index].pan = -1
            }
            let plan: RoutingPlan
            do { plan = try RoutingPlan(session) }
            catch {
                print("Headphone allocation failed for destinations \(destinations)")
                throw error
            }
            XCTAssertEqual(plan.inputs.flatMap { $0 }.filter { $0 != ES9.silentSource }.sorted(),
                           ES9.analogInputs.sorted())
            for block in 0..<2 {
                XCTAssertEqual(plan.inputs[block].count, 8)
                XCTAssertEqual(plan.outputs[block].count, 8)
                for column in 0..<8 where plan.inputs[block][column] != ES9.silentSource {
                    let index = ES9.analogInputs.firstIndex(of: plan.inputs[block][column])!
                    if index == ES9.clockInputIndex {
                        for row in (block * 8)..<(block * 8 + 8) {
                            XCTAssertEqual(plan.coefficients[row][column], 0)
                        }
                        continue
                    }
                    let destination = session.channels[index].destinations[0]
                    let target: UInt8 = destination == 0 ? 6 : ES9.jackOutputs[destination - 1]
                    let row = plan.outputs[block].firstIndex(of: target)!
                    XCTAssertTrue(plan.coefficients[block * 8 + row][column] > 0)
                    if destination == 0 {
                        XCTAssertTrue(plan.outputs[block].contains(12))
                        XCTAssertTrue(plan.outputs[block].contains(13))
                    }
                }
            }
        }
        var session = Session()
        for index in 0..<7 { session.channels[index].routeExclusively(to: index) }
        let old = try RoutingPlan(session)
        session.headphonesEnabled = true
        let plan = try RoutingPlan(session)
        XCTAssertTrue(plan.inputs != old.inputs)
        let packets = plan.messages(from: old)
        XCTAssertTrue(packets.prefix(128).allSatisfy { $0[5] & 0xF0 == 0x60 && Array($0[7...9]) == [0, 0, 0] })
        XCTAssertTrue(packets.contains(ES9.message(0x42, plan.inputs[0])))
        XCTAssertTrue(packets.contains(ES9.message(0x43, plan.inputs[1])))
        XCTAssertTrue(plan.messages(from: plan).isEmpty)
        session.headphonesEnabled = false
        let disabled = try RoutingPlan(session)
        XCTAssertEqual(disabled.inputs, old.inputs)
        XCTAssertEqual(disabled.outputs, old.outputs)
    }

    func testHeadphoneSessionMigration() throws {
        var session = Session()
        session.headphonesEnabled = true
        session.headphonesLevel = 1
        let encoded = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: encoded), session)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "headphonesEnabled")
        legacy.removeValue(forKey: "headphonesLevel")
        let restored = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(restored.headphonesEnabled)
        XCTAssertEqual(restored.headphonesLevel, 42.0 / 72.0)
        session.headphonesLevel = .nan
        XCTAssertThrowsError(try session.validate())
        session.headphonesLevel = 1.1
        XCTAssertThrowsError(try session.validate())
    }

    func testDeltaOnlySendsChangedLevels() throws {
        var session = Session()
        let old = try RoutingPlan(session)
        XCTAssertTrue(old.messages(from: old).isEmpty)
        session.channels[0].level = 1
        let updated = try RoutingPlan(session)
        let packets = updated.messages(from: old)
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(packets.map { $0[5] }, [0x60, 0x61])
    }

    func testReroutingSilencesBeforeChangingOutput() throws {
        var session = Session()
        let old = try RoutingPlan(session)
        session.channels[0].routeExclusively(to: 7)
        let packets = try RoutingPlan(session).messages(from: old)
        XCTAssertEqual(packets.count, 129)
        XCTAssertEqual(packets[64][5], 0x52)
        for packet in packets.prefix(64) { XCTAssertEqual(Array(packet[7...9]), [0, 0, 0]) }
    }

    func testProtocolValuesAndSetup() throws {
        XCTAssertEqual(ES9.mix(15, 7, 8192), [0xF0, 0, 0x21, 0x27, 0x19, 0x6F, 7, 0, 64, 0, 0xF7])
        let packets = try ES9.setup(dump())
        XCTAssertTrue(packets.contains(ES9.message(0x32, [3])))
        XCTAssertTrue(packets.contains(ES9.message(0x42, Array(ES9.analogInputs.prefix(7)) + [0x6E])))
        XCTAssertTrue(packets.contains(ES9.message(0x43, Array(ES9.analogInputs.suffix(7)) + [0x6E])))
        // EQ filters are owned by the routing plan, which writes all 64 of them at activation.
        XCTAssertEqual(packets.filter { $0[5] == 0x39 }.count, 0)
        let initial = try RoutingPlan(Session()).messages(from: nil).filter { $0[5] == 0x39 }
        XCTAssertEqual(initial.count, 64)
        XCTAssertTrue(initial.allSatisfy { $0[8] & 1 == 0 })
        XCTAssertEqual(Set(initial.map { [$0[6], $0[7]] }).count, 64)
        XCTAssertTrue(initial.allSatisfy { $0[6] < 16 && $0[7] < 4 })
        XCTAssertEqual(packets.filter { $0[5] == 0x3A }.count, 16)
        for row in 0..<16 {
            XCTAssertTrue(packets.contains(ES9.message(0x3A, [UInt8(row), 1])))
            XCTAssertFalse(packets.contains(ES9.message(0x3A, [UInt8(row), 0])))
        }
        XCTAssertTrue(packets.allSatisfy { $0.dropFirst().dropLast().allSatisfy { $0 < 128 } })
    }

    func testUSBPlaybackDirectRouting() throws {
        let expected: [UInt8] = [6, 7, 12, 13, 31, 31, 31, 31, 8, 9, 4, 5, 2, 3, 11, 10]
        XCTAssertEqual(ES9.usbPlaybackOutputs, expected)
        let packets = try ES9.setup(dump())
        let usbRoutes = packets.filter { [0x50, 0x51].contains($0[5]) }
        XCTAssertEqual(usbRoutes, [
            ES9.message(0x50, Array(expected.prefix(8))),
            ES9.message(0x51, Array(expected.suffix(8)))
        ])
        XCTAssertTrue(packets.contains(ES9.message(0x40, Array(ES9.analogInputs.prefix(8)))))
        XCTAssertTrue(packets.contains(ES9.message(0x41,
            Array(ES9.analogInputs.suffix(6)) + [ES9.silentSource, ES9.silentSource])))
        var session = Session()
        let previous = try RoutingPlan(session)
        session.channels[0].level = 1
        session.outputs[0].muted = true
        session.master = 0
        session.headphonesEnabled = true
        let current = try RoutingPlan(session)
        for messages in [previous.messages(from: nil), current.messages(from: previous)] {
            XCTAssertFalse(messages.contains { [0x50, 0x51].contains($0[5]) })
        }
    }

    func testControllerFaderCurveAndPickup() {
        XCTAssertEqual(ControllerFader.level(at: 0), 0)
        XCTAssertEqual(ControllerFader.level(at: 1), 1, accuracy: 0.000001)
        XCTAssertEqual(Channel.gain(ControllerFader.level(at: 0.2)), 0.01, accuracy: 0.000001)
        XCTAssertEqual(Channel.gain(ControllerFader.level(at: 0.4)), 0.1, accuracy: 0.000001)
        for step in 0...6 {
            let position = 0.4 + Double(step) * 0.1
            XCTAssertEqual(Channel.gain(ControllerFader.level(at: position)),
                           0.1 + Double(step) * 0.15, accuracy: 0.000001)
        }
        for range in [60.0, 72.0] {
            var previous = -1.0
            for cc in 0...127 {
                let position = Double(cc) / 127
                let level = ControllerFader.level(at: position, range: range)
                XCTAssertTrue(level > previous)
                XCTAssertTrue((0...1).contains(level))
                XCTAssertEqual(ControllerFader.position(for: level, range: range),
                               position, accuracy: 0.000001)
                previous = level
            }
        }
        // The saved -18 dB level stays unchanged; pickup uses physical travel.
        let target = ControllerFader.position(for: 0.7)
        XCTAssertEqual(Channel.gain(0.7), pow(10, -18.0 / 20), accuracy: 0.000001)
        var pickup = Pickup()
        XCTAssertFalse(pickup.accepts("fader0", value: 0.1, target: target))
        XCTAssertTrue(pickup.accepts("fader0", value: target + 0.03, target: target))
        pickup.reset("fader0")
        XCTAssertFalse(pickup.accepts("fader0", value: 0.7, target: target))
        XCTAssertTrue(pickup.accepts("fader0", value: target + 1.0 / 127, target: target))
    }

    func testDumpValidationAndRestore() throws {
        XCTAssertEqual(try ES9.configurationWords(dump()).count, 719)
        XCTAssertThrowsError(try ES9.configurationWords(dump(version: 4)))
        XCTAssertThrowsError(try ES9.configurationWords(Array(dump().dropLast())))
        XCTAssertThrowsError(try ES9.configurationWords(ES9.message(0x08, [0, 0, 0, 0, 3])))
        var corrupt = dump()
        corrupt[10] = 0x80
        XCTAssertThrowsError(try ES9.configurationWords(corrupt))
        let restored = try ES9.restore(dump())
        XCTAssertEqual(restored.count, 24)
        for (index, packet) in restored.enumerated() {
            XCTAssertEqual(packet.count, 105)
            XCTAssertEqual(Array(packet.prefix(8)), ES9.header + [0x09, UInt8(index), 0])
            XCTAssertEqual(packet.last, 0xF7)
        }
        let payload = restored.flatMap { Array($0[8..<104]) }
        XCTAssertEqual(Array(payload.prefix(719 * 3)), Array(dump()[8..<(dump().count - 1)]))
        XCTAssertTrue(payload.dropFirst(719 * 3).allSatisfy { $0 == 0 })
        var fullWords = Array(repeating: 0, count: 768)
        fullWords[0] = 3
        fullWords[767] = 12345
        let fullDump = ES9.message(0x08, [0, 0] + fullWords.flatMap(ES9.word))
        XCTAssertEqual(try ES9.restore(fullDump).flatMap { Array($0[8..<104]) }, fullWords.flatMap(ES9.word))
    }

    func testSessionValidationAndRoundTrip() throws {
        let session = Session()
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)), session)
        var bad = session
        bad.channels[0].jackSends.removeLast()
        XCTAssertThrowsError(try RoutingPlan(bad))
        bad = session
        bad.channels[0].level = .nan
        XCTAssertThrowsError(try bad.validate())
        bad = session
        bad.mappings = [
            ControlMapping(action: "fader0", status: 0xB0, number: 1),
            ControlMapping(action: "fader1", status: 0xB0, number: 1)
        ]
        XCTAssertThrowsError(try bad.validate())
    }

    func testPickupCrossingAndBankReset() {
        var pickup = Pickup()
        XCTAssertFalse(pickup.accepts("fader0", value: 0, target: 0.7))
        XCTAssertTrue(pickup.accepts("fader0", value: 0.8, target: 0.7))
        XCTAssertTrue(pickup.accepts("fader0", value: 0.2, target: 0.7))
        pickup.reset()
        XCTAssertFalse(pickup.accepts("fader0", value: 0.2, target: 0.7))
        XCTAssertTrue(pickup.accepts("fader0", value: 0.7, target: 0.7))
        pickup.reset("fader0")
        XCTAssertFalse(pickup.accepts("fader0", value: 0.2, target: 0.7))
    }

    func testMIDIFragmentationRunningStatusAndRealtime() {
        var parser = MIDIParser()
        XCTAssertEqual(parser.feed([0xB0, 1]), [])
        XCTAssertEqual(parser.feed([127, 2, 0xF8, 64]), [[0xB0, 1, 127], [0xB0, 2, 64]])
        XCTAssertEqual(parser.feed([0xF0, 0, 0x21]), [])
        XCTAssertEqual(parser.feed([0xF8, 0x27, 0x19, 0x32, 65, 0, 0xF7]),
                       [[0xF0, 0, 0x21, 0x27, 0x19, 0x32, 65, 0, 0xF7]])
        let configuration = dump()
        XCTAssertEqual(parser.feed(Array(configuration.prefix(300))), [])
        XCTAssertEqual(parser.feed(Array(configuration.dropFirst(300))), [configuration])
    }

    func testNoteCannotBeLearnedAsFader() {
        XCTAssertFalse(ControlMapping(action: "fader0", status: 0x90, number: 1).isValid)
        XCTAssertTrue(ControlMapping(action: "mute0", status: 0x90, number: 1).isValid)
        XCTAssertFalse(ControlMapping(action: "unknown", status: 0xB0, number: 1).isValid)
    }

    func testControllerLEDMessages() {
        let mapping = ControlMapping(action: "mute0", status: 0xB4, number: 42)
        XCTAssertEqual(ControllerLED.message(for: mapping, state: .off), [0x94, 42, 12])
        XCTAssertEqual(ControllerLED.message(for: mapping, state: .mute), [0x94, 42, 15])
        XCTAssertEqual(ControllerLED.message(for: mapping, state: .solo), [0x94, 42, 60])
    }

    func testOutputFadersMuteSoloAndIndependentBuses() throws {
        var session = Session()
        session.master = 1
        session.headphonesEnabled = true
        session.headphonesLevel = 60.0 / 72.0
        for index in 0..<14 {
            session.channels[index].level = 1
            session.channels[index].routeExclusively(to: index < 12 ? index % 7 + 1 : 0)
        }
        let original = try RoutingPlan(session)
        for output in 0..<7 {
            var changed = session
            changed.outputs[output].level = 0.5
            let attenuated = try RoutingPlan(changed)
            XCTAssertEqual(attenuated.inputs, original.inputs)
            XCTAssertEqual(attenuated.outputs, original.outputs)
            for input in 0..<12 where session.channels[input].jackSends[output].enabled {
                XCTAssertEqual(coefficient(attenuated, input: input, output: ES9.jackOutputs[output]), 259)
            }
            changed.outputs[output].muted = true
            let muted = try RoutingPlan(changed)
            for input in 0..<12 where session.channels[input].jackSends[output].enabled {
                XCTAssertEqual(coefficient(muted, input: input, output: ES9.jackOutputs[output]), 0)
            }
            changed.outputs[output].muted = false
            changed.outputs[output].level = 0
            XCTAssertEqual(try RoutingPlan(changed), muted)
        }
        session.outputs[0].soloed = true
        session.outputs[6].soloed = true
        let solo = try RoutingPlan(session)
        XCTAssertEqual(solo.inputs, original.inputs)
        XCTAssertEqual(solo.outputs, original.outputs)
        for input in 0..<12 {
            let destination = session.channels[input].destinations[0]
            XCTAssertEqual(coefficient(solo, input: input, output: ES9.jackOutputs[destination - 1]),
                           destination == 1 || destination == 7 ? 8192 : 0)
        }
        for input in 12..<13 {
            for output in [UInt8(6), 7, 12, 13] {
                XCTAssertEqual(coefficient(solo, input: input, output: output), 5793)
            }
        }
        XCTAssertEqual(coefficient(solo, input: ES9.clockInputIndex, output: 6), 0)
        session.outputs[0].muted = true
        let mutedSolo = try RoutingPlan(session)
        XCTAssertEqual(coefficient(mutedSolo, input: 0, output: 8), 0)
        XCTAssertEqual(coefficient(mutedSolo, input: 6, output: 11), 8192)
        XCTAssertTrue(mutedSolo.messages(from: solo).allSatisfy { (0x60...0x6F).contains($0[5]) })
        session.outputs[6].soloed = false
        XCTAssertFalse(session.outputIsAudible(7))
    }

    func testInputSoloAcrossMixersAndMutePriority() throws {
        var session = Session()
        session.headphonesEnabled = true
        session.headphonesLevel = 60.0 / 72.0
        session.master = 1
        for index in 0..<14 { session.channels[index].level = 1 }
        session.channels[13].routeExclusively(to: 7)
        let original = try RoutingPlan(session)
        session.channels[0].soloed = true
        session.channels[13].soloed = true
        let solo = try RoutingPlan(session)
        XCTAssertEqual(solo.inputs, original.inputs)
        XCTAssertEqual(solo.outputs, original.outputs)
        for input in 0..<13 {
            for output in [UInt8(6), 7, 12, 13] {
                XCTAssertEqual(coefficient(solo, input: input, output: output), input == 0 ? 5793 : 0)
            }
        }
        XCTAssertEqual(coefficient(solo, input: ES9.clockInputIndex, output: 11), 0)
        session.channels[0].muted = true
        session.channels[13].muted = true
        XCTAssertTrue(try RoutingPlan(session).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
        session.channels[0].soloed = false
        session.channels[13].soloed = false
        XCTAssertTrue(session.inputIsAudible(1))
        XCTAssertFalse(session.inputIsAudible(0))
        XCTAssertTrue(solo.messages(from: original).allSatisfy { (0x60...0x6F).contains($0[5]) })
    }

    func testClockInputIsExcludedFromAudioMix() throws {
        var session = Session()
        let baseline = try RoutingPlan(session)
        session.channels[ES9.clockInputIndex].mainEnabled = true
        session.channels[ES9.clockInputIndex].jackSends[0] = JackSend(enabled: true)
        session.channels[ES9.clockInputIndex].soloed = true
        session.channels[ES9.clockInputIndex].eq.enabled = true

        XCTAssertTrue(session.channels[ES9.clockInputIndex].destinations.isEmpty)
        XCTAssertFalse(session.inputIsAudible(ES9.clockInputIndex))
        XCTAssertTrue(session.inputIsAudible(0))
        XCTAssertEqual(try RoutingPlan(session), baseline)
    }

    func testCombinedInputAndOutputGain() throws {
        var session = Session()
        for index in 0..<14 { session.channels[index].muted = true }
        session.channels[0].muted = false
        session.channels[7].muted = false
        session.channels[0].routeExclusively(to: 1)
        session.channels[7].routeExclusively(to: 1)
        session.channels[0].level = 0.9
        session.channels[7].level = 0.8
        session.outputs[0].level = 0.9
        let plan = try RoutingPlan(session)
        XCTAssertEqual(coefficient(plan, input: 0, output: 8), 2058)
        XCTAssertEqual(coefficient(plan, input: 7, output: 8), 1031)
        session.master = 0
        XCTAssertEqual(try RoutingPlan(session), plan)
        session.outputs[7].soloed = true
        session.outputs[7].muted = true
        XCTAssertEqual(try RoutingPlan(session), plan)
        XCTAssertFalse(session.outputIsAudible(7))
        XCTAssertTrue(session.channels.allSatisfy { !$0.destinations.contains(8) })
        XCTAssertFalse(plan.outputs.flatMap { $0 }.contains(ES9.jackOutputs[7]))
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)), session)
    }

    func testMixerSessionMigrationAndOutputValidation() throws {
        var session = Session()
        session.channels[13].soloed = true
        session.outputs[7].level = 0.6
        session.outputs[7].muted = true
        session.outputs[7].soloed = true
        session.routingLocked = false
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)), session)
        let baseline = Session()
        let data = try JSONEncoder().encode(baseline)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "outputs")
        legacy.removeValue(forKey: "routingLocked")
        var channels = legacy["channels"] as! [[String: Any]]
        for index in channels.indices { channels[index].removeValue(forKey: "soloed") }
        legacy["channels"] = channels
        let restored = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored, baseline)
        XCTAssertEqual(try RoutingPlan(restored), try RoutingPlan(baseline))
        XCTAssertTrue(restored.routingLocked)
        for invalid in [-0.1, 1.1, Double.nan, Double.infinity] {
            var bad = baseline
            bad.outputs[0].level = invalid
            XCTAssertThrowsError(try bad.validate())
        }
        var bad = baseline
        bad.outputs.removeLast()
        XCTAssertThrowsError(try bad.validate())
        bad = baseline
        bad.outputs[0] = OutputChannel(id: 7)
        XCTAssertThrowsError(try bad.validate())
    }

    func testControllerOutputBankAndNewMappings() throws {
        XCTAssertEqual(ControllerBank.inputs1.target(7), .input(7))
        XCTAssertEqual(ControllerBank.inputs2.target(4), .input(12))
        XCTAssertEqual(ControllerBank.inputs2.target(5), nil)
        XCTAssertEqual(ControllerBank.inputs2.target(6), nil)
        XCTAssertEqual(ControllerBank.outputs.target(6), .output(6))
        XCTAssertEqual(ControllerBank.outputs.target(7), nil)
        XCTAssertEqual(ControllerBank.outputs.target(8), nil)
        XCTAssertEqual(ControllerBank.inputs1.target(-1), nil)
        XCTAssertEqual(ControllerBank.allCases.count, 3)
        for action in ["master", "headphones"] {
            XCTAssertTrue(ControlMapping(action: action, status: 0xB0, number: 1).isValid)
            XCTAssertFalse(ControlMapping(action: action, status: 0x90, number: 1).isValid)
            XCTAssertTrue(ControlMapping.isContinuous(action))
        }
        XCTAssertTrue(ControlMapping.actions.contains("muteAll"))
        XCTAssertEqual(ControlMapping.label("muteAll"), "Mute général")
        XCTAssertTrue(ControlMapping(action: "muteAll", status: 0x90, number: 1).isValid)
        XCTAssertFalse(ControlMapping.isContinuous("muteAll"))
        XCTAssertTrue(ControlMapping.actions.contains("sceneNext"))
        XCTAssertEqual(ControlMapping.label("sceneNext"), "Sous-scène suivante")
        XCTAssertTrue(ControlMapping(action: "sceneNext", status: 0x90, number: 1).isValid)
        XCTAssertTrue(ControlMapping(action: "sceneNext", status: 0xB0, number: 1).isValid)
        XCTAssertFalse(ControlMapping.isContinuous("sceneNext"))
        for slot in 0..<8 {
            XCTAssertTrue(ControlMapping(action: "solo\(slot)", status: 0x90, number: 1).isValid)
            XCTAssertTrue(ControlMapping(action: "solo\(slot)", status: 0xB0, number: 1).isValid)
            XCTAssertFalse(ControlMapping.isContinuous("solo\(slot)"))
        }
        var session = Session()
        session.mappings = [
            ControlMapping(action: "solo0", status: 0x90, number: 1),
            ControlMapping(action: "master", status: 0xB0, number: 1),
            ControlMapping(action: "headphones", status: 0xB0, number: 2),
            ControlMapping(action: "muteAll", status: 0x90, number: 3)
        ]
        try session.validate()
    }

    func testFullMatrixAll91Connections() throws {
        var session = Session()
        for input in 0..<14 {
            session.channels[input].mainEnabled = false
            session.channels[input].level = 1
            session.channels[input].jackSends = Array(repeating: JackSend(enabled: true), count: 8)
        }
        let plan = try RoutingPlan(session)
        let audioOutputs = Array(ES9.jackOutputs.prefix(7)) + [ES9.unusedOutput]
        XCTAssertEqual(plan.outputs, [audioOutputs, audioOutputs])
        XCTAssertEqual(plan.inputs.flatMap { $0 }.filter { $0 != ES9.silentSource }.sorted(),
                       ES9.analogInputs.sorted())
        XCTAssertEqual(plan.coefficients.flatMap { $0 }.filter { $0 == 8192 }.count, 91)
        for input in 0..<ES9.mixerInputCount {
            for output in ES9.jackOutputs.prefix(7) {
                XCTAssertEqual(coefficient(plan, input: input, output: output), 8192)
            }
        }
        session.headphonesEnabled = true
        XCTAssertEqual(try RoutingPlan(session), plan)
        session.master = 0
        XCTAssertEqual(try RoutingPlan(session), plan)
    }

    func testMatrixIndependentSendsAndBuses() throws {
        var session = Session()
        session.headphonesEnabled = true
        session.headphonesLevel = 60.0 / 72.0
        session.master = 1
        session.channels[0].level = 0.9
        session.channels[0].pan = -1
        session.channels[0].jackSends[0] = JackSend(enabled: true, level: 0.8)
        session.channels[0].jackSends[6] = JackSend(enabled: true)
        session.outputs[0].level = 0.9
        session.channels[7].level = 1
        session.channels[7].jackSends[0] = JackSend(enabled: true)
        let plan = try RoutingPlan(session)
        XCTAssertEqual(coefficient(plan, input: 0, output: 8), 517)
        XCTAssertEqual(coefficient(plan, input: 0, output: 11), 4106)
        XCTAssertEqual(coefficient(plan, input: 0, output: 6), 4106)
        XCTAssertEqual(coefficient(plan, input: 0, output: 12), 4106)
        XCTAssertEqual(coefficient(plan, input: 0, output: 7), 0)
        XCTAssertEqual(coefficient(plan, input: 7, output: 8), 4106)
        session.outputs[6].soloed = true
        var changed = try RoutingPlan(session)
        XCTAssertEqual(coefficient(changed, input: 0, output: 8), 0)
        XCTAssertEqual(coefficient(changed, input: 0, output: 11), 4106)
        XCTAssertEqual(coefficient(changed, input: 0, output: 12), 4106)
        session.outputs[6].muted = true
        changed = try RoutingPlan(session)
        XCTAssertEqual(coefficient(changed, input: 0, output: 11), 0)
        session.channels[0].soloed = true
        changed = try RoutingPlan(session)
        XCTAssertEqual(coefficient(changed, input: 7, output: 6), 0)
        session.channels[0].muted = true
        XCTAssertTrue(try RoutingPlan(session).coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    func testMatrixGainDeltasKeepRoutingAllocated() throws {
        var session = Session()
        for input in 0..<14 {
            session.channels[input].mainEnabled = false
            session.channels[input].jackSends = Array(repeating: JackSend(enabled: true), count: 8)
        }
        let old = try RoutingPlan(session)
        session.channels[0].jackSends[3].level = 0
        let updated = try RoutingPlan(session)
        XCTAssertEqual(updated.inputs, old.inputs)
        XCTAssertEqual(updated.outputs, old.outputs)
        XCTAssertEqual(updated.messages(from: old), [ES9.mix(3, 0, 0)])
        session.channels[0].muted = true
        session.outputs[6].soloed = true
        let muted = try RoutingPlan(session)
        XCTAssertEqual(muted.inputs, old.inputs)
        XCTAssertEqual(muted.outputs, old.outputs)
        XCTAssertTrue(muted.messages(from: updated).allSatisfy { (0x60...0x6F).contains($0[5]) })
        session.channels[0].muted = false
        session.outputs[6].soloed = false
        session.channels[0].jackSends[3].enabled = false
        XCTAssertEqual(try RoutingPlan(session), updated)
    }

    func testMatrixCapacityAndRedistribution() throws {
        var session = Session()
        session.headphonesEnabled = true
        for input in 0..<14 {
            session.channels[input].mainEnabled = input < 7
            session.channels[input].jackSends = (0..<8).map {
                JackSend(enabled: input < 7 ? $0 < 4 : true)
            }
        }
        let fits = try RoutingPlan(session)
        XCTAssertEqual(fits.outputs[0].filter { $0 != ES9.unusedOutput }.count, 8)
        XCTAssertEqual(fits.outputs[1], Array(ES9.jackOutputs.prefix(7)) + [ES9.unusedOutput])
        session.channels[6].jackSends = Array(repeating: JackSend(enabled: true), count: 8)
        session.channels[6].mainEnabled = false
        session.channels[7].jackSends = (0..<8).map { JackSend(enabled: $0 < 4) }
        session.channels[7].mainEnabled = true
        let redistributed = try RoutingPlan(session)
        XCTAssertTrue(redistributed.inputs != fits.inputs)
        XCTAssertEqual(redistributed.inputs.flatMap { $0 }.filter { $0 != ES9.silentSource }.sorted(),
                       ES9.analogInputs.sorted())
        let messages = redistributed.messages(from: fits)
        XCTAssertTrue(messages.prefix(128).allSatisfy { Array($0[7...9]) == [0, 0, 0] })
        XCTAssertEqual(messages[128][5], 0x42)

        for input in 0..<14 {
            session.channels[input].mainEnabled = false
            session.channels[input].jackSends = Array(repeating: JackSend(enabled: true), count: 8)
        }
        session.channels[0].mainEnabled = true
        XCTAssertThrowsError(try RoutingPlan(session))
        // Muting, silencing a send or disabling headphones must not hide an impossible allocation.
        session.channels[0].muted = true
        session.channels[0].jackSends[0].level = 0
        session.headphonesEnabled = false
        XCTAssertThrowsError(try RoutingPlan(session))
        session.channels[0].mainEnabled = false
        _ = try RoutingPlan(session)

        var withHeadphones = Session()
        for input in 0..<14 {
            withHeadphones.channels[input].jackSends = (0..<8).map { JackSend(enabled: $0 < 6) }
        }
        _ = try RoutingPlan(withHeadphones)
        withHeadphones.headphonesEnabled = true
        XCTAssertThrowsError(try RoutingPlan(withHeadphones))
    }

    func testMatrixLegacyMigrationAndRoundTrip() throws {
        var baseline = Session()
        for input in 0..<14 {
            baseline.channels[input].routeExclusively(to: input % 9)
            baseline.channels[input].level = Double(input + 1) / 14
            baseline.channels[input].pan = input % 2 == 0 ? -1 : 1
        }
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(baseline)) as! [String: Any]
        var channels = legacy["channels"] as! [[String: Any]]
        for input in 0..<14 {
            channels[input].removeValue(forKey: "mainEnabled")
            channels[input].removeValue(forKey: "jackSends")
            channels[input]["destination"] = input % 9
        }
        legacy["channels"] = channels
        let restored = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored, baseline)
        XCTAssertEqual(try RoutingPlan(restored), try RoutingPlan(baseline))
        baseline.channels[0].jackSends[7] = JackSend(enabled: true, level: 0.3)
        baseline.channels[13].mainEnabled = true
        let encoded = try JSONEncoder().encode(baseline)
        let decoded = try JSONDecoder().decode(Session.self, from: encoded)
        XCTAssertEqual(decoded, baseline)
        XCTAssertEqual(try RoutingPlan(decoded), try RoutingPlan(baseline))

        channels[0]["destination"] = 9
        legacy["channels"] = channels
        XCTAssertThrowsError(try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy)))
        channels[0]["destination"] = 0
        channels[0]["mainEnabled"] = true
        legacy["channels"] = channels
        XCTAssertThrowsError(try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy)))
    }

    func testMatrixSendValidationAndDisconnectedInput() throws {
        for invalid in [-0.1, 1.1, Double.nan, Double.infinity] {
            var session = Session()
            session.channels[0].jackSends[0].level = invalid
            XCTAssertThrowsError(try RoutingPlan(session))
        }
        var session = Session()
        session.channels[0].jackSends.append(JackSend())
        XCTAssertThrowsError(try RoutingPlan(session))
        session = Session()
        session.channels[0].mainEnabled = false
        session.channels[0].level = 1
        let plan = try RoutingPlan(session)
        for output in [UInt8(6), 7] {
            XCTAssertEqual(coefficient(plan, input: 0, output: output), 0)
        }
        for input in 0..<14 { session.channels[input].mainEnabled = false }
        let silent = try RoutingPlan(session)
        XCTAssertTrue(silent.outputs.flatMap { $0 }.allSatisfy { $0 == ES9.unusedOutput })
        XCTAssertTrue(silent.coefficients.flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    private func filterSlot(_ plan: RoutingPlan, input: Int) -> Int? {
        for block in 0..<2 {
            if let column = plan.inputs[block].firstIndex(of: ES9.analogInputs[input]) {
                return block * 32 + column * 4
            }
        }
        return nil
    }

    func testStripEQEncodingAndAddressing() throws {
        XCTAssertEqual(ES9EQ.frequencyWord(10), 0)
        XCTAssertEqual(ES9EQ.frequencyWord(22000), 32767)
        XCTAssertEqual(ES9EQ.qWord(0.707), 12341)
        XCTAssertEqual(ES9EQ.gainWord(15), 32767)
        XCTAssertEqual(ES9EQ.gainWord(0), 0)
        XCTAssertEqual(ES9EQ.gainWord(-15), 0x8001)
        XCTAssertEqual(ES9EQ.filterWords(EQBand(shape: .highShelf, frequency: 8000, gain: 15), enabled: true),
                       [11, ES9EQ.frequencyWord(8000), 12341, ES9EQ.gainWord(12)])

        var session = Session()
        session.channels[9].eq.enabled = true
        session.channels[9].eq.bands[0] = EQBand(shape: .lowShelf, frequency: 80, gain: 3)
        session.channels[9].eq.bands[1] = EQBand(frequency: 1000, q: 2, gain: -6)
        session.channels[9].eq.bands[2] = EQBand(frequency: 10000, gain: 4.5)
        let plan = try RoutingPlan(session)
        // Input 10 is column 2 of the second mixer: official address 8 × 1 + 2.
        XCTAssertEqual(filterSlot(plan, input: 9), 32 + 8)
        XCTAssertEqual(plan.filters[40], [9, ES9EQ.frequencyWord(80), 12341, ES9EQ.gainWord(3)])
        XCTAssertEqual(plan.filters[41][0], 13)
        XCTAssertEqual(plan.filters[43], ES9EQ.disabledFilter)
        let packet = ES9EQ.message(slot: 41, words: plan.filters[41])
        XCTAssertEqual(Array(packet.prefix(9)), [0xF0, 0, 0x21, 0x27, 0x19, 0x39, 10, 1, 13])
        XCTAssertEqual(Array(packet[15...17]), ES9.word(ES9EQ.gainWord(-6)))
        XCTAssertEqual(packet[15], 3)
        XCTAssertTrue(packet.dropFirst().dropLast().allSatisfy { $0 < 128 })
        XCTAssertEqual(plan.filters.enumerated().filter { $0.element[0] & 1 == 1 }.map(\.offset), [40, 41, 42])

        // An EQ change only sends that filter, without touching the routing or levels.
        var changed = session
        changed.channels[9].eq.bands[1].gain = 2
        let delta = try RoutingPlan(changed).messages(from: plan)
        XCTAssertEqual(delta, [ES9EQ.message(slot: 41, words: try RoutingPlan(changed).filters[41])])
        changed.channels[9].eq.enabled = false
        let bypass = try RoutingPlan(changed)
        XCTAssertEqual(bypass.messages(from: plan).count, 3)
        XCTAssertTrue(bypass.filters.allSatisfy { $0[0] & 1 == 0 })
        XCTAssertEqual(bypass.coefficients, plan.coefficients)

        changed.channels[9].eq.bands[1].q = 30
        XCTAssertThrowsError(try RoutingPlan(changed))
        changed = session
        changed.channels[9].eq.bands[2] = EQBand(shape: .highShelf, frequency: 8000, gain: 13)
        XCTAssertThrowsError(try RoutingPlan(changed))
        changed.channels[9].eq.bands.removeLast()
        XCTAssertThrowsError(try RoutingPlan(changed))
    }

    func testStripEQFollowsRedistributedInput() throws {
        var session = Session()
        session.headphonesEnabled = true
        for input in 0..<14 {
            session.channels[input].mainEnabled = input < 7
            session.channels[input].jackSends = (0..<8).map {
                JackSend(enabled: input < 7 ? $0 < 4 : true)
            }
        }
        session.channels[6].eq.enabled = true
        session.channels[7].eq.enabled = true
        session.channels[7].eq.bands[1].gain = 5
        let fits = try RoutingPlan(session)
        session.channels[6].jackSends = Array(repeating: JackSend(enabled: true), count: 8)
        session.channels[6].mainEnabled = false
        session.channels[7].jackSends = (0..<8).map { JackSend(enabled: $0 < 4) }
        session.channels[7].mainEnabled = true
        let redistributed = try RoutingPlan(session)
        XCTAssertTrue(redistributed.inputs != fits.inputs)
        for input in 0..<14 {
            guard let slot = filterSlot(redistributed, input: input) else { return XCTAssertTrue(false) }
            let eq = session.channels[input].eq
            for band in 0..<3 {
                XCTAssertEqual(redistributed.filters[slot + band], ES9EQ.filterWords(eq.bands[band], enabled: eq.enabled))
            }
        }
        // Filters move while the mixers are silenced, before any coefficient is restored.
        let messages = redistributed.messages(from: fits)
        let firstFilter = messages.firstIndex { $0[5] == 0x39 } ?? 0
        let firstLevel = messages.dropFirst(128).firstIndex { (0x60...0x6F).contains($0[5]) } ?? 0
        XCTAssertTrue(firstFilter >= 128)
        XCTAssertTrue(firstFilter < firstLevel)
    }

    func testInputDisplayOrderPreservesAudioAndIdentity() throws {
        var session = Session()
        session.channels[4].name = "Synth"
        session.channels[4].level = 0.65
        session.channels[4].trim = -3
        session.channels[4].eq.enabled = true
        session.channels[4].jackSends[0] = JackSend(enabled: true, level: 0.7)
        session.channels[1].soloed = true
        let original = session
        let plan = try RoutingPlan(session)

        try session.moveConsoleInput(from: 4, to: 0)
        XCTAssertEqual(session.consoleInputOrder, [4, 0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13])
        try session.moveConsoleInput(from: 2, to: 1)
        XCTAssertEqual(session.consoleInputOrder, [4, 1, 0, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13])
        XCTAssertEqual(session.stripInputs, original.stripInputs)
        try session.moveConsoleInput(from: 0, to: 13)
        XCTAssertEqual(session.consoleInputOrder, [1, 0, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 4])
        try session.moveConsoleInput(from: 13, to: 0)
        let reordered = session
        try session.moveConsoleInput(from: 0, to: 0)
        XCTAssertEqual(session, reordered)

        session.stripInputs = [4, 1, 9, 12]
        try session.moveStripInput(from: 0, to: 3)
        XCTAssertEqual(session.stripInputs, [1, 9, 12, 4])
        try session.moveStripInput(from: 3, to: 0)
        XCTAssertEqual(session.stripInputs, [4, 1, 9, 12])
        XCTAssertEqual(session.consoleInputOrder, reordered.consoleInputOrder)
        XCTAssertEqual(session.channels, original.channels)
        XCTAssertEqual(session.outputs, original.outputs)
        XCTAssertEqual(session.mappings, original.mappings)
        XCTAssertEqual(try RoutingPlan(session), plan)
        XCTAssertTrue(try RoutingPlan(session).messages(from: plan).isEmpty)
        for bank in ControllerBank.allCases {
            for slot in 0..<8 {
                // Physical controller targets do not depend on display positions.
                if case .input(let input) = bank.target(slot) {
                    XCTAssertEqual(session.channels[input].id, original.channels[input].id)
                }
            }
        }
    }

    func testInputDisplayOrderPersistenceAndMigration() throws {
        var session = Session()
        try session.moveConsoleInput(from: 4, to: 0)
        session.stripInputs = [4, 1, 12, 0]
        let encoded = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(Session.self, from: encoded)
        try restored.validate()
        XCTAssertEqual(restored, session)
        guard var legacy = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw MixerError.invalidSession
        }
        legacy.removeValue(forKey: "consoleInputOrder")
        legacy.removeValue(forKey: "stripInputs")
        let migrated = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        try migrated.validate()
        XCTAssertEqual(migrated.consoleInputOrder, Array(0..<14))
        XCTAssertEqual(migrated.stripInputs, [9, 10, 11, 12])
        XCTAssertEqual(migrated.channels, session.channels)
        XCTAssertEqual(try RoutingPlan(migrated), try RoutingPlan(session))

        session.stripInputs = [4, 1, ES9.clockInputIndex, 0]
        let withClockStrip = try JSONEncoder().encode(session)
        let migratedClockStrip = try JSONDecoder().decode(Session.self, from: withClockStrip)
        XCTAssertEqual(migratedClockStrip.stripInputs, [4, 1, 0, 0])
    }

    func testInputDisplayOrderValidation() throws {
        let original = Session()
        for order in [[], Array(0..<13), Array(0..<15), Array(repeating: 0, count: 14),
                      [-1] + Array(1..<14), Array(0..<13) + [14]] {
            var invalid = original
            invalid.consoleInputOrder = order
            XCTAssertThrowsError(try invalid.validate())
        }
        for inputs in [[], [0, 1, 2], [0, 1, 2, 3, 4], [-1, 1, 2, 3], [0, 1, 2, 14]] {
            var invalid = original
            invalid.stripInputs = inputs
            XCTAssertThrowsError(try invalid.validate())
        }
        var session = original
        for (source, destination) in [(-1, 0), (0, -1), (14, 0), (0, 14)] {
            XCTAssertThrowsError(try session.moveConsoleInput(from: source, to: destination))
            XCTAssertEqual(session, original)
        }
        for (source, destination) in [(-1, 0), (0, -1), (4, 0), (0, 4)] {
            XCTAssertThrowsError(try session.moveStripInput(from: source, to: destination))
            XCTAssertEqual(session, original)
        }
        // The strip selectors historically allow displaying the same input in multiple slots.
        session.stripInputs = [4, 4, 1, 1]
        try session.validate()
        try session.moveStripInput(from: 0, to: 3)
        XCTAssertEqual(session.stripInputs, [4, 1, 1, 4])
    }

    func testStripTrimGainAndMigration() throws {
        var session = Session()
        session.master = 1
        session.channels[9].level = 1
        session.channels[9].mainEnabled = false
        session.channels[9].jackSends[0] = JackSend(enabled: true, level: 1)
        session.channels[9].trim = -6
        var plan = try RoutingPlan(session)
        XCTAssertEqual(coefficient(plan, input: 9, output: ES9.jackOutputs[0]), Int((8192 * pow(10, -6.0 / 20)).rounded()))
        session.channels[9].trim = 12
        plan = try RoutingPlan(session)
        XCTAssertEqual(coefficient(plan, input: 9, output: ES9.jackOutputs[0]), 32613)
        session.channels[9].mainEnabled = true
        session.channels[9].pan = -1
        plan = try RoutingPlan(session)
        XCTAssertEqual(coefficient(plan, input: 9, output: 6), 32613)
        XCTAssertTrue(plan.coefficients.flatMap { $0 }.allSatisfy { $0 <= 32767 })
        for invalid in [-25.0, 12.5, .nan] {
            var candidate = session
            candidate.channels[9].trim = invalid
            XCTAssertThrowsError(try RoutingPlan(candidate))
        }

        let encoded = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: encoded), session)
        // Sessions saved before the strip view load with a neutral trim and a bypassed EQ.
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy["channels"] = (legacy["channels"] as! [[String: Any]]).map {
            var channel = $0
            channel.removeValue(forKey: "trim")
            channel.removeValue(forKey: "eq")
            return channel
        }
        let migrated = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.channels[9].trim, 0)
        XCTAssertEqual(migrated.channels[9].eq, ChannelEQ())
        XCTAssertFalse(migrated.channels[9].eq.enabled)
        XCTAssertTrue(try RoutingPlan(migrated).filters.allSatisfy { $0[0] & 1 == 0 })
    }
}

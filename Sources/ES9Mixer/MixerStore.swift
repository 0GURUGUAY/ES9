import AppKit
import Combine
import CoreMIDI
import MixerCore

enum DisplayMode: String, CaseIterable {
    case console = "Console"
    case matrix = "Matrice"
    case strip = "Strip"

    var symbol: String {
        switch self {
        case .console: return "slider.vertical.3"
        case .matrix: return "square.grid.3x3"
        case .strip: return "dial.medium"
        }
    }
}

@MainActor
final class MixerStore: ObservableObject {
    @Published var session = Session()
    @Published var sources: [MIDIEndpoint] = []
    @Published var destinations: [MIDIEndpoint] = []
    @Published var esInput: MIDIEndpointRef = 0
    @Published var esOutput: MIDIEndpointRef = 0
    @Published var controllerInput: MIDIEndpointRef = 0
    @Published var controllerOutput: MIDIEndpointRef = 0
    @Published var active = false
    @Published var busy = false
    @Published var bank = ControllerBank.inputs1
    @Published var showMIDI = false
    @Published var displayMode = DisplayMode.console
    @Published var stripInputs = [9, 10, 11, 12]
    @Published var flashSlot: Int?
    @Published var status = "Mode démonstration — aucun réglage envoyé à l’ES-9."
    @Published var firmware = "Non interrogé"
    @Published var error: String?
    @Published var learning: String?
    @Published var lastMIDI = "Aucun message reçu"
    @Published var pickupMessage = ""
    @Published private(set) var dspUsage: DSPUsage?
    @Published private(set) var dspStatus = "ES-9 non connecté."

    var dspLabel: String {
        guard let dspUsage else { return "DSP : —" }
        let first = String(format: "%.1f %%", dspUsage.first)
        if let second = dspUsage.second {
            return "DSP 1 : \(first) · DSP 2 : \(String(format: "%.1f %%", second))"
        }
        return "DSP 1 : \(first) · DSP 2 : inactif"
    }

    private var midi: MIDITransport?
    private var dspTimer: AnyCancellable?
    private var dspPendingSince: Date?
    private var dspReceivedAt: Date?
    private var dspSource: MIDIEndpointRef = 0
    private var dspDestination: MIDIEndpointRef = 0
    private var parsers: [MIDIEndpointRef: MIDIParser] = [:]
    private var controllerLEDMessages: [Int: [UInt8]] = [:]
    private var pickup = Pickup()
    private var pressed: Set<Int> = []
    private var lastPlan: RoutingPlan?
    private var updateTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var dumpContinuation: CheckedContinuation<[UInt8], Error>?
    private var saveContinuation: CheckedContinuation<String, Error>?
    private var responseTimeout: Task<Void, Never>?
    private var isSending = false
    private let sessionURL: URL
    private var terminateObserver: NSObjectProtocol?

    init() {
        sessionURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ES9Mixer/session.json")
        do {
            if FileManager.default.fileExists(atPath: sessionURL.path) {
                let restored = try JSONDecoder().decode(Session.self, from: Data(contentsOf: sessionURL))
                _ = try RoutingPlan(restored)
                session = restored
            }
            let transport = try MIDITransport()
            midi = transport
            transport.onBytes = { [weak self] source, bytes in self?.receive(source, bytes) }
            transport.onChange = { [weak self] in self?.refresh() }
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.persistNow() }
            }
            refresh()
            dspTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.pollDSP() }
        } catch {
            report(error)
        }
    }

    func refresh() {
        guard let midi else { return }
        sources = midi.sources()
        destinations = midi.destinations()
        if esInput != 0 && !sources.contains(where: { $0.id == esInput })
            || esOutput != 0 && !destinations.contains(where: { $0.id == esOutput }) {
            suspend()
            failPending("L’ES-9 a été déconnecté.")
            status = "ES-9 déconnecté — le contrôle est suspendu."
        }
        if !sources.contains(where: { $0.id == esInput }) {
            esInput = sources.first(where: { $0.name.localizedCaseInsensitiveContains("ES-9") })?.id ?? 0
        }
        if !destinations.contains(where: { $0.id == esOutput }) {
            esOutput = destinations.first(where: { $0.name.localizedCaseInsensitiveContains("ES-9") })?.id ?? 0
        }
        let controllerDestinations = destinations.filter { $0.id != esOutput }
        if !controllerDestinations.contains(where: { $0.id == controllerOutput }) {
            let selected = controllerDestinations.first(where: {
                $0.name.localizedCaseInsensitiveContains("Launch Control")
                || $0.name.localizedCaseInsensitiveContains("LaunchControl")
            })?.id ?? 0
            if selected != controllerOutput { controllerLEDMessages.removeAll() }
            controllerOutput = selected
        }
        if !sources.contains(where: { $0.id == controllerInput }) {
            controllerInput = sources.first(where: {
                $0.name.localizedCaseInsensitiveContains("Launch Control")
                || $0.name.localizedCaseInsensitiveContains("LaunchControl")
            })?.id ?? 0
            pickup.reset()
            pressed.removeAll()
        }
        do { try midi.subscribe(to: sources.filter { $0.id == esInput || $0.id == controllerInput }) }
        catch { report(error) }
        syncControllerLEDs(force: true)
        if dspSource != esInput || dspDestination != esOutput {
            resetDSP()
        }
        pollDSP()
    }

    func portsChanged() {
        suspend()
        failPending("La sélection MIDI a changé.")
        parsers.removeAll()
        pickup.reset()
        pressed.removeAll()
        firmware = "Non interrogé"
        resetDSP()
        refresh()
    }

    private func resetDSP() {
        dspUsage = nil
        dspReceivedAt = nil
        dspPendingSince = nil
        dspSource = esInput
        dspDestination = esOutput
        dspStatus = esInput == 0 || esOutput == 0 ? "ES-9 non connecté." : "En attente de la charge DSP…"
    }

    private func pollDSP() {
        if dspSource != esInput || dspDestination != esOutput { resetDSP() }
        guard esInput != 0, esOutput != 0 else { return }
        if let pending = dspPendingSince {
            guard Date().timeIntervalSince(pending) >= 4 else { return }
            dspPendingSince = nil
            dspUsage = nil
            dspStatus = "Charge DSP indisponible : aucune réponse après 4 secondes. Vérifiez les ports MIDI."
        }
        guard !busy, !isSending, dumpContinuation == nil, saveContinuation == nil else {
            if let received = dspReceivedAt, Date().timeIntervalSince(received) >= 6 {
                dspUsage = nil
                dspStatus = "Actualisation DSP suspendue pendant l’opération MIDI."
            }
            return
        }
        do {
            try send(ES9.dspUsageRequest)
            dspPendingSince = Date()
        } catch {
            dspUsage = nil
            dspStatus = "Lecture DSP impossible : \(error.localizedDescription)"
        }
    }

    func controllerPortChanged() {
        parsers.removeAll()
        pickup.reset()
        pressed.removeAll()
        learning = nil
        refresh()
    }

    func setControllerOutput(_ value: MIDIEndpointRef) {
        guard value == 0 || (value != esOutput && destinations.contains(where: { $0.id == value })) else {
            report(operationError("Choisissez une sortie MIDI Launch Control distincte de l’ES-9."))
            return
        }
        guard value != controllerOutput else { return }
        clearControllerLEDs()
        controllerOutput = value
        controllerLEDMessages.removeAll()
        syncControllerLEDs(force: true)
    }

    func suspend() {
        active = false
        lastPlan = nil
        updateTask?.cancel()
    }

    func probe() {
        do { try send(ES9.message(0x22)); status = "Demande de version envoyée…" }
        catch { report(error) }
    }

    func changeBank(_ value: ControllerBank) {
        bank = value
        pickup.reset()
        pickupMessage = "Rattrapage actif : rejoindre le niveau affiché avec les faders."
        syncControllerLEDs(force: true)
    }

    func changeChannel(_ index: Int, _ change: (inout Channel) -> Void) {
        guard !busy else { return }
        var updated = session.channels[index]
        change(&updated)
        guard !session.routingLocked || updated.destinations == session.channels[index].destinations else {
            report(operationError("Déverrouillez le routage avant de modifier une liaison."))
            return
        }
        var candidate = session
        candidate.channels[index] = updated
        do { _ = try RoutingPlan(candidate) }
        catch { report(error); return }
        session = candidate
        if bank.target(index % 8) == .input(index) {
            pickup.reset("fader\(index % 8)")
            pickup.reset("pan\(index % 8)")
        }
        changed()
    }

    func changeOutput(_ index: Int, _ change: (inout OutputChannel) -> Void) {
        guard !busy else { return }
        change(&session.outputs[index])
        if bank == .outputs { pickup.reset("fader\(index)") }
        changed()
    }

    func setRoutingLocked(_ value: Bool) {
        guard !busy else { return }
        session.routingLocked = value
        persistSoon()
    }

    func useJacksOnly() {
        guard !busy else { return }
        guard !session.routingLocked else {
            report(operationError("Déverrouillez le routage avant de couper les envois au général."))
            return
        }
        for index in session.channels.indices { session.channels[index].mainEnabled = false }
        changed()
    }

    func setMaster(_ value: Double) {
        guard !busy else { return }
        session.master = value
        pickup.reset("master")
        changed()
    }

    func toggleMuteAll() {
        guard !busy else { return }
        session.muteAll.toggle()
        changed()
    }

    func toggleMasterMute() {
        guard !busy else { return }
        session.masterMuted.toggle()
        changed()
    }

    func setHeadphonesEnabled(_ value: Bool) {
        guard !busy else { return }
        var candidate = session
        candidate.headphonesEnabled = value
        do { _ = try RoutingPlan(candidate) }
        catch { report(error); return }
        session = candidate
        changed()
    }

    func setHeadphonesLevel(_ value: Double) {
        guard !busy else { return }
        session.headphonesLevel = value
        pickup.reset("headphones")
        changed()
    }

    private func changed() {
        persistSoon()
        syncControllerLEDs()
        guard active else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000) }
            catch { return }
            await self?.flush()
        }
    }

    private func flush() async {
        guard active, !isSending, !busy else { return }
        isSending = true
        defer { isSending = false }
        do {
            // Changes made during transmission are sent in a subsequent complete delta.
            while active {
                let plan = try RoutingPlan(session)
                if plan == lastPlan { break }
                try await sendBatch(plan.messages(from: lastPlan), cancellable: false, requiresActive: true)
                lastPlan = plan
            }
        } catch {
            suspend()
            report(error)
            status = "Contrôle suspendu après erreur d’envoi. L’état matériel doit être vérifié."
        }
    }

    func activate() {
        guard !busy, !isSending, esInput != 0, esOutput != 0 else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let plan = try RoutingPlan(session)
                let dump = try await requestDump()
                _ = try ES9.configurationWords(dump)
                status = "Configuration du mélangeur en cours…"
                try await sendBatch(ES9.setup(dump))
                try await sendBatch(plan.messages(from: nil))
                try verify(try await requestDump(), plan)
                lastPlan = plan
                active = true
                status = "ES-9 piloté — mix analogique et USB direct relus et vérifiés. S/PDIF désactivé."
            } catch {
                suspend()
                report(error)
                status = "Activation interrompue. L’ES-9 a peut-être été modifié ; vérifiez son état avant utilisation."
            }
        }
    }

    func verifyHardware() {
        guard active, !busy, !isSending else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try verify(try await requestDump(), RoutingPlan(session))
                status = "Routage et niveaux relus dans l’ES-9 : conformes."
            } catch {
                suspend()
                report(error)
                status = "L’état de l’ES-9 n’est pas confirmé. Contrôle suspendu."
            }
        }
    }

    private func verify(_ dump: [UInt8], _ plan: RoutingPlan) throws {
        let words = try ES9.configurationWords(dump)
        guard words[450] & 1 == 1 else { throw operationError("Le deuxième mélangeur n’est pas activé.") }
        for block in 0..<2 {
            let inputStart = 18 + block * 8
            let expectedInputs = plan.inputs[block]
            guard Array(words[inputStart..<(inputStart + 8)]) == expectedInputs.map(Int.init),
                  Array(words[(50 + block * 8)..<(58 + block * 8)]) == plan.outputs[block].map(Int.init) else {
                throw operationError("Le routage reçu ne correspond pas au routage demandé.")
            }
        }
        guard Array(words[34..<50]) == ES9.usbPlaybackOutputs.map(Int.init) else {
            throw operationError("Le routage USB direct reçu ne correspond pas aux sorties demandées.")
        }
        guard Array(words[66..<194]) == plan.coefficients.flatMap({ $0 }),
              words[1] == 0x7F, words[453] == 0,
              words[718] == 0xFFFF,
              words[454..<462].allSatisfy({ $0 == 0 }),
              words[ES9EQ.firstWord..<(ES9EQ.firstWord + 4 * ES9EQ.filterCount)].map({ $0 & 0xFFFF })
                == plan.filters.flatMap({ $0 }) else {
            throw operationError("Les niveaux ou les traitements reçus ne correspondent pas aux réglages demandés.")
        }
    }

    func saveFlash(_ slot: UInt8) {
        guard active, !busy, !isSending else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try verify(try await requestDump(), RoutingPlan(session))
                let reply = try await withCheckedThrowingContinuation { continuation in
                    saveContinuation = continuation
                    do {
                        try send(ES9.message(0x24, [slot]))
                        startTimeout()
                    } catch { failPending(error.localizedDescription) }
                }
                guard reply == "OK" else { throw operationError("L’ES-9 a répondu : \(reply)") }
                status = "Configuration mémorisée dans l’ES-9 (\(slot == 0 ? "sans ordinateur" : "avec USB"))."
            } catch { report(error) }
        }
    }

    func restoreBackup() {
        guard !busy, !isSending, esInput != 0, esOutput != 0 else { return }
        let panel = NSOpenPanel()
        panel.title = "Restaurer une sauvegarde ES-9 (.syx)"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let dump = Array(try Data(contentsOf: url))
            let packet = try ES9.restore(dump)
            let alert = NSAlert()
            alert.messageText = "Restaurer la configuration matérielle ?"
            alert.informativeText = "Cette opération remplace les réglages actifs de l’ES-9, mais n’écrit pas dans sa mémoire permanente. Réduisez votre volume d’écoute."
            alert.addButton(withTitle: "Restaurer")
            alert.addButton(withTitle: "Annuler")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            suspend()
            busy = true
            Task {
                defer { busy = false }
                do {
                    try await sendBatch(packet)
                    try await Task.sleep(nanoseconds: 200_000_000)
                    let received = try await requestDump()
                    let savedWords = try ES9.configurationWords(dump)
                    let expectedWords = savedWords + Array(repeating: 0, count: 768 - savedWords.count)
                    guard try ES9.configurationWords(received) == expectedWords else {
                        throw operationError("La configuration restaurée n’a pas pu être confirmée.")
                    }
                    status = "Sauvegarde restaurée et vérifiée. Contrôle de la console suspendu."
                } catch { report(error) }
            }
        } catch { report(error) }
    }

    func saveSession() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ES9-session.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(session).write(to: url, options: .atomic) }
        catch { report(error) }
    }

    func openSession() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try JSONDecoder().decode(Session.self, from: Data(contentsOf: url))
            _ = try RoutingPlan(loaded)
            session = loaded
            pickup.reset()
            changed()
        } catch { report(error) }
    }

    func forgetMapping(_ action: String) {
        session.mappings.removeAll { $0.action == action }
        persistSoon()
        syncControllerLEDs()
    }

    private func receive(_ source: MIDIEndpointRef, _ bytes: [UInt8]) {
        var parser = parsers[source] ?? MIDIParser()
        let messages = parser.feed(bytes)
        parsers[source] = parser
        for message in messages {
            if source == esInput, message.starts(with: ES9.header), message.count >= 7 {
                if message[5] == 0x12, dspPendingSince != nil,
                   source == dspSource, esOutput == dspDestination {
                    dspPendingSince = nil
                    do {
                        dspUsage = try DSPUsage(packet: message)
                        dspReceivedAt = Date()
                        dspStatus = "Charge mesurée par l’ES-9 ; actualisation toutes les 2 secondes."
                    } catch {
                        dspUsage = nil
                        dspStatus = error.localizedDescription
                    }
                } else if message[5] == 0x08, let pending = dumpContinuation {
                    dumpContinuation = nil
                    responseTimeout?.cancel()
                    pending.resume(returning: message)
                } else if message[5] == 0x32 {
                    let text = String(bytes: message.dropFirst(6).prefix(while: { $0 != 0 && $0 != 0xF7 }),
                                      encoding: .ascii) ?? "Réponse texte invalide"
                    if let pending = saveContinuation {
                        saveContinuation = nil
                        responseTimeout?.cancel()
                        pending.resume(returning: text)
                    } else {
                        firmware = text
                        status = "Réponse ES-9 : \(text). Aucun changement de configuration."
                    }
                }
            }
            if source == controllerInput { controller(message) }
        }
    }

    private func controller(_ message: [UInt8]) {
        guard message.count == 3 else { return }
        let type = message[0] & 0xF0
        guard [0xB0, 0x90, 0x80].contains(type) else { return }
        lastMIDI = String(format: "%02X  %02X  %02X", message[0], message[1], message[2])
        let normalizedStatus = type == 0x80 ? (message[0] & 0x0F) | 0x90 : message[0]
        let candidate = ControlMapping(action: learning ?? "", status: normalizedStatus, number: message[1])
        if let action = learning, message[2] > 0, type != 0x80 {
            guard candidate.isValid else {
                pickupMessage = "Un contrôle de niveau ou un panoramique doit envoyer un MIDI CC."
                return
            }
            session.mappings.removeAll { $0.action == action || $0.signature == candidate.signature }
            session.mappings.append(candidate)
            learning = nil
            pickup.reset()
            persistSoon()
            syncControllerLEDs(force: true)
            return
        }
        guard !busy, let mapping = session.mappings.first(where: { $0.signature == candidate.signature }) else { return }
        let action = mapping.action
        if !ControlMapping.isContinuous(action) {
            let down = type != 0x80 && message[2] > 0
            if !down { pressed.remove(mapping.signature); return }
            guard pressed.insert(mapping.signature).inserted else { return }
            if action == "previous" || action == "next" {
                let offset = action == "next" ? 1 : -1
                if let next = ControllerBank(rawValue: bank.rawValue + offset) { changeBank(next) }
                return
            }
            if let slot = Int(action.dropFirst(4)), let target = bank.target(slot) {
                switch target {
                case .input(let index):
                    if action.hasPrefix("mute") { session.channels[index].muted.toggle() }
                    else { session.channels[index].soloed.toggle() }
                case .output(let index):
                    if action.hasPrefix("mute") { session.outputs[index].muted.toggle() }
                    else { session.outputs[index].soloed.toggle() }
                }
                changed()
            }
            return
        }
        let value = Double(message[2]) / 127
        if action == "master" || action == "headphones" {
            let range = action == "master" ? 60.0 : 72.0
            let target = ControllerFader.position(
                for: action == "master" ? session.master : session.headphonesLevel, range: range)
            guard pickup.accepts(action, value: value, target: target) else {
                pickupMessage = "\(ControlMapping.label(action)) : rejoindre la valeur affichée."
                return
            }
            let level = ControllerFader.level(at: value, range: range)
            if action == "master" { session.master = level }
            else { session.headphonesLevel = level }
            pickupMessage = "\(ControlMapping.label(action)) : niveau réglé."
            changed()
            return
        }
        let isPan = action.hasPrefix("pan")
        let prefix = isPan ? "pan" : "fader"
        guard let slot = Int(action.dropFirst(prefix.count)), let strip = bank.target(slot) else { return }
        let target: Double
        switch strip {
        case .input(let index):
            target = isPan ? (session.channels[index].pan + 1) / 2
                : ControllerFader.position(for: session.channels[index].level)
        case .output(let index):
            guard !isPan else {
                pickupMessage = "Les sorties jack sont mono : panoramiques inactifs dans cette banque."
                return
            }
            target = ControllerFader.position(for: session.outputs[index].level)
        }
        guard pickup.accepts(action, value: value, target: target) else {
            pickupMessage = "\(ControlMapping.label(action)) : rejoindre la valeur affichée."
            return
        }
        switch strip {
        case .input(let index):
            if isPan { session.channels[index].pan = value * 2 - 1 }
            else { session.channels[index].level = ControllerFader.level(at: value) }
            pickupMessage = "\(ControlMapping.label(action)) → entrée \(index + 1)"
        case .output(let index):
            session.outputs[index].level = ControllerFader.level(at: value)
            pickupMessage = "\(ControlMapping.label(action)) → sortie \(index + 1)"
        }
        changed()
    }

    private func requestDump() async throws -> [UInt8] {
        guard dumpContinuation == nil, saveContinuation == nil else {
            throw operationError("Une requête ES-9 est déjà en cours.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            dumpContinuation = continuation
            do {
                try send(ES9.message(0x23))
                startTimeout()
            } catch { failPending(error.localizedDescription) }
        }
    }

    private func startTimeout() {
        responseTimeout?.cancel()
        responseTimeout = Task {
            do { try await Task.sleep(nanoseconds: 4_000_000_000) }
            catch { return }
            failPending("Aucune réponse de l’ES-9 après 4 secondes. Vérifiez les deux ports MIDI.")
        }
    }

    private func failPending(_ text: String) {
        responseTimeout?.cancel()
        let dump = dumpContinuation
        let save = saveContinuation
        dumpContinuation = nil
        saveContinuation = nil
        dump?.resume(throwing: operationError(text))
        save?.resume(throwing: operationError(text))
    }

    private func send(_ message: [UInt8]) throws {
        guard let midi, esInput != 0, esOutput != 0 else { throw MIDIError.noDestination }
        try midi.send(message, to: esOutput)
    }

    private func syncControllerLEDs(force: Bool = false) {
        guard let midi, controllerOutput != 0,
              destinations.contains(where: { $0.id == controllerOutput }) else {
            controllerLEDMessages.removeAll()
            return
        }

        var desired: [Int: [UInt8]] = [:]
        for mapping in session.mappings {
            guard let state = controllerLEDState(for: mapping.action) else { continue }
            let key = (Int(mapping.status & 0x0F) << 7) | Int(mapping.number)
            desired[key] = ControllerLED.message(for: mapping, state: state)
        }

        let keys = Set(controllerLEDMessages.keys).union(desired.keys).sorted()
        do {
            for key in keys {
                guard force || controllerLEDMessages[key] != desired[key] else { continue }
                if let message = desired[key] {
                    try midi.send(message, to: controllerOutput)
                } else if var previous = controllerLEDMessages[key] {
                    previous[2] = 12
                    try midi.send(previous, to: controllerOutput)
                }
            }
            controllerLEDMessages = desired
        } catch {
            report(error)
        }
    }

    private func clearControllerLEDs() {
        guard let midi, controllerOutput != 0 else {
            controllerLEDMessages.removeAll()
            return
        }
        do {
            for var message in controllerLEDMessages.values {
                message[2] = 12
                try midi.send(message, to: controllerOutput)
            }
            controllerLEDMessages.removeAll()
        } catch {
            report(error)
        }
    }

    private func controllerLEDState(for action: String) -> ControllerLED.State? {
        let prefix: String
        if action.hasPrefix("mute") {
            prefix = "mute"
        } else if action.hasPrefix("solo") {
            prefix = "solo"
        } else {
            return nil
        }
        guard let slot = Int(action.dropFirst(prefix.count)), (0..<8).contains(slot) else {
            return nil
        }
        guard let target = bank.target(slot) else { return .off }
        switch target {
        case .input(let index):
            return prefix == "mute"
                ? (session.muteAll || session.channels[index].muted ? .mute : .off)
                : (session.channels[index].soloed ? .solo : .off)
        case .output(let index):
            return prefix == "mute"
                ? (session.outputs[index].muted ? .mute : .off)
                : (session.outputs[index].soloed ? .solo : .off)
        }
    }

    private func sendBatch(_ messages: [[UInt8]], cancellable: Bool = true, requiresActive: Bool = false) async throws {
        let destination = esOutput
        let source = esInput
        for packet in messages {
            if requiresActive && !active { throw operationError("Le contrôle MIDI a été suspendu.") }
            guard esOutput == destination, esInput == source,
                  destinations.contains(where: { $0.id == destination }),
                  sources.contains(where: { $0.id == source }) else {
                throw operationError("Connexion MIDI modifiée pendant l’envoi.")
            }
            if cancellable { try Task.checkCancellation() }
            try send(packet)
            // Pace SysEx traffic instead of flooding the module's command buffer.
            if cancellable { try await Task.sleep(nanoseconds: 2_000_000) }
            else { await pauseUncancelled() }
        }
    }

    private func pauseUncancelled() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { continuation.resume() }
        }
    }

    private func persistSoon() {
        persistenceTask?.cancel()
        persistenceTask = Task {
            do { try await Task.sleep(nanoseconds: 300_000_000) }
            catch { return }
            persistNow()
        }
    }

    private func persistNow() {
        do {
            try FileManager.default.createDirectory(at: sessionURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(session).write(to: sessionURL, options: .atomic)
        } catch { report(error) }
    }

    private func operationError(_ text: String) -> NSError {
        NSError(domain: "ES9Mixer", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func report(_ failure: Error) {
        error = failure.localizedDescription
    }
}

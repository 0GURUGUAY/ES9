import Foundation

public struct JackSend: Codable, Equatable {
    public var enabled: Bool
    public var level: Double

    public init(enabled: Bool = false, level: Double = 1) {
        self.enabled = enabled
        self.level = level
    }
}

public enum EQShape: String, Codable, Equatable {
    case peak, lowShelf, highShelf

    /// Filter type numbering of the ES-9 configuration tool 1.3.
    public var hardwareType: Int {
        switch self {
        case .lowShelf: return 4
        case .highShelf: return 5
        case .peak: return 6
        }
    }

    public var usesQ: Bool { self == .peak }
}

public struct EQBand: Codable, Equatable {
    public var shape: EQShape
    public var frequency: Double
    public var q: Double
    public var gain: Double

    public init(shape: EQShape = .peak, frequency: Double, q: Double = 0.707, gain: Double = 0) {
        self.shape = shape
        self.frequency = frequency
        self.q = q
        self.gain = gain
    }

    public static let frequencyLimits = 10.0...22000.0
    public static let qLimits = 0.1...18.0
    public static let gainLimits = -15.0...15.0
    /// The ES-9 limits high-shelf boosts to +12 dB.
    public static let highShelfMaximum = 12.0

    public var maximumGain: Double { shape == .highShelf ? Self.highShelfMaximum : Self.gainLimits.upperBound }

    public var isValid: Bool {
        frequency.isFinite && Self.frequencyLimits.contains(frequency)
        && q.isFinite && Self.qLimits.contains(q)
        && gain.isFinite && (Self.gainLimits.lowerBound...maximumGain).contains(gain)
    }
}

/// Three bands (low, mid, high) of the ES-9 native input EQ, applied before the mixer.
public struct ChannelEQ: Codable, Equatable {
    public var enabled: Bool
    public var bands: [EQBand]

    public init() {
        enabled = false
        bands = [EQBand(frequency: 100), EQBand(frequency: 1000), EQBand(frequency: 8000)]
    }

    public static let bandFrequencies: [ClosedRange<Double>] = [20...1000, 200...8000, 1000...20000]

    public var isValid: Bool {
        bands.count == 3 && bands.allSatisfy(\.isValid)
    }
}

public struct Channel: Codable, Equatable, Identifiable {
    public let id: Int
    public var name: String
    public var level: Double
    public var pan: Double
    public var muted: Bool
    public var soloed: Bool
    public var mainEnabled: Bool
    public var jackSends: [JackSend]
    /// Digital input gain in dB: the ES-9 has no analog preamp gain.
    public var trim: Double
    public var eq: ChannelEQ

    public static let trimLimits = -24.0...12.0

    /// Zero is the stereo main; 1...8 are the mono jack outputs.
    public var destinations: [Int] {
        (mainEnabled ? [0] : []) + jackSends.indices.filter { jackSends[$0].enabled }.map { $0 + 1 }
    }

    public init(id: Int) {
        self.id = id
        name = "Entrée \(id + 1)"
        level = 0.7
        pan = 0
        muted = false
        soloed = false
        mainEnabled = true
        jackSends = Array(repeating: JackSend(), count: 8)
        trim = 0
        eq = ChannelEQ()
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, level, pan, muted, soloed, destination, mainEnabled, jackSends, trim, eq
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        level = try values.decode(Double.self, forKey: .level)
        pan = try values.decode(Double.self, forKey: .pan)
        muted = try values.decode(Bool.self, forKey: .muted)
        soloed = try values.decodeIfPresent(Bool.self, forKey: .soloed) ?? false
        if values.contains(.mainEnabled) || values.contains(.jackSends) {
            mainEnabled = try values.decode(Bool.self, forKey: .mainEnabled)
            jackSends = try values.decode([JackSend].self, forKey: .jackSends)
        } else {
            let destination = try values.decode(Int.self, forKey: .destination)
            guard (0...8).contains(destination) else { throw MixerError.invalidSession }
            mainEnabled = destination == 0
            jackSends = (1...8).map { JackSend(enabled: $0 == destination) }
        }
        trim = try values.decodeIfPresent(Double.self, forKey: .trim) ?? 0
        eq = try values.decodeIfPresent(ChannelEQ.self, forKey: .eq) ?? ChannelEQ()
    }

    public var trimGain: Double { pow(10, trim / 20) }

    public static func signedDecibels(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(level, forKey: .level)
        try values.encode(pan, forKey: .pan)
        try values.encode(muted, forKey: .muted)
        try values.encode(soloed, forKey: .soloed)
        try values.encode(mainEnabled, forKey: .mainEnabled)
        try values.encode(jackSends, forKey: .jackSends)
        try values.encode(trim, forKey: .trim)
        try values.encode(eq, forKey: .eq)
    }

    public static func gain(_ level: Double) -> Double {
        level == 0 ? 0 : pow(10, (-60 + level * 60) / 20)
    }

    public static func decibels(_ level: Double) -> String {
        level == 0 ? "−∞ dB" : String(format: "%.1f dB", -60 + level * 60)
    }
}

public struct OutputChannel: Codable, Equatable, Identifiable {
    public let id: Int
    public var name: String
    public var level: Double
    public var muted: Bool
    public var soloed: Bool

    public init(id: Int) {
        self.id = id
        name = "Sortie \(id + 1)"
        level = 1
        muted = false
        soloed = false
    }
}

public struct Session: Codable, Equatable {
    public var channels: [Channel]
    public var outputs: [OutputChannel]
    public var routingLocked: Bool
    public var master: Double
    public var masterMuted: Bool
    public var mappings: [ControlMapping]
    public var headphonesEnabled: Bool
    public var headphonesLevel: Double
    public var muteAll: Bool

    public init() {
        channels = (0..<14).map(Channel.init)
        outputs = (0..<8).map(OutputChannel.init)
        routingLocked = true
        master = 0.8
        masterMuted = false
        mappings = []
        headphonesEnabled = false
        headphonesLevel = 42.0 / 72.0
        muteAll = false
    }

    private enum CodingKeys: String, CodingKey {
        case channels, outputs, routingLocked, master, masterMuted, mappings, headphonesEnabled, headphonesLevel, muteAll
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        channels = try values.decode([Channel].self, forKey: .channels)
        outputs = try values.decodeIfPresent([OutputChannel].self, forKey: .outputs)
            ?? (0..<8).map(OutputChannel.init)
        routingLocked = try values.decodeIfPresent(Bool.self, forKey: .routingLocked) ?? true
        master = try values.decode(Double.self, forKey: .master)
        masterMuted = try values.decodeIfPresent(Bool.self, forKey: .masterMuted) ?? false
        mappings = try values.decode([ControlMapping].self, forKey: .mappings)
        headphonesEnabled = try values.decodeIfPresent(Bool.self, forKey: .headphonesEnabled) ?? false
        headphonesLevel = try values.decodeIfPresent(Double.self, forKey: .headphonesLevel) ?? 42.0 / 72.0
        muteAll = try values.decodeIfPresent(Bool.self, forKey: .muteAll) ?? false
    }

    public static func headphonesGain(_ level: Double) -> Double {
        level == 0 ? 0 : pow(2, (-60 + level * 72) / 6)
    }

    public static func headphonesDecibels(_ level: Double) -> String {
        level == 0 ? "−∞ dB" : String(format: "%+.1f dB", -60 + level * 72)
    }

    public func inputIsAudible(_ index: Int) -> Bool {
        let channel = channels[index]
        return !muteAll && !channel.muted && (!channels.contains(where: \.soloed) || channel.soloed)
    }

    public func outputIsAudible(_ index: Int) -> Bool {
        let output = outputs[index]
        return !output.muted && (!outputs.contains(where: \.soloed) || output.soloed)
    }

    public func validate() throws {
        guard channels.count == 14, channels.map(\.id) == Array(0..<14),
              outputs.count == 8, outputs.map(\.id) == Array(0..<8),
              outputs.allSatisfy({ $0.level.isFinite && (0...1).contains($0.level) }),
              master.isFinite, (0...1).contains(master),
              headphonesLevel.isFinite, (0...1).contains(headphonesLevel),
              channels.allSatisfy({
                  $0.level.isFinite && (0...1).contains($0.level)
                  && $0.pan.isFinite && (-1...1).contains($0.pan)
                  && $0.jackSends.count == 8
                  && $0.jackSends.allSatisfy { $0.level.isFinite && (0...1).contains($0.level) }
                  && $0.trim.isFinite && Channel.trimLimits.contains($0.trim)
                  && $0.eq.isValid
              }),
              mappings.allSatisfy({ $0.isValid }),
              Set(mappings.map(\.action)).count == mappings.count,
              Set(mappings.map(\.signature)).count == mappings.count else {
            throw MixerError.invalidSession
        }
    }
}

public enum MixerError: LocalizedError {
    case invalidSession
    case invalidDump
    case invalidDSPUsage
    case unsupportedConfiguration(Int)
    case tooManyOutputs

    public var errorDescription: String? {
        switch self {
        case .invalidSession: return "Le fichier de session contient des réglages invalides."
        case .invalidDump: return "La réponse de configuration de l’ES-9 est incomplète ou invalide."
        case .invalidDSPUsage: return "La réponse de charge DSP de l’ES-9 est incomplète ou invalide."
        case .unsupportedConfiguration(let version):
            return "Format ES-9 \(version) non pris en charge. Cette version attend le format 3 (firmware 1.3)."
        case .tooManyOutputs:
            return "Routage impossible : chaque mélangeur dispose de huit sorties mono. Le général utilise deux sorties et le casque deux autres. Désactivez des liaisons ou l’envoi au général ; « Jacks uniquement » libère les huit sorties pour la matrice."
        }
    }
}

public struct DSPUsage: Equatable {
    public let first: Double
    public let second: Double?

    public init(packet: [UInt8]) throws {
        guard packet.count == 15, packet.starts(with: ES9.header + [0x12]),
              packet.last == 0xF7, packet[6..<14].allSatisfy({ $0 < 128 }) else {
            throw MixerError.invalidDSPUsage
        }
        let counters = stride(from: 6, to: 14, by: 2).map {
            (Int(packet[$0]) << 7) | Int(packet[$0 + 1])
        }
        func percentage(_ baseline: Int, _ used: Int) throws -> Double {
            guard baseline < 4096, used >= baseline else { throw MixerError.invalidDSPUsage }
            // Same available-cycle calculation as the official ES-9 configuration tool.
            return Double(used - baseline) * 100 / Double(4096 - baseline)
        }
        first = try percentage(counters[0], counters[1])
        second = counters[2] == 0 ? nil : try percentage(counters[2], counters[3])
    }
}

public enum ES9 {
    public static let header: [UInt8] = [0xF0, 0x00, 0x21, 0x27, 0x19]
    public static let analogInputs: [UInt8] =
        [0x78, 0x79, 0x76, 0x75, 0x74, 0x7B, 0x7A, 0x77, 0x73, 0x72, 0x7D, 0x7C, 0x7E, 0x7F]
    public static let jackOutputs: [UInt8] = [8, 9, 4, 5, 2, 3, 11, 10]
    public static let unusedOutput: UInt8 = 0x1F // Bus 16, never used as a source.
    public static let silentSource: UInt8 = 0x6E // Bus 15, never assigned an output.
    public static let usbPlaybackOutputs: [UInt8] =
        [6, 7, 12, 13, unusedOutput, unusedOutput, unusedOutput, unusedOutput] + jackOutputs

    public static func message(_ command: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        header + [command] + payload + [0xF7]
    }

    public static var dspUsageRequest: [UInt8] { message(0x2B) }

    public static func word(_ value: Int) -> [UInt8] {
        [UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    public static func mix(_ row: Int, _ column: Int, _ value: Int) -> [UInt8] {
        message(UInt8(0x60 + row), [UInt8(column)] + word(value))
    }

    public static func configurationWords(_ packet: [UInt8]) throws -> [Int] {
        guard packet.count >= 9, Array(packet.prefix(6)) == header + [0x08],
              packet[6] == 0, packet[7] == 0, packet.last == 0xF7,
              (packet.count - 9).isMultiple(of: 3),
              packet[8..<(packet.count - 1)].allSatisfy({ $0 < 128 }) else {
            throw MixerError.invalidDump
        }
        let words: [Int] = stride(from: 8, to: packet.count - 1, by: 3).map { index in
            let high = Int(packet[index]) << 14
            let middle = Int(packet[index + 1]) << 7
            let low = Int(packet[index + 2])
            return high | middle | low
        }
        guard let version = words.first else { throw MixerError.invalidDump }
        guard version == 3 else { throw MixerError.unsupportedConfiguration(version) }
        guard words.count >= 719 else { throw MixerError.invalidDump }
        return words
    }

    public static func restore(_ dump: [UInt8]) throws -> [[UInt8]] {
        var words = try configurationWords(dump)
        guard words.count <= 768 else { throw MixerError.invalidDump }
        words += Array(repeating: 0, count: 768 - words.count)
        return (0..<24).map { block in
            let start = block * 32
            let payload = words[start..<(start + 32)].flatMap { word($0) }
            return message(0x09, [UInt8(block), 0] + payload)
        }
    }

    public static func setup(_ dump: [UInt8]) throws -> [[UInt8]] {
        let words = try configurationWords(dump)
        var packets: [[UInt8]] = []
        // Silence the matrices before changing any of their output destinations.
        for row in 0..<16 {
            for column in 0..<8 { packets.append(mix(row, column, 0)) }
        }
        packets.append(message(0x32, [UInt8((words[450] & 2) | 1)]))
        packets.append(message(0x35, [0, 0]))
        packets.append(message(0x31, [0x7F]))
        for link in Array(0..<7) + Array(8..<32) {
            packets.append(message(0x33, [UInt8(link), 0]))
        }
        for row in 0..<16 { packets.append(message(0x3A, [UInt8(row), 1])) }
        // The 64 input EQ filters are written afterwards by RoutingPlan.messages(from: nil).
        for output in 0..<8 {
            packets.append(message(0x36, [UInt8(output), 0, 0, 0]))
        }
        // USB playback bypasses the analog mixer; shared output destinations sum both signals.
        packets.append(message(0x40, Array(analogInputs.prefix(8))))
        packets.append(message(0x41, Array(analogInputs.suffix(6)) + [silentSource, silentSource]))
        for dsp: UInt8 in [0, 1] {
            let start = Int(dsp) * 8
            packets.append(message(0x50 + dsp, Array(usbPlaybackOutputs[start..<(start + 8)])))
        }
        for mixer in 0..<2 {
            let inputs = Array(analogInputs[(mixer * 7)..<(mixer * 7 + 7)]) + [silentSource]
            packets.append(message(UInt8(0x42 + mixer), inputs))
        }
        return packets
    }
}

public enum ES9EQ {
    /// Configuration words 462..<718: 2 mixers × 8 inputs × 4 filters × (type, freq, Q, gain).
    public static let firstWord = 462
    public static let filterCount = 64

    public static func frequencyWord(_ hertz: Double) -> Int {
        clamp(log(hertz / 10) / log(22000.0 / 10) * 32767)
    }

    public static func qWord(_ q: Double) -> Int {
        clamp(log(q / 0.1) / log(18.0 / 0.1) * 32767)
    }

    /// Signed 16-bit value, ±15 dB full scale.
    public static func gainWord(_ decibels: Double) -> Int {
        Int((decibels * 32767 / 15).rounded()) & 0xFFFF
    }

    public static let disabledFilter = [EQShape.peak.hardwareType << 1, frequencyWord(1000), qWord(0.707), 0]

    public static func filterWords(_ band: EQBand, enabled: Bool) -> [Int] {
        [(band.shape.hardwareType << 1) | (enabled ? 1 : 0),
         frequencyWord(band.frequency), qWord(band.q), gainWord(min(band.gain, band.maximumGain))]
    }

    /// Same addressing as the official tool: mixer input 8 × mixer + column, then filter 0...3.
    public static func message(slot: Int, words: [Int]) -> [UInt8] {
        ES9.message(0x39, [UInt8(slot / 4), UInt8(slot % 4), UInt8(words[0] & 0x7F)]
            + ES9.word(words[1]) + ES9.word(words[2]) + ES9.word(words[3]))
    }

    private static func clamp(_ value: Double) -> Int {
        Int(min(32767, max(0, value.rounded())))
    }
}

public struct RoutingPlan: Equatable {
    public var inputs: [[UInt8]]
    public var outputs: [[UInt8]]
    public var coefficients: [[Int]]
    public var filters: [[Int]]

    public init(_ session: Session) throws {
        try session.validate()
        let groups = try Self.channelGroups(session)
        inputs = groups.map {
            $0.map { ES9.analogInputs[$0] } + Array(repeating: ES9.silentSource, count: 8 - $0.count)
        }
        outputs = []
        coefficients = Array(repeating: Array(repeating: 0, count: 8), count: 16)
        filters = Array(repeating: ES9EQ.disabledFilter, count: ES9EQ.filterCount)
        for (block, group) in groups.enumerated() {
            for (column, index) in group.enumerated() {
                let eq = session.channels[index].eq
                for (band, settings) in eq.bands.enumerated() {
                    filters[block * 32 + column * 4 + band] = ES9EQ.filterWords(settings, enabled: eq.enabled)
                }
            }
        }
        for block in 0..<2 {
            let channels = groups[block].map { session.channels[$0] }
            let destinations = Set(channels.flatMap(\.destinations)).sorted()
            var route: [UInt8] = []
            var rows: [Int: [Int]] = [:]
            var headphoneRows: [Int] = []
            for destination in destinations {
                if destination == 0 {
                    rows[0] = [route.count, route.count + 1]
                    route += [6, 7]
                } else {
                    rows[destination] = [route.count]
                    route.append(ES9.jackOutputs[destination - 1])
                }
            }
            if session.headphonesEnabled && rows[0] != nil {
                headphoneRows = [route.count, route.count + 1]
                route += [12, 13]
            }
            guard route.count <= 8 else { throw MixerError.tooManyOutputs }
            outputs.append(route + Array(repeating: ES9.unusedOutput, count: 8 - route.count))
            for (column, channel) in channels.enumerated() {
                guard session.inputIsAudible(groups[block][column]) else { continue }
                let gain = Channel.gain(channel.level) * channel.trimGain
                if channel.mainEnabled, let target = rows[0] {
                    let angle = (channel.pan + 1) * .pi / 4
                    let mainGain = session.masterMuted ? 0 : gain * Channel.gain(session.master)
                    coefficients[block * 8 + target[0]][column] = Self.coefficient(mainGain * cos(angle))
                    coefficients[block * 8 + target[1]][column] = Self.coefficient(mainGain * sin(angle))
                    if !headphoneRows.isEmpty {
                        let headphoneGain = gain * Session.headphonesGain(session.headphonesLevel)
                        for (side, balance) in [cos(angle), sin(angle)].enumerated() {
                            coefficients[block * 8 + headphoneRows[side]][column] =
                                Self.coefficient(headphoneGain * balance)
                        }
                    }
                }
                for outputIndex in 0..<8 where channel.jackSends[outputIndex].enabled {
                    if session.outputIsAudible(outputIndex), let target = rows[outputIndex + 1] {
                        let outputGain = Channel.gain(session.outputs[outputIndex].level)
                        let sendGain = Channel.gain(channel.jackSends[outputIndex].level)
                        coefficients[block * 8 + target[0]][column] =
                            Self.coefficient(gain * sendGain * outputGain)
                    }
                }
            }
        }
    }

    /// 8192 is unity gain; the ES-9 accepts up to 32767 (about +12 dB).
    private static func coefficient(_ gain: Double) -> Int {
        min(32767, Int((8192 * gain).rounded()))
    }

    private static func channelGroups(_ session: Session) throws -> [[Int]] {
        func fits(_ indices: [Int]) -> Bool {
            let destinations = Set(indices.flatMap { session.channels[$0].destinations })
            let stereoOutputs = destinations.contains(0) ? (session.headphonesEnabled ? 4 : 2) : 0
            return destinations.filter { $0 != 0 }.count + stereoOutputs <= 8
        }
        let standard = [Array(0..<7), Array(7..<14)]
        if standard.allSatisfy(fits) { return standard }
        // Keep muted and zero-gain routes allocated, so level changes never reroute hardware.
        for mask in 0..<(1 << 14) where mask & 1 != 0 && (6...8).contains(mask.nonzeroBitCount) {
            let first = (0..<14).filter { mask & (1 << $0) != 0 }
            let second = (0..<14).filter { mask & (1 << $0) == 0 }
            if fits(first) && fits(second) { return [first, second] }
        }
        throw MixerError.tooManyOutputs
    }

    public func messages(from old: RoutingPlan?) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        let inputsChanged = old == nil || old?.inputs != inputs
        if inputsChanged {
            for row in 0..<16 {
                for column in 0..<8 { packets.append(ES9.mix(row, column, 0)) }
            }
        }
        for block in 0..<2 {
            let changed = inputsChanged || old?.outputs[block] != outputs[block]
            if changed {
                if !inputsChanged {
                    for row in (block * 8)..<(block * 8 + 8) {
                        for column in 0..<8 { packets.append(ES9.mix(row, column, 0)) }
                    }
                } else {
                    packets.append(ES9.message(UInt8(0x42 + block), inputs[block]))
                }
                packets.append(ES9.message(UInt8(0x52 + block), outputs[block]))
            }
            for slot in (block * 32)..<(block * 32 + 32) where old?.filters[slot] != filters[slot] {
                packets.append(ES9EQ.message(slot: slot, words: filters[slot]))
            }
            for row in (block * 8)..<(block * 8 + 8) {
                for column in 0..<8 where changed || old?.coefficients[row][column] != coefficients[row][column] {
                    packets.append(ES9.mix(row, column, coefficients[row][column]))
                }
            }
        }
        return packets
    }
}

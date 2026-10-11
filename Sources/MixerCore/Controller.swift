import Foundation

public enum StripTarget: Equatable {
    case input(Int)
    case output(Int)
}

public enum ControllerBank: Int, CaseIterable {
    case inputs1, inputs2, outputs

    public var label: String {
        switch self {
        case .inputs1: return "Entrées 1–8"
        case .inputs2: return "Entrées 9–14"
        case .outputs: return "Sorties 1–8"
        }
    }

    public func target(_ slot: Int) -> StripTarget? {
        guard (0..<8).contains(slot) else { return nil }
        switch self {
        case .inputs1: return .input(slot)
        case .inputs2: return slot < 6 ? .input(slot + 8) : nil
        case .outputs: return .output(slot)
        }
    }
}

public enum ControllerFader {
    // Keep fine attenuation at the bottom and a linear gain above 40% travel.
    public static func level(at position: Double, range: Double = 60) -> Double {
        guard position > 0 else { return 0 }
        let attenuation: Double
        if position < 0.4 {
            attenuation = -range + position / 0.4 * (range - 20)
        } else {
            let gain = 0.1 + (position - 0.4) / 0.6 * 0.9
            attenuation = 20 * log10(gain)
        }
        return min(1, max(0, (attenuation + range) / range))
    }

    public static func position(for level: Double, range: Double = 60) -> Double {
        guard level > 0 else { return 0 }
        let attenuation = (level - 1) * range
        if attenuation < -20 {
            return level * range / (range - 20) * 0.4
        }
        return min(1, 0.4 + (pow(10, attenuation / 20) - 0.1) / 0.9 * 0.6)
    }
}

public struct ControlMapping: Codable, Equatable {
    public var action: String
    public var status: UInt8
    public var number: UInt8

    public init(action: String, status: UInt8, number: UInt8) {
        self.action = action
        self.status = status
        self.number = number
    }

    public var signature: Int { Int(status) * 128 + Int(number) }
    public var isValid: Bool {
        Self.actions.contains(action) && number < 128
        && ((status & 0xF0) == 0xB0 || (status & 0xF0) == 0x90)
        && (!Self.isContinuous(action) || (status & 0xF0) == 0xB0)
    }

    public static func isContinuous(_ action: String) -> Bool {
        action.hasPrefix("fader") || action.hasPrefix("pan") || action == "master" || action == "headphones"
    }

    public static let actions = (0..<8).map { "fader\($0)" }
        + (0..<8).map { "mute\($0)" }
        + (0..<8).map { "solo\($0)" }
        + (0..<8).map { "pan\($0)" }
        + ["master", "headphones", "previous", "next"]

    public static func label(_ action: String) -> String {
        for (prefix, name) in [("fader", "Fader"), ("mute", "Mute"), ("solo", "Solo"), ("pan", "Pan")] {
            if action.hasPrefix(prefix), let index = Int(action.dropFirst(prefix.count)) {
                return "\(name) \(index + 1)"
            }
            if action == "master" { return "Général" }
            if action == "headphones" { return "Casque" }
        }
        return action == "previous" ? "Banque précédente" : "Banque suivante"
    }
}

public enum ControllerLED {
    public enum State {
        case off
        case mute
        case solo
    }

    public static func message(for mapping: ControlMapping, state: State) -> [UInt8] {
        let velocity: UInt8
        switch state {
        case .off: velocity = 12
        case .mute: velocity = 15
        case .solo: velocity = 60
        }
        return [0x90 | (mapping.status & 0x0F), mapping.number, velocity]
    }
}

public struct Pickup {
    private var previous: [String: Double] = [:]
    private var caught: Set<String> = []
    public init() {}

    public mutating func reset() {
        previous.removeAll()
        caught.removeAll()
    }

    public mutating func reset(_ action: String) {
        previous.removeValue(forKey: action)
        caught.remove(action)
    }

    public mutating func accepts(_ action: String, value: Double, target: Double) -> Bool {
        defer { previous[action] = value }
        if caught.contains(action) { return true }
        let close = abs(value - target) <= 2.0 / 127
        let crossed = previous[action].map { (value - target) * ($0 - target) <= 0 } ?? false
        if close || crossed {
            caught.insert(action)
            return true
        }
        return false
    }
}

/// MIDI packets can split SysEx and can contain several running-status CC messages.
public struct MIDIParser {
    private var sysex: [UInt8] = []
    private var status: UInt8?
    private var data: [UInt8] = []
    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 {
                sysex = [byte]; status = nil; data = []
            } else if !sysex.isEmpty {
                if byte == 0xF7 {
                    sysex.append(byte); messages.append(sysex); sysex = []
                } else if byte < 128 && sysex.count < 65536 {
                    sysex.append(byte)
                } else {
                    sysex = []; status = nil; data = []
                }
            } else if byte >= 0x80 {
                status = byte < 0xF0 ? byte : nil
                data = []
            } else if let current = status {
                data.append(byte)
                let required = [0xC0, 0xD0].contains(current & 0xF0) ? 1 : 2
                if data.count == required {
                    messages.append([current] + data)
                    data = []
                }
            }
        }
        return messages
    }
}

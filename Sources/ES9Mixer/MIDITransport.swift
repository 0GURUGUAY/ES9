import CoreMIDI
import Foundation

struct MIDIEndpoint: Identifiable, Equatable {
    let id: MIDIEndpointRef
    let name: String
}

enum MIDIError: LocalizedError {
    case operation(String, OSStatus)
    case noDestination
    var errorDescription: String? {
        switch self {
        case .operation(let name, let status): return "\(name) : erreur CoreMIDI \(status)."
        case .noDestination: return "Aucune sortie MIDI ES-9 sélectionnée."
        }
    }
}

final class MIDITransport {
    private var client: MIDIClientRef = 0
    private var input: MIDIPortRef = 0
    private var output: MIDIPortRef = 0
    private var connected: Set<MIDIEndpointRef> = []
    var onBytes: ((MIDIEndpointRef, [UInt8]) -> Void)?
    var onChange: (() -> Void)?
    var onError: ((Error) -> Void)?

    init() throws {
        try check(MIDIClientCreateWithBlock("ES9 Mixer" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.onChange?() }
        }, "Création du client MIDI")
        do {
            try check(MIDIInputPortCreateWithBlock(client, "Entrées" as CFString, &input) { [weak self] list, context in
                let source = MIDIEndpointRef(UInt(bitPattern: context))
                let offset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
                var packet = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: MIDIPacket.self)
                for _ in 0..<list.pointee.numPackets {
                    let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
                    let data = UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
                    let bytes = Array(UnsafeBufferPointer(start: data, count: Int(packet.pointee.length)))
                    DispatchQueue.main.async { self?.onBytes?(source, bytes) }
                    packet = UnsafePointer(MIDIPacketNext(packet))
                }
            }, "Création du port d’entrée")
            try check(MIDIOutputPortCreate(client, "Sorties" as CFString, &output), "Création du port de sortie")
        } catch {
            MIDIClientDispose(client)
            throw error
        }
    }

    deinit {
        MIDIPortDispose(input)
        MIDIPortDispose(output)
        MIDIClientDispose(client)
    }

    func sources() -> [MIDIEndpoint] {
        (0..<MIDIGetNumberOfSources()).map { endpoint(MIDIGetSource($0)) }.filter { $0.id != 0 }
    }

    func destinations() -> [MIDIEndpoint] {
        (0..<MIDIGetNumberOfDestinations()).map { endpoint(MIDIGetDestination($0)) }.filter { $0.id != 0 }
    }

    func subscribe(to sources: [MIDIEndpoint]) throws {
        let wanted = Set(sources.map(\.id))
        for source in connected.subtracting(wanted) {
            // Removed endpoints may already have been disposed by CoreMIDI.
            if sourcesForSystem().contains(source) {
                try check(MIDIPortDisconnectSource(input, source), "Déconnexion MIDI")
            }
            connected.remove(source)
        }
        for source in wanted.subtracting(connected) {
            try check(MIDIPortConnectSource(input, source, UnsafeMutableRawPointer(bitPattern: UInt(source))),
                      "Connexion MIDI")
            connected.insert(source)
        }
    }

    func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) throws {
        guard destination != 0 else { throw MIDIError.noDestination }
        guard !bytes.isEmpty, bytes.count <= Int(UInt16.max) else {
            throw MIDIError.operation("Taille de paquet MIDI invalide", -1)
        }
        let capacity = max(MemoryLayout<MIDIPacketList>.size, bytes.count + 64)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(list)
        _ = bytes.withUnsafeBufferPointer {
            MIDIPacketListAdd(list, capacity, packet, 0, bytes.count, $0.baseAddress!)
        }
        try check(MIDISend(output, destination, list), "Envoi MIDI")
    }

    private func sourcesForSystem() -> Set<MIDIEndpointRef> {
        Set((0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) })
    }

    private func endpoint(_ ref: MIDIEndpointRef) -> MIDIEndpoint {
        var value: Unmanaged<CFString>?
        let result = MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &value)
        let name = result == noErr ? value?.takeRetainedValue() as String? : nil
        return MIDIEndpoint(id: ref, name: name ?? "Port MIDI \(ref)")
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw MIDIError.operation(operation, status) }
    }
}

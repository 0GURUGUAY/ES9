import CoreMIDI
import Foundation

func require(_ result: OSStatus, _ operation: String) {
    if result != noErr {
        fputs("FAIL \(operation): CoreMIDI \(result)\n", stderr)
        exit(1)
    }
}

var client: MIDIClientRef = 0
var source: MIDIEndpointRef = 0
var destination: MIDIEndpointRef = 0
require(MIDIClientCreateWithBlock("ES9Mixer validation" as CFString, &client, { _ in }), "client")
require(MIDISourceCreate(client, "ES9Mixer virtual source" as CFString, &source), "source")
require(MIDIDestinationCreateWithBlock(client, "ES9Mixer virtual destination" as CFString, &destination) { list, _ in
    require(MIDIReceived(source, list), "virtual loopback")
}, "destination")

let transport: MIDITransport
do { transport = try MIDITransport() }
catch {
    fputs("FAIL \(error.localizedDescription)\n", stderr)
    exit(1)
}

let sysex: [UInt8] = [0xF0, 0, 0x21, 0x27, 0x19, 0x08, 0, 0]
    + (0..<2157).map { UInt8($0 % 128) } + [0xF7]
let controls: [UInt8] = [0xB0, 13, 127, 0xB0, 14, 64]
let expected = sysex + controls
var received: [UInt8] = []
transport.onBytes = { endpoint, bytes in
    guard endpoint == source else {
        fputs("FAIL Unexpected MIDI source\n", stderr)
        exit(1)
    }
    received += bytes
    if received.count >= expected.count {
        guard received == expected else {
            fputs("FAIL MIDI payload was truncated or corrupted\n", stderr)
            exit(1)
        }
        print("PASS CoreMIDI virtual loopback: \(sysex.count)-byte SysEx and two CC messages, exact payload.")
        MIDIEndpointDispose(destination)
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
        exit(0)
    }
}

do {
    try transport.subscribe(to: [MIDIEndpoint(id: source, name: "Validation")])
    try transport.send(sysex, to: destination)
    try transport.send(controls, to: destination)
} catch {
    fputs("FAIL \(error.localizedDescription)\n", stderr)
    exit(1)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    fputs("FAIL MIDI timeout: received \(received.count) of \(expected.count) bytes\n", stderr)
    exit(1)
}
dispatchMain()

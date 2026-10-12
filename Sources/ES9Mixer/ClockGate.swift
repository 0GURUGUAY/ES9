import AudioToolbox
import CoreAudio
import Foundation
import GateState

enum ClockGateError: LocalizedError {
    case noDevice
    case operation(String, OSStatus)
    case channelCount(UInt32)

    var errorDescription: String? {
        switch self {
        case .noDevice: return "GATE Pamela : aucun périphérique audio ES-9 trouvé."
        case .operation(let operation, let status):
            return "GATE Pamela : \(operation) (CoreAudio \(status))."
        case .channelCount(let count):
            return "GATE Pamela : l’ES-9 doit exposer 16 sorties USB, mais \(count) ont été trouvées."
        }
    }
}

/// USB 16 is reserved for OUT 8. Other USB channels receive silence from this client.
final class ClockGate {
    private var unit: AudioUnit?
    private var state: OpaquePointer?
    private var running = false

    static let render: AURenderCallback = { context, _, _, _, _, data in
        guard let data else { return kAudio_ParamError }
        let state = OpaquePointer(context)
        let high = ES9GateStateGet(state)
        fillGateBuffers(data, high: high)
        if !high { ES9GateStateAcknowledgeLow(state) }
        return noErr
    }

    static func fillGateBuffers(_ data: UnsafeMutablePointer<AudioBufferList>, high: Bool) {
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        for (channel, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let value: Float = channel == 15 && high ? 0.5 : 0
            for sample in 0..<count { samples[sample] = value }
        }
    }

    deinit {
        do {
            try close()
        } catch {
            NSLog("ES9Mixer: %@", error.localizedDescription)
        }
    }

    func start() throws {
        if let state {
            guard running else {
                throw ClockGateError.operation("générateur indisponible après une erreur CoreAudio",
                                               kAudioUnitErr_Uninitialized)
            }
            ES9GateStateSet(state, true)
            return
        }
        let device = try Self.es9Device()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try Self.check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "lecture des sorties")
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try Self.check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage), "lecture des sorties")
        let count = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(UInt32(0)) { $0 + $1.mNumberChannels }
        guard count == 16 else { throw ClockGateError.channelCount(count) }

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw ClockGateError.operation("AudioUnit HAL introuvable", kAudio_ParamError)
        }
        var created: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &created), "création du générateur")
        guard let created else { throw ClockGateError.operation("création du générateur", kAudio_ParamError) }
        guard let state = ES9GateStateCreate() else {
            AudioComponentInstanceDispose(created)
            throw ClockGateError.operation("allocation du gate", kAudio_MemFullError)
        }
        do {
            var inputEnabled: UInt32 = 0
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input, 1, &inputEnabled, 4), "désactivation de l’entrée audio")
            var selectedDevice = device
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &selectedDevice, 4), "sélection de l’ES-9")
            var format = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(created, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output, 0, &format, &formatSize), "lecture du format audio")
            format = AudioStreamBasicDescription(
                mSampleRate: format.mSampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: 16, mBitsPerChannel: 32, mReserved: 0)
            try Self.check(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input, 0, &format, formatSize), "configuration des 16 sorties")
            var callback = AURenderCallbackStruct(
                inputProc: Self.render, inputProcRefCon: UnsafeMutableRawPointer(state))
            try Self.check(AudioUnitSetProperty(created, kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
                "configuration du gate")
            try Self.check(AudioUnitInitialize(created), "initialisation du gate")
            ES9GateStateSet(state, true)
            try Self.check(AudioOutputUnitStart(created), "démarrage du gate")
            unit = created
            self.state = state
            running = true
        } catch {
            ES9GateStateSet(state, false)
            let disposed = AudioComponentInstanceDispose(created)
            if disposed == noErr {
                ES9GateStateDestroy(state)
            } else {
                unit = created
                self.state = state
                throw ClockGateError.operation("libération après erreur", disposed)
            }
            throw error
        }
    }

    func stop() {
        if let state { ES9GateStateSet(state, false) }
    }

    func close() throws {
        guard let unit, let state else { return }
        ES9GateStateSet(state, false)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while !ES9GateStateLowRendered(state) && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        let renderedLow = ES9GateStateLowRendered(state)
        let stopped = AudioOutputUnitStop(unit)
        let disposed = AudioComponentInstanceDispose(unit)
        try Self.check(disposed, "libération du générateur")
        self.unit = nil
        self.state = nil
        running = false
        ES9GateStateDestroy(state)
        try Self.check(stopped, "arrêt du générateur")
        guard renderedLow else {
            throw ClockGateError.operation("niveau bas non confirmé par le moteur audio", kAudioUnitErr_CannotDoInCurrentContext)
        }
    }

    private static func es9Device() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size), "liste des périphériques")
        var devices = Array(repeating: AudioDeviceID(0), count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &devices), "liste des périphériques")
        for device in devices {
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            try check(AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name),
                      "nom du périphérique")
            if let name, (name.takeRetainedValue() as String).localizedCaseInsensitiveContains("ES-9") {
                return device
            }
        }
        throw ClockGateError.noDevice
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw ClockGateError.operation(operation, status) }
    }
}

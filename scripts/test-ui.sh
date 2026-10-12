#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target MixerCore
swift build --target GateState
BIN_DIR="$(swift build --show-bin-path)"
swiftc -D MIXER_UI_TESTS -target "$(uname -m)-apple-macosx13.0" \
    -I "$BIN_DIR/Modules" -I "$BIN_DIR/GateState.build" -I Sources/GateState/include \
    "$BIN_DIR/GateState.build/GateState.c.o" \
    "$BIN_DIR/MixerCore.build/Controller.swift.o" \
    "$BIN_DIR/MixerCore.build/Mixer.swift.o" \
    Sources/ES9Mixer/MIDITransport.swift \
    Sources/ES9Mixer/ClockGate.swift \
    Sources/ES9Mixer/MixerStore.swift \
    Sources/ES9Mixer/ContentView.swift \
    Sources/ES9Mixer/StripView.swift \
    Tests/MixerUIIntegration/main.swift \
    -o "$BIN_DIR/MixerUIIntegration"
"$BIN_DIR/MixerUIIntegration"

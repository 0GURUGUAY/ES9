#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/ES9Mixer/MIDITransport.swift Tests/MIDIIntegration/main.swift -o .build/MIDIIntegration
.build/MIDIIntegration

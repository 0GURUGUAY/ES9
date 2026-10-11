import Foundation

// A dependency-free runner also works with Apple's Command Line Tools, without Xcode/XCTest.
var failures = 0
var assertions = 0

func failure(_ message: String, _ file: StaticString, _ line: UInt) {
    failures += 1
    print("FAIL \(file):\(line): \(message)")
}

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    if actual != expected { failure("\(actual) != \(expected)", file, line) }
}

func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double,
                    file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    if !actual.isFinite || abs(actual - expected) > accuracy {
        failure("\(actual) != \(expected) ± \(accuracy)", file, line)
    }
}

func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    if !value { failure("Expected true", file, line) }
}

func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(!value, file: file, line: line)
}

func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                            file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do {
        _ = try expression()
        failure("Expected an error", file, line)
    } catch {
        // The error is the required result of this negative test.
    }
}

let suite = MixerCoreTests()
let tests: [(String, () throws -> Void)] = [
    ("Master mute isolates main mix and preserves session state", suite.testMasterMuteIsIndependent),
    ("Mute all preserves routing, individual mutes, solos and session state", suite.testMuteAllPreservesIndividualStateAndRouting),
    ("DSP usage request, decoding and fragmented response", suite.testDSPUsageProtocol),
    ("Stereo mix and master", suite.testDefaultStereoMixAndMaster),
    ("Stereo plus six mono outputs", suite.testSevenInputsCoverStereoAndSixMonoOutputs),
    ("Every destination subset", suite.testEveryPossibleDestinationSubsetFits),
    ("Jack mapping and exclusivity", suite.testJackMappingAndExclusiveDestinations),
    ("Input 1 to output 1 hardware route", suite.testInputOneToOutputOneHardwareRoute),
    ("Mute and pan", suite.testMuteAndPanExtremes),
    ("Headphone mix and independent level", suite.testHeadphoneMixAndIndependentLevel),
    ("Headphone allocation and safe rerouting", suite.testHeadphoneAllocationAndRerouting),
    ("Headphone session migration", suite.testHeadphoneSessionMigration),
    ("Level deltas", suite.testDeltaOnlySendsChangedLevels),
    ("Safe rerouting order", suite.testReroutingSilencesBeforeChangingOutput),
    ("SysEx encoding and setup", suite.testProtocolValuesAndSetup),
    ("USB direct playback and preserved capture", suite.testUSBPlaybackDirectRouting),
    ("Dump validation and restoration", suite.testDumpValidationAndRestore),
    ("Session validation", suite.testSessionValidationAndRoundTrip),
    ("Fader pickup", suite.testPickupCrossingAndBankReset),
    ("MIDI fader curve and physical pickup", suite.testControllerFaderCurveAndPickup),
    ("MIDI packet parser", suite.testMIDIFragmentationRunningStatusAndRealtime),
    ("Controller mapping", suite.testNoteCannotBeLearnedAsFader),
    ("Controller LED messages", suite.testControllerLEDMessages),
    ("Output faders, mute, solo and independent buses", suite.testOutputFadersMuteSoloAndIndependentBuses),
    ("Input solos across mixers and mute priority", suite.testInputSoloAcrossMixersAndMutePriority),
    ("Combined input and output gain", suite.testCombinedInputAndOutputGain),
    ("Mixer session migration and output validation", suite.testMixerSessionMigrationAndOutputValidation),
    ("Controller output bank and new mappings", suite.testControllerOutputBankAndNewMappings),
    ("Full matrix: 112 simultaneous connections", suite.testFullMatrixAll112Connections),
    ("Matrix independent sends and buses", suite.testMatrixIndependentSendsAndBuses),
    ("Matrix gains preserve routing", suite.testMatrixGainDeltasKeepRoutingAllocated),
    ("Matrix capacity and redistribution", suite.testMatrixCapacityAndRedistribution),
    ("Matrix legacy migration and persistence", suite.testMatrixLegacyMigrationAndRoundTrip),
    ("Matrix validation and disconnected inputs", suite.testMatrixSendValidationAndDisconnectedInput),
    ("Strip EQ encoding and addressing", suite.testStripEQEncodingAndAddressing),
    ("Strip EQ follows redistributed inputs", suite.testStripEQFollowsRedistributedInput),
    ("Strip trim gain and session migration", suite.testStripTrimGainAndMigration)
]

for (name, test) in tests {
    let before = failures
    do { try test() }
    catch { failure(error.localizedDescription, #filePath, #line) }
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
print("\(tests.count) tests, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)

import XCTest
@testable import ProprioCore

final class ProprioCoreTests: XCTestCase {
    func testMotionAnalyzerInitialization() throws {
        let analyzer = MotionAnalyzer()
        XCTAssertNotNil(analyzer, "MotionAnalyzer should be initialized")
        XCTAssertEqual(analyzer.tremorAmplitude, 0.0, "Initial tremor amplitude should be 0.0")
        XCTAssertEqual(analyzer.gaitStabilityIndex, 1.0, "Initial gait stability should be 1.0")
        XCTAssertFalse(analyzer.isActive, "Analyzer should not be active initially")
        XCTAssertNil(analyzer.lastError, "No error should be present initially")
    }

    func testMotionAnalyzerStartStop() throws {
        let analyzer = MotionAnalyzer()

        analyzer.startAnalysis()
        // startAnalysis dispatches to main queue, so we need to wait
        let startExpectation = expectation(description: "Analyzer becomes active")
        DispatchQueue.main.async {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)
        XCTAssertTrue(analyzer.isActive, "Analyzer should be active after startAnalysis()")

        analyzer.stopAnalysis()
        let stopExpectation = expectation(description: "Analyzer becomes inactive")
        DispatchQueue.main.async {
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 1.0)
        XCTAssertFalse(analyzer.isActive, "Analyzer should be inactive after stopAnalysis()")
    }

    func testHapticControllerInitialization() throws {
        let controller = HapticController()
        XCTAssertNotNil(controller, "HapticController should be initialized")
        XCTAssertFalse(controller.isPlayingEntrainment, "Entrainment should not be playing initially")
        XCTAssertEqual(controller.rhythmBpm, 60.0, "Default BPM should be 60.0")
    }

    func testHapticControllerBpmRange() throws {
        let controller = HapticController()
        controller.rhythmBpm = 120.0
        XCTAssertEqual(controller.rhythmBpm, 120.0, "BPM should be settable to 120")
        controller.rhythmBpm = 40.0
        XCTAssertEqual(controller.rhythmBpm, 40.0, "BPM should be settable to 40")
    }

    func testHapticErrorDescriptions() throws {
        let engineError = HapticError.engineNotSupported
        XCTAssertNotNil(engineError.errorDescription, "Engine error should have a description")
        XCTAssertTrue(engineError.errorDescription!.contains("not supported"))

        let patternError = HapticError.patternFailed(NSError(domain: "test", code: 1))
        XCTAssertNotNil(patternError.errorDescription, "Pattern error should have a description")
        XCTAssertTrue(patternError.errorDescription!.contains("Failed to play"))
    }

    func testMotionAnalysisErrorDescriptions() throws {
        let cameraError = MotionAnalysisError.cameraUnavailable
        XCTAssertNotNil(cameraError.errorDescription)
        XCTAssertTrue(cameraError.errorDescription!.contains("Camera"))

        let lowConfidence = MotionAnalysisError.lowConfidence
        XCTAssertNotNil(lowConfidence.errorDescription)
        XCTAssertTrue(lowConfidence.errorDescription!.contains("confidence"))

        let visionError = MotionAnalysisError.visionRequestFailed(NSError(domain: "test", code: 1))
        XCTAssertNotNil(visionError.errorDescription)
        XCTAssertTrue(visionError.errorDescription!.contains("Vision"))
    }
}

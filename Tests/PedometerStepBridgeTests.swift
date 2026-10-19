import XCTest
@testable import NavigationApp

final class PedometerStepBridgeTests: XCTestCase {
    func testConsumeEmitsOneEventPerNewStep() {
        var bridge = PedometerStepBridge()
        let first = bridge.consume(totalSteps: 3, timestamp: 1.0)
        XCTAssertEqual(first.count, 3)
        XCTAssertTrue(first.allSatisfy { $0.confidence == 1.0 })
        XCTAssertTrue(first.allSatisfy { $0.timestamp == 1.0 })
        XCTAssertEqual(bridge.lastTotalSteps, 3)

        let second = bridge.consume(totalSteps: 5, timestamp: 2.5)
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(bridge.lastTotalSteps, 5)
    }

    func testUnchangedTotalEmitsNothing() {
        var bridge = PedometerStepBridge()
        _ = bridge.consume(totalSteps: 2, timestamp: 0)
        XCTAssertTrue(bridge.consume(totalSteps: 2, timestamp: 1).isEmpty)
    }

    func testResetClearsLastTotal() {
        var bridge = PedometerStepBridge()
        _ = bridge.consume(totalSteps: 4, timestamp: 0)
        bridge.reset()
        XCTAssertEqual(bridge.lastTotalSteps, 0)
        XCTAssertEqual(bridge.consume(totalSteps: 1, timestamp: 1).count, 1)
    }

    func testNegativeTotalIsClamped() {
        var bridge = PedometerStepBridge()
        XCTAssertTrue(bridge.consume(totalSteps: -3, timestamp: 0).isEmpty)
        XCTAssertEqual(bridge.lastTotalSteps, 0)
    }
}

final class StepEmissionLedgerTests: XCTestCase {
    func testDetectorLedEmitsOddAndEven() {
        var ledger = StepEmissionLedger()
        ledger.usesPedometer = true

        ledger.noteDetectorStep()
        XCTAssertEqual(ledger.emitNextLength()!, 0.9144, accuracy: 1e-9)
        XCTAssertEqual(ledger.emittedCount, 1)

        ledger.noteDetectorStep()
        XCTAssertEqual(ledger.emitNextLength()!, 0.9144, accuracy: 1e-9)
        XCTAssertEqual(ledger.emittedCount, 2)

        ledger.noteDetectorStep()
        XCTAssertEqual(ledger.emitNextLength()!, 0.9144, accuracy: 1e-9)
        XCTAssertEqual(ledger.emittedCount, 3)
    }

    func testPedometerJumpDripsOnePerEmit() {
        var ledger = StepEmissionLedger()
        ledger.notePedometer(totalSteps: 2, distanceMeters: 1.6)

        XCTAssertEqual(ledger.emitNextLength()!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(ledger.emittedCount, 1)
        XCTAssertEqual(ledger.emitNextLength()!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(ledger.emittedCount, 2)
        XCTAssertNil(ledger.emitNextLength())
    }

    func testDesiredUsesMaxOfDetectorAndPedometer() {
        var ledger = StepEmissionLedger()
        ledger.noteDetectorStep()
        ledger.noteDetectorStep()
        ledger.notePedometer(totalSteps: 5, distanceMeters: 4.0)
        XCTAssertEqual(ledger.desiredCount, 5)

        var emitted = 0
        while ledger.emitNextLength() != nil {
            emitted += 1
        }
        XCTAssertEqual(emitted, 5)
        XCTAssertEqual(ledger.emittedCount, 5)
    }

    func testWithoutPedometerIgnoresPedometerTotal() {
        var ledger = StepEmissionLedger()
        ledger.usesPedometer = false
        ledger.notePedometer(totalSteps: 10, distanceMeters: 8)
        ledger.noteDetectorStep()
        XCTAssertEqual(ledger.desiredCount, 1)
        XCTAssertEqual(ledger.emitNextLength()!, 0.9144, accuracy: 1e-9)
        XCTAssertNil(ledger.emitNextLength())
    }

    func testPedometerDistanceDeltasSplitAcrossNewSteps() {
        var ledger = StepEmissionLedger()
        ledger.notePedometer(totalSteps: 2, distanceMeters: 2.0)
        XCTAssertEqual(ledger.emitNextLength()!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(ledger.emitNextLength()!, 1.0, accuracy: 1e-9)

        ledger.notePedometer(totalSteps: 5, distanceMeters: 5.0)
        XCTAssertEqual(ledger.emitNextLength()!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(ledger.emitNextLength()!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(ledger.emitNextLength()!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(ledger.allocatedDistanceMeters, 5.0, accuracy: 1e-9)
    }

    func testUnevenLegDistancesStayDistinct() {
        var ledger = StepEmissionLedger()

        ledger.notePedometer(totalSteps: 4, distanceMeters: 5.0)
        var outbound = 0.0
        for _ in 0..<4 {
            outbound += ledger.emitNextLength()!
        }
        XCTAssertEqual(outbound, 5.0, accuracy: 1e-9)

        ledger.notePedometer(totalSteps: 7, distanceMeters: 9.5)
        var inbound = 0.0
        for _ in 0..<3 {
            inbound += ledger.emitNextLength()!
        }
        XCTAssertEqual(inbound, 4.5, accuracy: 1e-9)
        XCTAssertEqual(outbound + inbound, 9.5, accuracy: 1e-9)
        XCTAssertNotEqual(outbound, inbound, accuracy: 0.1)
    }

    func testCoveredDistanceForReconcileWhenPedometerCatchesDetector() {
        var ledger = StepEmissionLedger()
        ledger.noteDetectorStep()
        ledger.noteDetectorStep()
        _ = ledger.emitNextLength()
        _ = ledger.emitNextLength()
        XCTAssertNil(ledger.coveredPedometerDistance())

        ledger.notePedometer(totalSteps: 2, distanceMeters: 1.5)
        XCTAssertEqual(ledger.coveredPedometerDistance()!, 1.5, accuracy: 1e-9)
    }

    func testNoDoubleCountWhenPedometerAndDetectorOverlap() {
        var ledger = StepEmissionLedger()
        ledger.noteDetectorStep()
        ledger.noteDetectorStep()
        ledger.notePedometer(totalSteps: 2, distanceMeters: 1.8)

        var total = 0.0
        var n = 0
        while let length = ledger.emitNextLength() {
            total += length
            n += 1
        }
        XCTAssertEqual(n, 2)
        XCTAssertEqual(total, 1.8, accuracy: 1e-9)
    }
}

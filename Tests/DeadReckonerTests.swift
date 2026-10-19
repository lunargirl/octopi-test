import XCTest
import simd
@testable import NavigationApp

final class DeadReckonerTests: XCTestCase {
    func testStepVectorAheadAtStartGoesPositiveY() {
        let v = DeadReckoner.stepVector(headingRelativeToStart: 0, length: 0.9144)
        XCTAssertEqual(v.x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.9144, accuracy: 1e-9)
    }

    func testStepVectorLeftTurnGoesNegativeX() {
        let v = DeadReckoner.stepVector(headingRelativeToStart: .pi / 2, length: 1)
        XCTAssertEqual(v.x, -1, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0, accuracy: 1e-9)
    }

    func testStepVectorRightTurnGoesPositiveX() {
        let v = DeadReckoner.stepVector(headingRelativeToStart: -.pi / 2, length: 1)
        XCTAssertEqual(v.x, 1, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0, accuracy: 1e-9)
    }

    func testTwoStepsAccumulateDistance() {
        let dr = DeadReckoner(config: DeadReckonerConfig(stepLengthMeters: 0.9144))
        dr.start(timestamp: 0)
        _ = dr.processStep(heading: 0, timestamp: 0.5)
        _ = dr.processStep(heading: 0, timestamp: 1.0)
        XCTAssertEqual(dr.stepCount, 2)
        XCTAssertEqual(dr.distanceMeters, 1.8288, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 1.8288, accuracy: 1e-9)
        XCTAssertEqual(dr.trajectory.count, 3)
    }

    func testDefaultStepLengthIsAboutOneYard() {
        XCTAssertEqual(DeadReckonerConfig().stepLengthMeters, 0.9144, accuracy: 1e-9)
    }

    func testLeftTurnPath() {
        var config = DeadReckonerConfig()
        config.stepLengthMeters = 1.0
        let dr = DeadReckoner(config: config)
        dr.start(timestamp: 0)
        _ = dr.processStep(heading: 0, timestamp: 1)
        _ = dr.processStep(heading: .pi / 2, timestamp: 2)
        XCTAssertEqual(dr.position.x, -1, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 1, accuracy: 1e-9)
        XCTAssertEqual(dr.trajectory.pathLength, 2, accuracy: 1e-9)
    }

    func testHeadingEstimatorLocksInitialRelativeToStart() {
        let est = HeadingEstimator()
        let sample = IMUSample(
            timestamp: 0,
            acceleration: .zero,
            rotationRate: .zero,
            attitude: SIMD3(0, 0, 0.5),
            yawRadians: 0.5
        )
        est.start(with: sample)
        XCTAssertTrue(est.isLocked)
        XCTAssertEqual(est.yawAtRecordingStart!, 0.5, accuracy: 1e-9)
        let next = IMUSample(
            timestamp: 0.1,
            acceleration: .zero,
            rotationRate: .zero,
            attitude: SIMD3(0, 0, 0.5 + .pi / 2),
            yawRadians: 0.5 + .pi / 2
        )
        let update = est.update(with: next)
        XCTAssertGreaterThan(update!.headingRelativeToStart, 0.2)
        XCTAssertLessThan(update!.headingRelativeToStart, .pi / 2 + 0.01)
        XCTAssertEqual(update!.relativeHeading, update!.headingRelativeToStart, accuracy: 1e-9)
    }

    func testHeadingSmoothingTracksLargeTurn() {
        let est = HeadingEstimator()
        est.start(with: IMUSample(
            timestamp: 0,
            acceleration: .zero,
            rotationRate: .zero,
            attitude: .zero,
            yawRadians: 0
        ))
        var last = 0.0
        for i in 1...20 {
            let yaw = min(.pi / 2, Double(i) * (.pi / 2) / 12.0)
            let sample = IMUSample(
                timestamp: Double(i) * 0.02,
                acceleration: .zero,
                rotationRate: .zero,
                attitude: SIMD3(0, 0, yaw),
                yawRadians: yaw
            )
            last = est.update(with: sample)!.headingRelativeToStart
        }
        XCTAssertEqual(last, .pi / 2, accuracy: 0.05)
    }

    func testStraightWalkStaysOnAheadAxis() {
        let dr = DeadReckoner(config: DeadReckonerConfig(stepLengthMeters: 1))
        dr.start(timestamp: 0)
        for i in 1...8 {
            _ = dr.processStep(heading: 0, timestamp: Double(i))
        }
        XCTAssertEqual(dr.position.x, 0, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 8, accuracy: 1e-9)
    }

    func testRightAngleCorner() {
        let dr = DeadReckoner(config: DeadReckonerConfig(stepLengthMeters: 1))
        dr.start(timestamp: 0)
        _ = dr.processStep(heading: 0, timestamp: 1)
        _ = dr.processStep(heading: 0, timestamp: 2)
        _ = dr.processStep(heading: -.pi / 2, timestamp: 3)
        _ = dr.processStep(heading: -.pi / 2, timestamp: 4)
        XCTAssertEqual(dr.position.x, 2, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 2, accuracy: 1e-9)
    }

    func testProcessStepUsesExplicitLength() {
        let dr = DeadReckoner(config: DeadReckonerConfig(stepLengthMeters: 0.9144))
        dr.start(timestamp: 0)
        _ = dr.processStep(heading: 0, timestamp: 1, lengthMeters: 1.25)
        _ = dr.processStep(heading: 0, timestamp: 2, lengthMeters: 0.75)
        XCTAssertEqual(dr.distanceMeters, 2.0, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 2.0, accuracy: 1e-9)
    }

    func testScaleTrajectoryMatchesPedometerTotal() {
        let dr = DeadReckoner(config: DeadReckonerConfig(stepLengthMeters: 1))
        dr.start(timestamp: 0)
        _ = dr.processStep(heading: 0, timestamp: 1, lengthMeters: 1)
        _ = dr.processStep(heading: 0, timestamp: 2, lengthMeters: 1)
        _ = dr.processStep(heading: .pi, timestamp: 3, lengthMeters: 1)
        _ = dr.processStep(heading: .pi, timestamp: 4, lengthMeters: 1)
        XCTAssertEqual(dr.distanceMeters, 4, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 0, accuracy: 1e-9)

        dr.scaleTrajectory(toTotalDistance: 3.2)
        XCTAssertEqual(dr.distanceMeters, 3.2, accuracy: 1e-9)
        XCTAssertEqual(dr.position.y, 0, accuracy: 1e-9)
        XCTAssertEqual(dr.trajectory.pathLength, 3.2, accuracy: 1e-9)
    }

    func testOutAndBackLegLengthsTrackVariableStride() {
        let dr = DeadReckoner(config: DeadReckonerConfig(stepLengthMeters: 1))
        dr.start(timestamp: 0)
        for i in 1...4 {
            _ = dr.processStep(heading: 0, timestamp: Double(i), lengthMeters: 1.25)
        }
        let outbound = dr.distanceMeters
        let turnIndex = dr.trajectory.count - 1
        for i in 5...7 {
            _ = dr.processStep(heading: .pi, timestamp: Double(i), lengthMeters: 1.5)
        }
        let inbound = dr.distanceMeters - outbound
        XCTAssertEqual(outbound, 5.0, accuracy: 1e-9)
        XCTAssertEqual(inbound, 4.5, accuracy: 1e-9)

        let mid = dr.trajectory.points[turnIndex].position.y
        XCTAssertEqual(mid, 5.0, accuracy: 1e-9)
    }

    func testWorldAheadMapsUpAndWorldLeftMapsLeftOnCanvas() {
        let ahead = DeadReckoner.stepVector(headingRelativeToStart: 0, length: 1)
        let left = DeadReckoner.stepVector(headingRelativeToStart: .pi / 2, length: 1)

        let aheadScreenY = screenY(worldY: ahead.y, canvasCenterY: 100)
        let leftScreenX = screenX(worldX: left.x, canvasCenterX: 100)
        let originScreenY = screenY(worldY: 0, canvasCenterY: 100)
        let originScreenX = screenX(worldX: 0, canvasCenterX: 100)

        XCTAssertLessThan(aheadScreenY, originScreenY)
        XCTAssertLessThan(leftScreenX, originScreenX)
    }

    // World +X (right) maps to screen +X.
    private func screenX(worldX: Double, canvasCenterX: Double) -> Double {
        canvasCenterX + worldX * 40
    }

    // World +Y (ahead) maps to screen −Y (up).
    private func screenY(worldY: Double, canvasCenterY: Double) -> Double {
        canvasCenterY - worldY * 40
    }
}

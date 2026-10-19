import Foundation
import simd

struct PathTrackerConfig: Equatable, Sendable {
    var stepLengthMeters: Double = 0.9144
}

final class PathTracker: @unchecked Sendable {
    var config: PathTrackerConfig

    private(set) var trajectory = Trajectory()
    private(set) var position: SIMD2<Double> = .zero
    private(set) var headingRel = 0.0
    private(set) var stepCount = 0
    private(set) var distance = 0.0

    var heading: Double { headingRel }

    init(config: PathTrackerConfig = PathTrackerConfig()) {
        self.config = config
    }

    func start(timestamp: TimeInterval) {
        reset()
        trajectory.append(TrajectoryPoint(
            position: .zero,
            heading: 0,
            timestamp: timestamp,
            stepIndex: 0
        ))
    }

    func reset() {
        trajectory = Trajectory()
        position = .zero
        headingRel = 0
        stepCount = 0
        distance = 0
    }

    func updateHeading(_ heading: Double) {
        headingRel = heading
    }

    @discardableResult
    func processStep(
        heading: Double,
        timestamp: TimeInterval,
        length: Double? = nil
    ) -> TrajectoryPoint {
        headingRel = heading
        let len = max(0, length ?? config.stepLengthMeters)
        position += PathTracker.stepVector(heading: heading, length: len)
        stepCount += 1
        distance += len

        let point = TrajectoryPoint(
            position: position,
            heading: heading,
            timestamp: timestamp,
            stepIndex: stepCount
        )
        trajectory.append(point)
        return point
    }

    func scaleTrajectory(to target: Double) {
        let tar = max(0, target)

        guard distance > 1e-9 else {
            distance = tar
            return
        }

        let scale = tar / distance
        guard abs(scale - 1) > 1e-6 else { return }

        var path = Trajectory()
        for p in trajectory.points {
            path.append(TrajectoryPoint(
                position: p.position * scale,
                heading: p.heading,
                timestamp: p.timestamp,
                stepIndex: p.stepIndex
            ))
        }

        trajectory = path
        position *= scale
        distance = tar
    }

    static func stepVector(heading: Double, length: Double) -> SIMD2<Double> {
        SIMD2(
            -length * sin(heading),
            length * cos(heading)
        )
    }

    static func stepVector(
        headingRelativeToStart: Double,
        length: Double
    ) -> SIMD2<Double> {
        stepVector(heading: headingRelativeToStart, length: length)
    }
}

import Foundation
import simd

struct TrajectoryPoint: Equatable, Sendable {
    var position: SIMD2<Double>
    var heading: Double
    var timestamp: TimeInterval
    var stepIndex: Int
}

struct Trajectory: Equatable, Sendable {
    private(set) var points: [TrajectoryPoint] = []

    var isEmpty: Bool { points.isEmpty }
    var count: Int { points.count }
    var start: TrajectoryPoint? { points.first }
    var end: TrajectoryPoint? { points.last }

    var pathLength: Double {
        guard points.count > 1 else { return 0 }

        var total = 0.0
        for i in 1..<points.count {
            total += simd_distance(
                points[i - 1].position,
                points[i].position
            )
        }
        return total
    }

    mutating func append(_ point: TrajectoryPoint) {
        points.append(point)
    }

    func positions() -> [SIMD2<Double>] {
        points.map(\.position)
    }
}

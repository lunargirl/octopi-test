import Foundation
import simd

struct DirectionEstimate: Equatable, Sendable {
    let relative: Double
    let absoluteYaw: Double
    let timestamp: TimeInterval
}

final class DirectionFinder: @unchecked Sendable {
    private(set) var startYaw: Double?
    private(set) var isLocked = false
    private(set) var latest: DirectionEstimate?

    private var filtered: Double?
    private let alpha = 0.55

    var initialYaw: Double? { startYaw }

    func start(with sample: IMUSample) {
        let yaw = sample.yawRadians
        startYaw = yaw
        isLocked = true
        filtered = 0
        latest = DirectionEstimate(
            relative: 0,
            absoluteYaw: yaw,
            timestamp: sample.timestamp
        )
    }

    func reset() {
        startYaw = nil
        isLocked = false
        latest = nil
        filtered = nil
    }

    @discardableResult
    func update(with sample: IMUSample) -> DirectionEstimate? {
        guard isLocked, let startYaw else { return nil }

        let yaw = sample.yawRadians
        let raw = Self.normalize(yaw - startYaw)
        let dir = Self.smooth(previous: filtered, raw: raw, alpha: alpha)

        filtered = dir

        let estimate = DirectionEstimate(
            relative: dir,
            absoluteYaw: yaw,
            timestamp: sample.timestamp
        )

        latest = estimate
        return estimate
    }

    func relativeDirection(forYaw yaw: Double) -> Double? {
        guard let startYaw else { return nil }
        return Self.normalize(yaw - startYaw)
    }

    static func normalize(_ angle: Double) -> Double {
        var angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if angle > .pi { angle -= 2 * .pi }
        if angle <= -.pi { angle += 2 * .pi }
        return angle
    }

    static func smooth(
        previous: Double?,
        raw: Double,
        alpha: Double
    ) -> Double {
        guard let previous else { return raw }

        let a = min(max(alpha, 0), 1)
        let delta = normalize(raw - previous)
        return normalize(previous + a * delta)
    }
}

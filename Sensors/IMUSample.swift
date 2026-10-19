import CoreMotion
import Foundation

struct IMUSample: Equatable, Sendable {
    let timestamp: TimeInterval
    let acceleration: SIMD3<Double>
    let rotationRate: SIMD3<Double>
    let magneticField: SIMD3<Double>?
    let attitude: SIMD3<Double>
    let yawRadians: Double

    init(
        timestamp: TimeInterval,
        acceleration: SIMD3<Double>,
        rotationRate: SIMD3<Double>,
        magneticField: SIMD3<Double>? = nil,
        attitude: SIMD3<Double>,
        yawRadians: Double? = nil
    ) {
        self.timestamp = timestamp
        self.acceleration = acceleration
        self.rotationRate = rotationRate
        self.magneticField = magneticField
        self.attitude = attitude
        self.yawRadians = yawRadians ?? attitude.z
    }

    init(deviceMotion: CMDeviceMotion) {
        timestamp = deviceMotion.timestamp

        let a = deviceMotion.userAcceleration
        acceleration = SIMD3(a.x, a.y, a.z)

        let r = deviceMotion.rotationRate
        rotationRate = SIMD3(r.x, r.y, r.z)

        let att = deviceMotion.attitude
        attitude = SIMD3(att.pitch, att.roll, att.yaw)
        yawRadians = att.yaw

        let m = deviceMotion.magneticField
        switch m.accuracy {
        case .low, .medium, .high:
            magneticField = SIMD3(m.field.x, m.field.y, m.field.z)
        case .uncalibrated:
            magneticField = nil
        @unknown default:
            magneticField = nil
        }
    }
}

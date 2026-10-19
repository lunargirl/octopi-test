import Foundation
import simd

struct StepEvent: Equatable, Sendable {
    let timestamp: TimeInterval
    let confidence: Double
    let length: Double

    init(
        timestamp: TimeInterval,
        confidence: Double,
        length: Double = 0.9144
    ) {
        self.timestamp = timestamp
        self.confidence = confidence
        self.length = length
    }
}

struct StepDetectorConfig: Equatable, Sendable {
    var magnitudeThreshold: Double = 0.1
    var minStepInterval: TimeInterval = 0.2
    var refractoryHold: TimeInterval = 0.10
    var enableSmoothing = true
    var smoothingAlpha: Double = 0.35
    var gravityLowPassAlpha: Double?
    var peakFallHysteresis: Double = 0.025
    var minPeakProminence: Double = 0.05
    var valleyConfirmRatio: Double = 0.50
    var minCycleDuration: TimeInterval = 0.1
    var minPeakToValley: Double = 0.05
    var minMotionEnergy: Double = 0.01
    var maxMotionEnergy: Double = 1.50
    var energyWindowSamples = 16
    var maxDirectionFlips = 16
    var jiggleEnergyCeiling: Double = 0.2
}

enum StepDetectorPhase: Equatable, Sendable {
    case idle
    case rising
    case falling
    case refractory
    case waitingForQuiet
}

final class StepDetector: @unchecked Sendable {
    var config: StepDetectorConfig

    private(set) var phase: StepDetectorPhase = .idle
    private(set) var stepCount = 0
    private(set) var lastEvent: StepEvent?
    private(set) var lastSmoothedMagnitude = 0.0

    private var smoothed: Double?
    private var gravity: SIMD3<Double>?
    private var prevMag: Double?
    private var peak = 0.0
    private var peakTime: TimeInterval = 0
    private var riseTime: TimeInterval = 0
    private var lastStepTime: TimeInterval?
    private var refractoryEnd: TimeInterval?
    private var mags: [Double] = []
    private var armed = true

    init(config: StepDetectorConfig = StepDetectorConfig()) {
        self.config = config
    }

    func reset() {
        phase = .idle
        stepCount = 0
        lastEvent = nil
        lastSmoothedMagnitude = 0
        smoothed = nil
        gravity = nil
        prevMag = nil
        peak = 0
        peakTime = 0
        riseTime = 0
        lastStepTime = nil
        refractoryEnd = nil
        mags.removeAll(keepingCapacity: true)
        armed = true
    }

    @discardableResult
    func process(_ sample: IMUSample) -> StepEvent? {
        process(
            acceleration: sample.acceleration,
            timestamp: sample.timestamp
        )
    }

    @discardableResult
    func process(
        acceleration: SIMD3<Double>,
        timestamp: TimeInterval
    ) -> StepEvent? {
        let acc = stripGravity(acceleration)
        let raw = simd_length(acc)
        let mag = smooth(raw)

        lastSmoothedMagnitude = mag
        rememberEnergy(mag)

        if mag < config.magnitudeThreshold {
            armed = true
        }

        defer { prevMag = mag }

        if phase == .refractory,
           let end = refractoryEnd,
           timestamp >= end {
            phase = .idle
            refractoryEnd = nil
        }

        switch phase {
        case .idle:
            if shouldRise(mag) {
                phase = .rising
                riseTime = timestamp
                peak = mag
                peakTime = timestamp
                armed = false
            }
            return nil

        case .waitingForQuiet:
            if mag < config.magnitudeThreshold {
                phase = .idle
            }
            return nil

        case .refractory:
            return nil

        case .rising:
            if mag >= peak {
                peak = mag
                peakTime = timestamp
                return nil
            }

            if peak - mag >= config.peakFallHysteresis {
                phase = .falling
            }
            return nil

        case .falling:
            if mag >= peak {
                phase = .rising
                riseTime = timestamp
                peak = mag
                peakTime = timestamp
                return nil
            }

            if valleyLooksReal(smoothed: mag, raw: raw) {
                return acceptPeak(
                    at: peakTime,
                    peak: peak,
                    valley: min(mag, raw),
                    valleyTime: timestamp
                )
            }
            return nil
        }
    }

    private func shouldRise(_ mag: Double) -> Bool {
        guard armed else { return false }
        guard mag >= config.magnitudeThreshold else { return false }
        guard energyLooksLikeWalking else { return false }
        guard !looksLikeJiggle else { return false }

        return prevMag.map { mag > $0 + 1e-6 } ?? true
    }

    private var energyLooksLikeWalking: Bool {
        avgEnergy >= config.minMotionEnergy
            && avgEnergy <= config.maxMotionEnergy
    }

    private var avgEnergy: Double {
        guard !mags.isEmpty else { return 0 }
        return mags.reduce(0, +) / Double(mags.count)
    }

    private var flipCount: Int {
        guard mags.count >= 3 else { return 0 }

        var count = 0
        for i in 2..<mags.count {
            let a = mags[i - 1] - mags[i - 2]
            let b = mags[i] - mags[i - 1]

            if a * b < 0 {
                count += 1
            }
        }
        return count
    }

    private var looksLikeJiggle: Bool {
        flipCount >= config.maxDirectionFlips
            && avgEnergy < config.jiggleEnergyCeiling
    }

    private func rememberEnergy(_ mag: Double) {
        mags.append(mag)

        let limit = max(1, config.energyWindowSamples)
        if mags.count > limit {
            mags.removeFirst(mags.count - limit)
        }
    }

    private func valleyLooksReal(smoothed: Double, raw: Double) -> Bool {
        peak - min(smoothed, raw) >= config.minPeakToValley
    }

    private func stripGravity(
        _ acc: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard let alpha = config.gravityLowPassAlpha else {
            return acc
        }

        let a = min(max(alpha, 0), 1)

        if let g = gravity {
            let next = g + a * (acc - g)
            gravity = next
            return acc - next
        }

        gravity = acc
        return .zero
    }

    private func smooth(_ mag: Double) -> Double {
        guard config.enableSmoothing else { return mag }

        let a = min(max(config.smoothingAlpha, 0), 1)

        guard let prev = smoothed else {
            smoothed = mag
            return mag
        }

        let next = prev + a * (mag - prev)
        smoothed = next
        return next
    }

    private func acceptPeak(
        at time: TimeInterval,
        peak: Double,
        valley: Double,
        valleyTime: TimeInterval
    ) -> StepEvent? {
        let prominence = peak - config.magnitudeThreshold
        let drop = peak - valley
        let duration = valleyTime - riseTime

        if prominence < config.minPeakProminence
            || drop < config.minPeakToValley
            || duration < config.minCycleDuration
            || !energyLooksLikeWalking
            || looksLikeJiggle
            || (lastStepTime.map {
                time - $0 < config.minStepInterval
            } ?? false) {
            phase = .waitingForQuiet
            return nil
        }

        let confidence = min(
            1,
            drop / max(config.minPeakToValley, 1e-6)
        )
        let event = StepEvent(
            timestamp: time,
            confidence: confidence
        )

        stepCount += 1
        lastEvent = event
        lastStepTime = time
        refractoryEnd = time + config.refractoryHold
        phase = .refractory

        return event
    }
}

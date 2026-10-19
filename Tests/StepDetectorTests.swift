import XCTest
@testable import NavigationApp

final class StepDetectorTests: XCTestCase {
    // Build a detector with the knobs this test cares about.
    private func makeDetector(
        threshold: Double = 0.12,
        minInterval: TimeInterval = 0.28,
        smoothing: Bool = false,
        alpha: Double = 1.0,
        gravityAlpha: Double? = nil,
        peakFall: Double = 0.02,
        minProminence: Double = 0.05,
        valleyRatio: Double = 0.5,
        minCycle: TimeInterval = 0.08,
        minEnergy: Double = 0.0,
        maxEnergy: Double = 10.0,
        minPeakToValley: Double = 0.05,
        refractoryHold: TimeInterval = 0.1,
        maxFlips: Int = 100
    ) -> StepDetector {
        var config = StepDetectorConfig()
        config.magnitudeThreshold = threshold
        config.minStepInterval = minInterval
        config.refractoryHold = refractoryHold
        config.enableSmoothing = smoothing
        config.smoothingAlpha = alpha
        config.peakFallHysteresis = peakFall
        config.gravityLowPassAlpha = gravityAlpha
        config.minPeakProminence = minProminence
        config.valleyConfirmRatio = valleyRatio
        config.minCycleDuration = minCycle
        config.minPeakToValley = minPeakToValley
        config.minMotionEnergy = minEnergy
        config.maxMotionEnergy = maxEnergy
        config.energyWindowSamples = 16
        config.maxDirectionFlips = maxFlips
        config.jiggleEnergyCeiling = 10
        return StepDetector(config: config)
    }

    // Stock production defaults (the ones walkers actually hit).
    private func defaultProductionDetector() -> StepDetector {
        StepDetector()
    }

    // One synthetic footfall: quiet → peak → quiet.
    private func walkingCycle(
        start: TimeInterval,
        dt: TimeInterval = 0.02,
        peak: Double = 0.35,
        samples: Int = 25
    ) -> [(SIMD3<Double>, TimeInterval)] {
        var out: [(SIMD3<Double>, TimeInterval)] = []
        for i in 0..<samples {
            let t = start + Double(i) * dt
            let phase = Double(i) / Double(samples - 1)
            let mag = peak * sin(.pi * phase)
            out.append((SIMD3(0, 0, mag), t))
        }
        return out
    }

    // Fast low-amp shake — should mostly be ignored.
    private func handheldJiggle(
        start: TimeInterval,
        duration: TimeInterval = 3.0,
        dt: TimeInterval = 0.02,
        amplitude: Double = 0.14,
        frequencyHz: Double = 4.5
    ) -> [(SIMD3<Double>, TimeInterval)] {
        var out: [(SIMD3<Double>, TimeInterval)] = []
        var t = start
        while t < start + duration {
            let mag = amplitude * abs(sin(2 * .pi * frequencyHz * t))
            out.append((SIMD3(0, mag * 0.3, mag), t))
            t += dt
        }
        return out
    }

    // Back-to-back walking sinusoid with no quiet gaps.
    private func continuousWalk(
        duration: TimeInterval = 5.0,
        frequencyHz: Double = 1.85,
        peak: Double = 0.75,
        dt: TimeInterval = 0.02
    ) -> [(SIMD3<Double>, TimeInterval)] {
        var out: [(SIMD3<Double>, TimeInterval)] = []
        var t: TimeInterval = 0
        while t < duration {
            let mag = peak * abs(sin(.pi * frequencyHz * t))
            out.append((SIMD3(0, 0, mag), t))
            t += dt
        }
        return out
    }

    // Run a batch of samples through the detector and collect events.
    private func feed(
        _ detector: StepDetector,
        _ samples: [(SIMD3<Double>, TimeInterval)]
    ) -> [StepEvent] {
        var events: [StepEvent] = []
        for (accel, t) in samples {
            if let event = detector.process(acceleration: accel, timestamp: t) {
                events.append(event)
            }
        }
        return events
    }

    func testOneWalkingCycleProducesOneStep() {
        let detector = makeDetector()
        var events = feed(detector, walkingCycle(start: 0))
        for i in 0..<10 {
            let t = 0.5 + Double(i) * 0.02
            if let event = detector.process(acceleration: .zero, timestamp: t) {
                events.append(event)
            }
        }

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(detector.stepCount, 1)
        XCTAssertGreaterThan(events[0].confidence, 0)
    }

    func testTwoSeparatedCyclesProduceTwoSteps() {
        let detector = makeDetector(minInterval: 0.25)
        var count = 0

        for (accel, t) in walkingCycle(start: 0, peak: 0.4) {
            if detector.process(acceleration: accel, timestamp: t) != nil { count += 1 }
        }
        for i in 0..<15 {
            _ = detector.process(acceleration: .zero, timestamp: 0.6 + Double(i) * 0.02)
        }
        for (accel, t) in walkingCycle(start: 1.0, peak: 0.4) {
            if detector.process(acceleration: accel, timestamp: t) != nil { count += 1 }
        }

        XCTAssertEqual(count, 2)
        XCTAssertEqual(detector.stepCount, 2)
    }

    func testDoubleCountPreventionWithinMinInterval() {
        let detector = makeDetector(minInterval: 0.5)
        var events = 0

        for (accel, t) in walkingCycle(start: 0, peak: 0.4, samples: 15) {
            if detector.process(acceleration: accel, timestamp: t) != nil { events += 1 }
        }
        for (accel, t) in walkingCycle(start: 0.15, peak: 0.4, samples: 15) {
            if detector.process(acceleration: accel, timestamp: t) != nil { events += 1 }
        }

        XCTAssertEqual(events, 1)
        XCTAssertEqual(detector.stepCount, 1)
    }

    func testSubThresholdNoiseProducesNoSteps() {
        let detector = makeDetector(threshold: 0.12)
        for i in 0..<100 {
            let t = Double(i) * 0.02
            let noise = 0.04 * sin(Double(i))
            _ = detector.process(acceleration: SIMD3(noise, 0, noise), timestamp: t)
        }
        XCTAssertEqual(detector.stepCount, 0)
        XCTAssertNil(detector.lastEvent)
        XCTAssertEqual(detector.phase, .idle)
    }

    func testResetClearsState() {
        let detector = makeDetector()
        for (accel, t) in walkingCycle(start: 0) {
            _ = detector.process(acceleration: accel, timestamp: t)
        }
        XCTAssertEqual(detector.stepCount, 1)

        detector.reset()
        XCTAssertEqual(detector.stepCount, 0)
        XCTAssertNil(detector.lastEvent)
        XCTAssertEqual(detector.phase, .idle)
        XCTAssertEqual(detector.lastSmoothedMagnitude, 0)
    }

    func testConfigurableThresholdRejectsSmallPeaks() {
        let detector = makeDetector(threshold: 0.5, minProminence: 0.05)
        for (accel, t) in walkingCycle(start: 0, peak: 0.3) {
            _ = detector.process(acceleration: accel, timestamp: t)
        }
        XCTAssertEqual(detector.stepCount, 0)
    }

    func testSmoothingStillDetectsClearStep() {
        let detector = makeDetector(smoothing: true, alpha: 0.4, minPeakToValley: 0.15)
        var events = 0
        for (accel, t) in walkingCycle(start: 0, dt: 0.02, peak: 0.8, samples: 50) {
            if detector.process(acceleration: accel, timestamp: t) != nil { events += 1 }
        }
        for i in 0..<40 {
            _ = detector.process(acceleration: .zero, timestamp: 1.2 + Double(i) * 0.02)
        }
        XCTAssertEqual(events, 1)
        XCTAssertEqual(detector.stepCount, 1)
    }

    func testStateMachineEntersRisingAboveThreshold() {
        let detector = makeDetector(smoothing: false)
        XCTAssertEqual(detector.phase, .idle)
        _ = detector.process(acceleration: SIMD3(0, 0, 0.05), timestamp: 0)
        _ = detector.process(acceleration: SIMD3(0, 0, 0.2), timestamp: 0.02)
        XCTAssertEqual(detector.phase, .rising)
    }

    func testRequiresValleyBeforeCountingStep() {
        let detector = makeDetector(
            threshold: 0.12,
            peakFall: 0.03,
            minProminence: 0.05,
            minCycle: 0.1,
            minPeakToValley: 0.20
        )
        let rising: [(SIMD3<Double>, TimeInterval)] = [
            (SIMD3(0, 0, 0.05), 0.00),
            (SIMD3(0, 0, 0.15), 0.04),
            (SIMD3(0, 0, 0.28), 0.08),
            (SIMD3(0, 0, 0.32), 0.12),
            (SIMD3(0, 0, 0.27), 0.16),
        ]
        XCTAssertTrue(feed(detector, rising).isEmpty)
        XCTAssertEqual(detector.phase, .falling)

        let stillHigh = detector.process(acceleration: SIMD3(0, 0, 0.22), timestamp: 0.20)
        XCTAssertNil(stillHigh)
        XCTAssertEqual(detector.phase, .falling)

        let confirmed = detector.process(acceleration: SIMD3(0, 0, 0.04), timestamp: 0.24)
        XCTAssertNotNil(confirmed)
        XCTAssertEqual(detector.stepCount, 1)
    }

    func testMildHandheldJiggleStaysNearZero() {
        let detector = defaultProductionDetector()
        let events = feed(detector, handheldJiggle(start: 0, duration: 4.0, amplitude: 0.12))
        XCTAssertLessThanOrEqual(events.count, 2)
        XCTAssertLessThanOrEqual(detector.stepCount, 2)
    }

    func testStrongHandheldJiggleDoesNotExplode() {
        let detector = defaultProductionDetector()
        let events = feed(
            detector,
            handheldJiggle(start: 0, duration: 3.0, amplitude: 0.18, frequencyHz: 5.5)
        )
        XCTAssertLessThanOrEqual(events.count, 4)
        XCTAssertLessThanOrEqual(detector.stepCount, 4)
    }

    func testAboveThresholdJiggleDoesNotExplode() {
        let detector = defaultProductionDetector()
        let events = feed(
            detector,
            handheldJiggle(start: 0, duration: 4.0, amplitude: 0.28, frequencyHz: 5.0)
        )
        XCTAssertLessThanOrEqual(events.count, 6)
        XCTAssertLessThanOrEqual(detector.stepCount, 6)
    }

    func testHighFrequencyJiggleStaysBounded() {
        let detector = defaultProductionDetector()
        let events = feed(
            detector,
            handheldJiggle(start: 0, duration: 5.0, amplitude: 0.40, frequencyHz: 4.0)
        )
        XCTAssertLessThanOrEqual(events.count, 8)
        XCTAssertLessThanOrEqual(detector.stepCount, 8)
    }

    func testWalkingLikeCadenceProducesAboutOneStepPerCycle() {
        let detector = defaultProductionDetector()
        var events: [StepEvent] = []
        let cycles = 5
        let period: TimeInterval = 0.55

        for cycle in 0..<cycles {
            let start = Double(cycle) * period
            events += feed(
                detector,
                walkingCycle(start: start, dt: 0.02, peak: 0.35, samples: 30)
            )
            let quietStart = start + 0.60
            for i in 0..<8 {
                if let event = detector.process(
                    acceleration: SIMD3(0, 0, 0.01),
                    timestamp: quietStart + Double(i) * 0.02
                ) {
                    events.append(event)
                }
            }
        }

        XCTAssertEqual(events.count, cycles)
        XCTAssertEqual(detector.stepCount, cycles)
    }

    func testContinuousWalkingSinusoidNearOnePerCycle() {
        let detector = defaultProductionDetector()
        let frequency = 1.85
        let duration = 5.0
        let events = feed(
            detector,
            continuousWalk(duration: duration, frequencyHz: frequency, peak: 0.35)
        )
        let expected = Int((duration * frequency).rounded())
        XCTAssertGreaterThanOrEqual(events.count, expected - 2)
        XCTAssertLessThanOrEqual(events.count, expected + 2)
        XCTAssertEqual(detector.stepCount, events.count)
    }

    func testModerateHandheldWalkCountsSteps() {
        let detector = defaultProductionDetector()
        let events = feed(
            detector,
            continuousWalk(duration: 4.0, frequencyHz: 1.7, peak: 0.28)
        )
        XCTAssertGreaterThanOrEqual(events.count, 5)
        XCTAssertLessThanOrEqual(events.count, 9)
    }

    func testSoftDefaultsMatchExpectedWalkingSensitivity() {
        let config = StepDetectorConfig()
        XCTAssertEqual(config.magnitudeThreshold, 0.12, accuracy: 1e-9)
        XCTAssertEqual(config.minStepInterval, 0.18, accuracy: 1e-9)
        XCTAssertEqual(config.refractoryHold, 0.10, accuracy: 1e-9)
        XCTAssertEqual(config.minPeakProminence, 0.05, accuracy: 1e-9)
        XCTAssertEqual(config.minPeakToValley, 0.06, accuracy: 1e-9)
    }

    func testLowMotionEnergyStandingIgnored() {
        var config = StepDetectorConfig()
        config.magnitudeThreshold = 0.12
        config.minStepInterval = 0.3
        config.refractoryHold = 0.1
        config.enableSmoothing = false
        config.gravityLowPassAlpha = nil
        config.minPeakProminence = 0.05
        config.minCycleDuration = 0.08
        config.minPeakToValley = 0.05
        config.minMotionEnergy = 0.2
        config.maxMotionEnergy = 1.6
        config.energyWindowSamples = 8
        config.maxDirectionFlips = 100
        let detector = StepDetector(config: config)

        for i in 0..<20 {
            let t = Double(i) * 0.02
            let mag = i < 10 ? 0.02 : 0.3
            _ = detector.process(acceleration: SIMD3(0, 0, mag), timestamp: t)
        }

        XCTAssertEqual(detector.stepCount, 0)
    }
}

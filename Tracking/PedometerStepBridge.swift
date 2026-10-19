import Foundation

struct PedometerStepBridge: Equatable, Sendable {
    private(set) var lastTotalSteps = 0

    mutating func reset() {
        lastTotalSteps = 0
    }

    mutating func consume(totalSteps: Int, timestamp: TimeInterval) -> [StepEvent] {
        let total = max(0, totalSteps)
        let delta = total - lastTotalSteps
        guard delta > 0 else { return [] }

        lastTotalSteps = total
        return (0..<delta).map { _ in
            StepEvent(timestamp: timestamp, confidence: 1.0)
        }
    }
}

struct StepEmissionLedger: Equatable, Sendable {
    private(set) var detectorCount = 0
    private(set) var pedometerTotal = 0
    private(set) var emittedCount = 0
    private(set) var pedometerDistanceMeters = 0.0
    private(set) var allocatedDistanceMeters = 0.0

    private var pendingDistanceMeters = 0.0
    private var pendingDistanceSteps = 0
    private var lastAverageStrideMeters: Double?

    var usesPedometer = true
    var fallbackStepLengthMeters = 0.9144

    var desiredCount: Int {
        max(detectorCount, usesPedometer ? pedometerTotal : detectorCount)
    }

    mutating func reset() {
        detectorCount = 0
        pedometerTotal = 0
        emittedCount = 0
        pedometerDistanceMeters = 0
        allocatedDistanceMeters = 0
        pendingDistanceMeters = 0
        pendingDistanceSteps = 0
        lastAverageStrideMeters = nil
    }

    mutating func noteDetectorStep() {
        detectorCount += 1
    }

    mutating func notePedometer(totalSteps: Int, distanceMeters: Double?) {
        guard usesPedometer else { return }

        let total = max(0, totalSteps)
        let oldTotal = pedometerTotal
        let stepDelta = max(0, total - oldTotal)
        pedometerTotal = max(pedometerTotal, total)

        guard let distanceMeters else { return }

        let distance = max(0, distanceMeters)
        let oldDistance = pedometerDistanceMeters
        let distDelta = max(0, distance - oldDistance)
        pedometerDistanceMeters = max(pedometerDistanceMeters, distance)

        guard distDelta > 0 else { return }

        if stepDelta > 0 {
            let oldCovered = min(emittedCount, oldTotal)
            let newCovered = min(emittedCount, pedometerTotal)
            let alreadyCovered = max(0, newCovered - oldCovered)
            let futureSteps = stepDelta - alreadyCovered

            if futureSteps > 0 {
                let share = distDelta * Double(futureSteps) / Double(stepDelta)
                pendingDistanceMeters += share
                pendingDistanceSteps += futureSteps
            }

            lastAverageStrideMeters = distDelta / Double(stepDelta)
        } else if pendingDistanceSteps > 0 {
            pendingDistanceMeters += distDelta
        } else if pedometerTotal > 0 {
            lastAverageStrideMeters = pedometerDistanceMeters / Double(pedometerTotal)
        }
    }

    mutating func emitNextLength() -> Double? {
        guard emittedCount < desiredCount else { return nil }
        emittedCount += 1

        let length: Double
        if usesPedometer, pendingDistanceSteps > 0 {
            length = max(0, pendingDistanceMeters / Double(pendingDistanceSteps))
            pendingDistanceMeters = max(0, pendingDistanceMeters - length)
            pendingDistanceSteps -= 1
        } else if usesPedometer, let avg = lastAverageStrideMeters, avg > 0 {
            length = avg
        } else {
            length = max(0, fallbackStepLengthMeters)
        }

        allocatedDistanceMeters += length
        return length
    }

    func coveredPedometerDistance() -> Double? {
        guard usesPedometer,
              pedometerDistanceMeters > 0,
              pedometerTotal > 0,
              emittedCount > 0,
              emittedCount <= pedometerTotal
        else { return nil }

        return pedometerDistanceMeters * Double(emittedCount) / Double(pedometerTotal)
    }

    mutating func markAllocatedDistance(_ meters: Double) {
        allocatedDistanceMeters = max(0, meters)
    }
}

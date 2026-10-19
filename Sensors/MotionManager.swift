import CoreMotion
import Foundation

@MainActor
final class MotionManager {
    private(set) var latestSample: IMUSample?
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    private(set) var stepCount = 0
    private(set) var usesPedometer = false

    private let updateHz = 50.0
    let stepDetector: StepDetector

    var onSample: ((IMUSample) -> Void)?
    var onStep: ((StepEvent, IMUSample) -> Void)?
    var onDistanceReconcile: ((Double) -> Void)?
    var onStateChange: (() -> Void)?

    private var cmManager: CMMotionManager?
    private var pedometerManager: CMPedometer?
    private var ledger = StepEmissionLedger()

    private var cm: CMMotionManager {
        if let cmManager { return cmManager }
        let cm = CMMotionManager()
        cmManager = cm
        return cm
    }
    private var pedometer: CMPedometer {
        if let pedometerManager { return pedometerManager }
        let pedometer = CMPedometer()
        pedometerManager = pedometer
        return pedometer
    }

    init(stepDetector: StepDetector = StepDetector()) {
        self.stepDetector = stepDetector
    }

    func start() {
        guard !isRunning else { return }

        errorMessage = nil
        guard cm.isDeviceMotionAvailable else {
            errorMessage = "motion unavailable"
            onStateChange?()
            return
        }

        stepDetector.reset()
        ledger.reset()
        ledger.usesPedometer = CMPedometer.isStepCountingAvailable()

        usesPedometer = ledger.usesPedometer
        stepCount = 0
        latestSample = nil
        isRunning = true
        onStateChange?()

        cm.deviceMotionUpdateInterval = 1.0 / updateHz
        cm.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) {
            [weak self] motion, error in

            let sample = motion.map(IMUSample.init(deviceMotion:))
            let msg = error?.localizedDescription

            Task { @MainActor [weak self] in
                self?.handleMotion(sample, errorMessage: msg)
            }
        }

        if usesPedometer {
            pedometer.startUpdates(from: Date()) { [weak self] data, error in
                let steps = data?.numberOfSteps.intValue
                let dist = data?.distance?.doubleValue
                let msg = error?.localizedDescription

                Task { @MainActor [weak self] in
                    self?.handlePedometer(
                        steps: steps,
                        distance: dist,
                        errorMessage: msg
                    )
                }
            }
        }
    }

    func stop() {
        let wasRunning = isRunning

        cmManager?.stopDeviceMotionUpdates()
        pedometerManager?.stopUpdates()

        isRunning = false
        usesPedometer = false
        ledger.usesPedometer = false

        if wasRunning {
            onStateChange?()
        }
    }

    private func handleMotion(
        _ sample: IMUSample?,
        errorMessage: String?
    ) {
        guard isRunning else { return }

        if let errorMessage {
            self.errorMessage = errorMessage
            stop()
            return
        }

        guard let sample else { return }

        latestSample = sample
        onSample?(sample)

        if stepDetector.process(sample) != nil {
            ledger.noteDetectorStep()
        }

        drainSteps(using: sample)
    }

    private func handlePedometer(
        steps: Int?,
        distance: Double?,
        errorMessage: String?
    ) {
        guard isRunning else { return }

        if let errorMessage {
            self.errorMessage = errorMessage
            dropPedometer()
            onStateChange?()
            return
        }

        guard let steps else { return }

        ledger.notePedometer(
            totalSteps: steps,
            distanceMeters: distance
        )

        nudgeDistance()

        if let sample = latestSample {
            drainSteps(using: sample)
        }
    }

    private func drainSteps(using sample: IMUSample) {
        var emitted = false

        while let len = ledger.emitNextLength() {
            stepCount = ledger.emittedCount

            let step = StepEvent(
                timestamp: sample.timestamp,
                confidence: 1.0,
                length: len
            )

            onStep?(step, sample)
            emitted = true
        }

        if emitted {
            onStateChange?()
        }
    }

    private func nudgeDistance() {
        guard let dist = ledger.coveredPedometerDistance(),
              dist.isFinite,
              dist >= 0,
              ledger.allocatedDistanceMeters > 1e-9
        else {
            return
        }

        let scale = dist / ledger.allocatedDistanceMeters
        guard scale.isFinite, abs(scale - 1) > 1e-3 else { return }

        onDistanceReconcile?(scale)
        ledger.markAllocatedDistance(dist)
    }

    private func dropPedometer() {
        pedometerManager?.stopUpdates()
        usesPedometer = false
        ledger.usesPedometer = false
    }
}

import Foundation
import simd

@MainActor
final class Recorder: ObservableObject {
    let motion = MotionManager()
    let dir = DirectionFinder()
    let tracker = PathTracker()

    @Published private(set) var recording = false
    @Published private(set) var pathPoints: [SIMD2<Double>] = []
    @Published private(set) var distance = 0.0
    @Published private(set) var pins: [SIMD2<Double>] = []
    @Published private(set) var stepCount = 0
    @Published private(set) var errorMessage: String?

    private var headingRad = 0.0
    private var pathDirty = false

    init() {
        motion.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
        motion.onStep = { [weak self] event, sample in
            self?.handleStep(event, sample: sample)
        }
        motion.onDistanceReconcile = { [weak self] factor in
            self?.handleScale(factor)
        }
        motion.onStateChange = { [weak self] in
            self?.pullMotionUI()
        }
    }

    var pathIsEmpty: Bool { pathPoints.isEmpty }

    func start() {
        dir.reset()
        tracker.reset()

        pathPoints = []
        pins = []
        distance = 0
        stepCount = 0
        headingRad = 0
        pathDirty = false
        errorMessage = nil
        recording = true

        motion.start()
        pullMotionUI()
    }

    func stop() {
        motion.stop()
        recording = false
        flushPath(force: true)
        distance = tracker.distance
        pullMotionUI()
    }

    func dropPin() {
        guard let pos = pathPoints.last ?? tracker.trajectory.end?.position else {
            return
        }
        pins.append(pos)
    }

    private func handleSample(_ sample: IMUSample) {
        if !dir.isLocked {
            dir.start(with: sample)
            tracker.start(timestamp: sample.timestamp)
            pathDirty = true
            flushPath(force: true)
        }

        if let estimate = dir.update(with: sample) {
            headingRad = estimate.relative
            tracker.updateHeading(estimate.relative)
        }
    }

    private func handleStep(_ event: StepEvent, sample: IMUSample) {
        guard recording else { return }

        let heading = dir.latest?.relative
            ?? dir.relativeDirection(forYaw: sample.yawRadians)
            ?? headingRad

        tracker.processStep(
            heading: heading,
            timestamp: event.timestamp,
            length: event.length
        )

        headingRad = heading
        pathDirty = true
    }

    private func handleScale(_ factor: Double) {
        guard recording, factor.isFinite, factor > 0,
              tracker.distance > 1e-9 else {
            return
        }

        tracker.scaleTrajectory(to: tracker.distance * factor)
        pins = pins.map { $0 * factor }

        pathDirty = true
        flushPath(force: true)
        distance = tracker.distance
    }

    private func flushPath(force: Bool = false) {
        guard force || pathDirty else { return }

        pathPoints = tracker.trajectory.positions()
        pathDirty = false
    }

    private func pullMotionUI() {
        if pathDirty {
            flushPath()
            distance = tracker.distance
        }

        stepCount = motion.stepCount
        errorMessage = motion.errorMessage
    }
}

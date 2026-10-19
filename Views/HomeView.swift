import SwiftUI

struct HomeView: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        VStack(spacing: 0) {
            PathCanvasView(
                points: recorder.pathPoints,
                pins: recorder.pins
            )
            .equatable() // maybe O(n) for no reason ?
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 28) {
                label("Steps", "\(recorder.stepCount)")
                label("Distance", String(format: "%.1f m", recorder.distance))
                if !recorder.pins.isEmpty {
                    label("Pins", "\(recorder.pins.count)")
                }
            }
            .padding(.vertical, 14)

            HStack(spacing: 12) {
                Button(recorder.recording ? "Stop" : "Start") {
                    recorder.recording ? recorder.stop() : recorder.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Pin") {
                    recorder.dropPin()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(recorder.pathIsEmpty)
            }
            .padding(.bottom, 20)

            if let err = recorder.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

#Preview {
    HomeView(recorder: Recorder())
}

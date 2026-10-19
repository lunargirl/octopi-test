import SwiftUI
import simd

struct PathCanvasView: View, Equatable {
    var points: [SIMD2<Double>]
    var pins: [SIMD2<Double>] = []

    private static let gridStep: CGFloat = 36
    private static let padding: CGFloat = 28

    // lazy upd idk if needed
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.points == rhs.points && lhs.pins == rhs.pins
    }

    var body: some View {
        Canvas { ctx, size in
            let fit = fitToCanvas(size)

            var g = Path()
            for x in stride(from: 0, through: size.width, by: Self.gridStep) {
                g.move(to: CGPoint(x: x, y: 0))
                g.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: Self.gridStep) {
                g.move(to: CGPoint(x: 0, y: y))
                g.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(g, with: .color(.secondary.opacity(0.12)), lineWidth: 1)

            if let f = points.first {
                var p = Path()
                p.move(to: toScreen(f, fit, size))
                for point in points.dropFirst() {
                    p.addLine(to: toScreen(point, fit, size))
                }
                if points.count > 1 {
                    ctx.stroke(p, with: .color(.accentColor), lineWidth: 3)
                }

                ctx.fill(
                    circle(at: toScreen(f, fit, size), radius: 7),
                    with: .color(.green)
                )
                if points.count > 1, let l = points.last {
                    ctx.fill(
                        circle(at: toScreen(l, fit, size), radius: 6),
                        with: .color(.orange)
                    )
                }
            }

            for pin in pins {
                let pos = toScreen(pin, fit, size)
                var p = Path()
                p.move(to: CGPoint(x: pos.x, y: pos.y - 8))
                p.addLine(to: CGPoint(x: pos.x + 7, y: pos.y))
                p.addLine(to: CGPoint(x: pos.x, y: pos.y + 8))
                p.addLine(to: CGPoint(x: pos.x - 7, y: pos.y))
                p.closeSubpath()
                ctx.fill(p, with: .color(.purple))
            }

            // filler pre-walk
            if points.isEmpty {
                ctx.draw(
                    Text("Start walking to draw a path")
                        .font(.subheadline)
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private struct Fit {
        let scale: CGFloat
        let center: SIMD2<Double>
    }
    
    private func fitToCanvas(_ size: CGSize) -> Fit {
        guard let first = points.first else {
            return Fit(scale: 1, center: .zero)
        }

        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y

        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let w = max(maxX - minX, 2)
        let h = max(maxY - minY, 2)
        let sw = max(Double(size.width - 2 * Self.padding), 0)
        let sh = max(Double(size.height - 2 * Self.padding), 0)

        return Fit(
            scale: CGFloat(min(sw / w, sh / h)),
            center: SIMD2((minX + maxX) / 2, (minY + maxY) / 2)
        )
    }

    private func toScreen(
        _ point: SIMD2<Double>,
        _ fit: Fit,
        _ size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: size.width / 2 + CGFloat(point.x - fit.center.x) * fit.scale,
            y: size.height / 2 - CGFloat(point.y - fit.center.y) * fit.scale
        )
    }

    private func circle(at p: CGPoint, radius r: CGFloat) -> Path {
        Path(
            ellipseIn: CGRect(
                x: p.x - r,
                y: p.y - r,
                width: r * 2,
                height: r * 2
            )
        )
    }
}


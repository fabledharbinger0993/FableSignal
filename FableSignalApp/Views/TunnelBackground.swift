import SwiftUI

/// Fractal tunnel animation — 28 hexagonal depth layers, counter-rotating triangle accents
/// every 4th layer, 12 rotating light rays, and a pulsing centre glow.
/// Rendered at 30 fps via TimelineView + Canvas. Zero UIKit, zero allocations per frame.
struct TunnelBackground: View {
    var hue: Double    // 0–1 base colour (intent-mapped by caller)
    var speed: Double  // animation rate multiplier

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            Canvas { gc, size in
                let t = context.date.timeIntervalSinceReferenceDate * speed
                render(gc: &gc, size: size, t: t)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Render

    private func render(gc: inout GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR   = max(size.width, size.height) * 0.72

        // Black base
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

        // 12 rotating light rays (wide tapered quads fading outward)
        for i in 0..<12 {
            let angle  = Double(i) * (.pi / 6.0) + t * 0.025
            let rHue   = (hue + Double(i) * 0.02).truncatingRemainder(dividingBy: 1)
            let halfW  = maxR * 0.065
            let far    = maxR * 2.6
            let ca = cos(angle), sa = sin(angle)
            let px = -sa * halfW, py = ca * halfW
            var ray = Path()
            ray.move(to:    CGPoint(x: center.x + px,              y: center.y + py))
            ray.addLine(to: CGPoint(x: center.x - px,              y: center.y - py))
            ray.addLine(to: CGPoint(x: center.x + ca * far - px,   y: center.y + sa * far - py))
            ray.addLine(to: CGPoint(x: center.x + ca * far + px,   y: center.y + sa * far + py))
            ray.closeSubpath()
            gc.fill(ray, with: .color(Color(hue: rHue, saturation: 0.7, brightness: 0.9, opacity: 0.04)))
        }

        // 28 hexagonal layers — depth-sorted, travelling toward the viewer
        let phase = t.truncatingRemainder(dividingBy: 1.0)
        for i in 0..<28 {
            let raw    = (Double(i) + phase) / 28.0
            let depth  = raw * raw                       // quadratic → perspective compression
            let radius = CGFloat(maxR * depth)
            guard radius > 1 else { continue }

            let lHue   = (hue + raw * 0.22).truncatingRemainder(dividingBy: 1)
            let alpha  = (1.0 - raw) * 0.55 + 0.05
            let bright = 0.45 + (1.0 - raw) * 0.55
            let lw     = CGFloat((1.0 - raw) * 3.0 + 0.5)
            let rot    = t * 0.18 * (i % 2 == 0 ? 1.0 : -1.0)

            gc.stroke(
                polygon(center: center, radius: radius, sides: 6, rotation: rot),
                with: .color(Color(hue: lHue, saturation: 0.75, brightness: bright, opacity: alpha)),
                lineWidth: lw
            )

            // Counter-rotating triangle accent every 4th layer
            if i % 4 == 0 {
                let tHue = (lHue + 0.35).truncatingRemainder(dividingBy: 1)
                let tRot = -t * 0.28 + Double(i) * 0.42
                gc.stroke(
                    polygon(center: center, radius: radius * 0.55, sides: 3, rotation: tRot),
                    with: .color(Color(hue: tHue, saturation: 0.8, brightness: 0.9, opacity: alpha * 0.5)),
                    lineWidth: lw * 0.7
                )
            }
        }

        // Pulsing centre glow
        let pulse = (sin(t * 0.7) + 1.0) * 0.5
        let glowR = CGFloat(maxR * (0.09 + pulse * 0.05))
        gc.fill(
            Path(ellipseIn: CGRect(
                x: center.x - glowR, y: center.y - glowR,
                width: glowR * 2,    height: glowR * 2
            )),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hue: hue, saturation: 0.45, brightness: 1.0, opacity: 0.65 + pulse * 0.25),
                    .clear
                ]),
                center: center,
                startRadius: 0,
                endRadius: glowR
            )
        )
    }

    // MARK: - Geometry

    private func polygon(center: CGPoint, radius: CGFloat, sides: Int, rotation: Double) -> Path {
        let step = 2.0 * .pi / Double(sides)
        var path = Path()
        for i in 0..<sides {
            let a  = Double(i) * step + rotation
            let pt = CGPoint(x: center.x + radius * CGFloat(cos(a)),
                             y: center.y + radius * CGFloat(sin(a)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

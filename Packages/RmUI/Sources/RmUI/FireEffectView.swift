import SwiftUI

/// A procedural fire/flame effect rendered with Canvas + TimelineView.
/// Intensity drives the visual progression from subtle embers to roaring flames.
struct FireEffectView: View {
    let intensity: Double
    let size: CGSize

    @State private var particles: [FireParticle] = []

    var body: some View {
        if intensity < 0.01 {
            // Static faint glow — no animation overhead
            staticGlow
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, canvasSize in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    drawFire(context: context, size: canvasSize, time: time)
                } symbols: {
                    EmptyView()
                }
                .onChange(of: timeline.date) { _, newDate in
                    updateParticles(time: newDate.timeIntervalSinceReferenceDate)
                }
            }
            .drawingGroup()
            .allowsHitTesting(false)
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Static Glow (idle)

    private var staticGlow: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.45)
            let radius = canvasSize.width * 0.25
            let gradient = Gradient(colors: [
                CorveilTheme.goldDark.opacity(0.08),
                Color.clear,
            ])
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
            )
        }
        .allowsHitTesting(false)
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Animated Fire Drawing

    private func drawFire(context: GraphicsContext, size: CGSize, time: Double) {
        let centerX = size.width / 2
        let baseY = size.height * 0.7

        // Layer 1: Ambient glow
        drawGlow(context: context, size: size, centerX: centerX, baseY: baseY)

        // Layer 2: Flame tongues (intensity > 0.15)
        if intensity > 0.15 {
            drawFlames(context: context, size: size, centerX: centerX, baseY: baseY, time: time)
        }

        // Layer 3: Spark particles (intensity > 0.5)
        if intensity > 0.5 {
            drawParticles(context: context)
        }

        // Layer 4: Heat shimmer (intensity > 0.7)
        if intensity > 0.7 {
            drawHeatShimmer(context: context, size: size, centerX: centerX, baseY: baseY, time: time)
        }
    }

    // MARK: - Layer 1: Ambient Glow

    private func drawGlow(context: GraphicsContext, size: CGSize, centerX: Double, baseY: Double) {
        let glowCenter = CGPoint(x: centerX, y: baseY - size.height * 0.15)
        let radiusX = size.width * (0.25 + intensity * 0.25)
        let radiusY = size.height * (0.2 + intensity * 0.25)
        let glowOpacity = 0.1 + intensity * 0.5

        let coreColor = interpolateColor(
            from: CorveilTheme.goldDark,
            to: CorveilTheme.fireOrange,
            t: intensity
        )

        let gradient = Gradient(colors: [
            coreColor.opacity(glowOpacity),
            coreColor.opacity(glowOpacity * 0.4),
            Color.clear,
        ])

        context.fill(
            Path(ellipseIn: CGRect(
                x: glowCenter.x - radiusX,
                y: glowCenter.y - radiusY,
                width: radiusX * 2,
                height: radiusY * 2
            )),
            with: .radialGradient(gradient, center: glowCenter, startRadius: 0, endRadius: max(radiusX, radiusY))
        )
    }

    // MARK: - Layer 2: Flame Tongues

    private func drawFlames(context: GraphicsContext, size: CGSize, centerX: Double, baseY: Double, time: Double) {
        // Number of flames scales with intensity
        let normalizedIntensity = (intensity - 0.15) / 0.85
        let flameCount = Int(3 + normalizedIntensity * 7) // 3–10 flames
        let spreadWidth = size.width * 0.6

        for i in 0..<flameCount {
            let phase = Double(i) * 1.37 // unique phase per flame
            let xOffset = (Double(i) / Double(max(flameCount - 1, 1)) - 0.5) * spreadWidth

            // Sway and height oscillation
            let sway = sin(time * 2.5 + phase) * (6 + normalizedIntensity * 8)
            let heightFactor = 0.8 + 0.2 * sin(time * 1.8 + phase * 0.7)
            let maxHeight = (20 + normalizedIntensity * 45) * heightFactor
            let flameWidth = 4 + normalizedIntensity * 6

            let flameBase = CGPoint(x: centerX + xOffset, y: baseY)
            let flameTip = CGPoint(
                x: centerX + xOffset + sway,
                y: baseY - maxHeight
            )

            let flamePath = Path { path in
                path.move(to: flameBase)
                path.addQuadCurve(
                    to: flameTip,
                    control: CGPoint(
                        x: flameBase.x - flameWidth + sway * 0.3,
                        y: flameBase.y - maxHeight * 0.5
                    )
                )
                path.addQuadCurve(
                    to: flameBase,
                    control: CGPoint(
                        x: flameBase.x + flameWidth + sway * 0.3,
                        y: flameBase.y - maxHeight * 0.5
                    )
                )
                path.closeSubpath()
            }

            let flameGradient = Gradient(colors: [
                CorveilTheme.fireCore.opacity(0.6 * normalizedIntensity),
                CorveilTheme.fireOrange.opacity(0.5 * normalizedIntensity),
                CorveilTheme.fireDeep.opacity(0.3 * normalizedIntensity),
                Color.clear,
            ])

            context.fill(
                flamePath,
                with: .linearGradient(
                    flameGradient,
                    startPoint: flameBase,
                    endPoint: flameTip
                )
            )
        }
    }

    // MARK: - Layer 3: Spark Particles

    private func drawParticles(context: GraphicsContext) {
        for particle in particles {
            let sparkSize = particle.size * CGFloat(particle.opacity)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: particle.x - sparkSize / 2,
                    y: particle.y - sparkSize / 2,
                    width: sparkSize,
                    height: sparkSize
                )),
                with: .color(CorveilTheme.fireCore.opacity(particle.opacity))
            )
        }
    }

    // MARK: - Layer 4: Heat Shimmer

    private func drawHeatShimmer(context: GraphicsContext, size: CGSize, centerX: Double, baseY: Double, time: Double) {
        let shimmerOpacity = (intensity - 0.7) / 0.3 * 0.15

        for i in 0..<3 {
            let yOffset = baseY - Double(i + 1) * 15 - 20
            let shimmerPath = Path { path in
                path.move(to: CGPoint(x: centerX - 30, y: yOffset))
                for x in stride(from: centerX - 30, through: centerX + 30, by: 2) {
                    let wave = sin(x * 0.15 + time * 3.0 + Double(i) * 2.0) * 2
                    path.addLine(to: CGPoint(x: x, y: yOffset + wave))
                }
            }
            context.stroke(
                shimmerPath,
                with: .color(CorveilTheme.fireCore.opacity(shimmerOpacity)),
                lineWidth: 0.8
            )
        }
    }

    // MARK: - Particle System

    private func updateParticles(time: Double) {
        guard intensity > 0.5 else {
            particles.removeAll()
            return
        }

        let normalizedIntensity = (intensity - 0.5) / 0.5
        let maxParticles = Int(5 + normalizedIntensity * 10) // 5–15

        // Age existing particles
        particles = particles.compactMap { p in
            var particle = p
            particle.y -= particle.vy
            particle.x += sin(time * 3 + particle.phase) * 0.5
            particle.opacity -= 0.02
            particle.lifetime -= 1
            return particle.lifetime > 0 && particle.opacity > 0 ? particle : nil
        }

        // Spawn new particles
        while particles.count < maxParticles {
            let spread = size.width * 0.3
            particles.append(FireParticle(
                x: size.width / 2 + Double.random(in: -spread...spread),
                y: size.height * 0.5 + Double.random(in: -10...10),
                vy: Double.random(in: 0.5...1.5),
                phase: Double.random(in: 0...(.pi * 2)),
                opacity: Double.random(in: 0.3...0.8) * normalizedIntensity,
                size: CGFloat.random(in: 1.5...3.0),
                lifetime: Int.random(in: 20...40)
            ))
        }
    }

    // MARK: - Helpers

    private func interpolateColor(from: Color, to: Color, t: Double) -> Color {
        // Use resolved colors for interpolation
        let clamped = max(0, min(1, t))
        return Color(
            red: lerp(from: colorComponent(from, \.red), to: colorComponent(to, \.red), t: clamped),
            green: lerp(from: colorComponent(from, \.green), to: colorComponent(to, \.green), t: clamped),
            blue: lerp(from: colorComponent(from, \.blue), to: colorComponent(to, \.blue), t: clamped)
        )
    }

    private func lerp(from: Double, to: Double, t: Double) -> Double {
        from + (to - from) * t
    }

    private func colorComponent(_ color: Color, _ keyPath: KeyPath<Color.Resolved, Float>) -> Double {
        Double(color.resolve(in: EnvironmentValues()).component(keyPath))
    }
}

// MARK: - Fire Particle

private struct FireParticle {
    var x: Double
    var y: Double
    var vy: Double
    var phase: Double
    var opacity: Double
    var size: CGFloat
    var lifetime: Int
}

// MARK: - Color.Resolved helper

private extension Color.Resolved {
    func component(_ keyPath: KeyPath<Color.Resolved, Float>) -> Float {
        self[keyPath: keyPath]
    }
}

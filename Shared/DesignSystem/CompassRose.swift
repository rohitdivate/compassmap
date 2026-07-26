import SwiftUI

/// The tapered dart that points at a spot.
///
/// Drawn rather than symbol-based so the silhouette is ours: a long tip, swept wings and a
/// deep tail notch, which reads as direction even at widget size.
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        path.move(to: p(0.5, 0.0))
        path.addQuadCurve(to: p(0.94, 0.88), control: p(0.74, 0.42))
        path.addQuadCurve(to: p(0.5, 0.66), control: p(0.68, 0.80))
        path.addQuadCurve(to: p(0.06, 0.88), control: p(0.32, 0.80))
        path.addQuadCurve(to: p(0.5, 0.0), control: p(0.26, 0.42))
        path.closeSubpath()
        return path
    }
}

/// The big arrow on the compass screen.
struct DirectionArrow: View {
    var theme: Theme
    /// Degrees to rotate. Pass an *unwrapped* angle (see `BearingMath.unwrapped`) so the
    /// arrow turns the short way when the heading crosses north.
    var angle: Double
    /// True when the phone is pointing close enough to count as "that way".
    var onTarget: Bool
    /// 0 far away, 1 practically there. Drives how hot the glow runs.
    var proximity: Double = 0
    var size: CGFloat = 190

    var body: some View {
        ZStack {
            // Glow sits behind and grows with proximity, so the arrow visibly heats up as
            // you close in without any text having to tell you.
            ArrowShape()
                .fill(theme.glow)
                .frame(width: size * 0.62, height: size)
                .blur(radius: onTarget ? 26 : 16)
                .opacity(0.30 + proximity * 0.45 + (onTarget ? 0.2 : 0))

            ArrowShape()
                .fill(theme.arrowGradient)
                .overlay {
                    // A single specular sweep along the leading edge.
                    ArrowShape()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .clear, .white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                }
                .overlay {
                    ArrowShape()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                }
                .frame(width: size * 0.62, height: size)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        }
        .rotationEffect(.degrees(angle))
        .scaleEffect(onTarget ? 1.06 : 1.0)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: onTarget)
        .animation(.interpolatingSpring(stiffness: 90, damping: 14), value: angle)
        .accessibilityHidden(true)
    }
}

/// The ring the arrow sits inside: ticks every five degrees, cardinal letters, and a pip on
/// the bearing of the spot you are heading to.
struct CompassRose: View {
    var theme: Theme
    /// Unwrapped device heading in degrees. The rose counter-rotates by this.
    var heading: Double
    /// Absolute bearing of the target, if there is one.
    var targetBearing: Double?
    var onTarget: Bool
    var diameter: CGFloat = 300

    var body: some View {
        ZStack {
            // Base plate
            Circle()
                .fill(.ultraThinMaterial)
                .overlay { Circle().fill(theme.deepest.opacity(0.35)) }
                .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1) }

            // On-target halo
            Circle()
                .strokeBorder(theme.glow, lineWidth: 2)
                .blur(radius: 6)
                .opacity(onTarget ? 0.9 : 0)
                .animation(.easeInOut(duration: 0.25), value: onTarget)

            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                for degrees in stride(from: 0, to: 360, by: 5) {
                    let isCardinal = degrees % 90 == 0
                    let isMajor = degrees % 30 == 0
                    let length: CGFloat = isCardinal ? 16 : (isMajor ? 11 : 6)
                    let width: CGFloat = isCardinal ? 2.4 : (isMajor ? 1.6 : 1)
                    let opacity: Double = isCardinal ? 0.95 : (isMajor ? 0.6 : 0.3)

                    let radians = (Double(degrees) - 90) * .pi / 180
                    let outer = CGPoint(
                        x: centre.x + cos(radians) * (radius - 12),
                        y: centre.y + sin(radians) * (radius - 12)
                    )
                    let inner = CGPoint(
                        x: centre.x + cos(radians) * (radius - 12 - length),
                        y: centre.y + sin(radians) * (radius - 12 - length)
                    )

                    var tick = Path()
                    tick.move(to: inner)
                    tick.addLine(to: outer)
                    context.stroke(
                        tick,
                        with: .color(isCardinal ? theme.accent.opacity(opacity) : theme.text.opacity(opacity)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round)
                    )
                }

                for (degrees, letter) in [(0, "N"), (90, "E"), (180, "S"), (270, "W")] {
                    let radians = (Double(degrees) - 90) * .pi / 180
                    let point = CGPoint(
                        x: centre.x + cos(radians) * (radius - 42),
                        y: centre.y + sin(radians) * (radius - 42)
                    )
                    context.draw(
                        Text(letter)
                            .font(Typography.tick)
                            .foregroundColor(degrees == 0 ? theme.accent : theme.textMuted),
                        at: point
                    )
                }

                // Where the spot actually is, marked on the ring.
                if let targetBearing {
                    let radians = (targetBearing - 90) * .pi / 180
                    let point = CGPoint(
                        x: centre.x + cos(radians) * (radius - 6),
                        y: centre.y + sin(radians) * (radius - 6)
                    )
                    let pip = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                    context.fill(pip, with: .color(theme.accent))
                    context.stroke(pip, with: .color(.white.opacity(0.7)), lineWidth: 1)
                }
            }
            .padding(2)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-heading))
        .animation(.interpolatingSpring(stiffness: 70, damping: 13), value: heading)
        .accessibilityHidden(true)
    }
}

/// Tiny arrow used on gallery cards, list rows and widgets, where there is no room for a
/// rose. Points using the same geometry as the big one.
struct MiniArrow: View {
    var theme: Theme
    var angle: Double
    var size: CGFloat = 26
    var filled: Bool = true

    var body: some View {
        ArrowShape()
            .fill(filled ? AnyShapeStyle(theme.arrowGradient) : AnyShapeStyle(theme.text.opacity(0.7)))
            .frame(width: size * 0.62, height: size)
            .rotationEffect(.degrees(angle))
            .animation(.interpolatingSpring(stiffness: 110, damping: 15), value: angle)
            .accessibilityHidden(true)
    }
}

/// Concentric rings that breathe outward — used behind the arrow while a heading session is
/// live, and on the map as range rings.
struct RadarRings: View {
    var theme: Theme
    var ringCount: Int = 3
    var diameter: CGFloat = 320

    /// Seconds for one ring to travel from the centre to the edge.
    var period: Double = 3.6

    var body: some View {
        // Driven from the clock rather than from an animated `@State`: the rings wrap around
        // continuously, and a wrapping value is exactly what SwiftUI's interpolation cannot
        // animate sensibly.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate / period
            ZStack {
                ForEach(0..<ringCount, id: \.self) { index in
                    let progress = (time + Double(index) / Double(ringCount))
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(theme.accent.opacity(0.45 * (1 - progress)), lineWidth: 1.5)
                        .scaleEffect(0.3 + progress * 0.7)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

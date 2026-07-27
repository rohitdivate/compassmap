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

    // Split into typed sub-views rather than one long chain: as a single expression this body
    // exceeded the type-checker's budget and failed to compile.
    var body: some View {
        ZStack {
            glow
            dart
        }
        .rotationEffect(.degrees(angle))
        .scaleEffect(onTarget ? 1.06 : 1.0)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: onTarget)
        .animation(.interpolatingSpring(stiffness: 90, damping: 14), value: angle)
        .accessibilityHidden(true)
    }

    /// Sits behind the arrow and grows with proximity, so the arrow visibly heats up as you
    /// close in without any text having to say so.
    private var glow: some View {
        ArrowShape()
            .fill(theme.glow)
            .frame(width: size * 0.62, height: size)
            .blur(radius: onTarget ? 26 : 16)
            .opacity(glowOpacity)
    }

    private var glowOpacity: Double {
        let base = 0.30 + proximity * 0.45
        return base + (onTarget ? 0.20 : 0)
    }

    private var dart: some View {
        ArrowShape()
            .fill(theme.arrowGradient)
            .overlay { specular }
            .overlay { ArrowShape().stroke(.white.opacity(0.35), lineWidth: 1) }
            .frame(width: size * 0.62, height: size)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }

    /// A single sweep of light along the leading edge.
    private var specular: some View {
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
    /// True when the rose sits on a photograph rather than on the canvas. A white card reads as a
    /// hole punched in the picture; a dark translucent disc reads as glass laid over it.
    var onPhoto: Bool = false

    // As with the arrow, this is deliberately split: the whole rose in one expression exceeds
    // the type-checker's budget.
    var body: some View {
        ZStack {
            basePlate
            halo
            Canvas(rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size)
            }
            .padding(2)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-heading))
        .animation(.interpolatingSpring(stiffness: 70, damping: 13), value: heading)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var basePlate: some View {
        if onPhoto {
            Circle()
                .fill(.black.opacity(0.22))
                .overlay { Circle().strokeBorder(.white.opacity(0.20), lineWidth: 1) }
        } else {
            Circle()
                .fill(theme.surface)
                .overlay { Circle().strokeBorder(theme.hairline, lineWidth: 1) }
                .modifier(RoseShadow(theme: theme))
        }
    }

    /// Lights up when the phone comes onto the bearing.
    private var halo: some View {
        Circle()
            .strokeBorder(theme.glow, lineWidth: 2)
            .blur(radius: 6)
            .opacity(onTarget ? 0.9 : 0)
            .animation(.easeInOut(duration: 0.25), value: onTarget)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2

        drawTicks(in: &context, centre: centre, radius: radius)
        drawCardinals(in: &context, centre: centre, radius: radius)
        drawTargetPip(in: &context, centre: centre, radius: radius)
    }

    /// A tick every five degrees, longer at the thirties and longer again at the cardinals.
    private func drawTicks(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        for degrees in stride(from: 0, to: 360, by: 5) {
            let isCardinal = degrees % 90 == 0
            let isMajor = degrees % 30 == 0
            let length: CGFloat = isCardinal ? 16 : (isMajor ? 11 : 6)
            let lineWidth: CGFloat = isCardinal ? 2.4 : (isMajor ? 1.6 : 1)
            let opacity: Double = isCardinal ? 0.95 : (isMajor ? 0.6 : 0.3)

            let outer = point(on: centre, radius: radius - 12, degrees: Double(degrees))
            let inner = point(on: centre, radius: radius - 12 - length, degrees: Double(degrees))

            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)

            let colour = isCardinal ? theme.accent : (onPhoto ? Color.white : theme.text)
            context.stroke(
                tick,
                with: .color(colour.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }

    private func drawCardinals(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let cardinals: [(Double, String)] = [(0, "N"), (90, "E"), (180, "S"), (270, "W")]
        for (degrees, letter) in cardinals {
            let position = point(on: centre, radius: radius - 42, degrees: degrees)
            let colour = degrees == 0 ? theme.accent : (onPhoto ? Color.white.opacity(0.7) : theme.textMuted)
            context.draw(
                Text(letter).font(theme.tickFont).foregroundColor(colour),
                at: position
            )
        }
    }

    /// Where the spot actually is, marked on the ring.
    private func drawTargetPip(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        guard let targetBearing else { return }
        let position = point(on: centre, radius: radius - 6, degrees: targetBearing)
        let box = CGRect(x: position.x - 5, y: position.y - 5, width: 10, height: 10)
        let pip = Path(ellipseIn: box)
        context.fill(pip, with: .color(theme.accent))
        context.stroke(pip, with: .color(.white.opacity(0.7)), lineWidth: 1)
    }

    /// Compass degrees to a point on the ring, with zero at the top rather than at three o'clock.
    ///
    /// The trigonometry is done in `Double` and converted once at the end: mixing `Double` and
    /// `CGFloat` in the same expression leaves `cos` and `sin` genuinely ambiguous.
    private func point(on centre: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        let distance = Double(radius)
        return CGPoint(
            x: centre.x + CGFloat(cos(radians) * distance),
            y: centre.y + CGFloat(sin(radians) * distance)
        )
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
        Group {
            if AppSettings.isUITesting {
                // XCUITest waits for the app to go idle before every interaction, and a 30 fps
                // clock that never stops means it never does — every tap stalls out its 60 s
                // animation budget. Under the test seam the rings hold one frame.
                rings(at: 0.5)
            } else {
                // Driven from the clock rather than from an animated `@State`: the rings wrap
                // around continuously, and a wrapping value is exactly what SwiftUI's
                // interpolation cannot animate sensibly.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    rings(at: context.date.timeIntervalSinceReferenceDate / period)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rings(at time: Double) -> some View {
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
}

/// The rose sits on a card, so it takes the theme's card shadow — which is nothing at all in a
/// hairline mood.
private struct RoseShadow: ViewModifier {
    var theme: Theme

    func body(content: Content) -> some View {
        if let shadow = theme.cardShadow {
            content.shadow(color: shadow.color, radius: shadow.radius * 3, y: shadow.y * 3)
        } else {
            content
        }
    }
}

import SwiftUI

/// The backdrop every screen sits on.
///
/// On iOS 18 and later it is a nine-point mesh gradient that drifts very slowly, which
/// gives the app the feeling of light moving on water. On iOS 17 it falls back to the
/// theme's linear gradient plus two soft radial blooms — different, but of the same family,
/// never obviously degraded.
struct ThemedBackground: View {
    var theme: Theme
    /// Slow drift. Worth it on the hero screens, wasteful everywhere else.
    var animated: Bool = false
    /// Warms the palette toward golden hour and cools it after dark.
    var timeTint: Bool = true

    var body: some View {
        ZStack {
            base
            bottomScrim
            if timeTint {
                TimeOfDay.current.overlay(for: theme)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            FilmGrain(opacity: theme.grainOpacity)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// Every backdrop runs warm and bright at its foot — which is exactly where the floating bar
    /// sits. Without this the tab labels land light-on-light and effectively disappear. Deep at the
    /// top, the sunset band through the middle, and deep again at the bottom also simply looks
    /// better: like watching the light from inside a dark room.
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.70),
                .init(color: theme.deepest.opacity(0.50), location: 0.88),
                .init(color: theme.deepest.opacity(0.80), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var base: some View {
        if #available(iOS 18.0, *) {
            MeshBackdrop(theme: theme, animated: animated)
        } else {
            LegacyBackdrop(theme: theme)
        }
    }
}

// MARK: - iOS 18 mesh

@available(iOS 18.0, *)
private struct MeshBackdrop: View {
    var theme: Theme
    var animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                mesh(phase: t)
            }
        } else {
            mesh(phase: 0)
        }
    }

    private func mesh(phase: Double) -> some View {
        // Corners stay pinned so the gradient never pulls away from the screen edges; only
        // the interior points wander, which is what makes the light look alive.
        let drift = { (i: Int, amount: Float) -> Float in
            Float(sin(phase * 0.11 + Double(i) * 1.7)) * amount
        }

        let points: [SIMD2<Float>] = [
            SIMD2(0.0, 0.0), SIMD2(0.5 + drift(0, 0.06), 0.0), SIMD2(1.0, 0.0),
            SIMD2(0.0, 0.5 + drift(1, 0.05)),
            SIMD2(0.5 + drift(2, 0.10), 0.5 + drift(3, 0.08)),
            SIMD2(1.0, 0.5 + drift(4, 0.05)),
            SIMD2(0.0, 1.0), SIMD2(0.5 + drift(5, 0.06), 1.0), SIMD2(1.0, 1.0),
        ]

        return MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: theme.mesh.count == 9 ? theme.mesh : Array(repeating: theme.deepest, count: 9),
            smoothsColors: true
        )
    }
}

// MARK: - iOS 17 fallback

private struct LegacyBackdrop: View {
    var theme: Theme

    var body: some View {
        ZStack {
            theme.backdropGradient
            RadialGradient(
                colors: [theme.accent.opacity(0.35), .clear],
                center: UnitPoint(x: 0.85, y: 0.12),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [theme.accentSoft.opacity(0.22), .clear],
                center: UnitPoint(x: 0.1, y: 0.8),
                startRadius: 0,
                endRadius: 380
            )
        }
    }
}

// MARK: - Grain

/// A fixed field of faint dots laid over the gradient.
///
/// Flat gradients on OLED show banding; a little noise hides it and gives the whole thing a
/// printed, sun-faded quality. The field is generated from a fixed seed so it never
/// shimmers between redraws.
struct FilmGrain: View {
    var opacity: Double
    var density: Int = 1400

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: 0x5EED_1234)
            for _ in 0..<density {
                let x = Double(rng.nextUnit()) * size.width
                let y = Double(rng.nextUnit()) * size.height
                let r = 0.4 + Double(rng.nextUnit()) * 1.1
                let shade = 0.5 + Double(rng.nextUnit()) * 0.5
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(.white.opacity(shade))
                )
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
        .drawingGroup()
    }
}

/// Small deterministic PRNG so procedural texture is stable across redraws.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<1`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A value in the given closed range.
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Time of day

/// The app warms up toward sunset and cools down after dark. Small effect, and the reason
/// the same theme feels different at 7am and 7pm.
enum TimeOfDay {
    case dawn, day, goldenHour, dusk, night

    static var current: TimeOfDay { at(Date()) }

    static func at(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<8: return .dawn
        case 8..<16: return .day
        case 16..<19: return .goldenHour
        case 19..<21: return .dusk
        default: return .night
        }
    }

    @ViewBuilder
    func overlay(for theme: Theme) -> some View {
        switch self {
        case .dawn:
            LinearGradient(
                colors: [theme.accentSoft.opacity(0.10), .clear],
                startPoint: .top, endPoint: .center
            )
        case .day:
            Color.white.opacity(0.03)
        case .goldenHour:
            LinearGradient(
                colors: [.clear, theme.accent.opacity(0.16)],
                startPoint: .top, endPoint: .bottom
            )
        case .dusk:
            LinearGradient(
                colors: [.clear, theme.accent.opacity(0.10)],
                startPoint: .center, endPoint: .bottom
            )
        case .night:
            Color.clear
        }
    }
}

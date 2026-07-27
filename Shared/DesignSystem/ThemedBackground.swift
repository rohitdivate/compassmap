import SwiftUI

/// The backdrop every screen sits on: a flat canvas, and in Tropical Spritz a little grain.
///
/// This used to be a nine-point mesh gradient. Both moods in the design forbid that. Spritz allows
/// "one gradient per screen, always behind a photo or as the hero — never on a button", so the
/// canvas itself is flat cream and the gradient belongs to `HeroPanel`. Nomad forbids gradients
/// outright: "no decoration — density is the aesthetic." What is left is deliberately plain, and the
/// screens are stronger for it — the colour now comes from the photographs and the accent.
struct ThemedBackground: View {
    var theme: Theme

    var body: some View {
        ZStack {
            theme.canvas
            if theme.grainOpacity > 0 {
                // Spritz is paper, and paper has tooth. Nomad is a screen and takes none.
                FilmGrain(opacity: theme.grainOpacity, tint: theme.text)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// The one gradient a screen is allowed, in the moods that allow one.
///
/// In Spritz this is Sunset Wash behind a hero header; in Nomad it resolves to a flat raised surface,
/// because that mood permits no gradient at all. Callers do not need to know which — they ask for a
/// hero panel and get whatever the theme's rules permit.
struct HeroPanel<Content: View>: View {
    var theme: Theme
    /// Rounded on three sides when it sits inside a screen; square when it is the top of one.
    var cornerRadius: CGFloat = 0
    /// The sky outside — Spritz's wash follows it through the day.
    var phase: TimeOfDay = .current
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                ZStack {
                    Rectangle().fill(theme.heroFill(for: phase))
                    if theme.heroGradient != nil {
                        // A soft bloom in the top-left, as the reference screen has it.
                        RadialGradient(
                            colors: [theme.canvas.opacity(0.35), .clear],
                            center: UnitPoint(x: 0.2, y: 0.1),
                            startRadius: 0,
                            endRadius: 320
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Grain

/// A fixed field of faint dots laid over the canvas.
///
/// Generated from a fixed seed so it never shimmers between redraws. The tint follows the theme's
/// ink rather than always being white: on cream paper, white noise is invisible and dark noise is
/// what reads as texture.
struct FilmGrain: View {
    var opacity: Double
    var tint: Color = .white
    var density: Int = 1400

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: 0x5EED_1234)
            for _ in 0..<density {
                let x = rng.nextUnit() * size.width
                let y = rng.nextUnit() * size.height
                let r = 0.4 + rng.nextUnit() * 1.1
                let shade = 0.5 + rng.nextUnit() * 0.5
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(tint.opacity(shade))
                )
            }
        }
        .opacity(opacity)
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

/// Used for the greeting above the app title — "Golden hour", "After dark".
///
/// This used to tint the whole backdrop as well. That is gone: both moods are explicit about how much
/// decoration they permit, and a drifting colour wash over the canvas is not among it. The copy
/// survives because it costs nothing and both moods want warm, short wording.
// TimeOfDay moved to Shared/Snapshot/LivingPalette.swift, where its boundaries are testable
// and the sky-reactive palettes live beside it.

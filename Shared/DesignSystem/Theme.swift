import SwiftUI

/// How a theme builds depth.
///
/// This is the difference between the two moods that colour alone cannot carry. Tropical Spritz
/// lifts white cards off a cream canvas with soft shadows; Nomad Money forbids shadows outright and
/// separates everything with a 1pt hairline, using a lighter surface as its only elevation cue.
enum Elevation: Hashable, Sendable {
    /// Cards are a lighter surface than the canvas, lifted on a soft shadow.
    case shadow
    /// Cards are separated by hairline borders. Elevation is a lighter fill, never a shadow.
    case hairline
}

/// Which family a theme sets its numerals in.
enum NumeralStyle: Hashable, Sendable {
    /// Proportional monospace — DM Mono. "Serif for feeling, mono for fact."
    case mono
    /// Tabular monospace — JetBrains Mono with `tabular-nums`, so columns of figures line up.
    case tabularMono
}

/// The corner radii a theme uses, which the two moods specify quite differently: Spritz is round
/// (999 pills, 20 cards), Nomad is tight (10 buttons, 14 rows, 16 cards).
struct Radii: Hashable, Sendable {
    /// Buttons and chips. A large value produces a pill.
    var control: CGFloat
    var card: CGFloat
    var row: CGFloat
    var avatar: CGFloat
    /// The inner corner of a phone screen, used by the preview and any full-bleed sheet.
    var screen: CGFloat

    var isPill: Bool { control >= 100 }
}

/// One complete look: palette, surfaces, type roles, radii and the rules for depth.
///
/// Both moods come from the Been There theme reference. They are not two colourways of one design —
/// one is a light editorial travel magazine, the other a dark financial ledger — so `Theme` carries
/// structure as well as colour. Every screen, component and widget reads from here, and there are no
/// ad-hoc colours anywhere else in the project.
struct Theme: Identifiable, Hashable, Sendable {

    let id: String
    let name: String
    /// One line of flavour, shown under the name in the picker.
    let tagline: String
    /// Longer characterisation, from the design's own description of the mood.
    let blurb: String
    /// SF Symbol used as the theme's mark.
    let symbol: String

    /// Light or dark. Each theme fixes its own rather than following the system, because neither
    /// mood survives being inverted.
    let colorScheme: ColorScheme

    // MARK: Surfaces

    /// The page. Cream in Spritz, near-black in Nomad.
    let canvas: Color
    /// Cards and rows sitting on the canvas.
    let surface: Color
    /// A step above `surface` — Nomad's only elevation cue; a pressed or nested state in Spritz.
    let surfaceRaised: Color
    /// Border colour. Load-bearing in Nomad, a whisper in Spritz.
    let hairline: Color
    let elevation: Elevation

    // MARK: Colour

    /// The primary action and identity colour.
    let accent: Color
    /// Text and glyphs placed on top of `accent`.
    let onAccent: Color
    /// A darker cut of the accent, used for the hard-offset button shadow in Spritz.
    let accentShadow: Color
    /// The second colour, for contrast against `accent`.
    let secondary: Color
    /// Reserved for badges, progress and toggles-on. "Lime is a highlight, not a surface."
    let highlight: Color
    /// Text and glyphs on `highlight`.
    let onHighlight: Color
    /// Deep counterweight — Spritz's "You're in" card, Nomad's raised chrome.
    let depth: Color

    let text: Color
    let textMuted: Color
    /// Tertiary — the 10-11px mono caps labels.
    let textFaint: Color

    /// Positive and negative deltas. Nomad's rules require them; Spritz uses them sparingly.
    let positive: Color
    let negative: Color

    // MARK: Signature

    /// The one gradient a Spritz screen is allowed, behind a photo or as the hero. Nil in Nomad,
    /// which forbids gradients entirely.
    let heroGradient: [Color]?
    /// The halo behind the arrow. Nomad keeps this to almost nothing — one accent, no decoration.
    let glow: Color
    /// Gradient along the arrow, tip last.
    let arrow: [Color]
    /// Palette for the arrival celebration.
    let celebration: [Color]
    /// Film grain over the backdrop. Spritz is paper and takes some; Nomad is a screen and takes none.
    let grainOpacity: Double

    // MARK: Type

    /// Display face — screen titles and headline numbers-adjacent text.
    let displayFont: String
    /// Body face.
    let bodyFont: String
    let bodyMediumFont: String
    let bodyBoldFont: String
    /// Numerals, labels, metadata.
    let monoFont: String
    let monoMediumFont: String
    let numerals: NumeralStyle
    /// Tracking for the display face. Both moods set it tight, Nomad more so.
    let displayTracking: CGFloat
    let scale: TypeScale

    let radii: Radii

    // MARK: - Derived

    /// True when the theme wants hairlines rather than shadows.
    var usesHairlines: Bool { elevation == .hairline }

    /// Shadow for a card, or nothing at all in a hairline theme.
    var cardShadow: (color: Color, radius: CGFloat, y: CGFloat)? {
        guard elevation == .shadow else { return nil }
        return (text.opacity(0.10), 3, 1)
    }

    /// The gradient a hero area uses. Falls back to a flat canvas where the mood forbids gradients.
    var heroFill: AnyShapeStyle {
        if let heroGradient {
            return AnyShapeStyle(LinearGradient(
                colors: heroGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(depth)
    }

    var arrowGradient: LinearGradient {
        LinearGradient(colors: arrow, startPoint: .bottom, endPoint: .top)
    }

    /// Colour for text and glyphs drawn over `heroFill`.
    var onHero: Color {
        heroGradient == nil ? text : Color.white
    }
}

/// The two moods from the Been There theme reference.
///
/// Palettes, type roles and radii are transcribed from that file; the swatch names are its names.
enum ThemeCatalog {

    /// Theme A — sun-soaked, editorial, tactile. Postcard warmth: cream paper, sunset photography,
    /// a serif that behaves like a travel magazine masthead. Colour does the emotional work while
    /// numerals stay mono so stats still read as data.
    static let tropicalSpritz = Theme(
        id: "tropicalSpritz",
        name: "Tropical Spritz",
        tagline: "Sun-soaked, editorial, tactile",
        blurb: "Postcard warmth. Cream paper, sunset photography, and a serif that behaves like a travel magazine masthead.",
        symbol: "sun.horizon.fill",
        colorScheme: .light,

        canvas: Color(hex: "#FFF6E9"),        // Piña Cream
        surface: Color(hex: "#FFFFFF"),       // white is reserved for cards, so they lift
        surfaceRaised: Color(hex: "#FFEBD9"),
        hairline: Color(hex: "#2B1B22").opacity(0.10),
        elevation: .shadow,

        accent: Color(hex: "#FF6B8B"),        // Paloma Pink · primary
        onAccent: Color(hex: "#FFFFFF"),
        accentShadow: Color(hex: "#D8456B"),  // the hard-offset button shadow
        secondary: Color(hex: "#1FA3B8"),     // Lagoon Blue
        highlight: Color(hex: "#B8E62E"),     // Margarita Lime · badges, progress, toggles on
        onHighlight: Color(hex: "#2B1B22"),
        depth: Color(hex: "#0E5C6B"),         // Deep Lagoon

        text: Color(hex: "#2B1B22"),          // Cacao Ink
        textMuted: Color(hex: "#2B1B22").opacity(0.66),
        textFaint: Color(hex: "#2B1B22").opacity(0.45),

        positive: Color(hex: "#3FA96B"),
        negative: Color(hex: "#D8456B"),

        // Sunset Wash — hero overlays only, never on a button.
        heroGradient: [Color(hex: "#FF8C42"), Color(hex: "#FF6B8B"), Color(hex: "#B06AB3")],
        glow: Color(hex: "#FF8C42"),          // Sunset Coral
        arrow: [Color(hex: "#D8456B"), Color(hex: "#FF6B8B"), Color(hex: "#FFB08C")],
        celebration: [
            Color(hex: "#FF6B8B"), Color(hex: "#FF8C42"),
            Color(hex: "#B8E62E"), Color(hex: "#1FA3B8"),
        ],
        grainOpacity: 0.035,

        displayFont: Fonts.Serif.regular,
        bodyFont: Fonts.Sans.regular,
        bodyMediumFont: Fonts.Sans.medium,
        bodyBoldFont: Fonts.Sans.bold,
        monoFont: Fonts.Mono.regular,
        monoMediumFont: Fonts.Mono.medium,
        numerals: .mono,
        displayTracking: -0.4,
        scale: TypeScale(
            display: 40, title: 27, sectionHead: 20, cardTitle: 15, body: 15,
            caption: 12, label: 11, eyebrow: 10.5, readout: 34, cardNumber: 26
        ),

        // 999 pills, 20 cards, 16 rows, 14 avatars, 36 screen.
        radii: Radii(control: 999, card: 20, row: 16, avatar: 14, screen: 36)
    )

    /// Theme B — Mercury × Revolut, tabular. Travel treated like a ledger: near-black surfaces,
    /// hairline borders, tabular numerals with delta chips, and exactly one accent doing all the
    /// signalling. No decoration; density is the aesthetic.
    static let nomadMoney = Theme(
        id: "nomadMoney",
        name: "Nomad Money",
        tagline: "Tabular, hairline, one accent",
        blurb: "Travel as a ledger. Near-black surfaces, hairline borders, and exactly one accent doing all the signalling.",
        symbol: "chart.bar.fill",
        colorScheme: .dark,

        canvas: Color(hex: "#0A0B0D"),        // Void
        surface: Color(hex: "#131519"),       // Surface
        surfaceRaised: Color(hex: "#1A1D22"),
        hairline: Color(hex: "#23262C"),      // Hairline · borders
        elevation: .hairline,

        accent: Color(hex: "#C6F24E"),        // Electric Lime · the only accent
        onAccent: Color(hex: "#0A0B0D"),
        accentShadow: Color(hex: "#7E8F3C"),
        secondary: Color(hex: "#8A9099"),     // Muted
        highlight: Color(hex: "#C6F24E"),
        onHighlight: Color(hex: "#0A0B0D"),
        depth: Color(hex: "#1A1D22"),

        text: Color(hex: "#F2F4F7"),          // Paper
        textMuted: Color(hex: "#8A9099"),     // Muted
        textFaint: Color(hex: "#5E646D"),

        positive: Color(hex: "#4ADE80"),      // Gain
        negative: Color(hex: "#FF6B5C"),      // Drop

        heroGradient: nil,                    // no gradients in this mood
        glow: Color(hex: "#C6F24E").opacity(0.55),
        arrow: [Color(hex: "#7E8F3C"), Color(hex: "#9CBB3E"), Color(hex: "#C6F24E")],
        celebration: [
            Color(hex: "#C6F24E"), Color(hex: "#9CBB3E"),
            Color(hex: "#4ADE80"), Color(hex: "#F2F4F7"),
        ],
        grainOpacity: 0,

        displayFont: Fonts.Grotesk.bold,
        bodyFont: Fonts.Grotesk.regular,
        bodyMediumFont: Fonts.Grotesk.medium,
        bodyBoldFont: Fonts.Grotesk.bold,
        monoFont: Fonts.GroteskMono.regular,
        monoMediumFont: Fonts.GroteskMono.medium,
        numerals: .tabularMono,
        displayTracking: -0.9,
        scale: TypeScale(
            display: 28, title: 22, sectionHead: 17, cardTitle: 14, body: 14.5,
            caption: 11.5, label: 10.5, eyebrow: 10, readout: 32, cardNumber: 24
        ),

        // 10 buttons, 14 rows, 16 cards, 9 avatars, 36 screen.
        radii: Radii(control: 10, card: 16, row: 14, avatar: 9, screen: 36)
    )

    static let all: [Theme] = [tropicalSpritz, nomadMoney]

    static let fallback = tropicalSpritz

    static func theme(id: String?) -> Theme {
        guard let id, let match = all.first(where: { $0.id == id }) else { return fallback }
        return match
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = ThemeCatalog.fallback
}

extension EnvironmentValues {
    /// The active theme. Injected once at the root and read by every component.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

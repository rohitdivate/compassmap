import SwiftUI

/// One complete look for the app: backdrop, arrow, glow, type colour, confetti.
///
/// Every screen and every widget reads its colour from a `Theme` — there are no ad-hoc
/// colours anywhere else in the project. Adding a theme is adding one entry to
/// `ThemeCatalog.all`, and it restyles the whole app including the home-screen widgets.
struct Theme: Identifiable, Hashable, Sendable {

    let id: String
    /// Shown in the picker.
    let name: String
    /// One line of flavour, shown under the name.
    let tagline: String
    /// SF Symbol used as the theme's mark in the picker.
    let symbol: String

    /// Backdrop gradient, top to bottom. Three or more stops.
    let backdrop: [Color]
    /// Nine colours laid out row-major for `MeshGradient` on iOS 18+. On iOS 17 the
    /// backdrop gradient is used instead, so this is enrichment and never a requirement.
    let mesh: [Color]

    /// Primary interactive colour: the arrow, the active chip, the ring when on target.
    let accent: Color
    /// Secondary accent, used for contrast against `accent` (the "citrus vs soda" pairing).
    let accentSoft: Color
    /// Gradient along the arrow, tip last.
    let arrow: [Color]
    /// The halo that blooms when the phone is pointing at the spot.
    let glow: Color

    let text: Color
    let textMuted: Color
    /// Tint layered under the frosted glass of cards and sheets.
    let cardTint: Color
    /// Palette for the arrival celebration.
    let celebration: [Color]

    /// How much film grain to lay over the backdrop. Small numbers; 0.05 is plenty.
    let grainOpacity: Double

    // MARK: - Derived

    var backdropGradient: LinearGradient {
        LinearGradient(colors: backdrop, startPoint: .top, endPoint: .bottom)
    }

    var arrowGradient: LinearGradient {
        LinearGradient(colors: arrow, startPoint: .bottom, endPoint: .top)
    }

    /// Deepest backdrop stop — used where a solid colour is needed (widget backgrounds,
    /// launch screen, map tint).
    var deepest: Color { backdrop.first ?? .black }

    /// Lightest backdrop stop.
    var shallowest: Color { backdrop.last ?? accent }
}

/// The six looks that ship with Tradewind. Tropical islands and long drinks: the two
/// things worth walking somewhere for.
enum ThemeCatalog {

    static let margarita = Theme(
        id: "margarita",
        name: "Margarita",
        tagline: "Lime zest, agave, salt on the rim",
        symbol: "leaf.fill",
        backdrop: [Color(hex: "#04231C"), Color(hex: "#0D4936"), Color(hex: "#1E8158")],
        mesh: [
            Color(hex: "#04231C"), Color(hex: "#07352A"), Color(hex: "#0B4433"),
            Color(hex: "#0D4936"), Color(hex: "#16694A"), Color(hex: "#2A8F5F"),
            Color(hex: "#1E8158"), Color(hex: "#5DAE6B"), Color(hex: "#C6F24E"),
        ],
        accent: Color(hex: "#C6F24E"),
        accentSoft: Color(hex: "#F3EBCF"),
        arrow: [Color(hex: "#4FBE71"), Color(hex: "#C6F24E"), Color(hex: "#EEFFA8")],
        glow: Color(hex: "#C6F24E"),
        text: Color(hex: "#F5FCEA"),
        textMuted: Color(hex: "#A6C69A"),
        cardTint: Color(hex: "#0B4433"),
        celebration: [
            Color(hex: "#C6F24E"), Color(hex: "#F3EBCF"),
            Color(hex: "#E3B23C"), Color(hex: "#6FD69A"),
        ],
        grainOpacity: 0.05
    )

    static let paloma = Theme(
        id: "paloma",
        name: "Paloma",
        tagline: "Grapefruit, soda, pink salt",
        symbol: "bird.fill",
        backdrop: [Color(hex: "#1E0B2B"), Color(hex: "#722A57"), Color(hex: "#E0736F")],
        mesh: [
            Color(hex: "#1E0B2B"), Color(hex: "#381240"), Color(hex: "#4C1A45"),
            Color(hex: "#722A57"), Color(hex: "#A63C61"), Color(hex: "#CE5468"),
            Color(hex: "#E0736F"), Color(hex: "#F2A08D"), Color(hex: "#9BD7E3"),
        ],
        accent: Color(hex: "#FF7A9C"),
        accentSoft: Color(hex: "#9BD7E3"),
        arrow: [Color(hex: "#FF5E86"), Color(hex: "#FF9DB4"), Color(hex: "#FFE1E8")],
        glow: Color(hex: "#FF8FA8"),
        text: Color(hex: "#FFF1F3"),
        textMuted: Color(hex: "#D6A9B8"),
        cardTint: Color(hex: "#4C1A45"),
        celebration: [
            Color(hex: "#FF7A9C"), Color(hex: "#9BD7E3"),
            Color(hex: "#FFD9A0"), Color(hex: "#FFFFFF"),
        ],
        grainOpacity: 0.045
    )

    static let hawaii = Theme(
        id: "hawaii",
        name: "Hawaii Sunset",
        tagline: "Mango, hibiscus, deep ocean violet",
        symbol: "sun.horizon.fill",
        backdrop: [Color(hex: "#250E4B"), Color(hex: "#9A2F6E"), Color(hex: "#FF8C42")],
        mesh: [
            Color(hex: "#1B0838"), Color(hex: "#33115A"), Color(hex: "#5A1C68"),
            Color(hex: "#9A2F6E"), Color(hex: "#C24272"), Color(hex: "#E85F6B"),
            Color(hex: "#FF8C42"), Color(hex: "#FFB25B"), Color(hex: "#FFD9A0"),
        ],
        accent: Color(hex: "#FFB25B"),
        accentSoft: Color(hex: "#FF5E93"),
        arrow: [Color(hex: "#FF6B35"), Color(hex: "#FFB25B"), Color(hex: "#FFE9A8")],
        glow: Color(hex: "#FFA24C"),
        text: Color(hex: "#FFF4E8"),
        textMuted: Color(hex: "#DFB4C0"),
        cardTint: Color(hex: "#5A1C68"),
        celebration: [
            Color(hex: "#FFB25B"), Color(hex: "#FF5E93"),
            Color(hex: "#29C7C0"), Color(hex: "#FFE9A8"),
        ],
        grainOpacity: 0.05
    )

    static let kingCoconut = Theme(
        id: "kingCoconut",
        name: "King Coconut",
        tagline: "Tea fields, cinnamon, amber husk",
        symbol: "cup.and.saucer.fill",
        backdrop: [Color(hex: "#12241A"), Color(hex: "#37552F"), Color(hex: "#D2953A")],
        mesh: [
            Color(hex: "#0E1D15"), Color(hex: "#193020"), Color(hex: "#264227"),
            Color(hex: "#37552F"), Color(hex: "#587038"), Color(hex: "#8C8B3C"),
            Color(hex: "#D2953A"), Color(hex: "#E8B45C"), Color(hex: "#F6DDA6"),
        ],
        accent: Color(hex: "#F0A93B"),
        accentSoft: Color(hex: "#9CC46A"),
        arrow: [Color(hex: "#C97B22"), Color(hex: "#F0A93B"), Color(hex: "#FFDE9E")],
        glow: Color(hex: "#F0A93B"),
        text: Color(hex: "#FBF4E4"),
        textMuted: Color(hex: "#BCC6A4"),
        cardTint: Color(hex: "#264227"),
        celebration: [
            Color(hex: "#F0A93B"), Color(hex: "#9CC46A"),
            Color(hex: "#A9552F"), Color(hex: "#FBF4E4"),
        ],
        grainOpacity: 0.06
    )

    static let mangoTemple = Theme(
        id: "mangoTemple",
        name: "Mango Temple",
        tagline: "Lagoon turquoise and temple gold",
        symbol: "building.columns.fill",
        backdrop: [Color(hex: "#07222A"), Color(hex: "#0F5F66"), Color(hex: "#F2B233")],
        mesh: [
            Color(hex: "#051A21"), Color(hex: "#08303A"), Color(hex: "#0B4750"),
            Color(hex: "#0F5F66"), Color(hex: "#1B8A85"), Color(hex: "#34B39C"),
            Color(hex: "#8FCB7A"), Color(hex: "#F2B233"), Color(hex: "#FFE066"),
        ],
        accent: Color(hex: "#FFC93C"),
        accentSoft: Color(hex: "#34D2C3"),
        arrow: [Color(hex: "#FF9F1C"), Color(hex: "#FFC93C"), Color(hex: "#FFF0A8")],
        glow: Color(hex: "#FFC93C"),
        text: Color(hex: "#F3FCFB"),
        textMuted: Color(hex: "#A2CCCB"),
        cardTint: Color(hex: "#0B4750"),
        celebration: [
            Color(hex: "#FFC93C"), Color(hex: "#34D2C3"),
            Color(hex: "#D4A017"), Color(hex: "#FFFFFF"),
        ],
        grainOpacity: 0.05
    )

    static let midnightTide = Theme(
        id: "midnightTide",
        name: "Midnight Tide",
        tagline: "Phosphorescence on a black sea",
        symbol: "moon.stars.fill",
        backdrop: [Color(hex: "#03070F"), Color(hex: "#091A2C"), Color(hex: "#123A4D")],
        mesh: [
            Color(hex: "#02050B"), Color(hex: "#040D18"), Color(hex: "#061423"),
            Color(hex: "#091A2C"), Color(hex: "#0D2839"), Color(hex: "#123A4D"),
            Color(hex: "#1A5560"), Color(hex: "#237A78"), Color(hex: "#4FE3C1"),
        ],
        accent: Color(hex: "#4FE3C1"),
        accentSoft: Color(hex: "#7FA6FF"),
        arrow: [Color(hex: "#1F9E92"), Color(hex: "#4FE3C1"), Color(hex: "#C9FFF1")],
        glow: Color(hex: "#4FE3C1"),
        text: Color(hex: "#EAF4FF"),
        textMuted: Color(hex: "#8CA2BE"),
        cardTint: Color(hex: "#0D2839"),
        celebration: [
            Color(hex: "#4FE3C1"), Color(hex: "#7FA6FF"),
            Color(hex: "#C9FFF1"), Color(hex: "#FFFFFF"),
        ],
        grainOpacity: 0.04
    )

    static let all: [Theme] = [margarita, paloma, hawaii, kingCoconut, mangoTemple, midnightTide]

    static let fallback = hawaii

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

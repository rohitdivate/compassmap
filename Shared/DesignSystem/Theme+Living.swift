import SwiftUI

/// The sky-reactive face of a theme. `LivingPalette` (pure, tested) owns the colours; this maps
/// them into SwiftUI. A theme that forbids gradients keeps its flat depth at every hour.
extension Theme {

    func heroColors(for phase: TimeOfDay) -> [Color]? {
        guard heroGradient != nil else { return nil }
        guard let hexes = LivingPalette.heroHexes(themeID: id, phase: phase) else {
            return heroGradient
        }
        return hexes.map { Color(hex: $0) }
    }

    /// The hero wash for the sky outside. Falls back exactly like `heroFill`.
    func heroFill(for phase: TimeOfDay) -> AnyShapeStyle {
        if let colors = heroColors(for: phase) {
            return AnyShapeStyle(LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(depth)
    }

    /// The arrow halo, matched to the wash.
    func glow(for phase: TimeOfDay) -> Color {
        guard let hex = LivingPalette.glowHex(themeID: id, phase: phase) else { return glow }
        return Color(hex: hex)
    }
}

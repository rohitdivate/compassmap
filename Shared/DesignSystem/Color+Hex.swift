import SwiftUI

extension Color {
    /// Builds a colour from a `RRGGBB` or `RRGGBBAA` hex string.
    ///
    /// The palettes read better as hex than as float triples, and a bad string degrades to
    /// magenta rather than crashing, which makes a typo obvious on screen.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16)
        else {
            self = Color(red: 1, green: 0, blue: 1)
            return
        }

        let hasAlpha = cleaned.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1

        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

import SwiftUI
import UIKit

/// The bundled typefaces, addressed by PostScript name.
///
/// Both moods in the design specify real families — Instrument Serif, DM Sans and DM Mono for
/// Tropical Spritz; Space Grotesk and JetBrains Mono for Nomad Money — so the TTFs ship in the
/// bundle and are registered through `UIAppFonts` in both the app's and the widget's Info.plist.
///
/// PostScript names, not families with a weight. Google's static cuts register their Medium weights
/// as *separate families* ("DM Sans Medium", "Space Grotesk Medium"), so asking for family
/// "DM Sans" at `.medium` silently gets you a synthesised or regular face. Naming each file's
/// PostScript name is the only reliable way to land on the intended cut.
enum Fonts {

    enum Serif {
        /// Display and screen titles in Tropical Spritz.
        static let regular = "InstrumentSerif-Regular"
    }

    enum Sans {
        static let regular = "DMSans-Regular"
        static let medium = "DMSans-Medium"
        /// Section heads in Tropical Spritz.
        static let bold = "DMSans-Bold"
    }

    enum Mono {
        /// Every numeral, label and piece of metadata in Tropical Spritz.
        static let regular = "DMMono-Regular"
        static let medium = "DMMono-Medium"
    }

    enum Grotesk {
        static let regular = "SpaceGrotesk-Regular"
        static let medium = "SpaceGrotesk-Medium"
        /// Display in Nomad Money, set tight.
        static let bold = "SpaceGrotesk-Bold"
    }

    enum GroteskMono {
        /// Every figure in Nomad Money, tabular.
        static let regular = "JetBrainsMono-Regular"
        static let medium = "JetBrainsMono-Medium"
        static let bold = "JetBrainsMono-Bold"
    }

    /// All bundled faces, for the launch-time check below.
    static let all: [String] = [
        Serif.regular,
        Sans.regular, Sans.medium, Sans.bold,
        Mono.regular, Mono.medium,
        Grotesk.regular, Grotesk.medium, Grotesk.bold,
        GroteskMono.regular, GroteskMono.medium, GroteskMono.bold,
    ]

    /// Reports any face that did not register.
    ///
    /// A missing custom font does not fail loudly — `Font.custom` quietly substitutes the system
    /// face, and the app looks subtly wrong in a way that is easy to stare past. This turns that
    /// into a console warning naming the file, which is usually a stale `UIAppFonts` entry or a
    /// font missing from the target's resources.
    @discardableResult
    static func verifyRegistration() -> [String] {
        let missing = all.filter { UIFont(name: $0, size: 12) == nil }
        if !missing.isEmpty {
            print("""
            [Tradewind] These fonts did not register: \(missing.joined(separator: ", ")).
            Check UIAppFonts in Info.plist and that the .ttf files are in the target's \
            Copy Bundle Resources phase.
            """)
        }
        return missing
    }
}

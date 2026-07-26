import SwiftUI

/// The size ramp, which the two moods set differently.
///
/// Tropical Spritz is a travel magazine: a 40pt serif masthead over 15pt body. Nomad Money is a
/// ledger: a 28pt tight grotesk over 14.5pt body, with more of the page given to figures. Sizes are
/// transcribed from the reference screens rather than derived from a ratio.
struct TypeScale: Hashable, Sendable {
    /// Screen titles.
    var display: CGFloat
    /// Secondary headings — a place name inside a card.
    var title: CGFloat
    var sectionHead: CGFloat
    var cardTitle: CGFloat
    var body: CGFloat
    var caption: CGFloat
    var label: CGFloat
    /// Mono caps eyebrow labels.
    var eyebrow: CGFloat
    /// The distance readout on a card or detail row.
    var readout: CGFloat
    var cardNumber: CGFloat
}

extension Theme {

    // MARK: - Words

    /// Screen titles. Instrument Serif in Spritz, tight Space Grotesk in Nomad.
    var displayTitleFont: Font { .custom(displayFont, size: scale.display) }

    var titleFont: Font { .custom(displayFont, size: scale.title) }

    /// Section headings sit in the *body* face, not the display face: in Spritz the serif is
    /// reserved for screen titles and feeling, and in Nomad section labels are mono caps entirely.
    var sectionTitleFont: Font { .custom(bodyBoldFont, size: scale.sectionHead) }

    var cardTitleFont: Font { .custom(bodyBoldFont, size: scale.cardTitle) }

    var bodyTextFont: Font { .custom(bodyFont, size: scale.body) }

    var bodyMediumTextFont: Font { .custom(bodyMediumFont, size: scale.body) }

    // MARK: - Data
    //
    // "Serif for feeling, mono for fact. Never set a number in the serif." Both moods put every
    // numeral, label and piece of metadata in their mono face.

    var captionFont: Font { .custom(monoFont, size: scale.caption) }

    var labelFont: Font { .custom(monoMediumFont, size: scale.label) }

    var eyebrowFont: Font { .custom(monoMediumFont, size: scale.eyebrow) }

    var readoutFont: Font { .custom(monoMediumFont, size: scale.readout) }

    var readoutUnitFont: Font { .custom(monoFont, size: scale.readout * 0.5) }

    var cardNumberFont: Font { .custom(monoMediumFont, size: scale.cardNumber) }

    var widgetNumberFont: Font { .custom(monoMediumFont, size: 25) }

    /// Compass-rose tick letters.
    var tickFont: Font { .custom(monoMediumFont, size: 11) }

    /// The arrow screen's distance. Size is passed in because it shrinks as the number lengthens.
    func heroNumberFont(_ size: CGFloat) -> Font {
        .custom(monoMediumFont, size: size)
    }

    /// Arbitrary mono, for the few places that need a size off the ramp.
    func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? monoMediumFont : monoFont, size: size)
    }

    /// Arbitrary body face.
    func sans(_ size: CGFloat, weight: SansWeight = .regular) -> Font {
        switch weight {
        case .regular: return .custom(bodyFont, size: size)
        case .medium: return .custom(bodyMediumFont, size: size)
        case .bold: return .custom(bodyBoldFont, size: size)
        }
    }

    enum SansWeight { case regular, medium, bold }

    /// Tracking for mono caps labels. Both moods track them out hard — .12em to .18em.
    func labelTracking(_ size: CGFloat) -> CGFloat { size * 0.15 }
}

extension View {
    /// Eyebrow label styling: tiny mono caps, tracked out. Used above nearly every heading in both
    /// moods, which is why it is a modifier rather than repeated inline.
    func eyebrowStyle(theme: Theme, color: Color? = nil) -> some View {
        self
            .font(theme.eyebrowFont)
            .textCase(.uppercase)
            .tracking(theme.labelTracking(theme.scale.eyebrow))
            .foregroundStyle(color ?? theme.accent)
    }

    /// Applies the theme's numeral behaviour. Nomad requires tabular figures so columns line up;
    /// Spritz's DM Mono is already fixed-width, so this is a no-op there.
    @ViewBuilder
    func numeric(_ theme: Theme) -> some View {
        if theme.numerals == .tabularMono {
            self.monospacedDigit()
        } else {
            self
        }
    }
}

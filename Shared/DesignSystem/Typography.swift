import SwiftUI

/// Type scale for Tradewind.
///
/// Two families, used deliberately: a serif for names and headings, which reads like a
/// beach-bar menu, and a rounded face for every number, because rounded digits are easier
/// to read at a glance and the whole app is really one big number.
enum Typography {

    // MARK: Numbers

    /// The distance on the arrow screen. Size is passed in because it shrinks as the
    /// number gets longer.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static let readout = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let readoutUnit = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let cardDistance = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let widgetDistance = Font.system(size: 26, weight: .bold, design: .rounded)
    static let tick = Font.system(size: 11, weight: .semibold, design: .rounded)

    // MARK: Words

    static let displayTitle = Font.system(size: 40, weight: .semibold, design: .serif)
    static let title = Font.system(size: 26, weight: .semibold, design: .serif)
    static let sectionTitle = Font.system(size: 19, weight: .semibold, design: .serif)
    static let cardTitle = Font.system(size: 18, weight: .semibold, design: .serif)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 13, weight: .medium)
    static let label = Font.system(size: 12, weight: .semibold)

    /// Wide letter-spacing small caps, for eyebrow labels above a heading.
    static let eyebrow = Font.system(size: 11, weight: .bold)
}

extension View {
    /// Eyebrow label styling: tiny, uppercase, tracked out.
    func eyebrowStyle(color: Color) -> some View {
        self
            .font(Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

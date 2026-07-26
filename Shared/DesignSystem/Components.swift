import SwiftUI

/// A card or panel.
///
/// This is where the two moods differ most, and it is why `Theme` carries structure and not just
/// colour. In Tropical Spritz a card is *white on cream, lifted on a soft shadow* — "cream, not
/// white, is the canvas; white is reserved for cards so they lift". In Nomad Money a card is a
/// slightly lighter surface separated by a 1pt hairline, and shadows are forbidden — "hairlines, not
/// shadows; elevation is a lighter surface". One component, two genuinely different treatments.
struct Surface<Content: View>: View {
    @Environment(\.theme) private var theme

    /// Nil takes the theme's card radius; rows and insets override it.
    var cornerRadius: CGFloat?
    var padding: CGFloat = 16
    /// Raised panels sit one step above the surrounding surface.
    var raised: Bool = false
    @ViewBuilder var content: Content

    private var radius: CGFloat { cornerRadius ?? theme.radii.card }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .background { shape.fill(raised ? theme.surfaceRaised : theme.surface) }
            .overlay { border }
            .clipShape(shape)
            .modifier(SurfaceShadow(theme: theme))
    }

    /// Only a hairline theme draws a border. In Spritz the shadow does that work, and adding a
    /// border too makes the card look printed rather than lifted.
    @ViewBuilder
    private var border: some View {
        if theme.usesHairlines {
            shape.strokeBorder(theme.hairline, lineWidth: 1)
        }
    }
}

/// Applies the theme's card shadow, or nothing where the mood forbids it.
private struct SurfaceShadow: ViewModifier {
    var theme: Theme

    func body(content: Content) -> some View {
        if let shadow = theme.cardShadow {
            content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
        } else {
            content
        }
    }
}

/// Small capsule label — trip names, "pinned", compass points.
struct PillLabel: View {
    @Environment(\.theme) private var theme

    var text: String
    var symbol: String?
    /// Filled in the accent, for the one thing on screen that matters most.
    var prominent: Bool = false
    /// Filled in the highlight colour. "Lime is a highlight, not a surface" — badges only.
    var badge: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(theme.labelFont)
                .tracking(theme.labelTracking(theme.scale.label) * 0.5)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(foreground)
        .background {
            Capsule(style: .continuous).fill(background)
            if !prominent, !badge, theme.usesHairlines {
                Capsule(style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)
            }
        }
    }

    private var foreground: Color {
        if badge { return theme.onHighlight }
        if prominent { return theme.onAccent }
        return theme.textMuted
    }

    private var background: Color {
        if badge { return theme.highlight }
        if prominent { return theme.accent }
        // A quiet fill: a tinted wash of the ink in Spritz, a raised surface in Nomad.
        return theme.usesHairlines ? theme.surfaceRaised : theme.text.opacity(0.07)
    }
}

/// Filter chip. A pill in Spritz, a tight segmented control in Nomad.
struct ChipButton: View {
    @Environment(\.theme) private var theme

    var title: String
    var symbol: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                }
                Text(title).font(theme.sans(theme.scale.caption, weight: .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background { shape.fill(background) }
            .overlay {
                if !isSelected, theme.usesHairlines {
                    shape.strokeBorder(theme.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    /// Spritz selects with the ink colour, as the reference screens do; Nomad selects with a raised
    /// surface, keeping the lime free for the one live thing on screen.
    private var foreground: Color {
        guard isSelected else { return theme.textMuted }
        return theme.usesHairlines ? theme.text : theme.canvas
    }

    private var background: Color {
        guard isSelected else {
            return theme.usesHairlines ? .clear : theme.text.opacity(0.07)
        }
        return theme.usesHairlines ? theme.surfaceRaised : theme.text
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
    }
}

/// The primary action.
///
/// Spritz gives it a hard-offset shadow — `0 3px 0 #D8456B` — which is what makes that mood feel
/// tactile, and it presses down by a point when tapped. Nomad has no shadows at all: a flat lime
/// rectangle at 10pt radius.
struct PrimaryButton: View {
    @Environment(\.theme) private var theme

    var title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                }
                Text(title).font(theme.sans(15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(theme.onAccent)
        }
        .buttonStyle(HardOffsetStyle(theme: theme))
    }
}

/// Presses into its own shadow. Spritz only; in a hairline theme the offset collapses to nothing.
private struct HardOffsetStyle: ButtonStyle {
    var theme: Theme

    private var offset: CGFloat { theme.usesHairlines ? 0 : 3 }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let drop = pressed ? max(0, offset - 1) : offset

        return configuration.label
            .background {
                RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
                    .fill(theme.accent)
                    .background(alignment: .bottom) {
                        if offset > 0 {
                            RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
                                .fill(theme.accentShadow)
                                .offset(y: drop)
                        }
                    }
            }
            .offset(y: pressed ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
    }
}

/// Quiet secondary action: outlined in Spritz, a raised surface in Nomad.
struct SecondaryButton: View {
    @Environment(\.theme) private var theme

    var title: String
    var symbol: String?
    /// On a photograph the button cannot borrow the canvas, so it borrows the picture instead —
    /// theme ink on a blurred photo is either invisible or a hole punched in it.
    var onPhoto: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(theme.sans(14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(onPhoto ? Color.white : theme.text)
            .background { shape.fill(fill) }
            .overlay { shape.strokeBorder(border, lineWidth: onPhoto || theme.usesHairlines ? 1 : 1.5) }
        }
        .buttonStyle(PressableStyle())
    }

    private var fill: Color {
        if onPhoto { return .white.opacity(0.14) }
        return theme.usesHairlines ? theme.surfaceRaised : .clear
    }

    private var border: Color {
        if onPhoto { return .white.opacity(0.22) }
        return theme.usesHairlines ? theme.hairline : theme.text
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
    }
}

/// Every tappable thing gives a little.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Section heading with a mono-caps eyebrow above it.
struct SectionHeader: View {
    @Environment(\.theme) private var theme

    var eyebrow: String?
    var title: String
    var trailing: AnyView?

    init(eyebrow: String? = nil, title: String, trailing: AnyView? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow).eyebrowStyle(theme: theme, color: theme.textFaint)
                }
                Text(title)
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.text)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// A figure and its label — the stat tile both moods build their home screen out of.
struct StatTile: View {
    @Environment(\.theme) private var theme

    var value: String
    var label: String
    /// Spritz colours each tile's figure differently; Nomad leaves them all in paper white.
    var valueColor: Color?
    /// Nomad's delta chip: "+3", "0".
    var delta: String?

    var body: some View {
        Surface(cornerRadius: theme.radii.row, padding: 15, raised: theme.usesHairlines) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(theme.cardNumberFont)
                        .numeric(theme)
                        .foregroundStyle(valueColor ?? theme.text)
                    if let delta {
                        Text(delta)
                            .font(theme.mono(11, medium: true))
                            .numeric(theme)
                            .foregroundStyle(theme.positive)
                    }
                }
                Text(label)
                    .font(theme.labelFont)
                    .textCase(.uppercase)
                    .tracking(theme.labelTracking(theme.scale.label))
                    .foregroundStyle(theme.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A horizontal bar, used for arrival progress and range indicators.
struct ThemedProgressBar: View {
    @Environment(\.theme) private var theme

    var fraction: Double
    var height: CGFloat = 6
    /// Progress is one of the few things the highlight colour is allowed to fill.
    var color: Color?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.usesHairlines ? theme.surfaceRaised : theme.text.opacity(0.12))
                Capsule()
                    .fill(color ?? theme.highlight)
                    .frame(width: max(height, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Empty-state block: a drawn mark, a line of copy, and one action.
struct EmptyStateView: View {
    @Environment(\.theme) private var theme

    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            mark
            Text(title)
                .font(theme.titleFont)
                .tracking(theme.displayTracking)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(theme.bodyTextFont)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, symbol: "camera.fill", action: action)
                    .padding(.top, 4)
                    .padding(.horizontal, 24)
            }
        }
        .padding(28)
    }

    private var mark: some View {
        ZStack {
            Circle().fill(theme.accent.opacity(0.12))
            Circle().strokeBorder(theme.accent.opacity(0.3), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.accent)
        }
        .frame(width: 92, height: 92)
    }
}

/// A round icon button — close, settings, the map controls.
struct CircularButton: View {
    @Environment(\.theme) private var theme

    var symbol: String
    var isActive: Bool = false
    /// Set when the button sits on a photo or hero gradient rather than on the canvas.
    var onHero: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 40, height: 40)
                .background { Circle().fill(background) }
                .overlay {
                    if !isActive, !onHero, theme.usesHairlines {
                        Circle().strokeBorder(theme.hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(PressableStyle())
    }

    private var foreground: Color {
        if isActive { return theme.onAccent }
        return onHero ? .white : theme.text
    }

    private var background: Color {
        if isActive { return theme.accent }
        if onHero { return .black.opacity(0.28) }
        return theme.usesHairlines ? theme.surface : theme.text.opacity(0.07)
    }
}

import SwiftUI

/// Frosted card. Everything that sits on the backdrop sits in one of these.
struct GlassCard<Content: View>: View {
    @Environment(\.theme) private var theme

    var cornerRadius: CGFloat = 26
    var tintStrength: Double = 0.55
    var strokeStrength: Double = 0.22
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background { glass }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var glass: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(theme.cardTint.opacity(tintStrength)).blendMode(.softLight) }
            .overlay { rim }
    }

    /// One highlight running off the top-left corner: the single cue that reads as glass.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [
                    .white.opacity(strokeStrength + 0.18),
                    .white.opacity(strokeStrength * 0.3),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
    }
}

/// Small capsule label — trip names, "pinned", compass points.
struct PillLabel: View {
    @Environment(\.theme) private var theme

    var text: String
    var symbol: String?
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(Typography.label)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(prominent ? theme.deepest : theme.text)
        .background {
            Capsule(style: .continuous)
                .fill(prominent ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(prominent ? 0 : 0.18), lineWidth: 1)
        }
    }
}

/// Filter chip used for trips and theme selection.
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
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                }
                Text(title).font(Typography.caption)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? theme.deepest : theme.text)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.ultraThinMaterial))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0 : 0.16), lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// The app's primary button: accent fill, deep text, presses in.
struct PrimaryButton: View {
    @Environment(\.theme) private var theme

    var title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(theme.deepest)
            .background {
                Capsule(style: .continuous)
                    .fill(theme.accent)
                    .shadow(color: theme.glow.opacity(0.45), radius: 16, y: 6)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Quiet secondary button.
struct SecondaryButton: View {
    @Environment(\.theme) private var theme

    var title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(theme.text)
            .background {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Every tappable thing in Tradewind gives a little.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Section heading with an eyebrow above it.
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
                    Text(eyebrow).eyebrowStyle(color: theme.accent)
                }
                Text(title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(theme.text)
            }
            Spacer()
            if let trailing { trailing }
        }
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
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.14))
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 92, height: 92)
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(theme.accent)
            }
            Text(title)
                .font(Typography.title)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
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
}

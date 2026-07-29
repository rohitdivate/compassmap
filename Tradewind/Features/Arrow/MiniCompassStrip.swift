import SwiftUI

/// The walk, condensed into the tab bar's bottom accessory: a small arrow, the spot's name,
/// and the live distance. Shown only while a Lock Screen walk is being tracked, so closing
/// the arrow screen never means losing the thread — the strip is the way back in.
///
/// Observation-wise this is a leaf, exactly like the arrow screen's own leaves: it reads
/// `DialState` and the change-guarded frame, so it moves at dial rate without dragging the
/// tab shell along.
struct MiniCompassStrip: View {
    @Environment(\.theme) private var theme
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var dial: DialState
    var solution: TargetSolution
    var name: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                MiniArrow(theme: theme, angle: dial.arrowAngle, size: 22)
                Text(name)
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                distance
                // Compact placement (bar minimized) keeps just arrow, name and number; the
                // chevron only earns its place at full width.
                if placement != .inline {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tracking-strip")
        .accessibilityLabel("Tracking \(name). Opens the compass.")
    }

    @ViewBuilder
    private var distance: some View {
        if let readout = solution.frame.distanceText {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(readout.value)
                    .font(theme.cardNumberFont)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(theme.text)
                Text(readout.unit)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textMuted)
            }
            .animation(.snappy(duration: 0.25), value: readout.value)
        }
    }
}

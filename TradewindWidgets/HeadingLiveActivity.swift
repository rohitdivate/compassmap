import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity: an active walk toward a spot, on the Lock Screen and in the Dynamic Island.
///
/// It shows distance and the compass bearing, not a live compass — ActivityKit updates are
/// throttled and heading changes many times a second, so a spinning arrow here would be a lie
/// most of the time. The distance counting down is the useful part anyway.
struct HeadingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeadingActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(theme(for: context).canvas.opacity(0.95))
                .activitySystemActionForegroundColor(theme(for: context).accent)
        } dynamicIsland: { context in
            island(for: context)
        }
    }

    // Each region is its own method: the whole island in one expression is more than the
    // type-checker will take.
    private func island(for context: ActivityViewContext<HeadingActivityAttributes>) -> DynamicIsland {
        let theme = theme(for: context)
        let attributes = context.attributes
        let state = context.state

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                expandedArrow(theme: theme, bearing: state.bearing)
            }
            DynamicIslandExpandedRegion(.trailing) {
                expandedDistance(theme: theme, state: state, attributes: attributes)
            }
            DynamicIslandExpandedRegion(.center) {
                expandedTitle(theme: theme, state: state, attributes: attributes)
            }
            DynamicIslandExpandedRegion(.bottom) {
                ActivityProgress(theme: theme, state: state)
            }
        } compactLeading: {
            arrowGlyph(colour: theme.accent, bearing: state.bearing, width: 9, height: 15)
        } compactTrailing: {
            Text(distanceText(state, attributes))
                .font(theme.mono(13, medium: true))
                .monospacedDigit()
                .foregroundStyle(theme.accent)
        } minimal: {
            arrowGlyph(colour: theme.accent, bearing: state.bearing, width: 8, height: 13)
        }
        .widgetURL(deepLink(for: attributes))
        .keylineTint(theme.accent)
    }

    private func expandedArrow(theme: Theme, bearing: Double) -> some View {
        ArrowShape()
            .fill(theme.arrowGradient)
            .frame(width: 18, height: 30)
            .rotationEffect(.degrees(bearing))
            .padding(.leading, 6)
    }

    private func expandedDistance(
        theme: Theme,
        state: HeadingActivityAttributes.ContentState,
        attributes: HeadingActivityAttributes
    ) -> some View {
        Text(distanceText(state, attributes))
            .font(theme.mono(20, medium: true))
            .monospacedDigit()
            .foregroundStyle(theme.accent)
            .padding(.trailing, 6)
    }

    private func expandedTitle(
        theme: Theme,
        state: HeadingActivityAttributes.ContentState,
        attributes: HeadingActivityAttributes
    ) -> some View {
        let subtitle = state.isArrived
            ? "You made it"
            : "Head \(BearingMath.compassPoint(forBearing: state.bearing))"
        return VStack(spacing: 1) {
            Text(attributes.spotName)
                .font(theme.sans(13, weight: .bold))
                .lineLimit(1)
            Text(subtitle)
                .font(theme.sans(10, weight: .medium))
                .foregroundStyle(theme.textMuted)
        }
    }

    private func arrowGlyph(
        colour: Color,
        bearing: Double,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ArrowShape()
            .fill(colour)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(bearing))
    }

    private func deepLink(for attributes: HeadingActivityAttributes) -> URL? {
        URL(string: "\(AppGroup.urlScheme)://spot?id=\(attributes.spotID.uuidString)")
    }

    private func theme(
        for context: ActivityViewContext<HeadingActivityAttributes>
    ) -> Theme {
        ThemeCatalog.theme(id: context.attributes.themeID)
    }

    private func distanceText(
        _ state: HeadingActivityAttributes.ContentState,
        _ attributes: HeadingActivityAttributes
    ) -> String {
        DistanceFormatting.compact(
            metres: state.distanceMetres,
            preference: attributes.unitPreference
        )
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<HeadingActivityAttributes>

    private var theme: Theme { ThemeCatalog.theme(id: context.attributes.themeID) }

    var body: some View {
        HStack(spacing: 14) {
            dial
            labels
            Spacer(minLength: 0)
            distance
        }
        .padding(16)
    }

    private var dial: some View {
        ZStack {
            Circle().fill(theme.accent.opacity(0.14))
            Circle().strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
            ArrowShape()
                .fill(theme.arrowGradient)
                .frame(width: 20, height: 33)
                .rotationEffect(.degrees(context.state.bearing))
        }
        .frame(width: 62, height: 62)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(context.state.isArrived ? "Arrived" : "Heading to")
                .font(theme.sans(10, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(theme.accent)

            Text(context.attributes.spotName)
                .font(theme.sans(17, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if let place = context.attributes.placeName, !place.isEmpty {
                Text(place)
                    .font(theme.sans(11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var distance: some View {
        let readout = DistanceFormatting.readout(
            metres: context.state.distanceMetres,
            preference: context.attributes.unitPreference
        )
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(readout.value)
                    .font(theme.mono(28, medium: true))
                    .monospacedDigit()
                Text(readout.unit)
                    .font(theme.mono(13, medium: true))
                    .foregroundStyle(theme.textMuted)
            }
            .foregroundStyle(theme.text)

            Text(BearingMath.compassPoint(forBearing: context.state.bearing))
                .font(theme.mono(11, medium: true))
                .foregroundStyle(theme.accent)
        }
    }
}

// MARK: - Progress

/// How far through the walk you are, measured against the distance when the walk began.
///
/// The starting distance is not stored in the activity state, so this uses a fixed reference of one
/// kilometre — enough to give the last stretch a sense of closing in without claiming to know how
/// far you set out from.
private struct ActivityProgress: View {
    var theme: Theme
    var state: HeadingActivityAttributes.ContentState

    private var progress: Double {
        max(0, min(1, 1 - state.distanceMetres / 1_000))
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.textMuted.opacity(0.25))
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: max(6, geometry.size.width * progress))
                }
            }
            .frame(height: 5)

            HStack {
                Text(state.isArrived ? "You made it" : "Closing in")
                    .font(theme.sans(9, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Text(state.updatedAt, style: .relative)
                    .font(theme.sans(9, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, 4)
    }
}

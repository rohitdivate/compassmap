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
                .activityBackgroundTint(theme(for: context).deepest.opacity(0.92))
                .activitySystemActionForegroundColor(theme(for: context).accent)
        } dynamicIsland: { context in
            let theme = theme(for: context)
            let attributes = context.attributes
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ArrowShape()
                        .fill(theme.arrowGradient)
                        .frame(width: 18, height: 30)
                        .rotationEffect(.degrees(state.bearing))
                        .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(distanceText(state, attributes))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                        .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(attributes.spotName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(state.isArrived
                            ? "You made it"
                            : "Head \(BearingMath.compassPoint(forBearing: state.bearing))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textMuted)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressBar(theme: theme, state: state)
                }
            } compactLeading: {
                ArrowShape()
                    .fill(theme.accent)
                    .frame(width: 9, height: 15)
                    .rotationEffect(.degrees(state.bearing))
            } compactTrailing: {
                Text(distanceText(state, attributes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            } minimal: {
                ArrowShape()
                    .fill(theme.accent)
                    .frame(width: 8, height: 13)
                    .rotationEffect(.degrees(state.bearing))
            }
            .widgetURL(URL(string: "\(AppGroup.urlScheme)://spot?id=\(attributes.spotID.uuidString)"))
            .keylineTint(theme.accent)
        }
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
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.14))
                Circle()
                    .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
                ArrowShape()
                    .fill(theme.arrowGradient)
                    .frame(width: 20, height: 33)
                    .rotationEffect(.degrees(context.state.bearing))
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.isArrived ? "Arrived" : "Heading to")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(theme.accent)

                Text(context.attributes.spotName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if let place = context.attributes.placeName, !place.isEmpty {
                    Text(place)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                let readout = DistanceFormatting.readout(
                    metres: context.state.distanceMetres,
                    preference: context.attributes.unitPreference
                )
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(readout.value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(readout.unit)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textMuted)
                }
                .foregroundStyle(theme.text)

                Text(BearingMath.compassPoint(forBearing: context.state.bearing))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(16)
    }
}

// MARK: - Progress

/// How far through the walk you are, measured against the distance when the walk began.
///
/// The starting distance is not stored in the activity state, so this uses a fixed reference of one
/// kilometre — enough to give the last stretch a sense of closing in without claiming to know how
/// far you set out from.
private struct ProgressBar: View {
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
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Text(state.updatedAt, style: .relative)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, 4)
    }
}

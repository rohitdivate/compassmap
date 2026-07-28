import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity: an active walk toward a spot, on the Lock Screen and in the Dynamic Island.
///
/// Two things about this surface are worth stating, because both were got wrong here before.
///
/// **It is not an app screen.** The Lock Screen draws this over a wallpaper, and the Dynamic Island
/// is always black whatever the app looks like. So the app's ink is the wrong ink: Tropical Spritz's
/// cream canvas rendered as a bright slab across the Lock Screen, and its near-black `textMuted` was
/// invisible inside the island. Everything here uses `theme.activityTint` as its ground and light
/// values on top of it, with the accent carrying the mood.
///
/// **The pointer is a bearing, not a compass.** It rotates as you *move*, because moving changes the
/// bearing, and `ActivityUpdateDriver` pushes on every fix — locked phone included, now that the
/// walk holds background location open. It will not rotate as you turn the phone on the spot —
/// ActivityKit cannot stream sensor data, and pretending otherwise would be a lie most of the time.
/// The ETA updates continuously for free besides: `Text(timerInterval:)` ticks on-device, and the
/// distances roll between pushes with `.contentTransition(.numericText)` instead of hard-cutting.
struct HeadingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeadingActivityAttributes.self) { context in
            LockScreenView(context: context)
                // Solid, not 0.95. Letting 5% of an unknown wallpaper through makes the contrast of
                // everything above it unpredictable, which is half of why this read badly.
                .activityBackgroundTint(theme(for: context).activityTint)
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
                ActivityProgress(theme: theme, state: state, attributes: attributes)
            }
        } compactLeading: {
            arrowGlyph(colour: theme.accent, bearing: state.bearing, width: 9, height: 15)
        } compactTrailing: {
            Text(distanceText(state, attributes))
                .font(theme.mono(13, medium: true))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(theme.accent)
        } minimal: {
            arrowGlyph(colour: theme.accent, bearing: state.bearing, width: 8, height: 13)
        }
        .widgetURL(deepLink(for: attributes))
        .keylineTint(theme.accent)
    }

    private func expandedArrow(theme: Theme, bearing: Double) -> some View {
        BearingDial(theme: theme, bearing: bearing, diameter: 44)
            .padding(.leading, 6)
    }

    private func expandedDistance(
        theme: Theme,
        state: HeadingActivityAttributes.ContentState,
        attributes: HeadingActivityAttributes
    ) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(distanceText(state, attributes))
                .font(theme.mono(20, medium: true))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(theme.accent)
            // The island is always black, so this must be light regardless of mood.
            if let walk = DistanceFormatting.walkingTime(metres: state.distanceMetres) {
                Text(walk)
                    .font(theme.sans(10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
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
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                // Was theme.textMuted, which in Spritz is near-black — invisible in the island.
                .foregroundStyle(.white.opacity(0.62))
                .font(theme.sans(10, weight: .medium))
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

// MARK: - Bearing dial

/// The pointer, with something to point *relative to*.
///
/// A bare arrow rotated to an absolute bearing reads as a random tilt — there was nothing on screen
/// establishing which way was north, so the angle carried no information. A north tick and a ring fix
/// that at almost no cost in space.
private struct BearingDial: View {
    var theme: Theme
    var bearing: Double
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.07))
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
            northTick
            ArrowShape()
                .fill(theme.arrowGradient)
                .frame(width: diameter * 0.30, height: diameter * 0.50)
                .rotationEffect(.degrees(bearing))
        }
        .frame(width: diameter, height: diameter)
    }

    /// A short mark at the top of the ring, and the letter beside it, so "up" means north rather
    /// than "up".
    private var northTick: some View {
        VStack(spacing: 0) {
            Text("N")
                .font(.system(size: diameter * 0.16, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
        .padding(.top, diameter * 0.045)
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<HeadingActivityAttributes>

    private var theme: Theme { ThemeCatalog.theme(id: context.attributes.themeID) }
    private var state: HeadingActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                BearingDial(theme: theme, bearing: state.bearing, diameter: 58)
                labels
                Spacer(minLength: 0)
                distance
            }
            ActivityProgress(theme: theme, state: state, attributes: context.attributes)
        }
        .padding(16)
        // Nomad separates with a hairline and nothing else, and on a Lock Screen its own dark surface
        // sits close enough to a photographic wallpaper that an edge is what makes the card a card.
        // Spritz's tint is distinct enough on its own, and that mood does not draw borders.
        .overlay(alignment: .top) { hairlineEdge }
    }

    @ViewBuilder
    private var hairlineEdge: some View {
        if theme.usesHairlines {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(state.isArrived ? "Arrived" : "Heading to")
                .font(theme.sans(10, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(theme.accent)

            Text(context.attributes.spotName)
                .font(theme.sans(17, weight: .bold))
                // On activityTint, not on the app canvas — theme.text would be near-black here.
                .foregroundStyle(.white)
                .lineLimit(1)

            if let place = context.attributes.placeName, !place.isEmpty {
                Text(place)
                    .font(theme.sans(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private var distance: some View {
        let readout = DistanceFormatting.readout(
            metres: state.distanceMetres,
            preference: context.attributes.unitPreference
        )
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(readout.value)
                    .font(theme.mono(28, medium: true))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(readout.unit)
                    .font(theme.mono(13, medium: true))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)

            Text(BearingMath.compassPoint(forBearing: state.bearing))
                .font(theme.mono(11, medium: true))
                .foregroundStyle(theme.accent)
        }
    }
}

// MARK: - Progress

/// How far through the walk you are, plus the arrival time.
///
/// The progress used to be `1 - distance / 1_000` against a kilometre nobody chose — so setting off
/// three kilometres away pinned it at zero the whole way. It now measures against the distance when
/// the walk began, and shows nothing at all rather than something invented when that is unknown.
///
/// The ETA is a `Text(timerInterval:)`, which counts down on-device between pushes. It is the one
/// genuinely live element available here and it costs no updates.
private struct ActivityProgress: View {
    var theme: Theme
    var state: HeadingActivityAttributes.ContentState
    var attributes: HeadingActivityAttributes

    private var fraction: Double? {
        ActivityProgressMath.fraction(
            remaining: state.distanceMetres,
            startingFrom: attributes.startingDistanceMetres
        )
    }

    /// When you would arrive at a walking pace, measured from the moment of the last push so the
    /// countdown stays anchored rather than jumping.
    private var arrival: Date? {
        guard !state.isArrived,
              let seconds = BearingMath.walkingDuration(forDistance: state.distanceMetres)
        else { return nil }
        return state.updatedAt.addingTimeInterval(seconds)
    }

    var body: some View {
        VStack(spacing: 4) {
            if let fraction { bar(fraction) }
            footer
        }
        .padding(.horizontal, 4)
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(theme.accent)
                    .frame(width: max(4, geometry.size.width * fraction))
            }
        }
        .frame(height: 5)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(state.isArrived ? "You made it" : (walkLabel ?? "On your way"))
                .font(theme.sans(10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 0)
            eta
        }
    }

    private var walkLabel: String? {
        DistanceFormatting.walkingTime(metres: state.distanceMetres)
    }

    @ViewBuilder
    private var eta: some View {
        if let arrival, arrival > state.updatedAt {
            // Counts down without the app being involved, so the card stays alive between pushes.
            Text(timerInterval: state.updatedAt...arrival, countsDown: true)
                .font(theme.mono(10, medium: true))
                .monospacedDigit()
                .foregroundStyle(theme.accent)
        }
    }
}

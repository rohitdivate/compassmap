import AppIntents
import SwiftUI
import WidgetKit

/// The main widget: one spot, its photo, the direction it lies in and how far away it is.
///
/// Configurable — long-press and pick a spot — and defaults to whichever spot is pinned in the
/// app, falling back to the nearest. It covers the home screen families and all three Lock Screen
/// accessories from one implementation, because they are all the same two facts at different sizes.
struct SpotCompassWidget: Widget {

    let kind = "SpotCompassWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectSpotIntent.self,
            provider: SpotCompassProvider()
        ) { entry in
            SpotCompassView(entry: entry)
        }
        .configurationDisplayName("Point Me There")
        .description("The direction and distance to one of your spots.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct SpotCompassProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> SpotEntry {
        SpotEntryBuilder.preview()
    }

    func snapshot(for configuration: SelectSpotIntent, in context: Context) async -> SpotEntry {
        // The gallery preview must appear instantly, so it never waits on a location fix.
        if context.isPreview { return SpotEntryBuilder.preview() }
        return await SpotEntryBuilder.entry(for: configuration.spot?.id)
    }

    func timeline(
        for configuration: SelectSpotIntent,
        in context: Context
    ) async -> Timeline<SpotEntry> {
        await SpotEntryBuilder.timeline(for: configuration.spot?.id)
    }
}

// MARK: - View

struct SpotCompassView: View {
    @Environment(\.widgetFamily) private var family

    var entry: SpotEntry

    var body: some View {
        content
            .widgetURL(entry.spot?.deepLinkURL)
            .containerBackground(for: .widget) {
                if isHomeScreen {
                    WidgetBackdrop(theme: entry.theme)
                } else {
                    // Lock Screen accessories render as a monochrome vibrant layer; giving them a
                    // coloured background only makes them muddy.
                    Color.clear
                }
            }
    }

    private var isHomeScreen: Bool {
        family == .systemSmall || family == .systemMedium || family == .systemLarge
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        case .accessoryCircular: circularView
        case .accessoryInline: inlineView
        case .accessoryRectangular: rectangularView
        default: smallView
        }
    }

    // MARK: Home screen

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WidgetArrow(theme: entry.theme, bearing: entry.bearing, size: 32)
                Spacer()
                if let glyph = entry.spot?.glyph, !glyph.isEmpty {
                    Text(glyph).font(.system(size: 18))
                }
            }

            Spacer(minLength: 4)

            if entry.metres == nil, let message = entry.placeholderMessage {
                WidgetPlaceholder(theme: entry.theme, message: message, compact: true)
            } else {
                WidgetDistanceText(readout: entry.readout, theme: entry.theme, numberSize: 34)
                Text(entry.spot?.name ?? "No spot")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.theme.text)
                    .lineLimit(1)
                Text(secondaryLine)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(entry.theme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetArrow(theme: entry.theme, bearing: entry.bearing, size: 30)
                Spacer(minLength: 2)
                WidgetDistanceText(readout: entry.readout, theme: entry.theme, numberSize: 30)
                Text(entry.spot?.name ?? "No spot")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.theme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            nearbyList(limit: 3, spacing: 6)
                .frame(maxWidth: .infinity)
        }
    }

    private var largeView: some View {
        VStack(spacing: 0) {
            photoHeader
            nearbyList(limit: 3, spacing: 7)
                .padding(.top, 10)
            Spacer(minLength: 0)
            widgetButtons
        }
    }

    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            WidgetPhoto(spot: entry.spot, theme: entry.theme)
                .frame(height: 128)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            HStack(alignment: .bottom, spacing: 10) {
                WidgetArrow(theme: entry.theme, bearing: entry.bearing, size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    WidgetDistanceText(readout: entry.readout, theme: entry.theme, numberSize: 32)
                    Text(entry.spot?.name ?? "No spot")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Cycling the pinned spot without opening the app is the whole point of interactive widgets.
    private var widgetButtons: some View {
        HStack(spacing: 10) {
            Button(intent: NextSpotIntent()) {
                Label("Next", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
            }
            Button(intent: PinNearestSpotIntent()) {
                Label("Nearest", systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(entry.theme.accent)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func nearbyList(limit: Int, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            if entry.nearby.isEmpty {
                WidgetPlaceholder(
                    theme: entry.theme,
                    message: entry.placeholderMessage ?? "No spots yet.",
                    compact: true
                )
            } else {
                ForEach(Array(entry.nearby.prefix(limit).enumerated()), id: \.offset) { _, item in
                    Link(destination: item.spot.deepLinkURL) {
                        NearbyRow(
                            theme: entry.theme,
                            unitPreference: entry.unitPreference,
                            spot: item.spot,
                            metres: item.metres,
                            bearing: item.bearing
                        )
                    }
                }
            }
        }
    }

    // MARK: Lock Screen

    /// The ring fills over the last kilometre — empty means "still a long way".
    private var circularView: some View {
        Gauge(value: gaugeValue) {
            Image(systemName: "location.north.line.fill")
        } currentValueLabel: {
            Text(entry.readout?.value ?? "—")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var inlineView: some View {
        // Inline is one line of text with an optional symbol; anything cleverer gets stripped.
        Label {
            Text(inlineText)
        } icon: {
            Image(systemName: "location.north.line.fill")
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.spot?.name ?? "Tradewind")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .widgetAccentable()

            if entry.nearby.isEmpty {
                Text(entry.placeholderMessage ?? "No spots yet")
                    .font(.system(size: 11))
            } else {
                ForEach(Array(entry.nearby.prefix(2).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        Text(item.spot.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(compact(item.metres))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var gaugeValue: Double {
        guard let metres = entry.metres else { return 0 }
        return max(0, min(1, 1 - metres / 1_000))
    }

    private var inlineText: String {
        guard let spot = entry.spot else { return "No spots saved" }
        guard let distance = entry.distanceText else { return spot.name }
        return "\(spot.name) · \(distance)"
    }

    /// Says "last known position" rather than quietly showing a stale distance as if it were live.
    private var secondaryLine: String {
        if entry.isStale { return "Last known position" }
        return entry.spot?.subtitle ?? ""
    }

    private func compact(_ metres: Double?) -> String {
        guard let metres else { return "—" }
        return DistanceFormatting.compact(metres: metres, preference: entry.unitPreference)
    }
}

// MARK: - Row

/// One spot in a list: arrow, name, distance. Used by the medium and large families.
struct NearbyRow: View {
    var theme: Theme
    var unitPreference: UnitPreference
    var spot: SharedSpot
    var metres: Double?
    var bearing: Double?

    var body: some View {
        HStack(spacing: 7) {
            ArrowShape()
                .fill(theme.arrowGradient)
                .frame(width: 10, height: 16)
                .rotationEffect(.degrees(bearing ?? 0))
                .opacity(bearing == nil ? 0.3 : 1)

            Text(spot.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(metres.map {
                DistanceFormatting.compact(metres: $0, preference: unitPreference)
            } ?? "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.accent)
        }
    }
}

import SwiftUI
import WidgetKit

/// "How far is everything from here" — the whole library ranked by distance, no configuration.
///
/// This is the widget the brief actually asked for: distance to all your photos from where you
/// are. The configurable single-spot widget answers a different question, so both exist.
struct NearestSpotsWidget: Widget {

    let kind = "NearestSpotsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearestSpotsProvider()) { entry in
            NearestSpotsView(entry: entry)
        }
        .configurationDisplayName("Everything Nearby")
        .description("Every spot you've saved, nearest first.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct NearestSpotsProvider: TimelineProvider {

    func placeholder(in context: Context) -> SpotEntry {
        SpotEntryBuilder.preview()
    }

    func getSnapshot(in context: Context, completion: @escaping (SpotEntry) -> Void) {
        if context.isPreview {
            completion(SpotEntryBuilder.preview())
            return
        }
        Task {
            completion(await SpotEntryBuilder.entry(for: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpotEntry>) -> Void) {
        Task {
            completion(await SpotEntryBuilder.timeline(for: nil))
        }
    }
}

struct NearestSpotsView: View {
    @Environment(\.widgetFamily) private var family

    var entry: SpotEntry

    /// The theme travels in the entry, since a widget has no environment to read it from.
    private var theme: Theme { entry.theme }

    /// The large family has room for more of them; the medium does not.
    private var rowLimit: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            if entry.nearby.isEmpty { placeholder } else { rows }
        }
        .containerBackground(for: .widget) {
            WidgetBackdrop(theme: entry.theme)
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("From here")
                .font(theme.sans(11, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(entry.theme.accent)
                .widgetAccentable()
            Spacer()
            if entry.isStale {
                Text("last known")
                    .font(theme.sans(9, weight: .medium))
                    .foregroundStyle(entry.theme.textMuted)
            }
        }
    }

    private var placeholder: some View {
        VStack {
            Spacer()
            WidgetPlaceholder(
                theme: entry.theme,
                message: entry.placeholderMessage ?? "Save a spot in Tradewind to see it here."
            )
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var rows: some View {
        VStack(spacing: family == .systemLarge ? 12 : 8) {
            ForEach(Array(entry.nearby.prefix(rowLimit).enumerated()), id: \.offset) { index, item in
                Link(destination: item.spot.deepLinkURL) {
                    SpotListRow(
                        theme: entry.theme,
                        unitPreference: entry.unitPreference,
                        spot: item.spot,
                        metres: item.metres,
                        bearing: item.bearing,
                        isFirst: index == 0,
                        showsPhoto: family == .systemLarge
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A richer row than the compass widget's: the nearest one gets emphasis, and on the large family
/// each row carries its photo.
struct SpotListRow: View {
    var theme: Theme
    var unitPreference: UnitPreference
    var spot: SharedSpot
    var metres: Double?
    var bearing: Double?
    var isFirst: Bool
    var showsPhoto: Bool

    var body: some View {
        HStack(spacing: 9) {
            if showsPhoto { thumbnail }
            arrow
            labels
            Spacer(minLength: 4)
            distance
        }
    }

    private var thumbnail: some View {
        WidgetPhoto(spot: spot, theme: theme)
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var arrow: some View {
        ArrowShape()
            .fill(theme.arrowGradient)
            .frame(width: isFirst ? 12 : 10, height: isFirst ? 19 : 16)
            .rotationEffect(.degrees(bearing ?? 0))
            .opacity(bearing == nil ? 0.3 : 1)
            .widgetAccentable()
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(spot.name)
                .font(theme.sans(isFirst ? 13 : 12, weight: isFirst ? .bold : .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            if showsPhoto, let place = spot.placeName, !place.isEmpty {
                Text(place)
                    .font(theme.sans(9))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var distance: some View {
        let readout = metres.map {
            DistanceFormatting.readout(metres: $0, preference: unitPreference)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(readout?.value ?? "—")
                .font(theme.mono(isFirst ? 16 : 14, medium: true))
                .monospacedDigit()
                .foregroundStyle(isFirst ? theme.accent : theme.text)
            if let unit = readout?.unit, !unit.isEmpty {
                Text(unit)
                    .font(theme.mono(9, medium: true))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }
}

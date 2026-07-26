import SwiftUI
import UIKit
import WidgetKit

/// One timeline entry: a spot, how far away it is, and which way it lies.
struct SpotEntry: TimelineEntry {
    var date: Date
    var theme: Theme
    var unitPreference: UnitPreference
    /// The spot this widget is about. Nil when there are no spots at all.
    var spot: SharedSpot?
    /// Nearest few, for the widgets that show a list.
    var nearby: [(spot: SharedSpot, metres: Double?, bearing: Double?)]
    var metres: Double?
    /// Absolute bearing from you to the spot, degrees from north.
    var bearing: Double?
    /// True when the distance came from a cached coordinate rather than a fresh fix.
    var isStale: Bool
    /// Set when there is nothing useful to draw, so every widget family can say the same thing.
    var placeholderMessage: String?

    var distanceText: String? {
        guard let metres else { return nil }
        return DistanceFormatting.string(metres: metres, preference: unitPreference)
    }

    var readout: DistanceReadout? {
        guard let metres else { return nil }
        return DistanceFormatting.readout(metres: metres, preference: unitPreference)
    }
}

/// Builds entries for every Tradewind widget.
///
/// Widgets are given a short window and no ability to keep a location manager running, so this
/// asks for one fix, falls back to the coordinate the app last recorded, and never blocks for
/// long. The refresh cadence is deliberately modest: WidgetKit budgets refreshes per day, and
/// burning them on a distance that changes by ten metres is how a widget stops updating at all
/// by mid-afternoon.
enum SpotEntryBuilder {

    /// Distance changes slowly unless you are moving, and if you are moving the app itself is
    /// nudging WidgetKit from its location callbacks.
    static let refreshInterval: TimeInterval = 15 * 60

    static func entry(for requestedSpotID: UUID?, date: Date = Date()) async -> SpotEntry {
        let snapshot = SharedSnapshotStore.load()
        let theme = ThemeCatalog.theme(id: snapshot?.themeID)
        let units = snapshot?.unitPreference ?? .automatic

        guard let snapshot, !snapshot.isEmpty else {
            return SpotEntry(
                date: date,
                theme: theme,
                unitPreference: units,
                spot: nil,
                nearby: [],
                metres: nil,
                bearing: nil,
                isStale: false,
                placeholderMessage: "Save a spot in Tradewind to see it here."
            )
        }

        let fresh = await CurrentLocationProbe.coordinate()
        let origin = fresh ?? CurrentLocationProbe.cachedCoordinate()

        let ordered = snapshot.spotsByDistance(from: origin)
        let nearby = ordered.prefix(3).map { pair -> (SharedSpot, Double?, Double?) in
            let bearing = origin.map { BearingMath.initialBearing(from: $0, to: pair.spot.coordinate) }
            return (pair.spot, pair.metres, bearing)
        }

        let chosen: SharedSpot? = {
            if let requestedSpotID, let match = snapshot.spot(id: requestedSpotID) { return match }
            return snapshot.featuredSpot(from: origin)
        }()

        let metres = origin.flatMap { start in
            chosen.map { BearingMath.distance(from: start, to: $0.coordinate) }
        }
        let bearing = origin.flatMap { start in
            chosen.map { BearingMath.initialBearing(from: start, to: $0.coordinate) }
        }

        return SpotEntry(
            date: date,
            theme: theme,
            unitPreference: units,
            spot: chosen,
            nearby: nearby.map { (spot: $0.0, metres: $0.1, bearing: $0.2) },
            metres: metres,
            bearing: bearing,
            isStale: fresh == nil && origin != nil,
            placeholderMessage: origin == nil ? "Waiting for your location." : nil
        )
    }

    static func timeline(for requestedSpotID: UUID?) async -> Timeline<SpotEntry> {
        let entry = await self.entry(for: requestedSpotID)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(refreshInterval))
        )
    }

    /// What the widget gallery shows. Never touches location — the gallery must render instantly.
    static func preview(date: Date = Date()) -> SpotEntry {
        let theme = ThemeCatalog.theme(id: SharedSnapshotStore.load()?.themeID)
        let sample = SharedSpot(
            id: UUID(),
            name: "Ravana Falls",
            placeName: "Ella, Sri Lanka",
            coordinate: Coordinate(latitude: 6.8395, longitude: 81.0553),
            capturedAt: date.addingTimeInterval(-86_400),
            glyph: "🌊"
        )
        let second = SharedSpot(
            id: UUID(),
            name: "Beach shack",
            placeName: "Mirissa",
            coordinate: Coordinate(latitude: 5.9483, longitude: 80.4589),
            capturedAt: date.addingTimeInterval(-172_800),
            glyph: "🍹"
        )
        let third = SharedSpot(
            id: UUID(),
            name: "Tea room",
            placeName: "Nuwara Eliya",
            coordinate: Coordinate(latitude: 6.9497, longitude: 80.7891),
            capturedAt: date.addingTimeInterval(-259_200),
            glyph: "☕️"
        )

        return SpotEntry(
            date: date,
            theme: theme,
            unitPreference: .automatic,
            spot: sample,
            nearby: [
                (spot: sample, metres: 240, bearing: 34),
                (spot: second, metres: 1_430, bearing: 156),
                (spot: third, metres: 3_820, bearing: 288),
            ],
            metres: 240,
            bearing: 34,
            isStale: false,
            placeholderMessage: nil
        )
    }
}

// MARK: - Shared widget pieces

/// The widget backdrop.
///
/// Flat canvas, matching the app. Spritz spends its one permitted gradient on a soft accent bloom in
/// the corner, which is what stops a cream widget looking like a blank card; Nomad has none at all.
struct WidgetBackdrop: View {
    var theme: Theme

    var body: some View {
        ZStack {
            theme.canvas
            if theme.heroGradient != nil {
                RadialGradient(
                    colors: [theme.accent.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.88, y: 0.06),
                    startRadius: 0,
                    endRadius: 190
                )
            }
        }
    }
}

/// Distance, split so the number can be big and the unit small.
struct WidgetDistanceText: View {
    var readout: DistanceReadout?
    var theme: Theme
    var numberSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(readout?.value ?? "—")
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let unit = readout?.unit, !unit.isEmpty {
                Text(unit)
                    .font(.system(size: numberSize * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .foregroundStyle(theme.text)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
}

/// The arrow, plus the small print that keeps it honest.
///
/// A widget cannot read the magnetometer, so this points at the spot's compass bearing with north
/// up — it is not a live compass and does not pretend to be. The letter underneath says which
/// way, which is the part that survives being glanced at.
struct WidgetArrow: View {
    var theme: Theme
    var bearing: Double?
    var size: CGFloat = 34
    var showsCompassPoint: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            ArrowShape()
                .fill(theme.arrowGradient)
                .frame(width: size * 0.62, height: size)
                .rotationEffect(.degrees(bearing ?? 0))
                .opacity(bearing == nil ? 0.35 : 1)
                .shadow(color: theme.glow.opacity(0.5), radius: 5)
            if showsCompassPoint, let bearing {
                Text(BearingMath.compassPoint(forBearing: bearing))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }
}

/// Shown instead of a distance when there is nothing to show.
struct WidgetPlaceholder: View {
    var theme: Theme
    var message: String
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: compact ? 16 : 22, weight: .light))
                .foregroundStyle(theme.accent)
            Text(message)
                .font(.system(size: compact ? 10 : 12, weight: .medium))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 8)
    }
}

/// The photo a widget draws, loaded from the App Group thumbnail the app leaves behind.
struct WidgetPhoto: View {
    var spot: SharedSpot?
    var theme: Theme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.surface, theme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let url = spot?.thumbnailURL,
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let glyph = spot?.glyph, !glyph.isEmpty {
                Text(glyph).font(.system(size: 26))
            }
        }
    }
}

import SwiftData
import SwiftUI
import UIKit

/// Home. Your spots, nearest first, with the distances ticking as you move.
struct SpotsGalleryView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Spot.capturedAt, order: .reverse) private var spots: [Spot]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var location = LocationService.shared
    @State private var selectedTripID: UUID?

    var hero: Namespace.ID

    private var store: SpotStore { SpotStore(context: modelContext) }

    private var filtered: [Spot] {
        guard let selectedTripID else { return spots }
        return spots.filter { $0.trip?.id == selectedTripID }
    }

    private var ranked: [RankedSpot] {
        SpotRanking.rank(filtered, from: location.coordinate)
    }

    private var heading: Double? {
        location.headingDegrees(preferTrueNorth: settings.usesTrueNorth)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if !location.isAuthorized {
                    LocationPromptCard(isDenied: location.isDenied) {
                        location.requestWhenInUseAuthorization()
                    }
                    .padding(.horizontal, 18)
                }

                if spots.isEmpty {
                    EmptyStateView(
                        symbol: "camera.viewfinder",
                        title: "Nowhere to go yet",
                        message: "Photograph somewhere worth coming back to. Tradewind remembers where you were standing and points you back.",
                        actionTitle: "Take the first photo",
                        action: { router.isShowingCapture = true }
                    )
                    .padding(.top, 40)
                } else {
                    if trips.count > 0 {
                        tripFilter
                    }

                    if let featured = SpotRanking.featured(in: ranked) {
                        FeaturedSpotCard(
                            ranked: featured,
                            heading: heading,
                            unitPreference: settings.unitPreference,
                            hero: hero,
                            onOpen: { open(featured.spot) }
                        )
                        .padding(.horizontal, 18)
                    }

                    if ranked.count > 1 {
                        SectionHeader(
                            eyebrow: location.coordinate == nil ? "Most recent" : "Nearest first",
                            title: "All your spots"
                        )
                        .padding(.horizontal, 18)

                        LazyVGrid(
                            columns: [GridItem(spacing: 14), GridItem(spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(Array(ranked.dropFirst(featuredIsFirst ? 1 : 0))) { item in
                                SpotGridCard(
                                    ranked: item,
                                    heading: heading,
                                    unitPreference: settings.unitPreference,
                                    hero: hero,
                                    onOpen: { open(item.spot) }
                                )
                                .contextMenu {
                                    spotMenu(for: item.spot)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            location.requestOneShotLocation()
            store.refreshSnapshot()
        }
    }

    /// True when the featured card is also the first item in the grid, which it is unless a
    /// further-away spot has been pinned.
    private var featuredIsFirst: Bool {
        guard let featured = SpotRanking.featured(in: ranked) else { return false }
        return ranked.first?.id == featured.id
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).eyebrowStyle(color: theme.accent)
                Text("Tradewind")
                    .font(Typography.displayTitle)
                    .foregroundStyle(theme.text)
                if !spots.isEmpty {
                    Text(summaryLine)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textMuted)
                }
            }
            Spacer()
            Button {
                router.isShowingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 42, height: 42)
                    .background { Circle().fill(.ultraThinMaterial) }
                    .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
    }

    private var greeting: String {
        switch TimeOfDay.current {
        case .dawn: return "Early start"
        case .day: return "Somewhere to be"
        case .goldenHour: return "Golden hour"
        case .dusk: return "Last light"
        case .night: return "After dark"
        }
    }

    private var summaryLine: String {
        let count = spots.count
        let noun = count == 1 ? "spot" : "spots"
        guard let nearest = ranked.first, let metres = nearest.metres else {
            return "\(count) \(noun) saved"
        }
        let distance = DistanceFormatting.string(metres: metres, preference: settings.unitPreference)
        return "\(count) \(noun) · nearest \(distance) away"
    }

    private var tripFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ChipButton(title: "Everywhere", symbol: "globe.americas.fill", isSelected: selectedTripID == nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTripID = nil }
                }
                ForEach(trips) { trip in
                    ChipButton(
                        title: trip.displayName,
                        symbol: "suitcase.fill",
                        isSelected: selectedTripID == trip.id
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTripID = selectedTripID == trip.id ? nil : trip.id
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func spotMenu(for spot: Spot) -> some View {
        Button {
            store.setPinned(spot.isPinned ? nil : spot)
            FeedbackService.shared.lightTap()
        } label: {
            Label(
                spot.isPinned ? "Unpin from widgets" : "Pin to widgets",
                systemImage: spot.isPinned ? "pin.slash" : "pin"
            )
        }
        if let url = spot.deepLinkURL {
            ShareLink(item: url) {
                Label("Share this spot", systemImage: "square.and.arrow.up")
            }
        }
        Button(role: .destructive) {
            store.delete(spot)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func open(_ spot: Spot) {
        FeedbackService.shared.lightTap()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            router.openSpot(id: spot.id)
        }
    }
}

// MARK: - Featured card

/// The hero: the spot you are most likely to want, big enough to tap without looking.
private struct FeaturedSpotCard: View {
    @Environment(\.theme) private var theme

    var ranked: RankedSpot
    var heading: Double?
    var unitPreference: UnitPreference
    var hero: Namespace.ID
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                PhotoView(data: ranked.spot.photoData, maxDimension: 1_400, glyph: ranked.spot.glyph)
                    .matchedGeometryEffect(id: "photo-\(ranked.spot.id)", in: hero)
                    .frame(height: 300)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.25), .black.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        if ranked.spot.isPinned {
                            PillLabel(text: "Pinned", symbol: "pin.fill", prominent: true)
                        }
                        if let trip = ranked.spot.trip?.name, !trip.isEmpty {
                            PillLabel(text: trip, symbol: "suitcase.fill")
                        }
                        if let bearing = ranked.bearing {
                            PillLabel(text: BearingMath.compassPoint(forBearing: bearing))
                        }
                    }

                    Text(ranked.spot.displayName)
                        .font(Typography.title)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(alignment: .center, spacing: 12) {
                        MiniArrow(theme: theme, angle: ranked.arrowAngle(heading: heading), size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            if let metres = ranked.metres {
                                let readout = DistanceFormatting.readout(
                                    metres: metres,
                                    preference: unitPreference
                                )
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(readout.value)
                                        .font(Typography.readout)
                                        .monospacedDigit()
                                    Text(readout.unit)
                                        .font(Typography.readoutUnit)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                .foregroundStyle(.white)
                                if let walk = DistanceFormatting.walkingTime(metres: metres) {
                                    Text(walk)
                                        .font(Typography.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            } else {
                                Text("Waiting for a fix")
                                    .font(Typography.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(18)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the compass for this spot")
    }

    private var accessibilityText: String {
        guard let metres = ranked.metres else { return ranked.spot.displayName }
        let distance = DistanceFormatting.string(metres: metres, preference: unitPreference)
        let compass = ranked.bearing.map { ", " + BearingMath.compassPoint(forBearing: $0) } ?? ""
        return "\(ranked.spot.displayName), \(distance) away\(compass)"
    }
}

// MARK: - Grid card

private struct SpotGridCard: View {
    @Environment(\.theme) private var theme

    var ranked: RankedSpot
    var heading: Double?
    var unitPreference: UnitPreference
    var hero: Namespace.ID
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    PhotoView(data: ranked.spot.photoData, maxDimension: 700, glyph: ranked.spot.glyph)
                        .matchedGeometryEffect(id: "photo-\(ranked.spot.id)", in: hero)
                        .frame(height: 132)

                    if ranked.spot.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.deepest)
                            .padding(6)
                            .background { Circle().fill(theme.accent) }
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(ranked.spot.displayName)
                        .font(Typography.cardTitle)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        MiniArrow(theme: theme, angle: ranked.arrowAngle(heading: heading), size: 20)
                        if let metres = ranked.metres {
                            let readout = DistanceFormatting.readout(
                                metres: metres,
                                preference: unitPreference
                            )
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(readout.value)
                                    .font(Typography.cardDistance)
                                    .monospacedDigit()
                                Text(readout.unit)
                                    .font(Typography.label)
                                    .foregroundStyle(theme.textMuted)
                            }
                            .foregroundStyle(theme.text)
                        } else {
                            Text("—")
                                .font(Typography.cardDistance)
                                .foregroundStyle(theme.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(12)
            }
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(theme.cardTint.opacity(0.45))
                            .blendMode(.softLight)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Permission prompt

private struct LocationPromptCard: View {
    @Environment(\.theme) private var theme

    var isDenied: Bool
    var onRequest: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isDenied ? "location.slash.fill" : "location.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text(isDenied ? "Location is switched off" : "Tradewind needs your location")
                        .font(Typography.cardTitle)
                        .foregroundStyle(theme.text)
                }
                Text(isDenied
                    ? "Distances and the arrow need location access. You can turn it back on in Settings › Privacy › Location Services."
                    : "Without it there is no arrow and no distance — everything else still works.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textMuted)

                if isDenied {
                    SecondaryButton(title: "Open Settings", symbol: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } else {
                    PrimaryButton(title: "Allow location", symbol: "location.fill", action: onRequest)
                }
            }
        }
    }
}

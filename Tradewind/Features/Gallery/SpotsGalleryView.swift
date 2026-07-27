import SwiftData
import SwiftUI
import UIKit

/// Home. Your spots, nearest first, with the distances ticking as you move.
struct SpotsGalleryView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Spot> { $0.deletedAt == nil },
        sort: \Spot.capturedAt,
        order: .reverse
    ) private var spots: [Spot]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var location = LocationService.shared
    @State private var selectedTripID: UUID?
    @State private var selectedKind: PlaceKind?
    @State private var searchQuery = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    var hero: Namespace.ID

    private var store: SpotStore { SpotStore(context: modelContext) }

    private var filtered: [Spot] {
        var result = spots
        if let selectedTripID {
            result = result.filter { $0.trip?.id == selectedTripID }
        }
        if let selectedKind {
            result = result.filter { $0.placeKind == selectedKind }
        }
        if isSearching {
            result = result.filter {
                SpotSearch.matches(
                    query: searchQuery,
                    name: $0.displayName,
                    placeName: $0.placeName,
                    note: $0.note
                )
            }
        }
        return result
    }

    /// Kinds actually in use. The chips only appear once there are two to choose between —
    /// a filter with one option is furniture.
    private var kindsInUse: [PlaceKind] {
        var seen: [PlaceKind] = []
        for spot in spots where !seen.contains(spot.placeKind) {
            seen.append(spot.placeKind)
        }
        return PlaceKind.pickable.filter(seen.contains)
    }

    private var ranked: [RankedSpot] {
        SpotRanking.rank(filtered, from: location.coordinate)
    }

    private var heading: Double? {
        location.headingDegrees(preferTrueNorth: settings.usesTrueNorth)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader
                VStack(alignment: .leading, spacing: 22) {
                    if !location.isAuthorized { permissionPrompt }
                    if spots.isEmpty { emptyState } else { content }
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)

        .refreshable {
            location.requestOneShotLocation()
            store.refreshSnapshot()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching { searchField }
        if !trips.isEmpty { tripFilter }
        if kindsInUse.count > 1 { kindFilter }
        if ranked.isEmpty, !spots.isEmpty { noMatches }
        if let featured = SpotRanking.featured(in: ranked) {
            FeaturedSpotCard(
                ranked: featured,
                heading: heading,
                unitPreference: settings.unitPreference,
                hero: hero,
                onOpen: { open(featured.spot) }
            )
            .contextMenu { spotMenu(for: featured.spot) }
            .padding(.horizontal, 18)
        }
        if ranked.count > 1 { grid }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                eyebrow: location.coordinate == nil ? "Most recent" : "Nearest first",
                title: "All your spots"
            )

            LazyVGrid(columns: [GridItem(spacing: 14), GridItem(spacing: 14)], spacing: 14) {
                ForEach(gridItems) { item in
                    SpotGridCard(
                        ranked: item,
                        heading: heading,
                        unitPreference: settings.unitPreference,
                        hero: hero,
                        onOpen: { open(item.spot) }
                    )
                    .contextMenu { spotMenu(for: item.spot) }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// Everything except the spot already shown as the hero card — unless a further-away spot is
    /// pinned, in which case the hero is not the first item and nothing is dropped.
    private var gridItems: [RankedSpot] {
        guard let featured = SpotRanking.featured(in: ranked) else { return ranked }
        guard ranked.first?.id == featured.id else { return ranked }
        return Array(ranked.dropFirst())
    }

    private var permissionPrompt: some View {
        LocationPromptCard(isDenied: location.isDenied) {
            location.requestWhenInUseAuthorization()
        }
        .padding(.horizontal, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                symbol: "camera.viewfinder",
                title: "Nowhere to go yet",
                message: "Photograph somewhere worth coming back to. Tradewind remembers where you were standing and points you back.",
                actionTitle: "Take the first photo",
                action: { router.isShowingCapture = true }
            )
            // The other two doors in, taught where they are needed: an empty screen is the
            // onboarding that arrives exactly on time.
            Button {
                router.isShowingSaveHere = true
            } label: {
                Text("No photo? Save this location, or search an address")
                    .font(theme.sans(13, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            .accessibilityIdentifier("empty-plan-place")
        }
        .padding(.top, 40)
    }

    // MARK: - Pieces

    /// The masthead, on the one gradient the mood allows.
    ///
    /// Structured after the reference Home screen: a hero block carrying the eyebrow, the title in
    /// the display face, and a status pill, with the cream body starting underneath it. In Nomad the
    /// same block resolves to a flat raised surface, because that mood permits no gradient.
    /// Solar-aware: the wash and the greeting both follow the actual sun at the actual place.
    private var skyPhase: TimeOfDay {
        TimeOfDay.current(at: location.coordinate)
    }

    private var heroHeader: some View {
        HeroPanel(theme: theme, phase: skyPhase) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(skyPhase.greeting)
                            .font(theme.eyebrowFont)
                            .textCase(.uppercase)
                            .tracking(theme.labelTracking(theme.scale.eyebrow))
                            .foregroundStyle(theme.onHero.opacity(0.8))
                        Text("Tradewind")
                            .font(theme.displayTitleFont)
                            .tracking(theme.displayTracking)
                            .foregroundStyle(theme.onHero)
                            .accessibilityIdentifier("gallery-screen")
                    }
                    Spacer()
                    CircularButton(symbol: "magnifyingglass", onHero: true) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            isSearching.toggle()
                        }
                        if isSearching {
                            searchFocused = true
                        } else {
                            searchQuery = ""
                        }
                    }
                    .accessibilityIdentifier("search-button")
                    .accessibilityLabel("Search spots")
                    CircularButton(symbol: "slider.horizontal.3", onHero: true) {
                        router.isShowingSettings = true
                    }
                    .accessibilityIdentifier("settings-button")
                    .accessibilityLabel("Settings")
                }

                HStack(spacing: 8) {
                    if !spots.isEmpty { statusPill }
                    saveHereChip
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 58)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One tap from anywhere on this screen to pin where you are standing — parking bay, hotel
    /// door, tent. The photo flow is for places worth looking at; this is for places worth finding.
    private var saveHereChip: some View {
        Button {
            router.isShowingSaveHere = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .bold))
                Text("Save here")
                    .font(theme.sans(theme.scale.caption, weight: .bold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(theme.onAccent)
            .background { Capsule().fill(theme.accent) }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("save-here-button")
        .accessibilityLabel("Save this location")
    }

    /// "Nearest 240 m away" — the reference screen's "Currently in Honolulu" chip, doing the job
    /// this app actually has.
    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(theme.highlight)
                .frame(width: 7, height: 7)
            Text(summaryLine)
                .font(theme.sans(theme.scale.caption, weight: .medium))
                .foregroundStyle(theme.onHero)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background {
            Capsule().fill(theme.onHero.opacity(0.18))
        }
    }

    private var summaryLine: String {
        let count = spots.count
        let noun = count == 1 ? "spot" : "spots"
        guard let nearest = ranked.first, let metres = nearest.metres else {
            return "\(count) \(noun) saved"
        }
        let distance = DistanceFormatting.string(metres: metres, preference: settings.unitPreference)
        return "Nearest is \(distance) away"
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

    private var searchField: some View {
        Surface(padding: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                TextField("Name, place, or a note like \"aisle F\"", text: $searchQuery)
                    .font(theme.bodyTextFont)
                    .foregroundStyle(theme.text)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("search-field")
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textFaint)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// Spots exist, the filters just excluded all of them — a different fact from "no spots yet",
    /// and one the person can fix from right here.
    private var noMatches: some View {
        VStack(spacing: 8) {
            Text("Nothing matches")
                .font(theme.sectionTitleFont)
                .foregroundStyle(theme.text)
            Text(searchQuery.isEmpty
                ? "No spots under these filters."
                : "No spot, place or note contains \"\(searchQuery)\".")
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
            Button("Clear filters") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    searchQuery = ""
                    selectedKind = nil
                    selectedTripID = nil
                }
            }
            .font(theme.sans(13, weight: .medium))
            .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityIdentifier("no-matches")
    }

    private var kindFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(kindsInUse) { candidate in
                    ChipButton(
                        title: candidate.pluralLabel,
                        symbol: candidate.symbol,
                        isSelected: selectedKind == candidate
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedKind = selectedKind == candidate ? nil : candidate
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
            // The undo toast is a root-level overlay fed by UndoCenter from inside the store —
            // this action only deletes.
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
                photo
                caption.padding(18)
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

    private var photo: some View {
        PhotoView(data: ranked.spot.photoData, maxDimension: 1_400, glyph: ranked.spot.glyph, fallbackSymbol: ranked.spot.placeKind.symbol)
            .matchedGeometryEffect(id: "photo-\(ranked.spot.id)", in: hero)
            .frame(height: 300)
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.25), .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 10) {
            pills
            Text(ranked.spot.displayName)
                .font(theme.titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)
            distanceRow
        }
    }

    @ViewBuilder
    private var pills: some View {
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
    }

    private var distanceRow: some View {
        HStack(alignment: .center, spacing: 12) {
            MiniArrow(theme: theme, angle: ranked.arrowAngle(heading: heading), size: 34)
            distanceBlock
            Spacer()
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.accent)
        }
    }

    @ViewBuilder
    private var distanceBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let metres = ranked.metres {
                let readout = DistanceFormatting.readout(metres: metres, preference: unitPreference)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(readout.value)
                        .font(theme.readoutFont)
                        .monospacedDigit()
                    Text(readout.unit)
                        .font(theme.readoutUnitFont)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)

                if let walk = DistanceFormatting.walkingTime(metres: metres) {
                    Text(walk)
                        .font(theme.captionFont)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Text("Waiting for a fix")
                    .font(theme.captionFont)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
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
                photo
                caption
            }
            .background { cardBackground }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityElement(children: .combine)
    }

    private var photo: some View {
        ZStack(alignment: .topTrailing) {
            PhotoView(data: ranked.spot.photoData, maxDimension: 700, glyph: ranked.spot.glyph, fallbackSymbol: ranked.spot.placeKind.symbol)
                .matchedGeometryEffect(id: "photo-\(ranked.spot.id)", in: hero)
                .frame(height: 132)

            if ranked.spot.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.canvas)
                    .padding(6)
                    .background { Circle().fill(theme.accent) }
                    .padding(8)
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ranked.spot.displayName)
                .font(theme.cardTitleFont)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            HStack(spacing: 8) {
                MiniArrow(theme: theme, angle: ranked.arrowAngle(heading: heading), size: 20)
                distanceText
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var distanceText: some View {
        if let metres = ranked.metres {
            let readout = DistanceFormatting.readout(metres: metres, preference: unitPreference)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(readout.value)
                    .font(theme.cardNumberFont)
                    .monospacedDigit()
                Text(readout.unit)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textMuted)
            }
            .foregroundStyle(theme.text)
        } else {
            Text("—")
                .font(theme.cardNumberFont)
                .foregroundStyle(theme.textMuted)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
            .fill(theme.surface)
    }
}

// MARK: - Permission prompt

private struct LocationPromptCard: View {
    @Environment(\.theme) private var theme

    var isDenied: Bool
    var onRequest: () -> Void

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isDenied ? "location.slash.fill" : "location.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text(isDenied ? "Location is switched off" : "Tradewind needs your location")
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                }
                Text(isDenied
                    ? "Distances and the arrow need location access. You can turn it back on in Settings › Privacy › Location Services."
                    : "Without it there is no arrow and no distance — everything else still works.")
                    .font(theme.captionFont)
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

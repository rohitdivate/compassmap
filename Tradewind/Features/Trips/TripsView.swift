import SwiftData
import SwiftUI

/// Spots grouped into trips. One island, one week, one very long afternoon.
struct TripsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @Query(filter: #Predicate<Spot> { $0.deletedAt == nil }) private var spots: [Spot]

    @State private var location = LocationService.shared
    @State private var isNaming = false
    @State private var draftName = ""

    var hero: Namespace.ID

    private var store: SpotStore { SpotStore(context: modelContext) }

    private var unassigned: [Spot] {
        spots.filter { $0.trip == nil }
    }

    var body: some View {
        content
            .alert("Name this trip", isPresented: $isNaming) {
                TextField("Sri Lanka, March", text: $draftName)
                Button("Create", action: createTrip)
                Button("Cancel", role: .cancel) { draftName = "" }
            }
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if trips.isEmpty { emptyState } else { tripList }
                    if !unassigned.isEmpty { looseSpots }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(theme.accent)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "suitcase",
            title: "No trips yet",
            message: "Group your spots into trips and each one gets its own cover — and its own look, if you want it.",
            actionTitle: "Start a trip",
            action: { isNaming = true }
        )
        .padding(.top, 30)
    }

    private var tripList: some View {
        VStack(spacing: 14) {
            ForEach(trips) { trip in
                NavigationLink {
                    TripDetailView(trip: trip, hero: hero)
                        .environment(settings)
                        .environment(router)
                        .environment(\.theme, theme)
                } label: {
                    TripCard(
                        trip: trip,
                        origin: location.coordinate,
                        unitPreference: settings.unitPreference
                    )
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(trip)
                    } label: {
                        Label("Delete trip", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var looseSpots: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "\(unassigned.count) loose", title: "Not in a trip")
                .padding(.horizontal, 18)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(SpotRanking.rank(unassigned, from: location.coordinate)) { item in
                        LooseSpotChip(
                            ranked: item,
                            unitPreference: settings.unitPreference,
                            trips: trips,
                            onOpen: { router.openSpot(id: item.spot.id) },
                            onAssign: { trip in store.assign(item.spot, to: trip) }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func createTrip() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.createTrip(name: name)
        draftName = ""
        FeedbackService.shared.lightTap()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trips.count) \(trips.count == 1 ? "trip" : "trips")")
                    .eyebrowStyle(theme: theme)
                Text("Trips")
                    .font(theme.displayTitleFont)
                    .foregroundStyle(theme.text)
                    .accessibilityIdentifier("trips-screen")
            }
            Spacer()
            // Settings used to exist only in the Spots masthead, which meant it did not exist at all
            // on this screen or the map.
            CircularButton(symbol: "slider.horizontal.3") {
                router.isShowingSettings = true
            }
            .accessibilityIdentifier("settings-button")
            .accessibilityLabel("Settings")
            Button {
                isNaming = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.canvas)
                    .frame(width: 42, height: 42)
                    .background { Circle().fill(theme.accent) }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("New trip")
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Trip card

private struct TripCard: View {
    @Environment(\.theme) private var theme

    var trip: Trip
    var origin: Coordinate?
    var unitPreference: UnitPreference

    /// The distance to the closest spot in the trip: the useful summary number, because a trip
    /// is only ever as far away as its nearest piece.
    private var nearestMetres: Double? {
        guard let origin else { return nil }
        return trip.orderedSpots
            .map { BearingMath.distance(from: origin, to: $0.coordinate) }
            .min()
    }

    private var tripTheme: Theme {
        trip.themeID.map { ThemeCatalog.theme(id: $0) } ?? theme
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            caption.padding(16)
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    @ViewBuilder
    private var coverPhoto: some View {
        if let coverSpot = trip.coverSpot {
            SpotPhotoView(spot: coverSpot, sizeClass: .card)
        } else {
            PhotoView(data: nil)
        }
    }

    private var cover: some View {
        coverPhoto
            .frame(height: 168)
            .overlay {
                LinearGradient(
                    colors: [
                        tripTheme.canvas.opacity(0.1),
                        tripTheme.canvas.opacity(0.55),
                        tripTheme.canvas.opacity(0.9),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            pills
            // The scrim under this caption resolves to the trip theme's canvas, so the text
            // takes that theme's text colour — white was invisible on Spritz's cream whenever
            // the trip had no cover photo.
            Text(trip.displayName)
                .font(theme.titleFont)
                .foregroundStyle(tripTheme.text)
                .lineLimit(1)
            if let subtitle = trip.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(tripTheme.text.opacity(0.75))
            }
        }
    }

    @ViewBuilder
    private var pills: some View {
        HStack(spacing: 6) {
            PillLabel(
                text: "\(trip.spotCount) \(trip.spotCount == 1 ? "spot" : "spots")",
                symbol: "photo.stack"
            )
            if let metres = nearestMetres {
                PillLabel(
                    text: DistanceFormatting.string(metres: metres, preference: unitPreference),
                    symbol: "location.fill",
                    prominent: true
                )
            }
        }
    }
}

// MARK: - Loose spot chip

private struct LooseSpotChip: View {
    @Environment(\.theme) private var theme

    var ranked: RankedSpot
    var unitPreference: UnitPreference
    var trips: [Trip]
    var onOpen: () -> Void
    var onAssign: (Trip) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SpotPhotoView(spot: ranked.spot, sizeClass: .card)
                .frame(width: 128, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.row, style: .continuous))

            Text(ranked.spot.displayName)
                .font(theme.captionFont)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if let metres = ranked.metres {
                Text(DistanceFormatting.string(metres: metres, preference: unitPreference))
                    .font(theme.labelFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(width: 128)
        .onTapGesture(perform: onOpen)
        .contextMenu {
            ForEach(trips) { trip in
                Button {
                    onAssign(trip)
                } label: {
                    Label("Add to \(trip.displayName)", systemImage: "suitcase.fill")
                }
            }
        }
    }
}

// MARK: - Trip detail

struct TripDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    let trip: Trip
    var hero: Namespace.ID

    @State private var location = LocationService.shared

    private var store: SpotStore { SpotStore(context: modelContext) }

    private var ranked: [RankedSpot] {
        SpotRanking.rank(trip.orderedSpots, from: location.coordinate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if ranked.isEmpty { emptyState } else { spotList }
                themePicker
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background {
            ThemedBackground(theme: theme)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(trip.spotCount) \(trip.spotCount == 1 ? "spot" : "spots")")
                .eyebrowStyle(theme: theme)
            Text(trip.displayName)
                .font(theme.displayTitleFont)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 18)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "photo.badge.plus",
            title: "Nothing here yet",
            message: "Long-press a spot on the Trips screen to add it to \(trip.displayName)."
        )
    }

    private var spotList: some View {
        VStack(spacing: 10) {
            ForEach(ranked) { item in
                Button {
                    router.openSpot(id: item.spot.id)
                } label: {
                    TripSpotRow(ranked: item, unitPreference: settings.unitPreference)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .contextMenu {
                    Button {
                        store.assign(item.spot, to: nil)
                    } label: {
                        Label("Remove from trip", systemImage: "minus.circle")
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// A trip can carry its own look. Opening the Sri Lanka trip should not feel identical to
    /// opening the Thailand one.
    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "Optional", title: "This trip's look")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ChipButton(title: "App default", isSelected: trip.themeID == nil) {
                        trip.themeID = nil
                    }
                    ForEach(ThemeCatalog.all) { candidate in
                        ChipButton(
                            title: candidate.name,
                            symbol: candidate.symbol,
                            isSelected: trip.themeID == candidate.id
                        ) {
                            trip.themeID = candidate.id
                            FeedbackService.shared.lightTap()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct TripSpotRow: View {
    @Environment(\.theme) private var theme

    var ranked: RankedSpot
    var unitPreference: UnitPreference

    var body: some View {
        Surface(padding: 12) {
            HStack(spacing: 14) {
                SpotPhotoView(spot: ranked.spot, sizeClass: .pin)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.avatar, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ranked.spot.displayName)
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(ranked.spot.subtitle)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let metres = ranked.metres {
                    distanceBlock(metres)
                }
                if let bearing = ranked.bearing {
                    MiniArrow(theme: theme, angle: bearing, size: 22)
                }
            }
        }
    }

    private func distanceBlock(_ metres: Double) -> some View {
        let readout = DistanceFormatting.readout(metres: metres, preference: unitPreference)
        return VStack(alignment: .trailing, spacing: 0) {
            Text(readout.value)
                .font(theme.cardNumberFont)
                .monospacedDigit()
                .foregroundStyle(theme.text)
            Text(readout.unit)
                .font(theme.labelFont)
                .foregroundStyle(theme.textMuted)
        }
    }
}

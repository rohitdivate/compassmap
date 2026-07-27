import Photos
import SwiftData
import SwiftUI

/// Places your photo library already knows, nearest first.
///
/// The scan is metadata-only and opt-in: the priming card explains exactly what happens before
/// the system prompt fires, nothing is imported without a tap, and the library's dominant
/// cluster — almost certainly home — is set apart rather than suggested. Suggestions within a
/// place-radius of an existing spot are dropped: this tab is for what is *not* saved yet.
struct NearbyView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Spot> { $0.deletedAt == nil },
        sort: \Spot.capturedAt,
        order: .reverse
    ) private var spots: [Spot]

    @State private var location = LocationService.shared
    @State private var phase: ScanPhase = .idle
    @State private var places: [PhotoClusters.Place] = []
    @State private var areaNames: [String: String] = [:]
    @State private var savedIDs: Set<String> = []

    private enum ScanPhase: Equatable {
        case idle
        case scanning(seen: Int)
        case done
        case denied
    }

    private var store: SpotStore { SpotStore(context: modelContext) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background { ThemedBackground(theme: theme) }
    }

    private var header: some View {
        HeroPanel(theme: theme, phase: TimeOfDay.current(at: location.coordinate)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("From your photos")
                            .font(theme.eyebrowFont)
                            .textCase(.uppercase)
                            .tracking(theme.labelTracking(theme.scale.eyebrow))
                            .foregroundStyle(theme.onHero.opacity(0.8))
                        Text("Nearby")
                            .font(theme.displayTitleFont)
                            .tracking(theme.displayTracking)
                            .foregroundStyle(theme.onHero)
                            .accessibilityIdentifier("nearby-screen")
                    }
                    Spacer()
                    CircularButton(symbol: "slider.horizontal.3", onHero: true) {
                        router.isShowingSettings = true
                    }
                    .accessibilityIdentifier("settings-button")
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 58)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            primingCard
        case .scanning(let seen):
            scanningCard(seen: seen)
        case .denied:
            deniedCard
        case .done:
            results
        }
    }

    // MARK: - States

    private var primingCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text("Start with places you've been")
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                }
                Text("Tradewind can scan your photo library's locations — on this phone, nothing leaves it — and suggest the places behind them. Nothing is saved until you choose it.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Scan my photos", symbol: "photo.on.rectangle.angled") {
                    startScan()
                }
                .accessibilityIdentifier("scan-photos")
            }
        }
    }

    private func scanningCard(seen: Int) -> some View {
        Surface {
            HStack(spacing: 12) {
                if !AppSettings.isUITesting { ProgressView().tint(theme.accent) }
                Text(seen > 0 ? "Scanning — \(seen) photos so far" : "Scanning your library")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    private var deniedCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text("Photos access is off")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.text)
                Text("Allow photo access in Settings › Privacy › Photos and the scan can run. Limited access works too — it scans what you've shared.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryButton(title: "Open Settings", symbol: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let visible = suggestions
        if visible.isEmpty, homePlace == nil {
            EmptyStateView(
                symbol: "sparkles",
                title: "Nothing new here",
                message: "Every place your photos know is already saved — or the library has no located photos yet.",
                actionTitle: "Scan again",
                action: { startScan() }
            )
            .padding(.top, 20)
        } else {
            SectionHeader(
                eyebrow: location.coordinate == nil ? "Most recent first" : "Nearest first",
                title: "Worth saving?"
            )
            ForEach(visible) { place in
                SuggestionCard(
                    place: place,
                    areaName: areaNames[place.id],
                    distanceText: distanceText(to: place),
                    isSaved: savedIDs.contains(place.id),
                    onSave: { save(place) }
                )
                .task { await resolveArea(for: place) }
            }
            if let home = homePlace {
                SectionHeader(eyebrow: "The library's biggest cluster", title: "Looks like home")
                SuggestionCard(
                    place: home,
                    areaName: areaNames[home.id],
                    distanceText: distanceText(to: home),
                    isSaved: savedIDs.contains(home.id),
                    saveTitle: "Save as Home",
                    onSave: { save(home, kind: .home) }
                )
                .task { await resolveArea(for: home) }
            }
        }
    }

    // MARK: - Data

    /// Ranked suggestions, minus home, minus anything already saved, nearest first with a fix.
    private var suggestions: [PhotoClusters.Place] {
        let unsaved = places.filter { !$0.isLikelyHome && !isAlreadySaved($0) }
        guard let origin = location.coordinate else { return unsaved }
        return unsaved.sorted {
            BearingMath.distance(from: origin, to: $0.centroid)
                < BearingMath.distance(from: origin, to: $1.centroid)
        }
    }

    private var homePlace: PhotoClusters.Place? {
        places.first { $0.isLikelyHome && !isAlreadySaved($0) }
    }

    private func isAlreadySaved(_ place: PhotoClusters.Place) -> Bool {
        spots.contains {
            BearingMath.distance(from: $0.coordinate, to: place.centroid) <= PhotoClusters.placeRadiusMetres
        }
    }

    private func distanceText(to place: PhotoClusters.Place) -> String? {
        guard let origin = location.coordinate else { return nil }
        let metres = BearingMath.distance(from: origin, to: place.centroid)
        return DistanceFormatting.string(metres: metres, preference: settings.unitPreference) + " away"
    }

    // MARK: - Behaviour

    private func startScan() {
        phase = .scanning(seen: 0)
        Task { @MainActor in
            // The seam skips authorization too — the system Photos dialog would otherwise sit
            // over the whole test run, and the canned scan needs no library anyway.
            let access: LibraryAccess = AppSettings.isUITesting
                ? .granted
                : await PhotoService.resolveLibraryAccess()
            guard access != .denied else {
                phase = .denied
                return
            }
            let points = await PhotoLibraryScanner.shared.scan { seen in
                Task { @MainActor in phase = .scanning(seen: seen) }
            }
            places = PhotoClusters.places(from: points, now: Date())
            phase = .done
        }
    }

    private func resolveArea(for place: PhotoClusters.Place) async {
        guard areaNames[place.id] == nil else { return }
        if AppSettings.isUITesting {
            areaNames[place.id] = "Canned Corner, London"
            return
        }
        if let name = await GeocodeService.shared.placeName(for: place.centroid) {
            areaNames[place.id] = name
        }
    }

    private func save(_ place: PhotoClusters.Place, kind: PlaceKind = .place) {
        Task { @MainActor in
            let photoData = await PhotoLibraryScanner.shared.fullImage(for: place.representativeID)
            let thumbnail = photoData.flatMap(PhotoService.thumbnailData(from:))
            store.createSpot(
                name: areaNames[place.id] ?? "",
                coordinate: place.centroid,
                capturedAt: place.lastAt,
                photoData: photoData,
                thumbnailData: thumbnail,
                kind: kind,
                placeName: areaNames[place.id]
            )
            savedIDs.insert(place.id)
            FeedbackService.shared.lightTap()
        }
    }
}

// MARK: - Card

private struct SuggestionCard: View {
    @Environment(\.theme) private var theme

    var place: PhotoClusters.Place
    var areaName: String?
    var distanceText: String?
    var isSaved: Bool
    var saveTitle: String = "Save"
    var onSave: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Surface(padding: 12) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 3) {
                    Text(areaName ?? "Somewhere you've been")
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(PhotoClusters.summary(place) + (distanceText.map { " · \($0)" } ?? ""))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.positive)
                        .accessibilityLabel("Saved")
                } else {
                    Button(saveTitle) { onSave() }
                        .font(theme.sans(13, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .accessibilityIdentifier("save-suggestion")
                }
            }
        }
        .task {
            thumbnail = await PhotoLibraryScanner.shared.thumbnail(for: place.representativeID)
        }
    }

    @ViewBuilder
    private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceRaised)
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo.stack")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

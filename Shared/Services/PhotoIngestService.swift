import Foundation

/// Quietly turns the photo library's places into spots.
///
/// There is no tab and no per-place "Save": once photo access is granted, every place the
/// library knows appears in the gallery by itself, named "Somewhere you've been" until the
/// geocoder describes the area. The decisions — when a pass is due, which clusters are new,
/// what kind each becomes — are `PhotoIngestPolicy`'s, tested in isolation; this class is the
/// plumbing around them.
@MainActor
final class PhotoIngestService {

    static let shared = PhotoIngestService()
    private init() {}

    /// A pass can be triggered from scene-activation and from onboarding completing in the same
    /// breath; the second call must be a no-op, not a duplicate scan.
    private var isRunning = false

    /// Runs a pass if one is due. Called on every scene activation and when onboarding finishes.
    func ingestIfDue(store: SpotStore, now: Date = Date()) {
        let settings = AppSettings.shared
        guard PhotoIngestPolicy.isDue(
            lastRunAt: settings.lastPhotoIngestAt,
            enabled: settings.photoIngestEnabled,
            onboarded: settings.hasCompletedOnboarding,
            now: now
        ) else { return }
        guard !isRunning else { return }
        isRunning = true

        Task { @MainActor in
            defer { isRunning = false }
            await run(store: store, settings: settings, now: now)
        }
    }

    private func run(store: SpotStore, settings: AppSettings, now: Date) async {
        // The system Photos dialog would sit over the whole UI-test run, and the canned scan
        // needs no library anyway — same seam the old Nearby tab used.
        let access: LibraryAccess = AppSettings.isUITesting
            ? .granted
            : await PhotoService.resolveLibraryAccess()
        guard access != .denied else {
            // Stamp anyway: asking again every activation would be nagging, not ingesting.
            settings.lastPhotoIngestAt = now
            return
        }

        let points = await PhotoLibraryScanner.shared.scan()
        let places = PhotoClusters.places(from: points, now: now)

        // De-dupe against everything, trash included — restoring a deleted place the person
        // threw away would be the scan overruling them.
        let existing = (store.allSpots() + store.deletedSpots()).map(\.coordinate)
        let chosen = PhotoIngestPolicy.clustersToIngest(
            places: places,
            existingSpotCoordinates: existing,
            seenKeys: Set(settings.photoIngestSeenKeys)
        )

        for place in chosen {
            let photoData = await PhotoLibraryScanner.shared.fullImage(for: place.representativeID)
            let thumbnail = photoData.flatMap(PhotoService.thumbnailData(from:))
            // GeocodeService has no test seam, so the canned pass names its spots directly.
            let cannedName = AppSettings.isUITesting ? "Canned Corner, London" : nil
            store.createSpot(
                name: cannedName ?? "",
                coordinate: place.centroid,
                capturedAt: place.lastAt,
                photoData: photoData,
                thumbnailData: thumbnail,
                kind: PhotoIngestPolicy.kind(for: place),
                placeName: cannedName,
                source: Spot.photoLibrarySource,
                refreshingSnapshot: false
            )
            settings.photoIngestSeenKeys.append(PhotoIngestPolicy.placeKey(for: place.centroid))
        }

        if !chosen.isEmpty {
            store.refreshSnapshot()
        }
        settings.lastPhotoIngestAt = now
    }
}

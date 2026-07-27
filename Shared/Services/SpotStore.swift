import CoreSpotlight
import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// The write path for spots and trips.
///
/// Views read through `@Query`, which is the point of SwiftData. Everything that *changes*
/// goes through here instead, because every change has the same three consequences: save the
/// model, rewrite the widget snapshot, and tell Spotlight. Scattering those three across the
/// view layer is how widgets end up stale.
///
/// Not actor-annotated on purpose: it is constructed from a view's `ModelContext` and only ever
/// touched from the main thread, and annotating it would force every call site through an
/// isolation hop for no benefit.
final class SpotStore {

    private let context: ModelContext
    private var settings: AppSettings { .shared }

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Creating

    @discardableResult
    func createSpot(
        name: String,
        coordinate: Coordinate,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        capturedAt: Date = Date(),
        headingAtCapture: Double? = nil,
        photoData: Data?,
        thumbnailData: Data?,
        glyph: String? = nil,
        note: String? = nil,
        kind: PlaceKind = .place,
        trip: Trip? = nil
    ) -> Spot {
        let spot = Spot(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            capturedAt: capturedAt,
            headingAtCapture: headingAtCapture,
            note: note,
            glyph: glyph,
            photoData: photoData,
            kind: kind,
            trip: trip
        )

        if let thumbnailData {
            spot.thumbnailFilename = SharedSnapshotStore.writeThumbnail(thumbnailData, for: spot.id)
        }

        context.insert(spot)
        save()

        // Name it properly in the background if the person did not.
        resolvePlaceName(for: spot)
        refreshSnapshot()
        donateToSpotlight(spot)

        return spot
    }

    @discardableResult
    func createTrip(name: String, subtitle: String? = nil, themeID: String? = nil) -> Trip {
        let trip = Trip(name: name, subtitle: subtitle, themeID: themeID)
        context.insert(trip)
        save()
        return trip
    }

    // MARK: - Editing

    func rename(_ spot: Spot, to name: String) {
        spot.name = name
        save()
        refreshSnapshot()
        donateToSpotlight(spot)
    }

    func update(_ spot: Spot, note: String?) {
        spot.note = note
        save()
    }

    func update(_ spot: Spot, kind: PlaceKind) {
        spot.placeKind = kind
        save()
        refreshSnapshot()
    }

    /// Records the fire date and schedules or cancels the notification in one move, so the stored
    /// date and the pending notification cannot disagree.
    func setReminder(_ spot: Spot, at fireDate: Date?) {
        spot.reminderAt = fireDate
        save()
        if let fireDate {
            ReminderService.shared.schedule(
                spotID: spot.id,
                spotName: spot.displayName,
                at: fireDate
            )
        } else {
            ReminderService.shared.cancel(spotID: spot.id)
        }
    }

    /// Switches the arrival alert for one spot and re-arms the geofences to match. When turning
    /// on, notification permission is requested here — the moment the person can see why.
    func setAlertsEnabled(_ spot: Spot, _ enabled: Bool) {
        spot.alertsEnabled = enabled
        save()
        // Not under UI testing: the system permission alert would sit over every assertion
        // that follows, and the simulator has nowhere to walk anyway.
        if enabled, !AppSettings.isUITesting {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        rearmGeofences()
    }

    func update(_ spot: Spot, glyph: String?) {
        spot.glyph = glyph
        save()
        refreshSnapshot()
    }

    func assign(_ spot: Spot, to trip: Trip?) {
        spot.trip = trip
        save()
        refreshSnapshot()
    }

    /// Only one spot is pinned at a time — the widgets lead with it, and "several favourites"
    /// is not a thing a small widget can express.
    func setPinned(_ spot: Spot?) {
        for existing in allSpots() where existing.isPinned {
            existing.isPinned = false
        }
        spot?.isPinned = true
        save()
        refreshSnapshot()
    }

    func delete(_ spot: Spot) {
        SharedSnapshotStore.removeThumbnail(named: spot.thumbnailFilename)
        let identifier = spot.id.uuidString
        let hadAlert = spot.alertsEnabled
        context.delete(spot)
        save()
        refreshSnapshot()
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier])
        // A deleted spot must not keep its geofence — that would be a notification for a place
        // that no longer exists in the app.
        if hadAlert { rearmGeofences() }
    }

    func delete(_ trip: Trip) {
        context.delete(trip)
        save()
        refreshSnapshot()
    }

    // MARK: - Reading

    func allSpots() -> [Spot] {
        let descriptor = FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func spot(id: UUID) -> Spot? {
        allSpots().first { $0.id == id }
    }

    func allTrips() -> [Trip] {
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Geofences

    /// Recomputes which spots deserve a monitored region and hands the set to `GeofenceService`.
    /// Called on scene-activation and after any toggle change; `GeofencePlan` owns the rule, so
    /// this is only plumbing.
    func rearmGeofences() {
        let regions = GeofencePlan.regions(
            from: allSpots().map(\.geofenceCandidate),
            origin: LocationService.shared.coordinate
        )
        GeofenceService.shared.rearm(regions)
    }

    // MARK: - Place names

    /// Fills in area names for spots that never got one — a capture with no network, or a spot
    /// that predates geocoding. A few per pass: CLGeocoder allows roughly a request a second and
    /// `GeocodeService` serialises, so a large backlog drains across launches rather than in one.
    func resolveMissingPlaceNames(limit: Int = 5) {
        let missing = allSpots().filter { ($0.placeName ?? "").isEmpty }
        for spot in missing.prefix(limit) {
            resolvePlaceName(for: spot)
        }
    }

    /// Re-resolves one spot's area name. Detail screens call this on appear, so names written by
    /// the old rule — which preferred the nearest business — improve as spots are looked at,
    /// without a bulk re-geocode that would hammer the rate limit.
    func refreshPlaceName(for spot: Spot) {
        resolvePlaceName(for: spot)
    }

    // MARK: - Widget snapshot

    /// Takes over a pin change made from outside the app.
    ///
    /// The widget's "pin nearest" and "next spot" buttons run in the widget's process, which has
    /// no access to the SwiftData store, so they move the pin in the shared snapshot instead. This
    /// pulls that back into the model — and it must run *before* `refreshSnapshot`, which would
    /// otherwise overwrite the snapshot with the model's stale idea of what is pinned.
    func adoptPinFromSnapshot() {
        guard let snapshot = SharedSnapshotStore.load() else { return }
        let spots = allSpots()
        let currentlyPinned = spots.first(where: \.isPinned)?.id
        guard snapshot.pinnedSpotID != currentlyPinned else { return }

        // A pin pointing at a spot that no longer exists is dropped rather than honoured.
        let target = snapshot.pinnedSpotID.flatMap { id in spots.first { $0.id == id } }
        for spot in spots where spot.isPinned {
            spot.isPinned = false
        }
        target?.isPinned = true
        save()
    }

    /// Rewrites the file the widgets read. Cheap enough to call after any mutation.
    func refreshSnapshot() {
        let spots = allSpots()

        // Backfill thumbnails for anything that arrived from another device via iCloud, where
        // the photo synced but the App Group file did not exist locally.
        for spot in spots where spot.thumbnailFilename == nil {
            guard let photoData = spot.photoData,
                  let thumbnail = PhotoService.thumbnailData(from: photoData)
            else { continue }
            spot.thumbnailFilename = SharedSnapshotStore.writeThumbnail(thumbnail, for: spot.id)
        }
        if context.hasChanges { save() }

        let shared = spots.map(\.sharedForm)
        let pinnedID = spots.first(where: \.isPinned)?.id
        let themeID = settings.themeID
        let units = settings.unitPreference

        let snapshot = SharedSnapshotStore.mutate(defaultThemeID: themeID) { snapshot in
            snapshot.spots = shared
            snapshot.pinnedSpotID = pinnedID
            snapshot.themeID = themeID
            snapshot.unitPreference = units
        }

        SharedSnapshotStore.pruneThumbnails(keeping: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Spotlight

    private func donateToSpotlight(_ spot: Spot) {
        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        attributes.title = spot.displayName
        attributes.contentDescription = spot.subtitle
        attributes.latitude = NSNumber(value: spot.latitude)
        attributes.longitude = NSNumber(value: spot.longitude)
        attributes.namedLocation = spot.placeName
        attributes.contentCreationDate = spot.capturedAt
        attributes.keywords = ["spot", "compass", spot.trip?.name].compactMap { $0 }
        if let thumbnail = spot.thumbnailFilename,
           let url = AppGroup.thumbnailsURL?.appendingPathComponent(thumbnail) {
            attributes.thumbnailURL = url
        }

        let item = CSSearchableItem(
            uniqueIdentifier: spot.id.uuidString,
            domainIdentifier: "com.tradewind.spots",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    // MARK: - Private

    private func save() {
        do {
            try context.save()
        } catch {
            // A failed save is worth knowing about in the console, but not worth taking the
            // app down for: the change is still in memory and the next save may succeed.
            print("[Tradewind] save failed: \(error)")
        }
    }

    /// Fills in a human-readable place name after the fact, so capture never waits on the
    /// network.
    private func resolvePlaceName(for spot: Spot) {
        let coordinate = spot.coordinate
        let id = spot.id
        Task { @MainActor [weak self] in
            guard let name = await GeocodeService.shared.placeName(for: coordinate) else { return }
            guard let self, let spot = self.spot(id: id) else { return }
            spot.placeName = name
            if spot.name.trimmingCharacters(in: .whitespaces).isEmpty {
                spot.name = name
            }
            self.save()
            self.refreshSnapshot()
            self.donateToSpotlight(spot)
        }
    }
}

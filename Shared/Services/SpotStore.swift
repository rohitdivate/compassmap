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
        id: UUID = UUID(),
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
        placeName: String? = nil,
        source: String? = nil,
        refreshingSnapshot: Bool = true,
        trip: Trip? = nil
    ) -> Spot {
        let spot = Spot(
            id: id,
            name: name,
            placeName: placeName,
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
            sourceRaw: source,
            trip: trip
        )

        if let thumbnailData {
            spot.thumbnailFilename = SharedSnapshotStore.writeThumbnail(thumbnailData, for: spot.id)
        }

        context.insert(spot)
        save()

        // Name it properly in the background if the person did not. A restore arrives with its
        // name already resolved, and re-geocoding forty imported spots would burn the rate limit
        // on answers we already have.
        if placeName == nil {
            resolvePlaceName(for: spot)
        }
        // A batch caller (the photo ingest) refreshes once at the end instead of once per spot.
        if refreshingSnapshot {
            scheduleSnapshotRefresh()
        }
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
        scheduleSnapshotRefresh()
        donateToSpotlight(spot)
    }

    func update(_ spot: Spot, note: String?) {
        spot.note = note
        save()
    }

    func update(_ spot: Spot, kind: PlaceKind) {
        spot.placeKind = kind
        save()
        scheduleSnapshotRefresh()
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
        scheduleSnapshotRefresh()
    }

    func assign(_ spot: Spot, to trip: Trip?) {
        spot.trip = trip
        save()
        scheduleSnapshotRefresh()
    }

    /// Only one spot is pinned at a time — the widgets lead with it, and "several favourites"
    /// is not a thing a small widget can express.
    func setPinned(_ spot: Spot?) {
        for existing in allSpots() where existing.isPinned {
            existing.isPinned = false
        }
        spot?.isPinned = true
        save()
        scheduleSnapshotRefresh()
    }

    /// Soft delete: the spot leaves every list and sits in Recently Deleted for thirty days.
    /// No confirmation dialog needed — the undo toast and the trash are the safety net, which is
    /// why this must faithfully cancel everything that could still fire for the spot.
    func delete(_ spot: Spot) {
        let name = spot.displayName
        spot.deletedAt = Date()
        if spot.isPinned { spot.isPinned = false }
        save()
        scheduleSnapshotRefresh()
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [spot.id.uuidString])
        ReminderService.shared.cancel(spotID: spot.id)
        if spot.alertsEnabled { rearmGeofences() }
        // Announced from here so every deletion path gets the toast, not just the one that
        // remembered to show it.
        UndoCenter.shared.show(spotID: spot.id, name: name)
    }

    /// Brings a deleted spot back, exactly as it was — except the widget thumbnail, which the
    /// snapshot pruner may have removed; clearing the stale filename lets
    /// `migrateThumbnailsIfNeeded` regenerate it from the stored photo on the next activation.
    func restore(_ spot: Spot) {
        spot.deletedAt = nil
        if let filename = spot.thumbnailFilename,
           let url = AppGroup.thumbnailsURL?.appendingPathComponent(filename),
           !FileManager.default.fileExists(atPath: url.path) {
            spot.thumbnailFilename = nil
        }
        save()
        scheduleSnapshotRefresh()
        donateToSpotlight(spot)
        if spot.alertsEnabled { rearmGeofences() }
        if let fireDate = spot.reminderAt, fireDate > Date() {
            ReminderService.shared.schedule(spotID: spot.id, spotName: spot.displayName, at: fireDate)
        }
    }

    /// The hard delete: photo, thumbnail and record, gone for good. Reached only from Recently
    /// Deleted (behind its confirmation) and from the expiry sweep.
    func purge(_ spot: Spot) {
        SharedSnapshotStore.removeThumbnail(named: spot.thumbnailFilename)
        let identifier = spot.id.uuidString
        context.delete(spot)
        save()
        scheduleSnapshotRefresh()
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier])
    }

    /// Purges whatever has sat in the trash past its thirty days. Called on scene-activation;
    /// cheap when the trash is empty.
    func purgeExpired(now: Date = Date()) {
        for spot in deletedSpots() where TrashPolicy.isExpired(deletedAt: spot.deletedAt ?? now, now: now) {
            purge(spot)
        }
    }

    func delete(_ trip: Trip) {
        context.delete(trip)
        save()
        scheduleSnapshotRefresh()
    }

    // MARK: - Reading

    /// Living spots only — the trash is invisible to every caller except the trash screen.
    func allSpots() -> [Spot] {
        fetchEverySpot().filter { $0.deletedAt == nil }
    }

    /// The trash, newest deletion first.
    func deletedSpots() -> [Spot] {
        fetchEverySpot()
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private func fetchEverySpot() -> [Spot] {
        let descriptor = FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func spot(id: UUID) -> Spot? {
        allSpots().first { $0.id == id }
    }

    /// Looks in the trash too — the undo toast restores by id after the spot left every list.
    func anySpot(id: UUID) -> Spot? {
        fetchEverySpot().first { $0.id == id }
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

    /// Spots whose names were re-checked since launch. Opening the same detail sheet five
    /// times used to mean five geocodes, five saves and five snapshot rewrites; once per
    /// launch preserves the quiet-upgrade behaviour at none of the cost.
    private static var refreshedPlaceNamesThisLaunch = Set<UUID>()

    /// Re-resolves one spot's area name. Detail screens call this on appear, so names written by
    /// the old rule — which preferred the nearest business — improve as spots are looked at,
    /// without a bulk re-geocode that would hammer the rate limit.
    func refreshPlaceName(for spot: Spot) {
        guard !Self.refreshedPlaceNamesThisLaunch.contains(spot.id) else { return }
        Self.refreshedPlaceNamesThisLaunch.insert(spot.id)
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

    /// Debounce state for the coalesced snapshot refresh. Static because `SpotStore` itself is
    /// a transient wrapper — views construct one per access — while the pending write is a
    /// property of the app. Main-thread only, like the store.
    private static var snapshotPendingSince: Date?
    private static var snapshotTask: Task<Void, Never>?

    /// The default after any mutation: rewrite the widget snapshot *soon*, once, no matter how
    /// many mutations land in the same gesture. A restore of forty spots used to mean forty
    /// full rewrites; now it means one, a quarter-second after the last.
    func scheduleSnapshotRefresh(now: Date = Date()) {
        let fireAt = SnapshotRefreshPolicy.fireDate(
            pendingSince: Self.snapshotPendingSince,
            requestedAt: now
        )
        if Self.snapshotPendingSince == nil { Self.snapshotPendingSince = now }
        Self.snapshotTask?.cancel()
        let context = context
        Self.snapshotTask = Task { @MainActor in
            let delay = fireAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            Self.snapshotPendingSince = nil
            Self.snapshotTask = nil
            SpotStore(context: context).refreshSnapshot()
        }
    }

    /// Rewrites the file the widgets read, now. The model read happens here on the main
    /// thread — that part is cheap — and the encode, file write, prune and widget reload
    /// happen off it. Prefer `scheduleSnapshotRefresh()` after mutations.
    func refreshSnapshot() {
        let spots = allSpots()
        let shared = spots.map(\.sharedForm)
        let pinnedID = spots.first(where: \.isPinned)?.id
        let themeID = settings.themeID
        let units = settings.unitPreference

        SharedSnapshotStore.mutateAsync(defaultThemeID: themeID) { snapshot in
            snapshot.spots = shared
            snapshot.pinnedSpotID = pinnedID
            snapshot.themeID = themeID
            snapshot.unitPreference = units
        } completion: { snapshot in
            SharedSnapshotStore.pruneThumbnails(keeping: snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Backfills App Group thumbnails for spots that arrived from another device via iCloud,
    /// where the photo synced but the local thumbnail file never existed. This used to run
    /// inside every snapshot rewrite, faulting every photo blob on the main thread; it is a
    /// migration, so it now runs once per activation, with the image work off-main.
    func migrateThumbnailsIfNeeded() async {
        let missing = allSpots().filter { $0.thumbnailFilename == nil }
        guard !missing.isEmpty else { return }
        let pairs: [(UUID, Data)] = missing.compactMap { spot in
            spot.photoData.map { (spot.id, $0) }
        }
        guard !pairs.isEmpty else { return }
        let thumbnails = await Task.detached(priority: .utility) {
            pairs.compactMap { id, data in
                PhotoService.thumbnailData(from: data).map { (id, $0) }
            }
        }.value
        guard !thumbnails.isEmpty else { return }
        for (id, thumbnail) in thumbnails {
            guard let spot = anySpot(id: id) else { continue }
            spot.thumbnailFilename = SharedSnapshotStore.writeThumbnail(thumbnail, for: id)
        }
        save()
        scheduleSnapshotRefresh()
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
            // The answer matching what is already stored is the common case for a re-check;
            // writing it anyway would ripple a save, a snapshot rewrite and a Spotlight donate
            // out of every detail-sheet open.
            let needsName = spot.name.trimmingCharacters(in: .whitespaces).isEmpty
            guard spot.placeName != name || needsName else { return }
            spot.placeName = name
            if needsName {
                spot.name = name
            }
            self.save()
            self.scheduleSnapshotRefresh()
            self.donateToSpotlight(spot)
        }
    }
}

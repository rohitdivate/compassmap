import AppleArchive
import CoreSpotlight
import Foundation
import System

/// Writes and reads the backup file — the only durability a free Apple account allows.
///
/// Nothing in the sandbox survives deleting the app, so a spot's real permanence is a file the
/// person exports and keeps (iCloud Drive via the Files picker needs no entitlement). The format
/// is an Apple Archive (`.aar` under our own extension): a compressed directory of `manifest.json`,
/// `spots.json`, `trips.json` and `photos/` — chosen because AppleArchive is the one archive
/// format iOS can both write *and* read natively, with no third-party dependency to audit.
/// `BackupArchive` (pure, tested) owns the record shapes and the merge rule; this class only
/// moves bytes.
final class BackupService {

    static let shared = BackupService()
    private init() {}

    static let fileExtension = "tradewindbackup"

    enum Failure: Error, LocalizedError {
        case notAnArchive
        case missingManifest
        case newerFormat(Int)

        var errorDescription: String? {
            switch self {
            case .notAnArchive:
                return "This file is not a Tradewind backup."
            case .missingManifest:
                return "The backup is missing its manifest — it may be truncated."
            case .newerFormat(let version):
                return "This backup was made by a newer Tradewind (format \(version)). Update the app to restore it."
            }
        }
    }

    // MARK: - Export

    /// Writes a complete backup to a temporary file and returns its URL, ready for the share
    /// sheet or the Files exporter. Includes the trash: a backup that silently dropped deleted
    /// spots would betray the thirty-day promise.
    func exportArchive(spots: [Spot], trips: [Trip]) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let photosDir = staging.appendingPathComponent(BackupArchive.photosDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let records = spots.map(\.backupRecord)
        let tripRecords = trips.map {
            BackupArchive.TripRecord(
                id: $0.id, name: $0.name, subtitle: $0.subtitle,
                themeID: $0.themeID, createdAt: $0.createdAt
            )
        }
        let manifest = BackupArchive.Manifest(
            exportedAt: Date(),
            spotCount: records.count,
            tripCount: tripRecords.count,
            appVersion: BuildInfo.current.summary()
        )

        try BackupArchive.encode(manifest)
            .write(to: staging.appendingPathComponent(BackupArchive.manifestFilename))
        try BackupArchive.encode(records)
            .write(to: staging.appendingPathComponent(BackupArchive.spotsFilename))
        try BackupArchive.encode(tripRecords)
            .write(to: staging.appendingPathComponent(BackupArchive.tripsFilename))

        for spot in spots {
            guard let data = spot.photoData, !data.isEmpty else { continue }
            try data.write(to: photosDir.appendingPathComponent(BackupArchive.photoFilename(spotID: spot.id)))
        }

        let name = "Tradewind Backup \(Self.filenameDateFormatter.string(from: Date()))"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(Self.fileExtension)
        try? FileManager.default.removeItem(at: destination)
        try compress(directory: staging, to: destination)
        return destination
    }

    // MARK: - Import

    struct RestorePlan {
        let manifest: BackupArchive.Manifest
        let spots: [BackupArchive.SpotRecord]
        let trips: [BackupArchive.TripRecord]
        /// Extracted archive directory; photos are read from here during commit.
        let contents: URL
    }

    /// Opens a backup file and describes what restoring it would do — nothing is written yet,
    /// so the confirmation sheet can tell the truth first.
    func read(archiveAt url: URL) throws -> RestorePlan {
        let contents = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        try extract(archiveAt: url, to: contents)

        let manifestURL = contents.appendingPathComponent(BackupArchive.manifestFilename)
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw Failure.missingManifest
        }
        let manifest = try BackupArchive.decode(BackupArchive.Manifest.self, from: manifestData)
        guard manifest.formatVersion <= BackupArchive.formatVersion else {
            throw Failure.newerFormat(manifest.formatVersion)
        }

        let spotsData = try Data(contentsOf: contents.appendingPathComponent(BackupArchive.spotsFilename))
        let spots = try BackupArchive.decode([BackupArchive.SpotRecord].self, from: spotsData)
        let tripsData = (try? Data(contentsOf: contents.appendingPathComponent(BackupArchive.tripsFilename))) ?? Data("[]".utf8)
        let trips = try BackupArchive.decode([BackupArchive.TripRecord].self, from: tripsData)

        return RestorePlan(manifest: manifest, spots: spots, trips: trips, contents: contents)
    }

    /// Merges a read backup into the store, by UUID, per `BackupArchive.decision`. Returns how
    /// many spots were added. Restoring the same file twice adds nothing the second time.
    @discardableResult
    func commit(_ plan: RestorePlan, store: SpotStore) -> Int {
        var tripsByID: [UUID: Trip] = [:]
        for trip in store.allTrips() { tripsByID[trip.id] = trip }
        for record in plan.trips where tripsByID[record.id] == nil {
            let trip = store.createTrip(name: record.name, subtitle: record.subtitle, themeID: record.themeID)
            trip.id = record.id
            trip.createdAt = record.createdAt
            tripsByID[record.id] = trip
        }

        var existingCaptures: [UUID: Date] = [:]
        for spot in store.allSpots() { existingCaptures[spot.id] = spot.capturedAt }
        for spot in store.deletedSpots() { existingCaptures[spot.id] = spot.capturedAt }

        var added = 0
        for record in plan.spots {
            guard BackupArchive.decision(
                incoming: record,
                existingCapturedAt: existingCaptures[record.id]
            ) == .insert else { continue }

            var photoData: Data?
            if let filename = record.photoFilename {
                let url = plan.contents
                    .appendingPathComponent(BackupArchive.photosDirectory)
                    .appendingPathComponent(filename)
                photoData = try? Data(contentsOf: url)
            }

            let spot = store.createSpot(
                id: record.id,
                name: record.name,
                coordinate: Coordinate(latitude: record.latitude, longitude: record.longitude),
                altitude: record.altitude,
                horizontalAccuracy: record.horizontalAccuracy,
                capturedAt: record.capturedAt,
                headingAtCapture: record.headingAtCapture,
                photoData: photoData,
                thumbnailData: photoData.flatMap(PhotoService.thumbnailData(from:)),
                glyph: record.glyph,
                note: record.note,
                kind: PlaceKind.from(rawValue: record.kindRaw),
                placeName: record.placeName,
                trip: record.tripID.flatMap { tripsByID[$0] }
            )
            spot.alertsEnabled = record.alertsEnabled
            spot.deletedAt = record.deletedAt
            spot.reminderAt = record.reminderAt
            spot.sourceRaw = record.sourceRaw
            // A spot restored into the trash must not be findable from the Home Screen.
            if record.deletedAt != nil {
                CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [record.id.uuidString])
            }
            added += 1
        }

        store.refreshSnapshot()
        try? FileManager.default.removeItem(at: plan.contents)
        return added
    }

    // MARK: - Automatic safety net

    /// A rolling snapshot in Documents, at most weekly. It dies with an uninstall — the Settings
    /// copy says so — but it survives "Offload App" and rides along in device backups, which is
    /// strictly better than nothing and costs one file.
    func autoSnapshotIfDue(store: SpotStore, now: Date = Date()) {
        let settings = AppSettings.shared
        if let last = settings.lastAutoSnapshotAt, now.timeIntervalSince(last) < 7 * 24 * 3_600 {
            return
        }
        let spots = store.allSpots() + store.deletedSpots()
        guard !spots.isEmpty else { return }
        do {
            let archive = try exportArchive(spots: spots, trips: store.allTrips())
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let destination = documents.appendingPathComponent("Automatic Backup.\(Self.fileExtension)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: archive, to: destination)
            settings.lastAutoSnapshotAt = now
        } catch {
            print("[Tradewind] auto snapshot failed: \(error)")
        }
    }

    // MARK: - Archive plumbing

    private func compress(directory: URL, to destination: URL) throws {
        guard let writeStream = ArchiveByteStream.fileStream(
            path: FilePath(destination.path),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw Failure.notAnArchive }
        defer { try? writeStream.close() }

        guard let compressStream = ArchiveByteStream.compressionStream(
            using: .lzfse,
            writingTo: writeStream
        ) else { throw Failure.notAnArchive }
        defer { try? compressStream.close() }

        guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else {
            throw Failure.notAnArchive
        }
        defer { try? encodeStream.close() }

        guard let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM") else {
            throw Failure.notAnArchive
        }
        try encodeStream.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keySet)
    }

    private func extract(archiveAt url: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let readStream = ArchiveByteStream.fileStream(
            path: FilePath(url.path),
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw Failure.notAnArchive }
        defer { try? readStream.close() }

        guard let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readStream) else {
            throw Failure.notAnArchive
        }
        defer { try? decompressStream.close() }

        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else {
            throw Failure.notAnArchive
        }
        defer { try? decodeStream.close() }

        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: FilePath(directory.path),
            flags: [.ignoreOperationNotPermitted]
        ) else { throw Failure.notAnArchive }
        defer { try? extractStream.close() }

        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

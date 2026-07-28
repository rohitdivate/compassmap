import Foundation

/// The backup file's contents, as data — what goes in, what comes out, and how a restore merges.
///
/// On a free Apple account nothing survives deleting the app: no iCloud, no App Group, and the
/// sandbox dies with the install. The only durability that is real is a file the person can put
/// in iCloud Drive themselves — so this format is the app's actual promise of permanence, and it
/// is versioned, explicit, and tested like one.
///
/// This layer is pure: structures, JSON coding, and the merge decision. Reading models and
/// writing archives to disk live in the app target.
enum BackupArchive {

    /// Bumped when the format changes shape. Readers accept anything ≤ their own version.
    static let formatVersion = 1

    /// Filenames inside the archive directory.
    static let manifestFilename = "manifest.json"
    static let spotsFilename = "spots.json"
    static let tripsFilename = "trips.json"
    static let photosDirectory = "photos"

    struct Manifest: Codable, Equatable {
        var formatVersion: Int = BackupArchive.formatVersion
        var exportedAt: Date
        var spotCount: Int
        var tripCount: Int
        var appVersion: String
    }

    /// Every field a spot owns, including the soft-delete stamp — a backup that silently dropped
    /// the trash would resurrect deleted spots on restore.
    struct SpotRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var placeName: String?
        var latitude: Double
        var longitude: Double
        var altitude: Double?
        var horizontalAccuracy: Double?
        var capturedAt: Date
        var headingAtCapture: Double?
        var note: String?
        var glyph: String?
        var kindRaw: String?
        var isPinned: Bool
        var alertsEnabled: Bool
        var deletedAt: Date?
        var reminderAt: Date?
        var sourceRaw: String?
        var tripID: UUID?
        /// Filename under `photos/` when the spot has a photo, nil otherwise.
        var photoFilename: String?
    }

    struct TripRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var subtitle: String?
        var themeID: String?
        var createdAt: Date
    }

    /// The photo file for a spot inside the archive.
    static func photoFilename(spotID: UUID) -> String {
        "\(spotID.uuidString).jpg"
    }

    // MARK: - Coding

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    // MARK: - Merge

    /// What a restore should do with one incoming spot, given what already exists.
    ///
    /// Merging is by UUID so restoring the same file twice changes nothing, and restoring an old
    /// backup never duplicates spots that still exist. Newest capture wins a conflict — a spot
    /// edited since the backup keeps its edits, because `capturedAt` never changes after creation
    /// and equal stamps mean "same spot, keep what's on the phone".
    enum MergeDecision: Equatable {
        case insert
        case skip
    }

    static func decision(incoming: SpotRecord, existingCapturedAt: Date?) -> MergeDecision {
        guard existingCapturedAt != nil else { return .insert }
        return .skip
    }

    /// A restore is described before it happens, so the confirmation can say what it will do.
    static func restoreSummary(incoming: Int, skipped: Int) -> String {
        let added = incoming - skipped
        switch (added, skipped) {
        case (0, _): return "Everything in this backup is already on this phone."
        case (_, 0): return "Adds \(added) \(added == 1 ? "spot" : "spots")."
        default: return "Adds \(added) \(added == 1 ? "spot" : "spots"); \(skipped) already here."
        }
    }
}

import Foundation

/// Reads and writes the snapshot the widgets consume.
///
/// Writes are atomic and serialised: the app can rewrite the snapshot from a location
/// callback while WidgetKit is mid-read, and a half-written file would show up as an empty
/// widget. Reads never throw — a corrupt or absent file simply reads as `nil`, and the app
/// rewrites it on next launch.
enum SharedSnapshotStore {

    private static let queue = DispatchQueue(label: "com.tradewind.snapshot", qos: .utility)

    /// Used when the App Group container is unavailable (unsigned builds, previews, tests).
    private static let fallbackDefaultsKey = "com.tradewind.snapshot.fallback"

    // MARK: - Pure coding

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ snapshot: SharedSnapshot) throws -> Data {
        try encoder().encode(snapshot)
    }

    static func decode(_ data: Data) throws -> SharedSnapshot {
        try decoder().decode(SharedSnapshot.self, from: data)
    }

    // MARK: - Persistence

    static func load() -> SharedSnapshot? {
        queue.sync { loadUnsynchronized() }
    }

    static func loadOrEmpty(defaultThemeID: String) -> SharedSnapshot {
        load() ?? .empty(themeID: defaultThemeID)
    }

    static func save(_ snapshot: SharedSnapshot) {
        queue.sync { saveUnsynchronized(snapshot) }
    }

    /// Read-modify-write in one atomic step, so two callers cannot clobber each other.
    @discardableResult
    static func mutate(
        defaultThemeID: String,
        _ body: (inout SharedSnapshot) -> Void
    ) -> SharedSnapshot {
        queue.sync {
            var snapshot = loadUnsynchronized() ?? .empty(themeID: defaultThemeID)
            body(&snapshot)
            snapshot.version = SharedSnapshot.currentVersion
            snapshot.updatedAt = Date()
            saveUnsynchronized(snapshot)
            return snapshot
        }
    }

    // MARK: - Thumbnails

    /// Writes a widget-sized JPEG into the shared container. Returns the filename to store
    /// on the spot, or nil if there is nowhere to write it.
    @discardableResult
    static func writeThumbnail(_ data: Data, for id: UUID) -> String? {
        guard let directory = AppGroup.thumbnailsURL else { return nil }
        let filename = "\(id.uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func removeThumbnail(named filename: String?) {
        guard let filename, let directory = AppGroup.thumbnailsURL else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    /// Deletes thumbnails no longer referenced by any spot. Cheap, and stops the shared
    /// container growing forever as spots are deleted.
    static func pruneThumbnails(keeping snapshot: SharedSnapshot) {
        guard let directory = AppGroup.thumbnailsURL else { return }
        let keep = Set(snapshot.spots.compactMap(\.thumbnailFilename))
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in contents where !keep.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: - Private

    private static func loadUnsynchronized() -> SharedSnapshot? {
        let data: Data?
        if let url = AppGroup.snapshotURL, let fileData = try? Data(contentsOf: url) {
            data = fileData
        } else {
            data = AppGroup.defaults.data(forKey: fallbackDefaultsKey)
        }
        guard let data else { return nil }
        guard let snapshot = try? decode(data) else { return nil }
        guard snapshot.version == SharedSnapshot.currentVersion else { return nil }
        return snapshot
    }

    private static func saveUnsynchronized(_ snapshot: SharedSnapshot) {
        guard let data = try? encode(snapshot) else { return }
        if let url = AppGroup.snapshotURL {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                // Fall through to defaults; better a stale widget than a lost write.
            }
        }
        AppGroup.defaults.set(data, forKey: fallbackDefaultsKey)
    }
}

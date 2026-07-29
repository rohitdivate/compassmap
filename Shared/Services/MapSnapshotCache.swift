import MapKit
import UIKit

/// Renders and caches the little context maps.
///
/// A live `MKMapView` was the most expensive single thing the detail sheet did — a whole map
/// engine booted for 600 m of non-interactive context. A rendered image is visually identical
/// here, and a saved place does not move, so once rendered it is a cache hit forever:
/// memory first, then disk, then one `MKMapSnapshotter` pass.
@MainActor
final class MapSnapshotCache {

    static let shared = MapSnapshotCache()

    private let memory = NSCache<NSString, UIImage>()
    /// One render per key at a time; a second request for an in-flight key awaits the first.
    private var inFlight: [MapSnapshotKey: Task<UIImage?, Never>] = [:]

    private var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = caches.appendingPathComponent("MapSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Instant answer or nil — for first paint, no async hop.
    func cachedImage(for key: MapSnapshotKey) -> UIImage? {
        if let hit = memory.object(forKey: key.filename as NSString) { return hit }
        guard let url = directory?.appendingPathComponent(key.filename),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data, scale: UIScreen.main.scale)
        else { return nil }
        memory.setObject(image, forKey: key.filename as NSString)
        return image
    }

    func image(for key: MapSnapshotKey, isDark: Bool) async -> UIImage? {
        if let hit = cachedImage(for: key) { return hit }
        if let running = inFlight[key] { return await running.value }

        let task = Task<UIImage?, Never> { [weak self] in
            let image = await Self.render(key: key, isDark: isDark)
            if let image {
                self?.store(image, for: key)
            }
            self?.inFlight[key] = nil
            return image
        }
        inFlight[key] = task
        return await task.value
    }

    // MARK: - Private

    private func store(_ image: UIImage, for key: MapSnapshotKey) {
        memory.setObject(image, forKey: key.filename as NSString)
        guard let url = directory?.appendingPathComponent(key.filename),
              let data = image.jpegData(compressionQuality: 0.85)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func render(key: MapSnapshotKey, isDark: Bool) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: Double(key.latitudeE4) / 10_000,
                longitude: Double(key.longitudeE4) / 10_000
            ),
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
        options.size = CGSize(
            width: CGFloat(key.pixelWidth) / UIScreen.main.scale,
            height: CGFloat(key.pixelHeight) / UIScreen.main.scale
        )
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(traitsFrom: [
            options.traitCollection,
            UITraitCollection(userInterfaceStyle: isDark ? .dark : .light),
        ])

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }
}

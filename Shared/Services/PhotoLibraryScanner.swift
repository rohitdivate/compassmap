import Foundation
import Photos
import UIKit

/// Sweeps the photo library's metadata and hands back geotagged points for clustering.
///
/// The sweep never decodes a pixel: `PHAsset` is a lightweight metadata record, and reading
/// `location` on tens of thousands of them is seconds, not minutes. PhotoKit cannot filter by
/// location server-side (the predicate key list does not include it), so the filter happens in
/// this loop. Images are fetched only when a card needs a thumbnail, and at full size only when
/// a suggestion is actually saved.
final class PhotoLibraryScanner {

    static let shared = PhotoLibraryScanner()
    private init() {}

    private let imageManager = PHCachingImageManager()

    /// All geotagged photos' metadata. Runs off the main thread; progress is photo count seen.
    func scan(progress: ((Int) -> Void)? = nil) async -> [PhotoClusters.PhotoPoint] {
        if AppSettings.isUITesting {
            return Self.cannedPoints
        }
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: options)

            var points: [PhotoClusters.PhotoPoint] = []
            points.reserveCapacity(min(assets.count, 4_096))
            assets.enumerateObjects { asset, index, _ in
                autoreleasepool {
                    guard let location = asset.location, let date = asset.creationDate else { return }
                    let coordinate = location.coordinate
                    guard abs(coordinate.latitude) <= 90, abs(coordinate.longitude) <= 180,
                          coordinate.latitude != 0 || coordinate.longitude != 0
                    else { return }
                    points.append(PhotoClusters.PhotoPoint(
                        id: asset.localIdentifier,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        capturedAt: date,
                        isFavorite: asset.isFavorite
                    ))
                    if index % 500 == 0 { progress?(index) }
                }
            }
            return points
        }.value
    }

    /// A small thumbnail for a suggestion card. Never pulls originals from iCloud.
    func thumbnail(for assetID: String, side: CGFloat = 240) async -> UIImage? {
        guard !AppSettings.isUITesting else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Opportunistic delivery can call back twice; resume once, preferring any image.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !resumed, image != nil || !degraded {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// The full-quality image for a suggestion being saved as a spot. Network allowed: this is
    /// the one moment the original is worth waiting for.
    func fullImage(for assetID: String) async -> Data? {
        guard !AppSettings.isUITesting else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Two canned London clusters for the UI tests and screenshots: a cafe visited twice, and a
    /// one-visit lookout — enough to exercise ranking, saving, and the cards.
    static var cannedPoints: [PhotoClusters.PhotoPoint] {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        var points: [PhotoClusters.PhotoPoint] = []
        for visit in 0..<2 {
            for shot in 0..<3 {
                points.append(PhotoClusters.PhotoPoint(
                    id: "cafe-\(visit)-\(shot)",
                    latitude: 51.5065 + Double(shot) * 0.0001,
                    longitude: -0.0920,
                    capturedAt: base.addingTimeInterval(Double(visit) * 86_400 + Double(shot) * 300)
                ))
            }
        }
        for shot in 0..<2 {
            points.append(PhotoClusters.PhotoPoint(
                id: "lookout-\(shot)",
                latitude: 51.5387,
                longitude: -0.1607 + Double(shot) * 0.0001,
                capturedAt: base.addingTimeInterval(200_000 + Double(shot) * 300)
            ))
        }
        return points
    }
}

import CoreLocation
import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// Image handling: pulling the location out of a photo, and making the two sizes Tradewind
/// stores.
///
/// Two sizes, on purpose. The full-size JPEG lives in the SwiftData store under external
/// storage and syncs through CloudKit. A small thumbnail is written into the App Group so
/// widgets can draw a photo without touching the database or the network.
enum PhotoService {

    /// Longest edge of the stored photo. Full camera resolution is wasted here — this is
    /// shown as a backdrop and a card, never printed — and it makes iCloud sync dramatically
    /// slower.
    static let storedMaxDimension: CGFloat = 2_048
    /// Longest edge of the widget thumbnail.
    static let thumbnailMaxDimension: CGFloat = 480

    // MARK: - Metadata

    /// Reads the GPS block from image data, if the photo carries one.
    static func location(fromImageData data: Data) -> PhotoLocation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        else { return nil }
        return GPSMetadata.parse(gpsDictionary: gps)
    }

    /// When the photo was taken, from EXIF, falling back to nil rather than to "now".
    static func captureDate(fromImageData data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let original = exif["DateTimeOriginal"] as? String
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: original)
    }

    /// Falls back to the Photos database when the picker handed us data with the GPS block
    /// stripped — which happens under limited library access.
    static func location(forAssetIdentifier identifier: String) async -> PhotoLocation? {
        let status = await requestLibraryReadAccess()
        guard status == .authorized || status == .limited else { return nil }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject, let location = asset.location else { return nil }

        return PhotoLocation(
            coordinate: Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            timestamp: asset.creationDate
        )
    }

    static func requestLibraryReadAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Resizing

    /// Downsamples with ImageIO, which decodes at the target size instead of decoding the
    /// full image and throwing most of it away.
    static func resizedJPEG(
        from data: Data,
        maxDimension: CGFloat,
        compression: CGFloat = 0.82
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: NSNumber(value: Double(maxDimension)),
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compression)
    }

    static func storedPhotoData(from data: Data) -> Data? {
        resizedJPEG(from: data, maxDimension: storedMaxDimension, compression: 0.86) ?? data
    }

    static func thumbnailData(from data: Data) -> Data? {
        resizedJPEG(from: data, maxDimension: thumbnailMaxDimension, compression: 0.78)
    }

    /// The whole capture pipeline in one call: shrink, make a thumbnail, and recover a
    /// location from the file if the caller has not supplied one.
    struct PreparedPhoto {
        var photoData: Data
        var thumbnailData: Data?
        var embeddedLocation: PhotoLocation?
        var captureDate: Date?
    }

    static func prepare(imageData data: Data) -> PreparedPhoto {
        PreparedPhoto(
            photoData: storedPhotoData(from: data) ?? data,
            thumbnailData: thumbnailData(from: data),
            embeddedLocation: location(fromImageData: data),
            captureDate: captureDate(fromImageData: data)
        )
    }

    // MARK: - Saving out

    /// Writes a copy to the user's library, used by the in-app camera so photos are not
    /// trapped inside Tradewind.
    static func saveToLibrary(imageData: Data, location: CLLocation?) async -> Bool {
        let status = await requestLibraryReadAccess()
        guard status == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
                if let location { request.location = location }
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

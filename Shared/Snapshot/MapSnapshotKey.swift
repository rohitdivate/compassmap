import Foundation

/// Identity of one cached map snapshot image.
///
/// The detail sheet used to boot a live `MKMapView` just to show 600 m of non-interactive
/// context — the single most expensive part of opening it. The map is now a rendered image,
/// and this key decides when a cached render is still the right one: same spot, same
/// coordinate to ~11 m (4 decimal places), same pixel size, same theme. Anything else is a
/// cache hit forever — a saved place does not move.
struct MapSnapshotKey: Hashable {

    var spotID: UUID
    var latitudeE4: Int
    var longitudeE4: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var themeID: String

    init(
        spotID: UUID,
        latitude: Double,
        longitude: Double,
        pointWidth: Double,
        pointHeight: Double,
        scale: Double,
        themeID: String
    ) {
        self.spotID = spotID
        latitudeE4 = Int((latitude * 10_000).rounded())
        longitudeE4 = Int((longitude * 10_000).rounded())
        pixelWidth = Int((pointWidth * scale).rounded())
        pixelHeight = Int((pointHeight * scale).rounded())
        self.themeID = themeID
    }

    /// Filename-safe, collision-free within the cache directory.
    var filename: String {
        "map-\(spotID.uuidString)-\(latitudeE4)_\(longitudeE4)-\(pixelWidth)x\(pixelHeight)-\(themeID).jpg"
    }
}

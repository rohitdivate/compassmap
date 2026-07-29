import Foundation

/// The three sizes a spot photo is ever decoded at.
///
/// There used to be nine ad-hoc `maxDimension` values across the app, which meant the decode
/// cache almost never hit — the same photo decoded at 200, 300, 400 and 700 is four cache
/// entries and four ImageIO passes. Three canonical sizes make the cache do its job, and two
/// of them are served by the 480 px App Group thumbnail file, so showing a grid, a map full
/// of pins or a trip list never faults a photo blob out of the database at all.
enum PhotoSizeClass: String, CaseIterable, Sendable {
    /// Map pins, chips, list rows.
    case pin
    /// Grid cells and covers — the native size of the stored thumbnail.
    case card
    /// The detail hero, the featured card, the arrow backdrop.
    case hero

    var maxDimension: Double {
        switch self {
        case .pin: return 240
        case .card: return 480
        case .hero: return 1_600
        }
    }

    /// Whether the App Group thumbnail file (480 px) is a sufficient source. Only `.hero`
    /// needs the full stored photo.
    var servedByThumbnail: Bool { self != .hero }
}

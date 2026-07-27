import Foundation

/// What sort of place a spot is.
///
/// Tradewind began as a photo compass, where every spot was somewhere you had photographed and the
/// picture was its identity. Saving where you are staying, where you live, or which station you came
/// out of is a different job — those are places you need to find again, not scenes you want to look
/// at, and half of them you will never photograph.
///
/// Lives here rather than beside `Spot` because the widgets need it too: it travels in the snapshot,
/// and `Shared/Snapshot` is Foundation-only and reachable by the test bundle.
///
/// The raw values are stored in SwiftData and in the snapshot JSON. **Do not rename them** — a
/// renamed case reads back as `nil` on a device that already has spots saved.
enum PlaceKind: String, CaseIterable, Sendable, Identifiable {
    case place
    case home
    case work
    case stay
    case transit
    case food
    case viewpoint
    case shop

    var id: String { rawValue }

    /// What Tradewind calls it. Short, because these appear as filter chips.
    var label: String {
        switch self {
        case .place: return "Place"
        case .home: return "Home"
        case .work: return "Work"
        case .stay: return "Stay"
        case .transit: return "Transit"
        case .food: return "Food"
        case .viewpoint: return "View"
        case .shop: return "Shop"
        }
    }

    /// Plural, for section headers and counts.
    var pluralLabel: String {
        switch self {
        case .place: return "Places"
        case .home: return "Home"
        case .work: return "Work"
        case .stay: return "Stays"
        case .transit: return "Transit"
        case .food: return "Food"
        case .viewpoint: return "Views"
        case .shop: return "Shops"
        }
    }

    /// SF Symbol. Chosen to be distinguishable at widget size, where they are 10pt or so.
    var symbol: String {
        switch self {
        case .place: return "mappin"
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .stay: return "bed.double.fill"
        case .transit: return "tram.fill"
        case .food: return "fork.knife"
        case .viewpoint: return "binoculars.fill"
        case .shop: return "bag.fill"
        }
    }

    /// A hint shown under the picker, so the categories mean the same thing to everyone.
    var hint: String {
        switch self {
        case .place: return "Anywhere worth returning to"
        case .home: return "Where you live"
        case .work: return "Where you work"
        case .stay: return "A hotel, an Airbnb, a spare room"
        case .transit: return "A station, a stop, a gate"
        case .food: return "A restaurant, a bar, a stall"
        case .viewpoint: return "Somewhere worth looking at"
        case .shop: return "A shop or a market"
        }
    }

    /// The default when nobody has chosen, and the value an existing spot decodes to.
    static let fallback: PlaceKind = .place

    /// Reads a stored raw value, tolerating nil and anything unrecognised.
    ///
    /// Unrecognised is not hypothetical: a spot synced from a future build with a case this one does
    /// not know about must still appear in the gallery rather than vanish.
    static func from(rawValue: String?) -> PlaceKind {
        guard let rawValue, let kind = PlaceKind(rawValue: rawValue) else { return fallback }
        return kind
    }

    /// Kinds offered in the picker, in the order they appear.
    ///
    /// `place` is deliberately first: it is the default, and the one that needs no thought.
    static let pickable: [PlaceKind] = [
        .place, .stay, .home, .work, .transit, .food, .viewpoint, .shop,
    ]

    /// Whether a spot of this kind is expected to have a photo.
    ///
    /// Drives copy, not behaviour — every kind can be saved without one. A station is a thing you
    /// need to find, not a thing you photograph, and the app should not imply otherwise.
    var usuallyPhotographed: Bool {
        switch self {
        case .place, .viewpoint, .food, .stay: return true
        case .home, .work, .transit, .shop: return false
        }
    }
}

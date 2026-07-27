import Foundation

/// Turns an address-search pick into spot fields.
///
/// This is the one place a point-of-interest name is *allowed* to become a spot's name: the
/// person typed it and chose it, which is the opposite of the Wave-3 bug where the geocoder
/// invented one. The area line still goes through `PlaceNameFormatter`, and the kind is guessed
/// from Apple's POI category so a hotel arrives pre-badged as a Stay — a guess the picker can
/// always override.
enum PlannedPlace {

    /// A fully resolved pick, ready to save.
    struct Resolved: Equatable, Sendable {
        var name: String
        var coordinate: Coordinate
        var areaLine: String?
        var kindGuess: PlaceKind
    }

    /// Maps `MKPointOfInterestCategory` raw values to a place kind. Conservative: anything
    /// unrecognised is a plain place, never a wrong badge.
    static func kind(forCategoryRaw raw: String?) -> PlaceKind {
        guard let raw else { return .place }
        switch raw {
        case "MKPOICategoryHotel", "MKPOICategoryCampground", "MKPOICategoryRVPark":
            return .stay
        case "MKPOICategoryRestaurant", "MKPOICategoryCafe", "MKPOICategoryBakery",
             "MKPOICategoryBrewery", "MKPOICategoryWinery", "MKPOICategoryFoodMarket",
             "MKPOICategoryNightlife", "MKPOICategoryDistillery":
            return .food
        case "MKPOICategoryPublicTransport", "MKPOICategoryAirport", "MKPOICategoryParking",
             "MKPOICategoryEVCharger", "MKPOICategoryGasStation":
            return .transit
        case "MKPOICategoryStore", "MKPOICategoryPharmacy", "MKPOICategoryLaundry":
            return .shop
        case "MKPOICategoryNationalPark", "MKPOICategoryPark", "MKPOICategoryBeach",
             "MKPOICategoryScenicViewpoint", "MKPOICategoryNationalMonument", "MKPOICategoryLandmark":
            return .viewpoint
        default:
            return .place
        }
    }

    /// The name a pick arrives with: the chosen title, trimmed; empty falls back to the
    /// address's own first line so a bare street search still names itself.
    static func name(fromTitle title: String, areaLine: String?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return areaLine ?? ""
    }
}

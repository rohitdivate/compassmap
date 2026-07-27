import Foundation
import Testing

/// The mapping from an address-search pick to spot fields: a hotel arrives badged as a Stay,
/// nothing unrecognised gets a wrong badge, and the chosen title becomes the name — the one
/// place a POI name is allowed to, because the person picked it.
@Suite("Planned places")
struct PlannedPlaceTests {

    @Test("Apple's POI categories map to sensible kinds")
    func kindMapping() {
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryHotel") == .stay)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryRestaurant") == .food)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryCafe") == .food)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryPublicTransport") == .transit)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryAirport") == .transit)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryStore") == .shop)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryBeach") == .viewpoint)
    }

    @Test("Unknown and missing categories stay a plain place — never a wrong badge")
    func conservativeFallback() {
        #expect(PlannedPlace.kind(forCategoryRaw: nil) == .place)
        #expect(PlannedPlace.kind(forCategoryRaw: "MKPOICategoryZoo") == .place)
        #expect(PlannedPlace.kind(forCategoryRaw: "SomethingFromAFutureOS") == .place)
    }

    @Test("The chosen title names the spot; a blank title falls back to the address")
    func naming() {
        #expect(PlannedPlace.name(fromTitle: "  Harbour Hotel  ", areaLine: "South Bank, London") == "Harbour Hotel")
        #expect(PlannedPlace.name(fromTitle: "   ", areaLine: "Baker Street, London") == "Baker Street, London")
        #expect(PlannedPlace.name(fromTitle: "", areaLine: nil) == "")
    }
}

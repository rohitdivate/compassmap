import Testing
import Foundation

/// The subtitle used to prefer the placemark's POI name — the nearest business to the coordinate,
/// a "random place" that means nothing a week later. These pin the replacement rule: street, then
/// neighbourhood, then town, never a POI (which `PlaceFields` cannot even represent).
@Suite("Place name formatting")
struct PlaceNameFormatterTests {

    @Test("A street anchors to its town")
    func streetAndTown() {
        let fields = PlaceFields(thoroughfare: "Baker Street", locality: "London", country: "United Kingdom")
        #expect(PlaceNameFormatter.line(from: fields) == "Baker Street, London")
    }

    @Test("No street: the neighbourhood carries it")
    func neighbourhood() {
        let fields = PlaceFields(subLocality: "Soho", locality: "London")
        #expect(PlaceNameFormatter.line(from: fields) == "Soho, London")
    }

    @Test("Rural coordinate: town and district, the user's own example")
    func townAndDistrict() {
        let fields = PlaceFields(
            locality: "Ella",
            subAdministrativeArea: "Badulla District",
            administrativeArea: "Uva Province",
            country: "Sri Lanka"
        )
        #expect(PlaceNameFormatter.line(from: fields) == "Ella, Badulla District")
    }

    @Test("Wilderness: region and country rather than nothing")
    func regionAndCountry() {
        let fields = PlaceFields(administrativeArea: "Uva Province", country: "Sri Lanka")
        #expect(PlaceNameFormatter.line(from: fields) == "Uva Province, Sri Lanka")
    }

    @Test("The same string at two levels does not repeat")
    func dedupes() {
        // Geocoders love "London, London" — city-states and metropolitan areas especially.
        let fields = PlaceFields(locality: "Singapore", administrativeArea: "singapore", country: "Singapore")
        #expect(PlaceNameFormatter.line(from: fields) == "Singapore")
    }

    @Test("Only a country still reads as a place")
    func countryOnly() {
        #expect(PlaceNameFormatter.line(from: PlaceFields(country: "Iceland")) == "Iceland")
    }

    @Test("Everything empty is nil, so callers can fall back to coordinates knowingly")
    func allEmpty() {
        #expect(PlaceNameFormatter.line(from: PlaceFields()) == nil)
        #expect(PlaceNameFormatter.line(from: PlaceFields(thoroughfare: "  ", locality: "")) == nil)
    }

    @Test("Whitespace-padded fields are trimmed, not shown padded")
    func trims() {
        let fields = PlaceFields(thoroughfare: " Baker Street ", locality: " London ")
        #expect(PlaceNameFormatter.line(from: fields) == "Baker Street, London")
    }

    @Test("Never more than two components")
    func twoComponentsMax() {
        let fields = PlaceFields(
            thoroughfare: "Baker Street",
            subLocality: "Marylebone",
            locality: "London",
            administrativeArea: "England",
            country: "United Kingdom"
        )
        let line = PlaceNameFormatter.line(from: fields)
        #expect(line == "Baker Street, Marylebone")
        #expect(line?.components(separatedBy: ", ").count == 2)
    }
}

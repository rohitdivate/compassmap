import Testing
import Foundation

/// Maps links carry coordinates in about six shapes, and the failure mode of getting one wrong is
/// silently dropping a pin somewhere the person then walks toward. Worth pinning properly.
@Suite("Maps link parsing")
struct MapsLinkParserTests {

    private func coordinate(_ string: String) -> Coordinate? {
        guard let url = URL(string: string) else { return nil }
        guard case .success(let result) = MapsLinkParser.parse(url) else { return nil }
        return result.coordinate
    }

    private func name(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        guard case .success(let result) = MapsLinkParser.parse(url) else { return nil }
        return result.name
    }

    private func failure(_ string: String) -> MapsLinkParser.Failure? {
        guard let url = URL(string: string) else { return nil }
        guard case .failure(let reason) = MapsLinkParser.parse(url) else { return nil }
        return reason
    }

    private func isClose(_ actual: Coordinate?, _ latitude: Double, _ longitude: Double) -> Bool {
        guard let actual else { return false }
        return abs(actual.latitude - latitude) < 0.0001
            && abs(actual.longitude - longitude) < 0.0001
    }

    // MARK: - Apple Maps

    @Test("Apple Maps ll parameter")
    func appleLL() {
        #expect(isClose(coordinate("https://maps.apple.com/?ll=6.8395,81.0553&q=Ravana%20Falls"), 6.8395, 81.0553))
        #expect(name("https://maps.apple.com/?ll=6.8395,81.0553&q=Ravana%20Falls") == "Ravana Falls")
    }

    @Test("A destination beats the map centre")
    func appleDestinationWins() {
        // daddr is where you asked to go; ll is wherever the viewport happened to be.
        #expect(isClose(
            coordinate("https://maps.apple.com/?ll=51.5,-0.12&daddr=6.8395,81.0553"),
            6.8395, 81.0553
        ))
    }

    @Test("The maps: scheme is handled like the web host")
    func appleScheme() {
        #expect(isClose(coordinate("maps://?ll=35.6812,139.7671"), 35.6812, 139.7671))
    }

    @Test("A coordinate arriving in the name slot is not used as a name")
    func coordinateIsNotAName() {
        #expect(isClose(coordinate("https://maps.apple.com/?q=48.8584,2.2945"), 48.8584, 2.2945))
        #expect(name("https://maps.apple.com/?q=48.8584,2.2945") == nil)
    }

    // MARK: - Google Maps

    @Test("Google place URL with an @ segment")
    func googlePlace() {
        let url = "https://www.google.com/maps/place/Ravana+Falls/@6.8395,81.0553,15z"
        #expect(isClose(coordinate(url), 6.8395, 81.0553))
        #expect(name(url) == "Ravana Falls")
    }

    @Test("Google query coordinates")
    func googleQuery() {
        #expect(isClose(coordinate("https://www.google.com/maps?q=13.7563,100.5018"), 13.7563, 100.5018))
    }

    @Test("Google directions destination")
    func googleDirections() {
        let url = "https://www.google.com/maps/dir/?api=1&destination=41.9028,12.4964"
        #expect(isClose(coordinate(url), 41.9028, 12.4964))
    }

    @Test("A bare @ segment with no place name still yields the coordinate")
    func googleBareAt() {
        #expect(isClose(coordinate("https://www.google.com/maps/@-33.8568,151.2153,17z"), -33.8568, 151.2153))
    }

    // MARK: - geo:

    @Test("geo scheme, with and without trailing parameters")
    func geoScheme() {
        #expect(isClose(coordinate("geo:52.5200,13.4050"), 52.52, 13.405))
        #expect(isClose(coordinate("geo:52.5200,13.4050;u=35"), 52.52, 13.405))
        #expect(isClose(coordinate("geo:52.5200,13.4050?q=Berlin"), 52.52, 13.405))
    }

    // MARK: - Signs and hemispheres

    @Test("All four hemispheres survive the round trip", arguments: [
        (-33.8688, 151.2093), (40.7128, -74.0060), (-22.9068, -43.1729), (55.7558, 37.6173),
    ])
    func hemispheres(latitude: Double, longitude: Double) {
        // Sign errors are the classic bug here and they put you on the wrong continent.
        let url = "https://maps.apple.com/?ll=\(latitude),\(longitude)"
        #expect(isClose(coordinate(url), latitude, longitude))
    }

    // MARK: - Refusing rather than guessing

    @Test("Out-of-range values are refused, not clamped")
    func outOfRangeRefused() {
        // Clamping would drop a pin near a pole and let someone walk toward it.
        #expect(MapsLinkParser.coordinatePair("200,10") == nil)
        #expect(MapsLinkParser.coordinatePair("10,400") == nil)
        #expect(MapsLinkParser.coordinatePair("-91,0") == nil)
    }

    @Test("Null Island is treated as a missing value")
    func zeroZeroRefused() {
        // 0,0 is in the Gulf of Guinea. It is almost always an unset field.
        #expect(MapsLinkParser.coordinatePair("0,0") == nil)
        #expect(MapsLinkParser.coordinatePair("0.0, 0.0") == nil)
    }

    @Test("Nonsense is refused")
    func nonsenseRefused() {
        #expect(MapsLinkParser.coordinatePair("hello,world") == nil)
        #expect(MapsLinkParser.coordinatePair("51.5") == nil)
        #expect(MapsLinkParser.coordinatePair("") == nil)
    }

    @Test("A Google short link asks to be redirected rather than failing outright")
    func shortLinkNeedsRedirect() {
        // These carry no coordinate at all — the app has to follow the redirect first, and the
        // difference between "cannot read this" and "needs a network round trip" is what lets the
        // app do something useful about it.
        let url = URL(string: "https://maps.app.goo.gl/abc123")!
        guard case .failure(.needsRedirect(let echoed)) = MapsLinkParser.parse(url) else {
            Issue.record("expected needsRedirect")
            return
        }
        #expect(echoed == url)
        #expect(MapsLinkParser.requiresRedirect(url))
    }

    @Test("A search with no coordinate is distinguished from an unreadable link")
    func searchWithoutCoordinate() {
        // "coffee near me" has nowhere to save; the app should say that rather than "invalid link".
        #expect(failure("https://www.google.com/maps?q=coffee+near+me") == .searchWithoutCoordinate)
        #expect(failure("https://maps.apple.com/?q=Big%20Ben") == .searchWithoutCoordinate)
    }

    @Test("Links that are not maps links at all are unrecognised")
    func notAMapsLink() {
        #expect(failure("https://example.com/page") == .unrecognised)
        #expect(failure("https://news.ycombinator.com/") == .unrecognised)
    }

    @Test("Percent-encoded and plus-encoded names both decode")
    func nameDecoding() {
        #expect(MapsLinkParser.placeName(from: "Ravana+Falls") == "Ravana Falls")
        #expect(MapsLinkParser.placeName(from: "Caf%C3%A9%20Central") == "Café Central")
        #expect(MapsLinkParser.placeName(from: "") == nil)
        // Absurdly long names are junk from a malformed path rather than a place.
        #expect(MapsLinkParser.placeName(from: String(repeating: "a", count: 200)) == nil)
    }
}

/// Place kinds are persisted by raw value, in SwiftData and in the widget snapshot.
@Suite("Place kinds")
struct PlaceKindTests {

    @Test("Unknown and missing raw values fall back rather than vanishing")
    func decodingIsTolerant() {
        // A spot synced from a future build with a kind this one has never heard of must still appear
        // in the gallery. Dropping it would look like data loss.
        #expect(PlaceKind.from(rawValue: nil) == .place)
        #expect(PlaceKind.from(rawValue: "") == .place)
        #expect(PlaceKind.from(rawValue: "helipad") == .place)
        #expect(PlaceKind.from(rawValue: "stay") == .stay)
    }

    @Test("Raw values are stable")
    func rawValuesAreStable() {
        // These strings are on disk. Renaming a case silently resets everyone's saved kinds, so this
        // test exists to make that a failing build rather than a support question.
        #expect(PlaceKind.place.rawValue == "place")
        #expect(PlaceKind.home.rawValue == "home")
        #expect(PlaceKind.work.rawValue == "work")
        #expect(PlaceKind.stay.rawValue == "stay")
        #expect(PlaceKind.transit.rawValue == "transit")
        #expect(PlaceKind.food.rawValue == "food")
        #expect(PlaceKind.viewpoint.rawValue == "viewpoint")
        #expect(PlaceKind.shop.rawValue == "shop")
    }

    @Test("Every kind is fully described")
    func everyKindIsUsable() {
        for kind in PlaceKind.allCases {
            #expect(kind.label.isEmpty == false)
            #expect(kind.pluralLabel.isEmpty == false)
            #expect(kind.symbol.isEmpty == false)
            #expect(kind.hint.isEmpty == false)
        }
    }

    @Test("The picker offers every kind, default first")
    func pickerIsComplete() {
        #expect(PlaceKind.pickable.first == .place)
        #expect(Set(PlaceKind.pickable) == Set(PlaceKind.allCases))
        #expect(PlaceKind.pickable.count == PlaceKind.allCases.count)
    }

    @Test("Kinds you would not photograph are marked as such")
    func photographyExpectations() {
        // Drives copy only — a station is somewhere to find, not something to photograph, and the
        // save flow should not imply a photo is missing.
        #expect(PlaceKind.transit.usuallyPhotographed == false)
        #expect(PlaceKind.home.usuallyPhotographed == false)
        #expect(PlaceKind.viewpoint.usuallyPhotographed)
    }
}

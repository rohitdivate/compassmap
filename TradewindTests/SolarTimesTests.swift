import Testing
import Foundation

@Suite("Sun times")
struct SolarTimesTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)!
    }

    private func hourUTC(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    @Test("On the equinox at the equator, the sun rises around six and sets around six")
    func equinoxAtEquator() throws {
        let equator = Coordinate(latitude: 0, longitude: 0)
        let events = try #require(SolarTimes.events(for: date(2026, 3, 20), at: equator))

        // Within twenty minutes of 06:00 and 18:00 UTC, which is as much as the low-precision
        // equation promises.
        #expect(abs(hourUTC(events.sunrise) - 6) < 0.34)
        #expect(abs(hourUTC(events.sunset) - 18) < 0.34)
    }

    @Test("Sunrise always precedes sunset, and golden hour precedes sunset")
    func ordering() throws {
        let places = [
            Coordinate(latitude: 21.3069, longitude: -157.8583),  // Honolulu
            Coordinate(latitude: 6.9271, longitude: 79.8612),      // Colombo
            Coordinate(latitude: 13.7563, longitude: 100.5018),    // Bangkok
            Coordinate(latitude: 51.5074, longitude: -0.1278),     // London
            Coordinate(latitude: -33.8688, longitude: 151.2093),   // Sydney
        ]

        for place in places {
            for month in [1, 4, 7, 10] {
                let events = try #require(
                    SolarTimes.events(for: date(2026, month, 15), at: place),
                    "expected sun events for \(place) in month \(month)"
                )
                #expect(events.sunrise < events.sunset)
                #expect(events.goldenHourStart <= events.sunset)
                #expect(events.sunset <= events.civilDusk)
                // Days are between five and twenty hours long everywhere outside the circles.
                let dayLength = events.sunset.timeIntervalSince(events.sunrise) / 3_600
                #expect(dayLength > 5 && dayLength < 20)
            }
        }
    }

    @Test("Longitude shifts the whole day, latitude changes its length")
    func geographyBehavesSensibly() throws {
        let day = date(2026, 6, 21)

        // Ninety degrees east means the sun sets roughly six hours earlier in UTC.
        let atZero = try #require(SolarTimes.events(for: day, at: Coordinate(latitude: 0, longitude: 0)))
        let atEast = try #require(SolarTimes.events(for: day, at: Coordinate(latitude: 0, longitude: 90)))
        let shift = atZero.sunset.timeIntervalSince(atEast.sunset) / 3_600
        #expect(abs(shift - 6) < 0.4)

        // Midsummer: a northern day is longer than a tropical one.
        let london = try #require(
            SolarTimes.events(for: day, at: Coordinate(latitude: 51.5074, longitude: -0.1278))
        )
        let colombo = try #require(
            SolarTimes.events(for: day, at: Coordinate(latitude: 6.9271, longitude: 79.8612))
        )
        let londonLength = london.sunset.timeIntervalSince(london.sunrise)
        let colomboLength = colombo.sunset.timeIntervalSince(colombo.sunrise)
        #expect(londonLength > colomboLength)
    }

    @Test("Polar day and polar night produce no events rather than nonsense")
    func polarRegions() {
        let northPole = Coordinate(latitude: 89, longitude: 0)
        #expect(SolarTimes.events(for: date(2026, 6, 21), at: northPole) == nil)
        #expect(SolarTimes.events(for: date(2026, 12, 21), at: northPole) == nil)
        // And it does have a sunrise around the equinox.
        #expect(SolarTimes.events(for: date(2026, 3, 25), at: Coordinate(latitude: 66, longitude: 0)) != nil)
    }

    @Test("Julian conversion round-trips")
    func julian() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let julian = SolarTimes.julianDay(from: now)
        let back = SolarTimes.date(fromJulianDay: julian)
        #expect(abs((back?.timeIntervalSince1970 ?? 0) - now.timeIntervalSince1970) < 0.001)
    }

    @Test("An invalid coordinate has no sun")
    func invalidCoordinate() {
        #expect(SolarTimes.events(for: Date(), at: Coordinate(latitude: .nan, longitude: 0)) == nil)
    }
}

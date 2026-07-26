import Testing
import Foundation

@Suite("Photo GPS metadata")
struct GPSMetadataTests {

    @Test("Southern and western hemispheres come back negative")
    func hemispheres() {
        // Kandy, Sri Lanka — north and east.
        let kandy = GPSMetadata.parse(gpsDictionary: [
            "Latitude": 7.2906, "LatitudeRef": "N",
            "Longitude": 80.6337, "LongitudeRef": "E",
        ])
        #expect(kandy?.coordinate.latitude == 7.2906)
        #expect(kandy?.coordinate.longitude == 80.6337)

        // Wellington — south and east.
        let wellington = GPSMetadata.parse(gpsDictionary: [
            "Latitude": 41.2866, "LatitudeRef": "S",
            "Longitude": 174.7756, "LongitudeRef": "E",
        ])
        #expect(wellington?.coordinate.latitude == -41.2866)
        #expect(wellington?.coordinate.longitude == 174.7756)

        // Honolulu — north and west.
        let honolulu = GPSMetadata.parse(gpsDictionary: [
            "Latitude": 21.3069, "LatitudeRef": "N",
            "Longitude": 157.8583, "LongitudeRef": "W",
        ])
        #expect(honolulu?.coordinate.latitude == 21.3069)
        #expect(honolulu?.coordinate.longitude == -157.8583)

        // Rio — south and west.
        let rio = GPSMetadata.parse(gpsDictionary: [
            "Latitude": 22.9068, "LatitudeRef": "S",
            "Longitude": 43.1729, "LongitudeRef": "W",
        ])
        #expect(rio?.coordinate.latitude == -22.9068)
        #expect(rio?.coordinate.longitude == -43.1729)
    }

    @Test("A reference already carrying a sign is not double-negated")
    func alreadySigned() {
        // Some writers store a signed magnitude alongside a ref. Taking abs() first means the
        // ref is always the single source of truth for the hemisphere.
        let parsed = GPSMetadata.parse(gpsDictionary: [
            "Latitude": -22.9068, "LatitudeRef": "S",
            "Longitude": -43.1729, "LongitudeRef": "W",
        ])
        #expect(parsed?.coordinate.latitude == -22.9068)
        #expect(parsed?.coordinate.longitude == -43.1729)
    }

    @Test("Missing references default to north and east")
    func missingRefs() {
        let parsed = GPSMetadata.parse(gpsDictionary: ["Latitude": 10.5, "Longitude": 20.25])
        #expect(parsed?.coordinate.latitude == 10.5)
        #expect(parsed?.coordinate.longitude == 20.25)
    }

    @Test("Values arriving as strings or numbers both work")
    func coercion() {
        let strings = GPSMetadata.parse(gpsDictionary: [
            "Latitude": "13.7563", "LatitudeRef": "N",
            "Longitude": "100.5018", "LongitudeRef": "E",
        ])
        #expect(strings?.coordinate.latitude == 13.7563)

        let numbers = GPSMetadata.parse(gpsDictionary: [
            "Latitude": NSNumber(value: 13.7563), "LatitudeRef": "N",
            "Longitude": NSNumber(value: 100.5018), "LongitudeRef": "E",
        ])
        #expect(numbers?.coordinate.longitude == 100.5018)
    }

    @Test("Altitude honours its below-sea-level flag")
    func altitude() {
        let above = GPSMetadata.parse(gpsDictionary: [
            "Latitude": 1, "Longitude": 1, "Altitude": 1_240.5,
        ])
        #expect(above?.altitude == 1_240.5)

        let below = GPSMetadata.parse(gpsDictionary: [
            "Latitude": 1, "Longitude": 1, "Altitude": 12.0, "AltitudeRef": 1,
        ])
        #expect(below?.altitude == -12.0)

        let none = GPSMetadata.parse(gpsDictionary: ["Latitude": 1, "Longitude": 1])
        #expect(none?.altitude == nil)
    }

    @Test("Photos with no fix are rejected rather than placed at null island")
    func nullIsland() {
        #expect(GPSMetadata.parse(gpsDictionary: ["Latitude": 0, "Longitude": 0]) == nil)
        #expect(GPSMetadata.parse(gpsDictionary: [:]) == nil)
        #expect(GPSMetadata.parse(gpsDictionary: ["Latitude": 12.0]) == nil)
        // Out of range values are metadata corruption, not places.
        #expect(GPSMetadata.parse(gpsDictionary: ["Latitude": 200.0, "Longitude": 10.0]) == nil)
    }

    @Test("Timestamps are read as UTC across the two EXIF fields")
    func timestamps() {
        let date = GPSMetadata.timestamp(dateStamp: "2026:03:14", timeStamp: "09:26:53")
        #expect(date != nil)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 14
        components.hour = 9
        components.minute = 26
        components.second = 53
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(date == calendar.date(from: components))

        // Fractional seconds, which some cameras write, must not defeat parsing.
        #expect(GPSMetadata.timestamp(dateStamp: "2026:03:14", timeStamp: "09:26:53.221") != nil)
        #expect(GPSMetadata.timestamp(dateStamp: nil, timeStamp: "09:26:53") == nil)
        #expect(GPSMetadata.timestamp(dateStamp: "not a date", timeStamp: "09:26:53") == nil)
    }
}

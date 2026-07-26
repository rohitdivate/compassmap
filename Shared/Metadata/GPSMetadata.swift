import Foundation

/// A location recovered from a photo's metadata.
struct PhotoLocation: Equatable, Sendable {
    var coordinate: Coordinate
    var altitude: Double?
    var timestamp: Date?
}

/// Reads the GPS block out of an image's metadata.
///
/// Deliberately takes a plain dictionary rather than a `CGImageSource`, so the fiddly part —
/// EXIF stores latitude and longitude as unsigned magnitudes with a separate hemisphere
/// reference, and getting that wrong silently puts spots in the wrong hemisphere — can be
/// tested without an image file.
///
/// Keys match ImageIO's `kCGImagePropertyGPS*` constants, which are bare strings such as
/// `"Latitude"` and `"LatitudeRef"`.
enum GPSMetadata {

    static func parse(gpsDictionary gps: [String: Any]) -> PhotoLocation? {
        guard let latitudeMagnitude = double(gps["Latitude"]),
              let longitudeMagnitude = double(gps["Longitude"])
        else { return nil }

        let latitudeRef = string(gps["LatitudeRef"])?.uppercased() ?? "N"
        let longitudeRef = string(gps["LongitudeRef"])?.uppercased() ?? "E"

        let latitude = latitudeRef == "S" ? -abs(latitudeMagnitude) : abs(latitudeMagnitude)
        let longitude = longitudeRef == "W" ? -abs(longitudeMagnitude) : abs(longitudeMagnitude)

        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else { return nil }

        // 0.0, 0.0 is what a camera writes when it had no fix at all. A spot in the Gulf of
        // Guinea is never what the person meant.
        if latitude == 0 && longitude == 0 { return nil }

        var altitude: Double?
        if let value = double(gps["Altitude"]) {
            // AltitudeRef 1 means "below sea level".
            let belowSeaLevel = (double(gps["AltitudeRef"]) ?? 0) == 1
            altitude = belowSeaLevel ? -abs(value) : value
        }

        return PhotoLocation(
            coordinate: coordinate,
            altitude: altitude,
            timestamp: timestamp(
                dateStamp: string(gps["DateStamp"]),
                timeStamp: string(gps["TimeStamp"])
            )
        )
    }

    /// EXIF splits the fix time across two fields, both UTC.
    static func timestamp(dateStamp: String?, timeStamp: String?) -> Date? {
        guard let dateStamp, let timeStamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // Some cameras write fractional seconds into TimeStamp.
        let trimmedTime = timeStamp.split(separator: ".").first.map(String.init) ?? timeStamp
        return formatter.date(from: "\(dateStamp) \(trimmedTime)")
    }

    // MARK: - Coercion
    //
    // Metadata values arrive as NSNumber, String, or occasionally an array of rationals
    // depending on the camera. Coerce rather than assume.

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let string as String: return Double(string)
        case let array as [Any]: return array.first.flatMap(double)
        default: return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}

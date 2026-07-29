import Foundation

/// Sunrise, sunset and golden hour for a coordinate.
///
/// Tradewind is an app about walking somewhere to look at it, so the useful question about a
/// spot is not just "how far" but "when will the light be good there". This is the standard
/// low-precision sunrise equation — accurate to a minute or two, which is far better than the
/// decision it informs.
enum SolarTimes {

    struct Events: Equatable, Sendable {
        var sunrise: Date
        var sunset: Date
        /// When the sun drops to 6° above the horizon: the start of the warm light.
        var goldenHourStart: Date
        /// When the sun reaches 6° below the horizon and the colour goes.
        var civilDusk: Date

        var goldenHourRange: ClosedRange<Date> { goldenHourStart...sunset }
    }

    /// Standard refraction-corrected sun altitude for sunrise and sunset.
    private static let sunriseAltitude: Double = -0.833
    private static let goldenHourAltitude: Double = 6.0
    private static let civilAltitude: Double = -6.0

    /// Returns nil inside the polar day or polar night, where the events do not occur.
    static func events(for date: Date, at coordinate: Coordinate) -> Events? {
        guard coordinate.isValid else { return nil }
        guard let sunrise = time(for: date, at: coordinate, altitude: sunriseAltitude, rising: true),
              let sunset = time(for: date, at: coordinate, altitude: sunriseAltitude, rising: false)
        else { return nil }

        // Golden hour and civil dusk are nice-to-haves; if the sun never reaches those angles
        // on this day, fall back to sunset itself rather than losing the whole result.
        let golden = time(for: date, at: coordinate, altitude: goldenHourAltitude, rising: false) ?? sunset
        let civil = time(for: date, at: coordinate, altitude: civilAltitude, rising: false) ?? sunset

        return Events(
            sunrise: sunrise,
            sunset: sunset,
            goldenHourStart: golden,
            civilDusk: civil
        )
    }

    /// The moment the sun crosses a given altitude, rising or setting.
    static func time(
        for date: Date,
        at coordinate: Coordinate,
        altitude: Double,
        rising: Bool
    ) -> Date? {
        let julian = julianDay(from: date)

        // Mean solar noon, in days since J2000.
        let n = (julian - 2_451_545.0 + 0.0008).rounded()
        let meanSolarNoon = n - coordinate.longitude / 360

        // Solar mean anomaly.
        let meanAnomaly = (357.5291 + 0.98560028 * meanSolarNoon).truncatingRemainder(dividingBy: 360)
        let m = meanAnomaly * .pi / 180

        // Equation of the centre.
        let centre = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)

        // Ecliptic longitude.
        let eclipticLongitude = (meanAnomaly + centre + 180 + 102.9372)
            .truncatingRemainder(dividingBy: 360)
        let lambda = eclipticLongitude * .pi / 180

        // Solar transit (local noon).
        let transit = 2_451_545.0 + meanSolarNoon + 0.0053 * sin(m) - 0.0069 * sin(2 * lambda)

        // Declination of the sun.
        let obliquity = 23.4397 * .pi / 180
        let sinDeclination = sin(lambda) * sin(obliquity)
        let declination = asin(sinDeclination)

        // Hour angle for the requested altitude.
        let phi = coordinate.latitude * .pi / 180
        let targetAltitude = altitude * .pi / 180
        let numerator = sin(targetAltitude) - sin(phi) * sin(declination)
        let denominator = cos(phi) * cos(declination)
        guard denominator != 0 else { return nil }

        let cosHourAngle = numerator / denominator
        // Outside -1...1 the sun never reaches that altitude on this day.
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }

        let hourAngle = acos(cosHourAngle) * 180 / .pi
        let julianResult = rising ? transit - hourAngle / 360 : transit + hourAngle / 360
        return self.date(fromJulianDay: julianResult)
    }

    // MARK: - Julian conversions

    static func julianDay(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    static func date(fromJulianDay julian: Double) -> Date? {
        guard julian.isFinite else { return nil }
        return Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86_400)
    }

    // MARK: - Phrasing

    /// Cached per time zone: `DateFormatter` construction costs real fractions of a
    /// millisecond, and this used to run inside a view body.
    private static var goldenHourFormatters: [String: DateFormatter] = [:]

    /// "Golden hour at 18:42" — in the time zone the caller hands us, which for a spot on the
    /// other side of the world should be that spot's, not ours.
    static func describeGoldenHour(_ events: Events, timeZone: TimeZone = .current) -> String {
        let formatter: DateFormatter
        if let cached = goldenHourFormatters[timeZone.identifier] {
            formatter = cached
        } else {
            let fresh = DateFormatter()
            fresh.timeStyle = .short
            fresh.dateStyle = .none
            fresh.timeZone = timeZone
            goldenHourFormatters[timeZone.identifier] = fresh
            formatter = fresh
        }
        return "Golden hour \(formatter.string(from: events.goldenHourStart))–\(formatter.string(from: events.sunset))"
    }
}

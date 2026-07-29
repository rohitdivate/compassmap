import Foundation

/// Which units to show distances in. `.automatic` follows the device locale.
enum UnitPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case metric
    case imperial

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .metric: return "Metres & kilometres"
        case .imperial: return "Feet & miles"
        }
    }
}

/// Turns a distance in metres into the two strings the UI actually wants: a number and a
/// unit, kept apart so the arrow screen can set them at different type sizes.
///
/// The rules are chosen for "how far is that thing over there", not for scientific
/// accuracy: close up you want whole metres, far away you want one decimal of a
/// kilometre, and nobody wants "1043.7 m".
struct DistanceReadout: Equatable, Sendable {
    var value: String
    var unit: String

    var combined: String { "\(value) \(unit)" }
}

enum DistanceFormatting {

    static func usesImperial(preference: UnitPreference, locale: Locale = .current) -> Bool {
        switch preference {
        case .metric: return false
        case .imperial: return true
        case .automatic:
            let system = locale.measurementSystem
            return system == .us || system == .uk
        }
    }

    /// The headline distance readout.
    static func readout(
        metres: Double,
        preference: UnitPreference = .automatic,
        locale: Locale = .current
    ) -> DistanceReadout {
        guard metres.isFinite, metres >= 0 else {
            return DistanceReadout(value: "—", unit: "")
        }

        if usesImperial(preference: preference, locale: locale) {
            let feet = metres * 3.280839895
            if feet < 1000 {
                return DistanceReadout(value: number(feet, decimals: 0, locale: locale), unit: "ft")
            }
            let miles = metres / 1609.344
            let decimals = miles < 10 ? 1 : 0
            return DistanceReadout(value: number(miles, decimals: decimals, locale: locale), unit: "mi")
        }

        if metres < 1000 {
            let decimals = metres < 10 ? 1 : 0
            return DistanceReadout(value: number(metres, decimals: decimals, locale: locale), unit: "m")
        }
        let km = metres / 1000
        let decimals = km < 10 ? 1 : 0
        return DistanceReadout(value: number(km, decimals: decimals, locale: locale), unit: "km")
    }

    /// A single string, for widgets and Siri responses where typography is not ours to control.
    static func string(
        metres: Double,
        preference: UnitPreference = .automatic,
        locale: Locale = .current
    ) -> String {
        readout(metres: metres, preference: preference, locale: locale).combined
    }

    /// Very short form for lock-screen accessories, where every character counts.
    static func compact(
        metres: Double,
        preference: UnitPreference = .automatic,
        locale: Locale = .current
    ) -> String {
        let readout = readout(metres: metres, preference: preference, locale: locale)
        return readout.value + readout.unit
    }

    /// Walking time from a straight-line distance, phrased as the estimate it is.
    ///
    /// The input is crow-flies and streets are not, so the detour factor is applied and the label
    /// carries a tilde. Surfaces that can afford a routing request (the arrow screen, the detail
    /// screen) replace this with the real answer from `WalkingRouteService`; this is for the
    /// gallery, widgets and Siri, where a network call per row is not on.
    static func walkingTime(metres: Double, locale: Locale = .current) -> String? {
        let detoured = RoutePolicy.estimatedWalkMetres(crowMetres: metres)
        guard let seconds = BearingMath.walkingDuration(forDistance: detoured) else { return nil }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "~\(minutes) min walk" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 12 { return nil }  // past the point where "walk" is useful advice
        return remainder == 0 ? "~\(hours) h walk" : "~\(hours) h \(remainder) min walk"
    }

    /// Signed elevation difference, e.g. "48 m above you".
    static func elevationDelta(
        metres: Double,
        preference: UnitPreference = .automatic,
        locale: Locale = .current
    ) -> String? {
        guard metres.isFinite, abs(metres) >= 5 else { return nil }
        let readout = readout(metres: abs(metres), preference: preference, locale: locale)
        return metres > 0 ? "\(readout.combined) above you" : "\(readout.combined) below you"
    }

    // MARK: - Private

    /// Formatters are expensive to build and this runs on every compass tick, so they are
    /// cached per (decimals, locale). Main-thread only, like everything else in this type.
    private static var formatterCache: [String: NumberFormatter] = [:]

    private static func number(_ value: Double, decimals: Int, locale: Locale) -> String {
        let key = "\(decimals)-\(locale.identifier)"
        let formatter: NumberFormatter
        if let cached = formatterCache[key] {
            formatter = cached
        } else {
            let fresh = NumberFormatter()
            fresh.locale = locale
            fresh.numberStyle = .decimal
            fresh.minimumFractionDigits = decimals
            fresh.maximumFractionDigits = decimals
            fresh.usesGroupingSeparator = true
            formatterCache[key] = fresh
            formatter = fresh
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }
}

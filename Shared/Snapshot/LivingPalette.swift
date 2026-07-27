import Foundation

/// The time of day, as the app's palettes and copy understand it.
///
/// Boundaries follow the actual sun when a coordinate is available — `SolarTimes` is already in
/// the codebase and golden hour in Reykjavik is not 5 pm — and fall back to civil-hour
/// heuristics when there is no fix. Lives in the pure layer so the boundaries are testable.
enum TimeOfDay: CaseIterable, Sendable {
    case dawn, day, goldenHour, dusk, night

    static var current: TimeOfDay { at(Date()) }

    /// Solar-aware phase for a place. The hour heuristic covers the no-fix case.
    static func current(at coordinate: Coordinate?, date: Date = Date()) -> TimeOfDay {
        guard let coordinate, let events = SolarTimes.events(for: date, at: coordinate) else {
            return at(date)
        }
        return at(date, sunrise: events.sunrise, sunset: events.sunset)
    }

    static func at(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<8: return .dawn
        case 8..<16: return .day
        case 16..<19: return .goldenHour
        case 19..<21: return .dusk
        default: return .night
        }
    }

    /// Phase from real sun times: dawn is the hour around sunrise, golden hour the last ninety
    /// minutes of sun, dusk the forty-five after it sets.
    static func at(_ date: Date, sunrise: Date, sunset: Date) -> TimeOfDay {
        if date < sunrise.addingTimeInterval(-30 * 60) { return .night }
        if date < sunrise.addingTimeInterval(60 * 60) { return .dawn }
        if date < sunset.addingTimeInterval(-90 * 60) { return .day }
        if date < sunset { return .goldenHour }
        if date < sunset.addingTimeInterval(45 * 60) { return .dusk }
        return .night
    }

    var greeting: String {
        switch self {
        case .dawn: return "Early start"
        case .day: return "Somewhere to be"
        case .goldenHour: return "Golden hour"
        case .dusk: return "Last light"
        case .night: return "After dark"
        }
    }
}

/// The sky-reactive half of the design system: Tropical Spritz's hero wash follows the actual
/// sky through the day — five distinct washes, dawn to night — the move Tide Guide won its
/// Apple Design Award on. Nomad Money deliberately does not participate: a ledger's discipline
/// is that it looks the same at 3 am, and that contrast *is* the two-mood system.
///
/// Hex strings rather than Colors so this stays Foundation-only and the exact palettes are
/// pinned by tests.
enum LivingPalette {

    /// The three-stop hero wash for a theme at a phase, or nil when the mood forbids gradients.
    static func heroHexes(themeID: String, phase: TimeOfDay) -> [String]? {
        guard themeID == "tropicalSpritz" else { return nil }
        switch phase {
        case .dawn: return ["#FFB08C", "#FF8FA8", "#C9A0DC"]
        case .day: return ["#FF8C42", "#FF6B8B", "#B06AB3"]
        case .goldenHour: return ["#FF7A2F", "#F0537B", "#8E4E9E"]
        case .dusk: return ["#E85A71", "#9A5AA8", "#3D3A6E"]
        case .night: return ["#243B55", "#3A2E58", "#0E5C6B"]
        }
    }

    /// The arrow-halo colour that matches the wash.
    static func glowHex(themeID: String, phase: TimeOfDay) -> String? {
        guard themeID == "tropicalSpritz" else { return nil }
        switch phase {
        case .dawn: return "#FFB08C"
        case .day: return "#FF8C42"
        case .goldenHour: return "#FF7A2F"
        case .dusk: return "#E85A71"
        case .night: return "#1FA3B8"
        }
    }
}

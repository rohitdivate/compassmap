import Foundation

/// Turns reverse-geocoded address fields into the line a person would say.
///
/// The old formatter preferred the placemark's `name`, which for an arbitrary coordinate is
/// usually the nearest business or building — a "random place" that means nothing a week later.
/// What people actually recall is the street or the neighbourhood, so this type formats *only*
/// those fields. There is deliberately no POI field in `PlaceFields`: the bug is unrepresentable
/// here, not merely avoided.
struct PlaceFields: Equatable, Sendable {
    var thoroughfare: String?
    /// Neighbourhood or district — "Soho", "Shibuya".
    var subLocality: String?
    /// Town or city.
    var locality: String?
    /// District/county above the town — "Uva Province", "Kreis Steinfurt".
    var subAdministrativeArea: String?
    /// State/province.
    var administrativeArea: String?
    var country: String?

    init(
        thoroughfare: String? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        subAdministrativeArea: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil
    ) {
        self.thoroughfare = thoroughfare
        self.subLocality = subLocality
        self.locality = locality
        self.subAdministrativeArea = subAdministrativeArea
        self.administrativeArea = administrativeArea
        self.country = country
    }
}

enum PlaceNameFormatter {

    /// The display line: most specific *area* first, one broader anchor second, two parts at most.
    ///
    /// "Baker Street, London" · "Soho, London" · "Ella, Uva Province" · "Uva Province, Sri Lanka".
    /// Returns nil only when every field is empty, so callers can keep coordinates as the last
    /// resort rather than showing an empty string.
    static func line(from fields: PlaceFields) -> String? {
        let specific = firstNonEmpty(
            fields.thoroughfare,
            fields.subLocality,
            fields.locality,
            fields.subAdministrativeArea,
            fields.administrativeArea,
            fields.country
        )
        guard let specific else { return nil }

        // The anchor is the next broader thing that is not just the specific part repeated —
        // geocoders love returning the same string at two levels ("London, London").
        let anchor = firstNonEmpty(
            fields.subLocality,
            fields.locality,
            fields.subAdministrativeArea,
            fields.administrativeArea,
            fields.country,
            after: specific
        )

        guard let anchor else { return specific }
        return "\(specific), \(anchor)"
    }

    /// First trimmed, non-empty candidate.
    private static func firstNonEmpty(_ candidates: String?..., after excluded: String? = nil) -> String? {
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let excluded, trimmed.compare(excluded, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                continue
            }
            return trimmed
        }
        return nil
    }
}

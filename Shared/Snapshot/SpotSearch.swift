import Foundation

/// Text search over spots.
///
/// A gallery is scannable at ten spots and a wall at forty; past that point typing three letters
/// beats scrolling. The matching lives here — pure, Foundation-only, testable — because "does
/// 'cafe' find 'Café Central'" is exactly the kind of question that must not be answered by
/// eyeballing a simulator.
enum SpotSearch {

    /// Case- and diacritic-insensitive fold, so "cafe" finds "Café" and "STATION" finds "station".
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a spot matches a query, across every text a person might remember it by.
    ///
    /// The note is deliberately included: "aisle" should find the parking spot whose note says
    /// "Level 3, aisle F", because the note is often the only text on a photo-less spot.
    static func matches(
        query: String,
        name: String,
        placeName: String? = nil,
        note: String? = nil
    ) -> Bool {
        let needle = normalize(query)
        // An empty query filters nothing — the field being open must not hide the gallery.
        guard !needle.isEmpty else { return true }

        for haystack in [name, placeName ?? "", note ?? ""] {
            if normalize(haystack).contains(needle) { return true }
        }
        return false
    }
}

import Testing
import Foundation

/// "Does 'cafe' find 'Café Central'" is not a question to answer by eyeballing a simulator.
@Suite("Spot search")
struct SpotSearchTests {

    @Test("Case does not matter")
    func caseInsensitive() {
        #expect(SpotSearch.matches(query: "STATION", name: "King's Cross station"))
        #expect(SpotSearch.matches(query: "station", name: "STATION"))
    }

    @Test("Diacritics do not matter, in either direction")
    func diacriticInsensitive() {
        // The classic: a place saved with accents, searched without — and the reverse.
        #expect(SpotSearch.matches(query: "cafe", name: "Café Central"))
        #expect(SpotSearch.matches(query: "café", name: "Cafe Central"))
        #expect(SpotSearch.matches(query: "sao", name: "São Paulo viewpoint"))
    }

    @Test("The place name and the note are searchable, not just the title")
    func searchesAllFields() {
        // A photo-less parking spot is often named nothing; its note is its identity.
        #expect(SpotSearch.matches(query: "aisle", name: "Stay", note: "Level 3, aisle F"))
        #expect(SpotSearch.matches(query: "mirissa", name: "Beach shack", placeName: "Mirissa, Sri Lanka"))
        #expect(SpotSearch.matches(query: "nowhere", name: "Stay", placeName: "Ella", note: "back door") == false)
    }

    @Test("An empty or whitespace query hides nothing")
    func emptyQueryMatchesAll() {
        // The search field being open must not blank the gallery.
        #expect(SpotSearch.matches(query: "", name: "Anything"))
        #expect(SpotSearch.matches(query: "   ", name: "Anything"))
    }

    @Test("Substrings match anywhere in the text, not only at the start")
    func substringAnywhere() {
        #expect(SpotSearch.matches(query: "falls", name: "Ravana Falls"))
        #expect(SpotSearch.matches(query: "van", name: "Ravana Falls"))
    }

    @Test("Queries with surrounding whitespace still match")
    func trimmedQuery() {
        #expect(SpotSearch.matches(query: "  falls  ", name: "Ravana Falls"))
    }

    @Test("Nil fields are simply not matched, never crashed on")
    func nilFields() {
        #expect(SpotSearch.matches(query: "x", name: "y", placeName: nil, note: nil) == false)
    }
}

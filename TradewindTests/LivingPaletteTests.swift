import Foundation
import Testing

/// The sky-reactive palette: Spritz gets five distinct washes keyed to the real sun; Nomad's
/// refusal to participate is part of the design and pinned here so nobody "fixes" it.
@Suite("Living palette")
struct LivingPaletteTests {

    @Test("Solar boundaries: dawn hugs sunrise, golden hour ends at sunset, night after dusk")
    func solarPhases() {
        let sunrise = Date(timeIntervalSince1970: 1_785_060_000)
        let sunset = sunrise.addingTimeInterval(14 * 3_600)

        #expect(TimeOfDay.at(sunrise.addingTimeInterval(-2 * 3_600), sunrise: sunrise, sunset: sunset) == .night)
        #expect(TimeOfDay.at(sunrise.addingTimeInterval(10 * 60), sunrise: sunrise, sunset: sunset) == .dawn)
        #expect(TimeOfDay.at(sunrise.addingTimeInterval(5 * 3_600), sunrise: sunrise, sunset: sunset) == .day)
        #expect(TimeOfDay.at(sunset.addingTimeInterval(-30 * 60), sunrise: sunrise, sunset: sunset) == .goldenHour)
        #expect(TimeOfDay.at(sunset.addingTimeInterval(20 * 60), sunrise: sunrise, sunset: sunset) == .dusk)
        #expect(TimeOfDay.at(sunset.addingTimeInterval(2 * 3_600), sunrise: sunrise, sunset: sunset) == .night)
    }

    @Test("Spritz has five washes and no two are the same sky")
    func spritzWashesDistinct() {
        var seen: Set<String> = []
        for phase in TimeOfDay.allCases {
            let hexes = LivingPalette.heroHexes(themeID: "tropicalSpritz", phase: phase)
            #expect(hexes?.count == 3, "A wash is three stops")
            seen.insert(hexes?.joined(separator: ",") ?? "")
            #expect(LivingPalette.glowHex(themeID: "tropicalSpritz", phase: phase) != nil)
        }
        #expect(seen.count == TimeOfDay.allCases.count)
    }

    @Test("Nomad never gets a wash — the ledger looks the same at 3 am, by design")
    func nomadAbstains() {
        for phase in TimeOfDay.allCases {
            #expect(LivingPalette.heroHexes(themeID: "nomadMoney", phase: phase) == nil)
            #expect(LivingPalette.glowHex(themeID: "nomadMoney", phase: phase) == nil)
        }
    }

    @Test("Every phase greets differently")
    func greetings() {
        let greetings = Set(TimeOfDay.allCases.map(\.greeting))
        #expect(greetings.count == TimeOfDay.allCases.count)
    }
}

import Foundation
import SwiftData

/// Seeds the in-memory store with a believable little library.
///
/// Only reachable under the `-ui-testing` seam with `-demo-data` alongside it — the screenshot
/// suite photographs these spots so every design change produces reviewable images from CI.
/// The data is fixed, not random: screenshots need to be comparable across runs.
///
/// Coordinates sit around central London because the UI-test location seam stands at Trafalgar
/// Square, which gives the cards walkable, readable distances — plus two Sri Lanka spots so a
/// trip and a long-haul distance appear too.
enum DemoData {

    static var isRequested: Bool {
        CommandLine.arguments.contains("-demo-data")
    }

    static func seed(into container: ModelContainer) {
        let context = ModelContext(container)

        let trip = Trip(
            name: "Sri Lanka",
            subtitle: "Ten days, one tuk-tuk",
            createdAt: Date(timeIntervalSince1970: 1_735_000_000)
        )
        context.insert(trip)

        let spots: [Spot] = [
            Spot(
                name: "Harbour Hotel",
                placeName: "South Bank, London",
                latitude: 51.5033, longitude: -0.1195,
                capturedAt: Date(timeIntervalSince1970: 1_753_400_000),
                note: "Room 214, breakfast till 10",
                isPinned: true,
                kind: .stay
            ),
            Spot(
                name: "Borough Market",
                placeName: "Borough, London",
                latitude: 51.5055, longitude: -0.0910,
                capturedAt: Date(timeIntervalSince1970: 1_753_300_000),
                note: "The cheese stall in the far corner",
                glyph: "🍹",
                kind: .food
            ),
            Spot(
                name: "Primrose lookout",
                placeName: "Primrose Hill, London",
                latitude: 51.5387, longitude: -0.1607,
                capturedAt: Date(timeIntervalSince1970: 1_753_200_000),
                glyph: "🌅",
                kind: .viewpoint
            ),
            Spot(
                name: "Waterloo",
                placeName: "Waterloo, London",
                latitude: 51.5031, longitude: -0.1132,
                capturedAt: Date(timeIntervalSince1970: 1_753_100_000),
                note: "Exit 3, past the clock",
                kind: .transit
            ),
            Spot(
                name: "Ella hideout",
                placeName: "Ella, Badulla District",
                latitude: 6.8667, longitude: 81.0466,
                capturedAt: Date(timeIntervalSince1970: 1_736_000_000),
                glyph: "🐘",
                kind: .place,
                trip: trip
            ),
            Spot(
                name: "Beach shack",
                placeName: "Mirissa, Southern Province",
                latitude: 5.9440, longitude: 80.4718,
                capturedAt: Date(timeIntervalSince1970: 1_735_900_000),
                note: "Kottu after sunset",
                glyph: "🥥",
                kind: .food,
                trip: trip
            ),
        ]

        for spot in spots {
            context.insert(spot)
        }
        try? context.save()
    }
}

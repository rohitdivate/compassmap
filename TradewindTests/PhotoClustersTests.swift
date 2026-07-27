import Foundation
import Testing

/// The clustering arithmetic that turns a photo library into suggested places. Radii and gaps
/// are the difference between "your hotel" and "three fragments of your hotel", so they are
/// pinned here.
@Suite("Photo clustering")
struct PhotoClustersTests {

    private let hotel = Coordinate(latitude: 51.5033, longitude: -0.1195)
    private let market = Coordinate(latitude: 51.5055, longitude: -0.0910)
    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    private func point(
        _ id: String,
        at coordinate: Coordinate,
        offsetMetres: Double = 0,
        minutes: Double,
        favorite: Bool = false
    ) -> PhotoClusters.PhotoPoint {
        PhotoClusters.PhotoPoint(
            id: id,
            latitude: coordinate.latitude + offsetMetres / 111_000,
            longitude: coordinate.longitude,
            capturedAt: t0.addingTimeInterval(minutes * 60),
            isFavorite: favorite
        )
    }

    @Test("Photos close in time and space are one place; a distant batch is another")
    func basicSplit() {
        let points = [
            point("h1", at: hotel, minutes: 0),
            point("h2", at: hotel, offsetMetres: 30, minutes: 10),
            point("m1", at: market, minutes: 60),
            point("m2", at: market, offsetMetres: 20, minutes: 70),
        ]
        let places = PhotoClusters.places(from: points, now: t0.addingTimeInterval(86_400))
        #expect(places.count == 2)
    }

    @Test("Visits on different days merge into one place with the visit count to show for it")
    func revisitsMerge() {
        let dayTwo = 24.0 * 60
        let points = [
            point("a", at: hotel, minutes: 0),
            point("b", at: hotel, offsetMetres: 20, minutes: 15),
            point("c", at: hotel, offsetMetres: 40, minutes: dayTwo),
            point("d", at: hotel, minutes: dayTwo + 20),
        ]
        let places = PhotoClusters.places(from: points, now: t0.addingTimeInterval(3 * 86_400))
        #expect(places.count == 1)
        #expect(places.first?.visitCount == 2)
        #expect(places.first?.photoCount == 4)
    }

    @Test("A three-hour gap ends a visit even without moving")
    func gapSplitsSessions() {
        let points = [
            point("a", at: hotel, minutes: 0),
            point("b", at: hotel, minutes: 10),
            point("c", at: hotel, minutes: 10 + 4 * 60),
        ]
        let sessions = PhotoClusters.sessions(from: points)
        #expect(sessions.count == 2)
    }

    @Test("A single stray photo is not a place")
    func singletonDropped() {
        let points = [
            point("a", at: hotel, minutes: 0),
            point("b", at: hotel, minutes: 5),
            point("stray", at: market, minutes: 300),
        ]
        let places = PhotoClusters.places(from: points, now: t0.addingTimeInterval(86_400))
        #expect(places.count == 1)
        #expect(places.first?.photoIDs.contains("stray") == false)
    }

    @Test("Photos taken while moving do not become a phantom place")
    func movingSessionDropped() {
        // Five photos in twenty minutes, each 200 m further along a road.
        let points = (0..<5).map { i in
            point("walk\(i)", at: hotel, offsetMetres: Double(i) * 200, minutes: Double(i) * 5)
        }
        let places = PhotoClusters.places(from: points, now: t0.addingTimeInterval(86_400))
        #expect(places.isEmpty)
    }

    @Test("A favourite photo represents its place; otherwise the middle of the stay")
    func representativePick() {
        let noFavorite = [
            point("first", at: hotel, minutes: 0),
            point("middle", at: hotel, minutes: 10),
            point("last", at: hotel, minutes: 20),
        ]
        #expect(PhotoClusters.representative(of: noFavorite).id == "middle")

        let withFavorite = [
            point("first", at: hotel, minutes: 0),
            point("starred", at: hotel, minutes: 10, favorite: true),
            point("last", at: hotel, minutes: 20),
        ]
        #expect(PhotoClusters.representative(of: withFavorite).id == "starred")
    }

    @Test("The library's dominant long-span cluster is flagged as home, not ranked as a suggestion")
    func homeDetection() {
        var points: [PhotoClusters.PhotoPoint] = []
        // Home: 5 visits spread over ~90 days, 15 photos — the dominant share.
        for visit in 0..<5 {
            for shot in 0..<3 {
                points.append(point(
                    "home-\(visit)-\(shot)",
                    at: hotel,
                    offsetMetres: Double(shot) * 10,
                    minutes: Double(visit) * 20 * 24 * 60 + Double(shot) * 5
                ))
            }
        }
        // A holiday spot: one visit, 3 photos.
        for shot in 0..<3 {
            points.append(point("trip-\(shot)", at: market, offsetMetres: Double(shot) * 10, minutes: 5_000 + Double(shot) * 5))
        }
        let places = PhotoClusters.places(from: points, now: t0.addingTimeInterval(100 * 86_400))
        let home = places.first { $0.photoIDs.contains("home-0-0") }
        let trip = places.first { $0.photoIDs.contains("trip-0") }
        #expect(home?.isLikelyHome == true)
        #expect(trip?.isLikelyHome == false)
    }
}

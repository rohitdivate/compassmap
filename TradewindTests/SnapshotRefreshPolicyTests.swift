import Foundation
import Testing

@Suite("Snapshot refresh policy")
struct SnapshotRefreshPolicyTests {

    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("A lone request fires after the debounce")
    func loneRequest() {
        let fire = SnapshotRefreshPolicy.fireDate(pendingSince: nil, requestedAt: t0)
        #expect(fire == t0.addingTimeInterval(SnapshotRefreshPolicy.debounce))
    }

    @Test("A follow-up request pushes the write back")
    func followUpDebounces() {
        let later = t0.addingTimeInterval(0.1)
        let fire = SnapshotRefreshPolicy.fireDate(pendingSince: t0, requestedAt: later)
        #expect(fire == later.addingTimeInterval(SnapshotRefreshPolicy.debounce))
    }

    @Test("A steady stream still lands within the max latency")
    func ceilingHolds() {
        // Requests keep arriving right up to the ceiling; the fire date stops moving.
        let nearCeiling = t0.addingTimeInterval(1.9)
        let fire = SnapshotRefreshPolicy.fireDate(pendingSince: t0, requestedAt: nearCeiling)
        #expect(fire == t0.addingTimeInterval(SnapshotRefreshPolicy.maxLatency))
    }
}

@Suite("Map snapshot key")
struct MapSnapshotKeyTests {

    private let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func key(
        latitude: Double = 51.50648,
        longitude: Double = -0.09201,
        width: Double = 340,
        height: Double = 160,
        scale: Double = 3,
        themeID: String = "spritz"
    ) -> MapSnapshotKey {
        MapSnapshotKey(
            spotID: id, latitude: latitude, longitude: longitude,
            pointWidth: width, pointHeight: height, scale: scale, themeID: themeID
        )
    }

    @Test("Sub-11-metre coordinate noise is the same key")
    func coordinateRounding() {
        #expect(key(latitude: 51.50648) == key(latitude: 51.506482))
        #expect(key(latitude: 51.5064) != key(latitude: 51.5066))
    }

    @Test("Size, scale and theme are all part of identity")
    func identityParts() {
        #expect(key(width: 340) != key(width: 350))
        #expect(key(scale: 2) != key(scale: 3))
        #expect(key(themeID: "spritz") != key(themeID: "nomad"))
    }

    @Test("Filename is stable and filesystem-safe")
    func filename() {
        let name = key().filename
        #expect(name == "map-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE-515065_-920-1020x480-spritz.jpg")
        #expect(!name.contains("/"))
        #expect(!name.contains(" "))
    }
}

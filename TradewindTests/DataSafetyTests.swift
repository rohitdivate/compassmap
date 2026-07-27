import Foundation
import Testing

/// The rules that decide when someone's spot is really gone, and whether a backup restores
/// faithfully. These are the two places a bug destroys a memory instead of a pixel.
@Suite("Trash policy")
struct TrashPolicyTests {

    private let deleted = Date(timeIntervalSince1970: 1_000_000)

    @Test("Thirty days, then gone")
    func expiry() {
        let justUnder = deleted.addingTimeInterval(TrashPolicy.retention - 1)
        let exactly = deleted.addingTimeInterval(TrashPolicy.retention)
        #expect(!TrashPolicy.isExpired(deletedAt: deleted, now: justUnder))
        #expect(TrashPolicy.isExpired(deletedAt: deleted, now: exactly))
    }

    @Test("Days remaining round up and never go negative")
    func daysRemaining() {
        let now = deleted.addingTimeInterval(60)
        #expect(TrashPolicy.daysRemaining(deletedAt: deleted, now: now) == 30)
        let lastDay = deleted.addingTimeInterval(TrashPolicy.retention - 3_600)
        #expect(TrashPolicy.daysRemaining(deletedAt: deleted, now: lastDay) == 1)
        let past = deleted.addingTimeInterval(TrashPolicy.retention + 3_600)
        #expect(TrashPolicy.daysRemaining(deletedAt: deleted, now: past) == 0)
        #expect(TrashPolicy.remainingLabel(deletedAt: deleted, now: past) == "Deleting soon")
    }
}

@Suite("GPX round trip")
struct GPXCodecTests {

    @Test("What is written can be read back")
    func roundTrip() {
        let out = [
            GPXCodec.Waypoint(
                latitude: 51.5074,
                longitude: -0.1278,
                elevation: 11,
                time: Date(timeIntervalSince1970: 1_700_000_000),
                name: "Harbour Hotel",
                note: "Level 3, aisle F"
            ),
            GPXCodec.Waypoint(latitude: 6.8395, longitude: 81.0553),
        ]
        let document = GPXCodec.document(from: out)
        let back = GPXCodec.waypoints(from: document)
        #expect(back == out)
    }

    @Test("XML-hostile names survive")
    func escaping() {
        let out = [GPXCodec.Waypoint(latitude: 1, longitude: 2, name: "Fish & Chips <best>")]
        let back = GPXCodec.waypoints(from: GPXCodec.document(from: out))
        #expect(back.first?.name == "Fish & Chips <best>")
    }

    @Test("Other apps' files parse: CDATA names, no time, junk extensions")
    func foreignDialect() {
        let foreign = """
        <?xml version="1.0"?>
        <gpx version="1.1" creator="SomeoneElse">
          <wpt lat="35.0116" lon="135.7681">
            <name><![CDATA[Kyoto ryokan]]></name>
            <extensions><name>not-the-name</name></extensions>
          </wpt>
          <wpt lat="200" lon="0"><name>Impossible latitude</name></wpt>
        </gpx>
        """
        let points = GPXCodec.waypoints(from: foreign)
        #expect(points.count == 1)
        #expect(points.first?.name == "Kyoto ryokan")
        #expect(points.first?.time == nil)
    }
}

@Suite("Backup archive")
struct BackupArchiveTests {

    private func record(id: UUID = UUID()) -> BackupArchive.SpotRecord {
        BackupArchive.SpotRecord(
            id: id,
            name: "Taverna",
            placeName: "Naxos, Cyclades",
            latitude: 37.1,
            longitude: 25.4,
            altitude: 4,
            horizontalAccuracy: 8,
            capturedAt: Date(timeIntervalSince1970: 1_690_000_000),
            headingAtCapture: 210,
            note: "Ask for the table by the water",
            glyph: nil,
            kindRaw: "food",
            isPinned: false,
            alertsEnabled: true,
            deletedAt: nil,
            reminderAt: nil,
            tripID: nil,
            photoFilename: "abc.jpg"
        )
    }

    @Test("Records survive encode and decode byte-exactly")
    func codableRoundTrip() throws {
        let original = record()
        let data = try BackupArchive.encode([original])
        let back = try BackupArchive.decode([BackupArchive.SpotRecord].self, from: data)
        #expect(back == [original])
    }

    @Test("Restore inserts the unknown and skips the present — idempotent by UUID")
    func mergeDecisions() {
        let incoming = record()
        #expect(BackupArchive.decision(incoming: incoming, existingCapturedAt: nil) == .insert)
        #expect(
            BackupArchive.decision(incoming: incoming, existingCapturedAt: incoming.capturedAt) == .skip
        )
    }

    @Test("The restore summary tells the truth in all three shapes")
    func summaries() {
        #expect(BackupArchive.restoreSummary(incoming: 3, skipped: 3)
            == "Everything in this backup is already on this phone.")
        #expect(BackupArchive.restoreSummary(incoming: 2, skipped: 0) == "Adds 2 spots.")
        #expect(BackupArchive.restoreSummary(incoming: 3, skipped: 2) == "Adds 1 spot; 2 already here.")
    }
}

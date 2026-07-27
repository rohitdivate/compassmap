import Foundation

/// Reads and writes GPX waypoints — the lingua franca of saved places.
///
/// GPX is what Gaia, Organic Maps, AllTrails and every handheld GPS accept, so it is the export
/// that lets someone's spots outlive this app, and the import that lets a hiking life move in.
/// Only waypoints are spoken here: routes and tracks are someone else's job.
///
/// Writing is exact string assembly rather than an XML framework, because the format is tiny and
/// the test needs to pin bytes. Parsing uses `XMLParser` underneath via a small scanner-free
/// delegate — tolerant of the many dialects in the wild: missing `<time>`, `<name>` in CDATA,
/// waypoints nested under other vendors' extensions.
enum GPXCodec {

    struct Waypoint: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var elevation: Double?
        var time: Date?
        var name: String?
        var note: String?
    }

    // MARK: - Writing

    static func document(from waypoints: [Waypoint]) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<gpx version=\"1.1\" creator=\"Tradewind\" xmlns=\"http://www.topografix.com/GPX/1/1\">")
        for point in waypoints {
            lines.append(String(format: "  <wpt lat=\"%.6f\" lon=\"%.6f\">", point.latitude, point.longitude))
            if let elevation = point.elevation {
                lines.append(String(format: "    <ele>%.1f</ele>", elevation))
            }
            if let time = point.time {
                lines.append("    <time>\(timestampFormatter.string(from: time))</time>")
            }
            if let name = point.name, !name.isEmpty {
                lines.append("    <name>\(escaped(name))</name>")
            }
            if let note = point.note, !note.isEmpty {
                lines.append("    <desc>\(escaped(note))</desc>")
            }
            lines.append("  </wpt>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Reading

    static func waypoints(from data: Data) -> [Waypoint] {
        let reader = WaypointReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.waypoints
    }

    static func waypoints(from text: String) -> [Waypoint] {
        waypoints(from: Data(text.utf8))
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Accepts both `2024-05-01T10:00:00Z` and the fractional-seconds variant some apps write.
    fileprivate static func parseTimestamp(_ text: String) -> Date? {
        if let date = timestampFormatter.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// `XMLParser` delegate collecting `<wpt>` elements. A class because `XMLParser` requires one.
private final class WaypointReader: NSObject, XMLParserDelegate {

    var waypoints: [GPXCodec.Waypoint] = []

    private var current: GPXCodec.Waypoint?
    private var textBuffer = ""
    private var elementStack: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        elementStack.append(name)
        textBuffer = ""

        if name == "wpt",
           let lat = attributeDict["lat"].flatMap(Double.init),
           let lon = attributeDict["lon"].flatMap(Double.init),
           (-90...90).contains(lat), (-180...180).contains(lon) {
            current = GPXCodec.Waypoint(latitude: lat, longitude: lon)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        textBuffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        defer { elementStack.removeLast(elementStack.isEmpty ? 0 : 1) }

        // Only fields directly inside <wpt> count; a <name> inside <extensions> is not the name.
        let directChildOfWaypoint = elementStack.count >= 2
            && elementStack[elementStack.count - 2] == "wpt"
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "wpt":
            if let waypoint = current { waypoints.append(waypoint) }
            current = nil
        case "ele" where directChildOfWaypoint:
            current?.elevation = Double(text)
        case "time" where directChildOfWaypoint:
            current?.time = GPXCodec.parseTimestamp(text)
        case "name" where directChildOfWaypoint:
            if !text.isEmpty { current?.name = text }
        case "desc" where directChildOfWaypoint:
            if !text.isEmpty { current?.note = text }
        default:
            break
        }
        textBuffer = ""
    }
}

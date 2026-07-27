import Foundation

/// Pulls a coordinate out of a Maps link, so somewhere can be saved without a photo.
///
/// Sharing a place from Apple or Google Maps produces a URL, and those URLs carry the coordinate in
/// about six different shapes depending on which app, which platform and whether the place is a
/// business or a dropped pin. This handles the forms that actually appear, and — importantly — says
/// when it cannot, rather than guessing at a location the person will then walk toward.
///
/// Foundation-only and pure, in a directory the test bundle compiles. URL parsing is exactly the kind
/// of code that looks obviously right and is full of off-by-one hemispheres.
enum MapsLinkParser {

    struct Result: Equatable, Sendable {
        var coordinate: Coordinate
        /// A name carried by the link, when it has one worth using.
        var name: String?
    }

    /// Why a link produced nothing, so the app can say something useful instead of "failed".
    enum Failure: Equatable, Sendable {
        /// Not a maps link at all.
        case unrecognised
        /// A Google short link. These carry no coordinate; the redirect has to be followed first.
        case needsRedirect(URL)
        /// A maps link, but one describing a search rather than a place — "coffee near me" has no
        /// coordinate to save.
        case searchWithoutCoordinate
    }

    // MARK: - Entry point

    static func parse(_ url: URL) -> Swift.Result<Result, Failure> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return .failure(.unrecognised)
        }
        let host = (components.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()

        // geo:lat,lon — the Android/RFC form, also produced by some share sheets.
        if scheme == "geo" {
            guard let result = parseGeoScheme(url) else { return .failure(.unrecognised) }
            return .success(result)
        }

        // Google's short links resolve to a real URL by HTTP redirect and carry nothing themselves.
        if host.hasSuffix("goo.gl") || host == "maps.app.goo.gl" {
            return .failure(.needsRedirect(url))
        }

        if host.contains("apple") || scheme == "maps" {
            return parseAppleMaps(components)
        }
        if host.contains("google") {
            return parseGoogleMaps(components, path: url.path)
        }
        return .failure(.unrecognised)
    }

    /// Whether following a redirect is worth attempting for this URL.
    static func requiresRedirect(_ url: URL) -> Bool {
        if case .failure(.needsRedirect) = parse(url) { return true }
        return false
    }

    // MARK: - Apple Maps

    /// `maps.apple.com/?ll=51.5,-0.12&q=Name`, `?sll=`, `?daddr=`, or `maps://?ll=`.
    private static func parseAppleMaps(_ components: URLComponents) -> Swift.Result<Result, Failure> {
        let items = components.queryItems ?? []
        func value(_ names: String...) -> String? {
            for name in names {
                if let found = items.first(where: { $0.name.lowercased() == name })?.value,
                   !found.isEmpty {
                    return found
                }
            }
            return nil
        }

        let name = value("q", "name").flatMap(placeName(from:))

        // `ll` is the map centre, `sll` a search origin, `daddr` a destination. In that order of
        // trust: `daddr` is where you asked to go, so it wins when present.
        for key in ["daddr", "ll", "sll", "coordinate"] {
            if let raw = value(key), let coordinate = coordinatePair(raw) {
                return .success(Result(coordinate: coordinate, name: name))
            }
        }
        // `q` sometimes *is* the coordinate rather than a label.
        if let raw = value("q"), let coordinate = coordinatePair(raw) {
            return .success(Result(coordinate: coordinate, name: nil))
        }
        // A named place with an address but no coordinate — a search, not a location.
        if name != nil || value("address") != nil {
            return .failure(.searchWithoutCoordinate)
        }
        return .failure(.unrecognised)
    }

    // MARK: - Google Maps

    /// `google.com/maps/place/Name/@51.5,-0.12,15z`, `/maps?q=51.5,-0.12`, `/maps/@lat,lon,z`,
    /// and the `?destination=` form used by directions links.
    private static func parseGoogleMaps(
        _ components: URLComponents,
        path: String
    ) -> Swift.Result<Result, Failure> {
        let items = components.queryItems ?? []
        func value(_ names: String...) -> String? {
            for name in names {
                if let found = items.first(where: { $0.name.lowercased() == name })?.value,
                   !found.isEmpty {
                    return found
                }
            }
            return nil
        }

        // The path name segment, when there is one: /maps/place/Ravana+Falls/@...
        let segments = path.split(separator: "/").map(String.init)
        var name: String?
        if let placeIndex = segments.firstIndex(of: "place"), placeIndex + 1 < segments.count {
            let candidate = segments[placeIndex + 1]
            // The @-segment is the coordinate, not a name.
            if !candidate.hasPrefix("@") { name = placeName(from: candidate) }
        }

        // Explicit query coordinates beat the map centre: `q`/`destination` is the place, `@` is
        // wherever the viewport happened to be.
        for key in ["destination", "q", "query", "daddr", "ll", "center"] {
            if let raw = value(key), let coordinate = coordinatePair(raw) {
                return .success(Result(coordinate: coordinate, name: name))
            }
        }

        // The @lat,lon,zoom segment.
        if let atSegment = segments.first(where: { $0.hasPrefix("@") }) {
            let trimmed = String(atSegment.dropFirst())
            if let coordinate = coordinatePair(trimmed) {
                return .success(Result(coordinate: coordinate, name: name))
            }
        }

        if name != nil || value("q", "query", "destination") != nil {
            return .failure(.searchWithoutCoordinate)
        }
        return .failure(.unrecognised)
    }

    // MARK: - geo:

    private static func parseGeoScheme(_ url: URL) -> Result? {
        // geo:51.5,-0.12 — the pair sits in the opaque part, with optional ;u= and ?q= after it.
        let body = url.absoluteString.dropFirst("geo:".count)
        let head = body.split(separator: "?").first ?? body
        let pair = head.split(separator: ";").first ?? head
        guard let coordinate = coordinatePair(String(pair)) else { return nil }
        return Result(coordinate: coordinate, name: nil)
    }

    // MARK: - Shared parsing

    /// A "lat,lon" pair, tolerating whitespace, a trailing zoom segment, and `+` for space.
    ///
    /// Rejects out-of-range values rather than clamping. A link that says latitude 200 is not a link
    /// about a place near the pole; it is a link this parser does not understand, and saying so beats
    /// dropping a pin in the sea.
    static func coordinatePair(_ raw: String) -> Coordinate? {
        let cleaned = raw
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180
        else { return nil }
        // 0,0 is in the Gulf of Guinea and is almost always a missing value rather than a place.
        if latitude == 0, longitude == 0 { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Turns a URL path or query fragment into something worth showing as a name.
    static func placeName(from raw: String) -> String? {
        let decoded = raw
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? raw
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        // A coordinate is not a name, even when it arrives in the name slot.
        if coordinatePair(trimmed) != nil { return nil }
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        return trimmed
    }
}

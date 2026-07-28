import Foundation
import Observation

/// Where the app is, and what it has been asked to show.
///
/// Deep links, Spotlight results, widget taps and Siri all arrive as "show me this spot", from
/// four different directions. They all land here so the rest of the app only has to understand
/// one of them.
@Observable
final class AppRouter {

    enum Tab: String, CaseIterable, Identifiable {
        case spots
        case map
        case trips

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spots: return "Spots"
            case .map: return "Map"
            case .trips: return "Trips"
            }
        }

        var symbol: String {
            switch self {
            case .spots: return "photo.stack"
            case .map: return "map"
            case .trips: return "suitcase.fill"
            }
        }
    }

    var tab: Tab = .spots

    /// The spot whose arrow screen is showing, if any.
    var activeSpotID: UUID?

    /// A coordinate opened from a shared link that does not exist in this library yet. The
    /// arrow still works, and the person is offered the chance to save it.
    var guestDestination: GuestDestination?

    var isShowingCapture = false
    var isShowingSettings = false
    var isShowingSaveHere = false
    var isShowingImporter = false

    /// Set when a link referenced a spot we do not have, so the UI can say so rather than
    /// silently doing nothing.
    var unresolvedLinkMessage: String?

    struct GuestDestination: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var coordinate: Coordinate
    }

    // MARK: - Entry points

    func openSpot(id: UUID) {
        guestDestination = nil
        activeSpotID = id
    }

    func openSpot(identifier: String) {
        guard let id = UUID(uuidString: identifier) else { return }
        openSpot(id: id)
    }

    func openGuest(name: String, coordinate: Coordinate) {
        activeSpotID = nil
        guestDestination = GuestDestination(name: name, coordinate: coordinate)
    }

    func dismissDestination() {
        activeSpotID = nil
        guestDestination = nil
    }

    /// Handles `tradewind://spot?id=…&lat=…&lon=…&name=…`.
    ///
    /// The id is used when the spot is in this library; the coordinates are the fallback, which
    /// is what makes a shared link work for someone who has never seen the photo.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == AppGroup.urlScheme else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        switch url.host?.lowercased() {
        case "spot":
            if let idString = value("id"), let id = UUID(uuidString: idString) {
                openSpot(id: id)
                return
            }
            openCoordinateFromLink(value: value)

        case "here", "capture":
            isShowingCapture = true

        case "settings":
            isShowingSettings = true

        default:
            openCoordinateFromLink(value: value)
        }
    }

    private func openCoordinateFromLink(value: (String) -> String?) {
        guard let latitude = value("lat").flatMap(Double.init),
              let longitude = value("lon").flatMap(Double.init)
        else {
            unresolvedLinkMessage = "That link didn't include a place."
            return
        }
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else {
            unresolvedLinkMessage = "That link pointed somewhere impossible."
            return
        }
        openGuest(name: value("name") ?? "Shared spot", coordinate: coordinate)
    }
}

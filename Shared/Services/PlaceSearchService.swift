import Foundation
import MapKit
import Observation

/// As-you-type place and address search, for saving somewhere you are not standing.
///
/// Backed by `MKLocalSearchCompleter` — Apple's autocomplete: free at any scale, no key,
/// worldwide, the same engine Apple Maps' search box uses. Suggestions are biased toward the
/// current location when there is one, so "harbour hotel" finds yours before Sydney's.
///
/// Main-actor bound: the completer calls back on the main queue and every consumer is a view.
@MainActor
@Observable
final class PlaceSearchService: NSObject, MKLocalSearchCompleterDelegate {

    struct Suggestion: Identifiable, Equatable {
        let id: Int
        let title: String
        let subtitle: String
    }

    private let completer = MKLocalSearchCompleter()
    /// Kept alongside the display rows: resolution needs the original completion object.
    private var completions: [MKLocalSearchCompletion] = []

    private(set) var suggestions: [Suggestion] = []

    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            if AppSettings.isUITesting {
                // The CI simulator's network is not a test dependency worth having: any
                // non-empty query yields one canned suggestion, resolved to a fixed place.
                suggestions = query.isEmpty ? [] : [
                    Suggestion(id: 0, title: "Test Palace", subtitle: "Canned Road, London")
                ]
                return
            }
            if query.isEmpty {
                suggestions = []
                completions = []
                completer.cancel()
            } else {
                completer.queryFragment = query
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        if let coordinate = LocationService.shared.coordinate {
            completer.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = results
            self.suggestions = results.prefix(8).enumerated().map { index, completion in
                Suggestion(id: index, title: completion.title, subtitle: completion.subtitle)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // A failed autocomplete round is not worth surfacing; the next keystroke retries.
    }

    /// Resolves a picked suggestion to a coordinate, an area line, and a kind guess.
    func resolve(_ suggestion: Suggestion) async -> PlannedPlace.Resolved? {
        if AppSettings.isUITesting {
            return PlannedPlace.Resolved(
                name: "Test Palace",
                coordinate: Coordinate(latitude: 51.5014, longitude: -0.1419),
                areaLine: "Canned Road, London",
                kindGuess: .viewpoint
            )
        }
        guard suggestion.id < completions.count else { return nil }
        let request = MKLocalSearch.Request(completion: completions[suggestion.id])
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first
        else { return nil }

        let placemark = item.placemark
        let areaLine = PlaceNameFormatter.line(from: PlaceFields(
            thoroughfare: placemark.thoroughfare,
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country
        ))
        return PlannedPlace.Resolved(
            name: PlannedPlace.name(fromTitle: item.name ?? suggestion.title, areaLine: areaLine),
            coordinate: Coordinate(
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            ),
            areaLine: areaLine,
            kindGuess: PlannedPlace.kind(forCategoryRaw: item.pointOfInterestCategory?.rawValue)
        )
    }
}

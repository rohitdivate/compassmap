import ActivityKit
import Foundation

/// The Live Activity: "you are on your way to X, and it is this far".
///
/// Shared between the app (which starts and updates it) and the widget extension (which draws
/// it). Kept small — every update crosses a process boundary, and ActivityKit throttles
/// generous payloads harder than lean ones.
struct HeadingActivityAttributes: ActivityAttributes {

    /// The part that changes as you walk.
    public struct ContentState: Codable, Hashable {
        /// Distance remaining, in metres.
        public var distanceMetres: Double
        /// Absolute bearing to the spot, degrees from north. Drawn as a fixed arrow: a Live
        /// Activity cannot follow the magnetometer, so it shows the compass direction rather
        /// than pretending to be a live compass.
        public var bearing: Double
        public var isArrived: Bool
        public var updatedAt: Date

        public init(
            distanceMetres: Double,
            bearing: Double,
            isArrived: Bool = false,
            updatedAt: Date = Date()
        ) {
            self.distanceMetres = distanceMetres
            self.bearing = bearing
            self.isArrived = isArrived
            self.updatedAt = updatedAt
        }
    }

    public var spotID: UUID
    public var spotName: String
    public var placeName: String?
    /// So the Live Activity matches whatever theme the app is wearing.
    public var themeID: String
    /// `UnitPreference.rawValue`, passed as a string to keep the attributes trivially Codable.
    public var unitPreferenceRaw: String

    public init(
        spotID: UUID,
        spotName: String,
        placeName: String? = nil,
        themeID: String,
        unitPreferenceRaw: String
    ) {
        self.spotID = spotID
        self.spotName = spotName
        self.placeName = placeName
        self.themeID = themeID
        self.unitPreferenceRaw = unitPreferenceRaw
    }

    var unitPreference: UnitPreference {
        UnitPreference(rawValue: unitPreferenceRaw) ?? .automatic
    }
}

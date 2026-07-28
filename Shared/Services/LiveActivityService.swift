import ActivityKit
import Foundation
import Observation

/// Starts, updates and ends the "heading there" Live Activity.
///
/// Updates are throttled: ActivityKit will quietly start dropping them if an app pushes on
/// every location fix, and a distance that refreshes every twenty metres is indistinguishable
/// from one that refreshes every metre when it is living in the Dynamic Island.
///
/// The activity owns its own update source: starting one starts an `ActivityUpdateDriver`,
/// which holds background location open for the walk and pushes on every fix. Ending the
/// activity — arrival or by hand — tears the driver down with it, so background GPS can never
/// outlive the card that justified it.
@Observable
@MainActor
final class LiveActivityService {

    static let shared = LiveActivityService()

    @ObservationIgnored private var activity: Activity<HeadingActivityAttributes>?
    @ObservationIgnored private var lastPush: ActivityPushPolicy.LastPush?
    @ObservationIgnored private var driver: ActivityUpdateDriver?

    private(set) var activeSpotID: UUID?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool { activity != nil }

    private init() {}

    // MARK: - Lifecycle

    @discardableResult
    func start(
        spotID: UUID,
        spotName: String,
        placeName: String?,
        coordinate: Coordinate,
        distanceMetres: Double,
        bearing: Double,
        themeID: String,
        unitPreference: UnitPreference
    ) -> Bool {
        guard isSupported else { return false }
        if activeSpotID == spotID, isRunning { return true }
        end()

        let attributes = HeadingActivityAttributes(
            spotID: spotID,
            spotName: spotName,
            placeName: placeName,
            themeID: themeID,
            unitPreferenceRaw: unitPreference.rawValue,
            // Fixed for the life of the walk, so the progress bar can measure against where you
            // actually set out from instead of a made-up kilometre.
            startingDistanceMetres: distanceMetres
        )
        let state = HeadingActivityAttributes.ContentState(
            distanceMetres: distanceMetres,
            bearing: bearing
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 20)),
                pushType: nil
            )
            activeSpotID = spotID
            lastPush = ActivityPushPolicy.LastPush(
                at: Date(),
                distanceMetres: distanceMetres,
                bearingDegrees: bearing
            )
            let driver = ActivityUpdateDriver(target: coordinate, service: self)
            self.driver = driver
            driver.start()
            return true
        } catch {
            print("[Tradewind] could not start Live Activity: \(error)")
            return false
        }
    }

    func update(distanceMetres: Double, bearing: Double, isArrived: Bool) {
        guard let activity else { return }

        let now = Date()
        guard ActivityPushPolicy.shouldPush(
            distanceMetres: distanceMetres,
            bearingDegrees: bearing,
            isArrived: isArrived,
            last: lastPush,
            now: now
        ) else { return }

        lastPush = ActivityPushPolicy.LastPush(
            at: now,
            distanceMetres: distanceMetres,
            bearingDegrees: bearing
        )

        let state = HeadingActivityAttributes.ContentState(
            distanceMetres: distanceMetres,
            bearing: bearing,
            isArrived: isArrived
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 20))
            )
        }
    }

    /// Ends with a final state, so the last thing shown on the Lock Screen is the arrival
    /// rather than a stale distance.
    func finish(distanceMetres: Double, bearing: Double) {
        guard let activity else { return }
        driver?.stop()
        driver = nil
        let state = HeadingActivityAttributes.ContentState(
            distanceMetres: distanceMetres,
            bearing: bearing,
            isArrived: true
        )
        self.activity = nil
        activeSpotID = nil
        lastPush = nil
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
        }
    }

    func end() {
        driver?.stop()
        driver = nil
        guard let activity else { return }
        self.activity = nil
        activeSpotID = nil
        lastPush = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

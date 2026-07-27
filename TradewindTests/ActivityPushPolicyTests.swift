import Testing
import Foundation

/// Guards the rule behind a Live Activity pointer that looked frozen.
///
/// The old policy required distance to have moved 20 m **and** 8 seconds to have passed, and never
/// looked at bearing. Walking pace makes 20 m about fifteen seconds, so turning a corner that swung
/// the direction sixty degrees moved the pointer not at all until the distance also changed.
@Suite("Live Activity push policy")
struct ActivityPushPolicyTests {

    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    private func last(
        secondsAgo: TimeInterval,
        distance: Double,
        bearing: Double
    ) -> ActivityPushPolicy.LastPush {
        ActivityPushPolicy.LastPush(
            at: origin.addingTimeInterval(-secondsAgo),
            distanceMetres: distance,
            bearingDegrees: bearing
        )
    }

    private func shouldPush(
        distance: Double,
        bearing: Double,
        isArrived: Bool = false,
        last: ActivityPushPolicy.LastPush?
    ) -> Bool {
        ActivityPushPolicy.shouldPush(
            distanceMetres: distance,
            bearingDegrees: bearing,
            isArrived: isArrived,
            last: last,
            now: origin
        )
    }

    // MARK: - The regression

    @Test("A direction change with no distance change pushes")
    func bearingSwingAlonePushes() {
        // The reported bug: rounding a corner. Same distance, sixty degrees of swing.
        let previous = last(secondsAgo: 5, distance: 400, bearing: 20)
        #expect(shouldPush(distance: 400, bearing: 80, last: previous))
    }

    @Test("A distance change with no direction change also pushes")
    func distanceAloneStillPushes() {
        let previous = last(secondsAgo: 5, distance: 400, bearing: 20)
        #expect(shouldPush(distance: 380, bearing: 20, last: previous))
    }

    // MARK: - Not spending the budget on noise

    @Test("Jitter below both thresholds is ignored")
    func jitterIsIgnored() {
        let previous = last(secondsAgo: 5, distance: 400, bearing: 20)
        // Two metres at 400 m out is under the 10 m threshold, and two degrees is under four.
        #expect(shouldPush(distance: 398, bearing: 22, last: previous) == false)
    }

    @Test("Nothing pushes inside the minimum interval, however much changed")
    func intervalFloorHolds() {
        let previous = last(secondsAgo: 0.5, distance: 400, bearing: 20)
        // A big swing and a big move, but too soon: ActivityKit drops updates from apps that spend
        // their budget this fast, which would make the card stop updating altogether.
        #expect(shouldPush(distance: 100, bearing: 200, last: previous) == false)
    }

    @Test("Arrival ignores the floor entirely")
    func arrivalAlwaysPushes() {
        let previous = last(secondsAgo: 0.1, distance: 400, bearing: 20)
        #expect(shouldPush(distance: 8, bearing: 20, isArrived: true, last: previous))
        // Even with no previous push at all.
        #expect(shouldPush(distance: 8, bearing: 20, isArrived: true, last: nil))
    }

    @Test("The first update always goes out")
    func firstPushAlwaysGoes() {
        #expect(shouldPush(distance: 400, bearing: 20, last: nil))
    }

    @Test("A long quiet spell pushes anyway, so the card never looks abandoned")
    func heartbeat() {
        let previous = last(secondsAgo: 45, distance: 400, bearing: 20)
        #expect(shouldPush(distance: 400, bearing: 20, last: previous))
    }

    // MARK: - Closing in

    @Test("Thresholds tighten as you get close")
    func thresholdTightensNearTarget() {
        // The last stretch is where the readout is watched hardest, and where 25 m would be the
        // entire remaining walk.
        #expect(ActivityPushPolicy.distanceThreshold(forRemaining: 30) < ActivityPushPolicy.distanceThreshold(forRemaining: 500))
        #expect(ActivityPushPolicy.distanceThreshold(forRemaining: 500) < ActivityPushPolicy.distanceThreshold(forRemaining: 5_000))
    }

    @Test("A three-metre step matters at thirty metres out but not at three kilometres")
    func sameStepDifferentMeaning() {
        let near = last(secondsAgo: 5, distance: 30, bearing: 20)
        #expect(shouldPush(distance: 27, bearing: 20, last: near))

        let far = last(secondsAgo: 5, distance: 3_000, bearing: 20)
        #expect(shouldPush(distance: 2_997, bearing: 20, last: far) == false)
    }

    // MARK: - Angles are on a circle

    @Test("Bearing deltas take the short way round north")
    func angleWrapping() {
        // 358 to 2 is four degrees, not 356. Getting this wrong would push on every crossing of north.
        #expect(ActivityPushPolicy.shortestAngleDelta(358, 2) == 4)
        #expect(ActivityPushPolicy.shortestAngleDelta(2, 358) == 4)
        #expect(ActivityPushPolicy.shortestAngleDelta(0, 180) == 180)
        #expect(ActivityPushPolicy.shortestAngleDelta(90, 90) == 0)
        #expect(ActivityPushPolicy.shortestAngleDelta(10, 350) == 20)
    }

    @Test("Crossing north with a small real change is not treated as a huge swing")
    func crossingNorthIsQuiet() {
        let previous = last(secondsAgo: 5, distance: 400, bearing: 359)
        #expect(shouldPush(distance: 400, bearing: 1, last: previous) == false)
    }
}

/// The progress bar used to measure against a hardcoded kilometre.
@Suite("Live Activity progress")
struct ActivityProgressMathTests {

    @Test("Nothing walked yet reads as zero")
    func atTheStart() {
        #expect(ActivityProgressMath.fraction(remaining: 800, startingFrom: 800) == 0)
    }

    @Test("Arrival reads as complete")
    func atTheEnd() {
        #expect(ActivityProgressMath.fraction(remaining: 0, startingFrom: 800) == 1)
    }

    @Test("Halfway reads as half")
    func halfway() {
        #expect(ActivityProgressMath.fraction(remaining: 400, startingFrom: 800) == 0.5)
    }

    @Test("Walking away from it does not produce negative progress")
    func movingAwayClamps() {
        // Overshooting the start is normal — you might set off in the wrong direction.
        #expect(ActivityProgressMath.fraction(remaining: 1_200, startingFrom: 800) == 0)
    }

    @Test("Overshooting past the target clamps at complete")
    func overshootClamps() {
        #expect(ActivityProgressMath.fraction(remaining: -50, startingFrom: 800) == 1)
    }

    @Test("With no starting distance there is no bar, rather than a misleading one")
    func missingStartYieldsNil() {
        // An activity started by an older build decodes with this absent. Drawing a bar from a made-up
        // reference is what this replaced, so it must not silently reappear.
        #expect(ActivityProgressMath.fraction(remaining: 400, startingFrom: nil) == nil)
        #expect(ActivityProgressMath.fraction(remaining: 400, startingFrom: 0) == nil)
    }
}

import Foundation
import Testing

/// The frame is the compass screen's entire vocabulary, and its equality is the throttle:
/// the engine publishes a frame only when it differs from the last one, so anything that
/// changes when it shouldn't re-renders half a screen at 30 Hz, and anything that fails to
/// change freezes a readout mid-walk.
@Suite("Compass frame")
struct CompassFrameTests {

    private func frame(
        bearing: Double? = 312.4,
        metres: Double? = 180,
        offBy: Double? = 42,
        usable: Bool = true,
        elevation: Double? = nil,
        wasArrived: Bool = false
    ) -> CompassFrame {
        CompassFrame.make(
            bearing: bearing,
            distanceMetres: metres,
            offBy: offBy,
            headingIsUsable: usable,
            elevationDeltaMetres: elevation,
            wasArrived: wasArrived,
            unitPreference: .metric,
            locale: Locale(identifier: "en_GB")
        )
    }

    // MARK: - Quantization equality (the throttle)

    @Test("Sub-display jitter produces an equal frame")
    func jitterIsInvisible() {
        // 0.3° of bearing wobble and 20 cm of GPS drift — nothing on screen changes.
        #expect(frame(bearing: 312.4, metres: 180.2, offBy: 42.3)
            == frame(bearing: 312.1, metres: 180.4, offBy: 42.4))
    }

    @Test("Crossing a display boundary produces an unequal frame")
    func boundariesPublish() {
        #expect(frame(offBy: 42.4) != frame(offBy: 43.6))          // whole-degree hint
        #expect(frame(metres: 180) != frame(metres: 172))          // proximity band (8 m)
        #expect(frame(metres: 999) != frame(metres: 1_001))        // "999 m" -> "1 km"
    }

    @Test("A still phone at the same fix is one frame forever")
    func stillPhoneIsQuiet() {
        let a = frame()
        let b = frame()
        #expect(a == b)
    }

    // MARK: - On target

    @Test("On target within the tolerance, off outside it")
    func onTargetTolerance() {
        #expect(frame(offBy: 7.9).onTarget)
        #expect(frame(offBy: -7.9).onTarget)
        #expect(!frame(offBy: 8.6).onTarget)
    }

    // MARK: - Arrival hysteresis

    @Test("Arrival enters at the radius and holds until well clear")
    func arrivalHysteresis() {
        #expect(CompassFrame.arrived(previous: false, metres: 24))
        #expect(!CompassFrame.arrived(previous: false, metres: 26))
        // Between the radius and the exit radius, the previous answer stands.
        #expect(CompassFrame.arrived(previous: true, metres: 40))
        #expect(!CompassFrame.arrived(previous: false, metres: 40))
        // Beyond 2.5x the radius, arrived always ends.
        #expect(!CompassFrame.arrived(previous: true, metres: 63))
    }

    // MARK: - Turn hint

    @Test("Turn hint covers the four states and the headingless fallback")
    func turnHints() {
        #expect(CompassFrame.turnHint(offBy: 3, bearing: 90, headingIsUsable: true) == "Straight ahead")
        #expect(CompassFrame.turnHint(offBy: 40, bearing: 90, headingIsUsable: true) == "Turn right")
        #expect(CompassFrame.turnHint(offBy: -40, bearing: 90, headingIsUsable: true) == "Turn left")
        #expect(CompassFrame.turnHint(offBy: 170, bearing: 90, headingIsUsable: true) == "It's behind you")
        #expect(CompassFrame.turnHint(offBy: 40, bearing: 90, headingIsUsable: false) == "Head E")
        #expect(CompassFrame.turnHint(offBy: nil, bearing: nil, headingIsUsable: true) == "Looking for a signal")
    }

    // MARK: - Proximity bands

    @Test("Proximity is banded in 2% steps of the range")
    func proximitySteps() {
        #expect(CompassFrame.proximityStep(forMetres: 400) == 0)
        #expect(CompassFrame.proximityStep(forMetres: 1_000) == 0)   // beyond the range clamps
        #expect(CompassFrame.proximityStep(forMetres: 0) == 50)
        #expect(CompassFrame.proximityStep(forMetres: 200) == 25)
    }

    // MARK: - Formatted strings ride along

    @Test("Distance, bearing label and elevation are pre-formatted")
    func formattedStrings() {
        let f = frame(bearing: 312.4, metres: 1_240, elevation: 48)
        #expect(f.distanceText == DistanceReadout(value: "1.2", unit: "km"))
        #expect(f.bearingLabel == "NW 312°")
        #expect(f.elevationText == "48 m above you")
    }

    @Test("No fix means empty readouts and a waiting hint")
    func noFix() {
        let f = frame(bearing: nil, metres: nil, offBy: nil)
        #expect(f.distanceText == nil)
        #expect(f.bearingLabel == nil)
        #expect(f.turnHint == "Looking for a signal")
        #expect(!f.onTarget)
        #expect(!f.hasArrived)
    }

    // MARK: - VoiceOver

    @Test("Accessibility description speaks distance, compass point and direction")
    func accessibility() {
        let f = frame(bearing: 90, metres: 120, offBy: 30)
        let text = f.accessibilityDescription(spotName: "The Cafe")
        #expect(text.contains("The Cafe"))
        #expect(text.contains("120 m"))
        #expect(text.contains("E"))
        #expect(text.contains("30 degrees to your right"))

        let locked = frame(bearing: 90, metres: 120, offBy: 2)
        #expect(locked.accessibilityDescription(spotName: "The Cafe").contains("straight ahead"))

        let waiting = frame(bearing: nil, metres: nil, offBy: nil)
        #expect(waiting.accessibilityDescription(spotName: "The Cafe")
            == "The Cafe. Waiting for your location.")
    }
}

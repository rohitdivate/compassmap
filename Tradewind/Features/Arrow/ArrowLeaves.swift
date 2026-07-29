import SwiftUI

/// The arrow screen's leaves — each one owns exactly the engine reads it draws.
///
/// The rule that keeps the screen fast: `ArrowScreen` itself reads *nothing* from the
/// compass engine, so the view that hosts the overflow menu and the detail sheet is never
/// invalidated by a heading tick. Views that genuinely change at dial rate (the rose, the
/// arrow, the backdrop parallax) read `DialState`; everything else reads the change-guarded
/// `TargetSolution` and updates a few times a minute.

// MARK: - Backdrop

/// The photo, pushed out of focus and drifting with the arrow. It is the reason the screen
/// feels like a place rather than a readout.
struct ArrowBackdrop: View {
    var theme: Theme
    var destination: ArrowDestination
    var dial: DialState

    @State private var timeOfDay = TimeOfDay.current(at: nil)

    var body: some View {
        ZStack {
            // No photo (a spot saved from a shared link) still gets a hero: the mood's own gradient
            // in Spritz — following the sky outside — its deep surface in Nomad.
            Rectangle()
                .fill(theme.heroFill(for: timeOfDay))
                .ignoresSafeArea()

            if let spot = destination.spot, spot.thumbnailFilename != nil {
                blurredPhoto(spot)
            }

            // The photo is the hero here, so the scrim is dark and the text on top is white —
            // in both moods. A cream scrim over a photograph washes it out, and this screen is
            // the one place the design's "one gradient, behind a photo" rule clearly applies.
            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.05), .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            timeOfDay = TimeOfDay.current(at: LocationService.shared.coordinate)
        }
    }

    /// The destination photo, out of focus and drifting a little with the arrow. The parallax
    /// angle is quantized to 3° in `DialState` — enough to feel physical, coarse enough that
    /// the blur is not re-composited thirty times a second. `.hero` shares its decode with the
    /// gallery's featured card and the detail sheet, so opening the arrow from either is free.
    private func blurredPhoto(_ spot: Spot) -> some View {
        let radians = dial.parallaxAngle * .pi / 180
        return SpotPhotoView(spot: spot, sizeClass: .hero)
            .scaleEffect(1.25)
            .blur(radius: 44, opaque: false)
            .opacity(0.5)
            .offset(x: CGFloat(sin(radians)) * -16, y: CGFloat(cos(radians)) * -10)
            .animation(.smooth(duration: 0.6), value: dial.parallaxAngle)
            .ignoresSafeArea()
    }
}

// MARK: - Turn hint

/// The eyebrow line above the title. Its own view so the title block — which shares a bar
/// with the overflow menu — does not update when the advice changes.
struct TurnHintLabel: View {
    var theme: Theme
    var solution: TargetSolution

    var body: some View {
        Text(solution.frame.turnHint).eyebrowStyle(theme: theme)
    }
}

// MARK: - Compass cluster

/// Rings, rose, arrow and the arrival stamp — the one part of the screen that is *supposed*
/// to move at dial rate.
struct CompassCluster: View {
    var theme: Theme
    var dial: DialState
    var solution: TargetSolution
    var destinationName: String

    var body: some View {
        let frame = solution.frame
        ZStack {
            if !frame.hasArrived {
                RadarRings(theme: theme, diameter: 340)
                    .opacity(0.5 + frame.proximity * 0.4)
            }

            CompassRose(
                theme: theme,
                heading: frame.headingIsUsable ? dial.roseAngle : 0,
                targetBearing: frame.bearingDegrees.map(Double.init),
                onTarget: frame.onTarget,
                diameter: 300,
                onPhoto: true
            )

            DirectionArrow(
                theme: theme,
                angle: dial.arrowAngle,
                onTarget: frame.onTarget,
                proximity: frame.proximity,
                size: 176
            )

            if frame.hasArrived {
                ArrivalStamp(theme: theme, title: "You made it", subtitle: destinationName)
                    .offset(y: 128)
            }
        }
        .frame(height: 340)
        .accessibilityElement()
        .accessibilityLabel(frame.accessibilityDescription(spotName: destinationName))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Distance readout

struct DistanceReadoutView: View {
    var theme: Theme
    var solution: TargetSolution

    @State private var location = LocationService.shared

    var body: some View {
        if let distance = solution.frame.distanceText {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(distance.value)
                    .font(theme.heroNumberFont(heroFontSize(for: distance.value)))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                Text(distance.unit)
                    .font(theme.mono(26))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 6)
            }
            .animation(.snappy(duration: 0.25), value: distance.value)
        } else {
            VStack(spacing: 6) {
                // The spinner is the other animation that never ends: a simulator has no fix, so
                // under the test seam it would keep the app from ever idling for XCUITest.
                if !AppSettings.isUITesting {
                    ProgressView().tint(theme.accent)
                }
                Text(location.isAuthorized ? "Finding you" : "Location is off")
                    .font(theme.captionFont)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(height: 80)
        }
    }

    /// Big numbers get a smaller face so "1,240" does not run off the edge.
    private func heroFontSize(for value: String) -> CGFloat {
        switch value.count {
        case 0...3: return 96
        case 4: return 84
        case 5: return 72
        default: return 62
        }
    }
}

// MARK: - Pills

struct ArrowPills: View {
    var theme: Theme
    var solution: TargetSolution
    var walkingRoute: WalkingRouteService.Answer?
    var unitPreference: UnitPreference

    var body: some View {
        HStack(spacing: 8) {
            walkingPill
            if let elevation = solution.frame.elevationText {
                PillLabel(text: elevation, symbol: "mountain.2.fill")
            }
            if let bearing = solution.frame.bearingLabel {
                PillLabel(text: bearing, symbol: "location.north.line.fill")
            }
        }
    }

    /// A routed walk states itself as fact; the estimate admits the tilde.
    @ViewBuilder
    private var walkingPill: some View {
        switch RoutePolicy.readout(
            routeMetres: walkingRoute?.distanceMetres,
            routeSeconds: walkingRoute?.expectedSeconds,
            crowMetres: solution.frame.crowMetres
        ) {
        case .routed(let minutes, let metres):
            PillLabel(
                text: "\(minutes) min · \(DistanceFormatting.string(metres: metres, preference: unitPreference)) on foot",
                symbol: "figure.walk"
            )
        case .estimated(let minutes):
            PillLabel(text: "~\(minutes) min walk", symbol: "figure.walk")
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Status note

/// The one line of small print, when there is something honest to say about the reading.
struct ArrowStatusNote: View {
    var theme: Theme
    var solution: TargetSolution
    var destination: ArrowDestination

    @State private var location = LocationService.shared

    var body: some View {
        if solution.frame.hasArrived {
            noteText(arrivalNote, .white.opacity(0.72))
        } else if !solution.frame.headingIsUsable {
            noteText("No compass reading — showing the direction from north instead.", .white.opacity(0.7))
        } else if location.needsCalibration {
            noteText(
                "Magnetic interference. Move away from metal, or wave the phone in a figure of eight.",
                theme.secondary
            )
        } else if let accuracy = solution.accuracyBucket, accuracy > 40 {
            noteText("Rough fix — accurate to about \(accuracy) m", .white.opacity(0.7))
        }
    }

    /// Arrival is the one moment the screen can say something other than a measurement.
    private var arrivalNote: String {
        // The note you left yourself outranks everything: "Level 3, aisle F" is the payload of a
        // parking spot, and arrival is precisely when it is needed.
        if let note = destination.spot?.note, !note.isEmpty {
            return note
        }
        guard let spot = destination.spot else {
            return "Close enough to see it."
        }
        if !spot.hasPhoto {
            return "You're back. Saved \(spot.placeKind.label.lowercased()) — this is the place."
        }
        let days = Calendar.current.dateComponents([.day], from: spot.capturedAt, to: Date()).day ?? 0
        switch days {
        case ..<1: return "Close enough to see it. You photographed this today."
        case 1: return "Close enough to see it. You photographed this yesterday."
        default: return "Close enough to see it. You photographed this spot \(days) days ago."
        }
    }

    private func noteText(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(theme.captionFont)
            .foregroundStyle(colour)
            .multilineTextAlignment(.center)
            // Wraps rather than truncates: "showing the direction fro…" helps nobody.
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Actions

struct ArrowActionsView: View {
    var solution: TargetSolution
    var destination: ArrowDestination
    var onTakeAnotherPhoto: () -> Void
    var onClose: () -> Void
    var onStartTracking: () -> Void
    var onSaveGuest: () -> Void

    @State private var liveActivity = LiveActivityService.shared

    var body: some View {
        if solution.frame.hasArrived {
            arrivalActions
        } else {
            trackingActions
        }
    }

    /// You are standing on it. Offering to track it on the Lock Screen is the one thing that no
    /// longer makes sense, so arrival replaces the bar rather than adding to it.
    private var arrivalActions: some View {
        VStack(spacing: 10) {
            if destination.spot?.hasPhoto ?? true {
                PrimaryButton(title: "Take another photo here", symbol: "camera.fill") {
                    onTakeAnotherPhoto()
                }
            }
            SecondaryButton(title: "Back to my spots", symbol: "chevron.left", onPhoto: true) {
                onClose()
            }
        }
    }

    private var trackingActions: some View {
        HStack(spacing: 10) {
            if liveActivity.isSupported {
                if liveActivity.isRunning, liveActivity.activeSpotID == destination.id {
                    SecondaryButton(title: "Stop tracking", symbol: "stop.circle") {
                        liveActivity.end()
                    }
                } else {
                    PrimaryButton(title: "Track on Lock Screen", symbol: "bolt.badge.clock") {
                        onStartTracking()
                    }
                }
            }

            if destination.spot == nil {
                PrimaryButton(title: "Save this spot", symbol: "plus.circle.fill") {
                    onSaveGuest()
                }
            }
        }
    }
}

// MARK: - Event bridge

/// A zero-size view that owns the screen's `.onChange` reactions to the engine, so those
/// observation dependencies never attach to the screen itself.
struct EngineEventBridge: View {
    var solution: TargetSolution
    var onTargetLock: (Bool) -> Void
    var onProximityChange: (Double) -> Void
    var onFrameChange: () -> Void
    var onArrivalChange: (Bool) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: solution.frame.onTarget) { _, isOnTarget in
                onTargetLock(isOnTarget)
            }
            .onChange(of: solution.frame.proximityStep) { _, _ in
                onProximityChange(solution.frame.proximity)
            }
            .onChange(of: solution.frame) { _, _ in
                onFrameChange()
            }
            .onChange(of: solution.frame.hasArrived) { _, arrived in
                onArrivalChange(arrived)
            }
    }
}

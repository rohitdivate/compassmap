import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// The screen the whole app exists for: an arrow, a distance, and the photo of where you are
/// going sitting behind both.
struct ArrowScreen: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    var destination: ArrowDestination
    var engine: CompassEngine
    var hero: Namespace.ID
    var onClose: () -> Void

    @State private var liveActivity = LiveActivityService.shared
    @State private var location = LocationService.shared
    @State private var celebrationStartedAt: Date?
    @State private var isShowingDetail = false
    @State private var hasAnnouncedArrival = false
    /// Area name for a guest destination — a coordinate from a shared link has no stored
    /// `placeName`, so it is resolved here and shown instead of raw degrees.
    @State private var guestArea: String?
    /// The real walking route, when Apple's router has answered. Nil shows the detour-factored
    /// estimate instead — the compass distance is a straight line and streets are not.
    @State private var walkingRoute: WalkingRouteService.Answer?
    @State private var lastRouteRequest: RoutePolicy.Request?

    private var store: SpotStore { SpotStore(context: modelContext) }

    // Split across two shorter modifier chains: one long chain carrying five closures was more
    // than the type-checker would take in one expression.
    var body: some View {
        screen
            .onChange(of: engine.onTarget) { _, isOnTarget in
                if isOnTarget { FeedbackService.shared.onTarget() }
            }
            .onChange(of: engine.proximity) { _, proximity in
                FeedbackService.shared.updatePulse(proximity: proximity)
            }
            .onChange(of: engine.distanceMetres) { _, _ in
                pushLiveActivityUpdate()
                refreshWalkingRoute()
            }
            .onChange(of: engine.hasArrived) { _, arrived in
                handleArrival(arrived)
            }
    }

    private var screen: some View {
        layers
            // Gives the overlay a surface so taps do not fall through to the gallery behind it.
            .background(Color.black.opacity(0.001))
            .onAppear(perform: begin)
            .onDisappear(perform: finish)
            .sheet(isPresented: $isShowingDetail) { detailSheet }
    }

    private var layers: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                compass
                Spacer(minLength: 8)
                readout
                actions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            if let celebrationStartedAt {
                CelebrationView(theme: theme, startedAt: celebrationStartedAt)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var detailSheet: some View {
        if let spot = destination.spot {
            SpotDetailView(spot: spot)
                .environment(settings)
                .environment(\.theme, theme)
        }
    }

    private func handleArrival(_ arrived: Bool) {
        guard arrived, !hasAnnouncedArrival else { return }
        hasAnnouncedArrival = true
        celebrationStartedAt = Date()
        FeedbackService.shared.arrived()
        FeedbackService.shared.stopPulsing()
        pushLiveActivityUpdate()
    }

    // MARK: - Backdrop

    /// The photo, pushed out of focus and drifting with the arrow. It is the reason the screen
    /// feels like a place rather than a readout.
    private var backdrop: some View {
        ZStack {
            // No photo (a spot saved from a shared link) still gets a hero: the mood's own gradient
            // in Spritz, its deep surface in Nomad.
            Rectangle().fill(theme.heroFill).ignoresSafeArea()

            if let photoData = destination.photoData {
                blurredPhoto(photoData)
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
    }

    /// The destination photo, out of focus and drifting a little with the arrow. The parallax is
    /// small on purpose — enough to feel physical, not enough to notice as an effect.
    private func blurredPhoto(_ data: Data) -> some View {
        let radians = engine.arrowAngle * .pi / 180
        return PhotoView(data: data, maxDimension: 1_200)
            .matchedGeometryEffect(id: "photo-\(destination.id)", in: hero)
            .scaleEffect(1.25)
            .blur(radius: 44, opaque: false)
            .opacity(0.5)
            .offset(x: CGFloat(sin(radians)) * -16, y: CGFloat(cos(radians)) * -10)
            .animation(.easeOut(duration: 0.6), value: engine.arrowAngle)
            .ignoresSafeArea()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onClose) {
                circularGlyph("chevron.down")
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")

            titleBlock
                .frame(maxWidth: .infinity, alignment: .leading)

            if let spot = destination.spot {
                overflowMenu(for: spot)
            }
        }
        .padding(.top, 6)
    }

    /// For a saved spot the title is a way into the details — a bigger, more obvious target than
    /// the overflow menu, and one XCUITest can actually drive: SwiftUI's `Menu` never reports its
    /// animations finished, so every interaction behind it stalls out the idle wait on CI.
    @ViewBuilder
    private var titleBlock: some View {
        if destination.spot != nil {
            Button {
                isShowingDetail = true
            } label: {
                titleContent
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("spot-title-button")
            .accessibilityHint("Shows this spot's details")
        } else {
            titleContent
        }
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(engine.turnHint()).eyebrowStyle(theme: theme)
            Text(destination.name)
                .font(theme.titleFont)
                .tracking(theme.displayTracking)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle = displaySubtitle {
                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
    }

    private func overflowMenu(for spot: Spot) -> some View {
        Menu {
            Button {
                store.setPinned(spot.isPinned ? nil : spot)
            } label: {
                Label(
                    spot.isPinned ? "Unpin from widgets" : "Pin to widgets",
                    systemImage: spot.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                isShowingDetail = true
            } label: {
                Label("Spot details", systemImage: "info.circle")
            }
            .accessibilityIdentifier("spot-details-item")
            if let url = spot.deepLinkURL {
                ShareLink(item: url) {
                    Label("Share this spot", systemImage: "square.and.arrow.up")
                }
            }
            Button(action: openInMaps) {
                Label("Open in Maps", systemImage: "map")
            }
        } label: {
            circularGlyph("ellipsis")
        }
        .accessibilityIdentifier("spot-more-button")
        .accessibilityLabel("More options")
    }

    /// The frosted circular button shape used by both controls in the bar.
    private func circularGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background { Circle().fill(.black.opacity(0.28)) }
    }

    // MARK: - Compass

    private var compass: some View {
        ZStack {
            if !engine.hasArrived {
                RadarRings(theme: theme, diameter: 340)
                    .opacity(0.5 + engine.proximity * 0.4)
            }

            CompassRose(
                theme: theme,
                heading: engine.headingIsUsable ? engine.roseAngle : 0,
                targetBearing: engine.bearing,
                onTarget: engine.onTarget,
                diameter: 300,
                onPhoto: true
            )

            DirectionArrow(
                theme: theme,
                angle: engine.arrowAngle,
                onTarget: engine.onTarget,
                proximity: engine.proximity,
                size: 176
            )

            if engine.hasArrived {
                ArrivalStamp(theme: theme, title: "You made it", subtitle: destination.name)
                    .offset(y: 128)
            }
        }
        .frame(height: 340)
        .accessibilityElement()
        .accessibilityLabel(engine.accessibilityDescription(spotName: destination.name))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Readout

    private var readout: some View {
        VStack(spacing: 10) {
            distanceBlock
            pills.frame(maxWidth: .infinity)
            statusNote
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var distanceBlock: some View {
        if let distance = engine.distanceReadout() {
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

    @ViewBuilder
    private var pills: some View {
        HStack(spacing: 8) {
            walkingPill
            if let elevation = engine.elevationText() {
                PillLabel(text: elevation, symbol: "mountain.2.fill")
            }
            if let bearing = engine.bearing {
                PillLabel(text: bearingLabel(bearing), symbol: "location.north.line.fill")
            }
        }
    }

    private func bearingLabel(_ bearing: Double) -> String {
        let point = BearingMath.compassPoint(forBearing: bearing)
        return "\(point) \(Int(bearing.rounded()))°"
    }

    /// A routed walk states itself as fact; the estimate admits the tilde.
    @ViewBuilder
    private var walkingPill: some View {
        switch RoutePolicy.readout(
            routeMetres: walkingRoute?.distanceMetres,
            routeSeconds: walkingRoute?.expectedSeconds,
            crowMetres: engine.distanceMetres
        ) {
        case .routed(let minutes, let metres):
            PillLabel(
                text: "\(minutes) min · \(DistanceFormatting.string(metres: metres, preference: settings.unitPreference)) on foot",
                symbol: "figure.walk"
            )
        case .estimated(let minutes):
            PillLabel(text: "~\(minutes) min walk", symbol: "figure.walk")
        case .none:
            EmptyView()
        }
    }

    /// Asks the router when `RoutePolicy` says the last answer no longer covers where we are.
    private func refreshWalkingRoute() {
        guard !AppSettings.isUITesting else { return }
        guard let origin = location.coordinate, let crow = engine.distanceMetres else { return }
        let destination = destination.coordinate
        guard RoutePolicy.shouldRequest(
            previous: lastRouteRequest,
            origin: origin,
            destination: destination,
            crowMetres: crow,
            now: Date()
        ) else { return }
        lastRouteRequest = RoutePolicy.Request(origin: origin, destination: destination, at: Date())
        Task { @MainActor in
            if let answer = await WalkingRouteService.shared.walkingRoute(from: origin, to: destination) {
                walkingRoute = answer
            }
        }
    }

    /// The one line of small print, when there is something honest to say about the reading.
    @ViewBuilder
    private var statusNote: some View {
        if engine.hasArrived {
            noteText(arrivalNote, .white.opacity(0.72))
        } else if !engine.headingIsUsable {
            noteText("No compass reading — showing the direction from north instead.", .white.opacity(0.7))
        } else if location.needsCalibration {
            noteText(
                "Magnetic interference. Move away from metal, or wave the phone in a figure of eight.",
                theme.secondary
            )
        } else if let accuracy = engine.horizontalAccuracy, accuracy > 40 {
            noteText("Rough fix — accurate to about \(Int(accuracy)) m", .white.opacity(0.7))
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

    /// Big numbers get a smaller face so "1,240" does not run off the edge.
    private func heroFontSize(for value: String) -> CGFloat {
        switch value.count {
        case 0...3: return 96
        case 4: return 84
        case 5: return 72
        default: return 62
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if engine.hasArrived {
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
                    if liveActivity.isRunning { liveActivity.end() }
                    router.isShowingCapture = true
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
                        startLiveActivity()
                    }
                }
            }

            if destination.spot == nil {
                PrimaryButton(title: "Save this spot", symbol: "plus.circle.fill") {
                    saveGuestDestination()
                }
            }
        }
    }

    // MARK: - Behaviour

    /// The guest area once resolved, otherwise whatever the destination already knows. Saved
    /// spots carry their own `placeName`; only shared coordinates need the live lookup.
    private var displaySubtitle: String? {
        if destination.spot == nil, let guestArea { return guestArea }
        return destination.subtitle
    }

    private func begin() {
        engine.target = destination.coordinate
        engine.targetAltitude = destination.altitude
        engine.start()
        FeedbackService.shared.startPulsing()
        if engine.hasArrived {
            hasAnnouncedArrival = true
        }
        resolveGuestArea()
        refreshWalkingRoute()
    }

    /// A shared coordinate arrives nameless; naming its street or district beats showing degrees.
    private func resolveGuestArea() {
        guard destination.spot == nil, guestArea == nil else { return }
        let coordinate = destination.coordinate
        Task { @MainActor in
            guestArea = await GeocodeService.shared.placeName(for: coordinate)
        }
    }

    private func finish() {
        engine.target = nil
        FeedbackService.shared.stopPulsing()
    }

    private func startLiveActivity() {
        guard let distance = engine.distanceMetres, let bearing = engine.bearing else { return }
        let started = liveActivity.start(
            spotID: destination.id,
            spotName: destination.name,
            placeName: destination.subtitle,
            distanceMetres: distance,
            bearing: bearing,
            themeID: settings.themeID,
            unitPreference: settings.unitPreference
        )
        if started {
            FeedbackService.shared.lightTap()
            // Background updates are what keep the Lock Screen honest once the phone is in a
            // pocket, and they need "always" authorization.
            location.requestAlwaysAuthorization()
        }
    }

    private func pushLiveActivityUpdate() {
        guard liveActivity.isRunning, liveActivity.activeSpotID == destination.id else { return }
        guard let distance = engine.distanceMetres, let bearing = engine.bearing else { return }
        if engine.hasArrived {
            liveActivity.finish(distanceMetres: distance, bearing: bearing)
        } else {
            liveActivity.update(distanceMetres: distance, bearing: bearing, isArrived: false)
        }
    }

    /// Turns a shared link into a spot of your own.
    private func saveGuestDestination() {
        let coordinate = destination.coordinate
        let name = destination.name
        let spot = store.createSpot(
            name: name,
            coordinate: coordinate,
            photoData: nil,
            thumbnailData: nil,
            glyph: "📍"
        )
        FeedbackService.shared.lightTap()
        router.openSpot(id: spot.id)
    }

    private func openInMaps() {
        let coordinate = destination.coordinate
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
        let item = MKMapItem(placemark: placemark)
        item.name = destination.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

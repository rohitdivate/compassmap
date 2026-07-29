import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

/// The screen the whole app exists for: an arrow, a distance, and the photo of where you are
/// going sitting behind both.
///
/// Performance contract: this view reads **nothing** from the compass engine. It hosts the
/// overflow menu and the detail sheet, and a menu that is rebuilt at heading rate is a menu
/// that opens late. Everything that moves lives in the leaves (`ArrowLeaves.swift`), each
/// observing exactly the slice of engine state it draws; the engine's event stream reaches
/// this screen only through closures on `EngineEventBridge`.
struct ArrowScreen: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var destination: ArrowDestination
    var engine: CompassEngine
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
    /// Set by the detail sheet's delete confirmation; honoured once the sheet has closed.
    @State private var deleteWhenDetailCloses = false

    private var store: SpotStore { SpotStore(context: modelContext) }

    var body: some View {
        screen
            // The screen that is actively guiding someone must not dim mid-walk. Cleared on
            // every path out — including the scene going inactive — so it can never stick.
            .onChange(of: scenePhase) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active
            }
    }

    private var screen: some View {
        layers
            // Gives the overlay a surface so taps do not fall through to the gallery behind it.
            .background(Color.black.opacity(0.001))
            // The engine's reactions live on a zero-size leaf, not on this screen, so their
            // observation dependencies never attach here.
            .background(eventBridge)
            .onAppear(perform: begin)
            .onDisappear(perform: finish)
            // The delete waits for the sheet to finish closing. Deleting mid-dismissal removes
            // this screen — the sheet's presenter — while the presentation is still animating,
            // and SwiftUI leaves a phantom presentation that blocks the whole surface.
            .sheet(isPresented: $isShowingDetail, onDismiss: performPendingDelete) { detailSheet }
    }

    private var eventBridge: some View {
        EngineEventBridge(
            solution: engine.solution,
            hapticsEnabled: settings.hapticsEnabled,
            onTargetLock: { isOnTarget in
                if isOnTarget { FeedbackService.shared.onTarget() }
            },
            onProximityChange: { proximity in
                FeedbackService.shared.updatePulse(proximity: proximity)
            },
            onFrameChange: {
                refreshWalkingRoute()
            },
            onArrivalChange: { arrived in
                handleArrival(arrived)
            }
        )
    }

    private func performPendingDelete() {
        guard deleteWhenDetailCloses, let spot = destination.spot else { return }
        deleteWhenDetailCloses = false
        store.delete(spot)
        // The shell no longer watches the whole spot table, so a deletion does not close this
        // screen by side effect any more — close it deliberately. The undo toast lives above
        // the shell and survives the collapse.
        onClose()
    }

    private var layers: some View {
        ZStack {
            ArrowBackdrop(theme: theme, destination: destination, dial: engine.dial)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                CompassCluster(
                    theme: theme,
                    dial: engine.dial,
                    solution: engine.solution,
                    destinationName: destination.name
                )
                Spacer(minLength: 8)
                readout
                ArrowActionsView(
                    solution: engine.solution,
                    destination: destination,
                    onTakeAnotherPhoto: {
                        if liveActivity.isRunning { liveActivity.end() }
                        router.isShowingCapture = true
                    },
                    onClose: onClose,
                    onStartTracking: startLiveActivity,
                    onSaveGuest: saveGuestDestination
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            if let celebrationStartedAt {
                // Bloom under confetti: the wash of colour says "done" before the eye has
                // resolved a single particle.
                ArrivalBloom()
                    .ignoresSafeArea()
                CelebrationView(theme: theme, startedAt: celebrationStartedAt)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var detailSheet: some View {
        if let spot = destination.spot {
            SpotDetailView(spot: spot, onDeleteConfirmed: { deleteWhenDetailCloses = true })
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
        // The driver ends the activity on its own fix; this only covers an arrival the engine
        // noticed first, so the Lock Screen card says "arrived" the same moment the app does.
        if liveActivity.isRunning, liveActivity.activeSpotID == destination.id,
           let distance = engine.distanceMetres, let bearing = engine.bearing {
            liveActivity.finish(distanceMetres: distance, bearing: bearing)
        }
    }

    // MARK: - Top bar

    /// Both round controls share one `GlassEffectContainer`, so the system renders them as
    /// one sheet of glass and can morph between them; `.interactive()` supplies the press
    /// squish `PressableStyle` used to fake.
    private var topBar: some View {
        GlassEffectContainer {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onClose) {
                    circularGlyph("chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let spot = destination.spot {
                    overflowMenu(for: spot)
                }
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
            TurnHintLabel(theme: theme, solution: engine.solution)
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

    /// The circular glass button shape used by both controls in the bar. Real glass rather
    /// than the old frosted fill: this chrome floats over a photograph, which is exactly
    /// where glass pays for itself.
    private func circularGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Readout

    private var readout: some View {
        VStack(spacing: 10) {
            DistanceReadoutView(theme: theme, solution: engine.solution)
            ArrowPills(
                theme: theme,
                solution: engine.solution,
                walkingRoute: walkingRoute,
                unitPreference: settings.unitPreference
            )
            .frame(maxWidth: .infinity)
            ArrowStatusNote(theme: theme, solution: engine.solution, destination: destination)
        }
        .padding(.bottom, 16)
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
        UIApplication.shared.isIdleTimerDisabled = true
        FeedbackService.shared.startPulsing()
        // The pulse re-seeds only when the proximity band changes; without this it would run
        // at the default rate until the first 8 m of walking.
        FeedbackService.shared.updatePulse(proximity: engine.solution.frame.proximity)
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
        // A tracked walk keeps the engine's target: the tab bar's mini compass strip reads
        // the same dial and frame this screen did, and it takes over the moment this closes.
        if !(liveActivity.isRunning && liveActivity.activeSpotID == destination.id) {
            engine.target = nil
        }
        UIApplication.shared.isIdleTimerDisabled = false
        FeedbackService.shared.stopPulsing()
    }

    private func startLiveActivity() {
        guard let distance = engine.distanceMetres, let bearing = engine.bearing else { return }
        // The activity drives its own updates from here on — `ActivityUpdateDriver` recomputes
        // distance and bearing on every fix, locked phone included, so this screen no longer
        // pushes anything itself.
        let started = liveActivity.start(
            spotID: destination.id,
            spotName: destination.name,
            placeName: destination.subtitle,
            coordinate: destination.coordinate,
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

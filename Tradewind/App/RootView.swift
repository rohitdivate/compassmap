import SwiftData
import SwiftUI

/// The app shell: a system tab bar (Liquid Glass, minimizing on scroll), a floating glass
/// shutter, and the arrow screen presented as a full-screen cover.
///
/// The arrow used to be a ZStack overlay so a card could grow into it with
/// `matchedGeometryEffect`; the zoom navigation transition does the same job across a real
/// presentation now — the whole card grows, not just its photo — and the system bar brings
/// the bottom accessory (the tracking strip) and the scroll-minimize behaviour with it.
struct RootView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var engine = CompassEngine()
    @State private var location = LocationService.shared
    @State private var liveActivity = LiveActivityService.shared
    @Namespace private var hero

    private var store: SpotStore { SpotStore(context: modelContext) }

    // The chain here is long — three presentations, an alert, and lifecycle handling — so it is
    // split across three shorter chains rather than one the type-checker has to swallow whole.
    var body: some View {
        presentations
            .onAppear {
                if location.isAuthorized { engine.start() }
                syncWithOutsideWorld()
            }
            .onChange(of: scenePhase) { _, phase in
                handle(scenePhase: phase)
            }
            // The first activation happens under the onboarding cover, so the first ingest has
            // to wait for the moment onboarding is dismissed — this is that moment.
            .onChange(of: settings.hasCompletedOnboarding) { _, onboarded in
                if onboarded {
                    PhotoIngestService.shared.ingestIfDue(store: store)
                }
            }
    }

    /// Presentations, deliberately spread across three hosts rather than chained onto one.
    ///
    /// Settings could not be opened. Two `fullScreenCover`s and a `sheet` were all attached to the
    /// same view, and SwiftUI does not reliably honour competing presentation modifiers on one host —
    /// the last one added is the one that loses, and that was Settings. Each now sits on a distinct
    /// level of the hierarchy: onboarding outermost, Settings in the middle, capture innermost on the
    /// content itself.
    private var presentations: some View {
        onboardingLayer
            .alert("Nothing to show", isPresented: hasUnresolvedLink) {
                Button("OK", role: .cancel) { router.unresolvedLinkMessage = nil }
            } message: {
                Text(router.unresolvedLinkMessage ?? "")
            }
    }

    private var onboardingLayer: some View {
        settingsLayer
            .fullScreenCover(isPresented: hasNotOnboarded) {
                OnboardingView()
                    .environment(settings)
                    .environment(\.theme, theme)
            }
    }

    private var settingsLayer: some View {
        stack
            .sheet(isPresented: showingSettings) {
                SettingsView()
                    .environment(settings)
                    .environment(\.theme, theme)
            }
    }

    private var stack: some View {
        ZStack {
            tabs
            shutterOverlay
            // Above everything: a deletion from the arrow's detail sheet closes the arrow
            // cover, and the undo must be standing here when the collapse finishes.
            UndoToastHost()
                .zIndex(30)
        }
        // The arrow rides its own presentation now. The cover's content carries the zoom
        // transition, so the tapped card grows into the screen — unless Reduce Motion or the
        // UI-test seam says otherwise (MotionPolicy).
        .fullScreenCover(item: destinationItem) { destination in
            arrowScreen(for: destination)
        }
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab(AppRouter.Tab.spots.title, systemImage: AppRouter.Tab.spots.symbol, value: .spots) {
                surface { SpotsGalleryView(hero: hero) }
            }
            Tab(AppRouter.Tab.map.title, systemImage: AppRouter.Tab.map.symbol, value: .map) {
                surface { SpotsMapView() }
            }
            Tab(AppRouter.Tab.trips.title, systemImage: AppRouter.Tab.trips.symbol, value: .trips) {
                surface { TripsView(hero: hero) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { trackingAccessory }
        .fullScreenCover(isPresented: showingCapture) {
            CaptureFlowView()
                .environment(settings)
                .environment(router)
                .environment(\.theme, theme)
        }
    }

    private func surface(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            ThemedBackground(theme: theme)
            content()
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    /// The walk, kept in hand: while a Lock Screen walk is tracked, the tab bar grows the
    /// mini compass strip, and tapping it reopens the arrow.
    @ViewBuilder
    private var trackingAccessory: some View {
        if let id = liveActivity.activeSpotID {
            MiniCompassStrip(
                dial: engine.dial,
                solution: engine.solution,
                name: liveActivity.activeSpotName ?? "On your way"
            ) {
                FeedbackService.shared.lightTap()
                router.openSpot(id: id)
            }
        }
    }

    /// The shutter floats above the bar on its own — not a tab, because photographing where
    /// you stand is the app's verb, not a place in it.
    private var shutterOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                GlassShutter {
                    FeedbackService.shared.lightTap()
                    router.isShowingCapture = true
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 104)
        .ignoresSafeArea(.keyboard)
        // Its own host, per the presentation-conflict lesson: nothing else presents here.
        .sheet(isPresented: showingSaveHere) {
            SaveHereView()
                .environment(settings)
                .environment(\.theme, theme)
        }
    }

    private func arrowScreen(for destination: ArrowDestination) -> some View {
        ArrowScreen(
            destination: destination,
            engine: engine,
            onClose: { router.dismissDestination() }
        )
        .environment(settings)
        .environment(router)
        .environment(\.theme, theme)
        .modifier(ZoomTransition(sourceID: destination.id, namespace: hero))
    }

    private var tabSelection: Binding<AppRouter.Tab> {
        Binding(
            get: { router.tab },
            set: { newValue in
                if router.tab != newValue { FeedbackService.shared.lightTap() }
                router.tab = newValue
            }
        )
    }

    private var destinationItem: Binding<ArrowDestination?> {
        Binding(
            get: { destination },
            set: { newValue in
                if newValue == nil { router.dismissDestination() }
            }
        )
    }

    private func handle(scenePhase phase: ScenePhase) {
        switch phase {
        case .active:
            if location.isAuthorized { engine.start() }
            syncWithOutsideWorld()
        case .background, .inactive:
            engine.stop()
            FeedbackService.shared.stopPulsing()
        default:
            break
        }
    }

    private var showingCapture: Binding<Bool> {
        Binding(get: { router.isShowingCapture }, set: { router.isShowingCapture = $0 })
    }

    private var showingSaveHere: Binding<Bool> {
        Binding(get: { router.isShowingSaveHere }, set: { router.isShowingSaveHere = $0 })
    }

    private var showingSettings: Binding<Bool> {
        Binding(get: { router.isShowingSettings }, set: { router.isShowingSettings = $0 })
    }

    private var hasUnresolvedLink: Binding<Bool> {
        Binding(
            get: { router.unresolvedLinkMessage != nil },
            set: { if !$0 { router.unresolvedLinkMessage = nil } }
        )
    }

    // MARK: - Behaviour

    /// Picks up anything that happened while the app was closed: a pin moved by a widget button,
    /// and an intent from Siri, Shortcuts or a widget tap asking for a particular screen.
    ///
    /// Only the two steps that gate first paint run synchronously — the adopted pin (which the
    /// snapshot rewrite would otherwise overwrite) and the pending deep-link action. The rest
    /// is housekeeping, and housekeeping used to be the jank: six full-table fetches, a
    /// snapshot rewrite per geocode, and once a week a full photo archive, all inside the
    /// activation frame.
    private func syncWithOutsideWorld() {
        let store = self.store
        store.adoptPinFromSnapshot()

        switch PendingAction.take() {
        case .openSpot(let id):
            router.openSpot(id: id)
        case .openCapture:
            router.isShowingCapture = true
        case nil:
            break
        }

        Task(priority: .utility) {
            store.scheduleSnapshotRefresh()
            await store.migrateThumbnailsIfNeeded()
            // Geofences drift while the app is closed — spots deleted from a widget flow, the
            // person now on the other side of town — so every activation recomputes the armed
            // set. Names for spots that never got one trickle in a few at a time, inside the
            // geocoder's rate limit.
            store.rearmGeofences()
            store.resolveMissingPlaceNames()
            store.purgeExpired()
            BackupService.shared.autoSnapshotIfDue(store: store)
            PhotoIngestService.shared.ingestIfDue(store: store)
        }
    }

    // MARK: - Pieces

    /// Resolves whatever the router has been asked to show into something the arrow screen can
    /// draw. A link to a deleted spot resolves to nothing rather than to an empty screen.
    ///
    /// A one-shot fetch, not a `@Query` over every spot: the shell used to observe the whole
    /// table just to resolve one id, which meant every mutation anywhere — a glyph change, a
    /// thumbnail backfill — redrew the backdrop, the bar and the current tab. The delete path
    /// closes the arrow through the router now (`ArrowScreen.performPendingDelete`), which the
    /// query's disappearance used to do implicitly.
    private var destination: ArrowDestination? {
        if let id = router.activeSpotID {
            var descriptor = FetchDescriptor<Spot>(
                predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
            )
            descriptor.fetchLimit = 1
            if let spot = (try? modelContext.fetch(descriptor))?.first {
                return .saved(spot)
            }
            return nil
        }
        if let guest = router.guestDestination {
            return .guest(guest)
        }
        return nil
    }

    private var hasNotOnboarded: Binding<Bool> {
        Binding(
            get: { !settings.hasCompletedOnboarding },
            set: { settings.hasCompletedOnboarding = !$0 }
        )
    }
}

/// What the arrow screen is pointing at: a spot from the library, or a coordinate someone sent
/// you.
enum ArrowDestination: Identifiable {
    case saved(Spot)
    case guest(AppRouter.GuestDestination)

    var id: UUID {
        switch self {
        case .saved(let spot): return spot.id
        case .guest(let guest): return guest.id
        }
    }

    var name: String {
        switch self {
        case .saved(let spot): return spot.displayName
        case .guest(let guest): return guest.name
        }
    }

    var subtitle: String? {
        switch self {
        case .saved(let spot): return spot.subtitle
        case .guest(let guest):
            return String(format: "%.4f°, %.4f°", guest.coordinate.latitude, guest.coordinate.longitude)
        }
    }

    var coordinate: Coordinate {
        switch self {
        case .saved(let spot): return spot.coordinate
        case .guest(let guest): return guest.coordinate
        }
    }

    var altitude: Double? {
        switch self {
        case .saved(let spot): return spot.altitude
        case .guest: return nil
        }
    }

    var photoData: Data? {
        switch self {
        case .saved(let spot): return spot.photoData
        case .guest: return nil
        }
    }

    var spot: Spot? {
        switch self {
        case .saved(let spot): return spot
        case .guest: return nil
        }
    }
}

// MARK: - Shutter

/// The camera, one tap from anywhere: a floating Liquid Glass button in the theme's accent.
/// Interactive glass gives the press its squish; the identifier is load-bearing for XCUITest.
private struct GlassShutter: View {
    @Environment(\.theme) private var theme

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 60, height: 60)
        }
        .glassEffect(.regular.tint(theme.accent).interactive(), in: .circle)
        .accessibilityIdentifier("capture-button")
        .accessibilityLabel("Take a photo")
    }
}

// MARK: - Zoom transition

/// Applies the zoom navigation transition when `MotionPolicy` allows it. A plain conditional
/// modifier because `NavigationTransition` values of different concrete types cannot share a
/// ternary.
private struct ZoomTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var sourceID: UUID
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if MotionPolicy.allowsZoomTransition(
            reduceMotion: reduceMotion,
            isUITesting: AppSettings.isUITesting
        ) {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

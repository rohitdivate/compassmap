import SwiftData
import SwiftUI

/// The app shell: backdrop, the three main surfaces, a floating bar, and the arrow screen
/// which rises over all of it.
///
/// The arrow screen is an overlay in this same view tree rather than a sheet, so a tapped card
/// can grow into it with `matchedGeometryEffect`. That transition is the moment the app either
/// feels made-for-this or feels like a list of coordinates, so it is worth the slightly less
/// conventional structure.
struct RootView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Spot.capturedAt, order: .reverse) private var spots: [Spot]

    @State private var engine = CompassEngine()
    @State private var location = LocationService.shared
    @Namespace private var hero

    private var store: SpotStore { SpotStore(context: modelContext) }

    var body: some View {
        ZStack {
            ThemedBackground(
                theme: theme,
                animated: false,
                timeTint: settings.timeOfDayTintEnabled
            )

            surface
                .safeAreaInset(edge: .bottom) {
                    // Reserve room for the floating bar so content can still scroll clear of it.
                    Color.clear.frame(height: 78)
                }

            VStack {
                Spacer()
                FloatingBar(
                    selection: router.tab,
                    onSelect: { tab in
                        FeedbackService.shared.lightTap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            router.tab = tab
                        }
                    },
                    onCapture: {
                        FeedbackService.shared.lightTap()
                        router.isShowingCapture = true
                    }
                )
                .padding(.bottom, 8)
            }
            .ignoresSafeArea(.keyboard)

            if let destination {
                ArrowScreen(
                    destination: destination,
                    engine: engine,
                    hero: hero,
                    onClose: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            router.dismissDestination()
                        }
                    }
                )
                .zIndex(10)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity.combined(with: .scale(scale: 0.97))
                ))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: router.activeSpotID)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: router.guestDestination)
        .fullScreenCover(isPresented: hasNotOnboarded) {
            OnboardingView()
                .environment(settings)
                .environment(\.theme, theme)
        }
        .fullScreenCover(isPresented: Binding(
            get: { router.isShowingCapture },
            set: { router.isShowingCapture = $0 }
        )) {
            CaptureFlowView()
                .environment(settings)
                .environment(router)
                .environment(\.theme, theme)
        }
        .sheet(isPresented: Binding(
            get: { router.isShowingSettings },
            set: { router.isShowingSettings = $0 }
        )) {
            SettingsView()
                .environment(settings)
                .environment(\.theme, theme)
        }
        .alert(
            "Nothing to show",
            isPresented: Binding(
                get: { router.unresolvedLinkMessage != nil },
                set: { if !$0 { router.unresolvedLinkMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { router.unresolvedLinkMessage = nil }
        } message: {
            Text(router.unresolvedLinkMessage ?? "")
        }
        .onAppear {
            if location.isAuthorized { engine.start() }
            syncWithOutsideWorld()
        }
        .onChange(of: scenePhase) { _, phase in
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
    }

    // MARK: - Behaviour

    /// Picks up anything that happened while the app was closed: a pin moved by a widget button,
    /// and an intent from Siri, Shortcuts or a widget tap asking for a particular screen.
    private func syncWithOutsideWorld() {
        let store = self.store
        store.adoptPinFromSnapshot()
        store.refreshSnapshot()

        switch PendingAction.take() {
        case .openSpot(let id):
            router.openSpot(id: id)
        case .openCapture:
            router.isShowingCapture = true
        case nil:
            break
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var surface: some View {
        switch router.tab {
        case .spots:
            SpotsGalleryView(hero: hero)
        case .map:
            SpotsMapView()
        case .trips:
            TripsView(hero: hero)
        }
    }

    /// Resolves whatever the router has been asked to show into something the arrow screen can
    /// draw. A link to a deleted spot resolves to nothing rather than to an empty screen.
    private var destination: ArrowDestination? {
        if let id = router.activeSpotID, let spot = spots.first(where: { $0.id == id }) {
            return .saved(spot)
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

// MARK: - Floating bar

/// Three surfaces and a shutter. A capsule rather than a system tab bar because the backdrop
/// is the point of the app and a solid bar across the bottom would cut it in half.
private struct FloatingBar: View {
    @Environment(\.theme) private var theme

    var selection: AppRouter.Tab
    var onSelect: (AppRouter.Tab) -> Void
    var onCapture: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AppRouter.Tab.allCases) { tab in
                    Button {
                        onSelect(tab)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 17, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(width: 62, height: 46)
                        .foregroundStyle(selection == tab ? theme.accent : theme.textMuted)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(theme.accent.opacity(0.14))
                            }
                        }
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(5)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            }
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

            Button(action: onCapture) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(theme.deepest)
                    .frame(width: 56, height: 56)
                    .background {
                        Circle()
                            .fill(theme.accent)
                            .shadow(color: theme.glow.opacity(0.5), radius: 16, y: 6)
                    }
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Save this place")
        }
        .padding(.horizontal, 16)
    }
}

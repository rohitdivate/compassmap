import AppIntents
import Foundation
import WidgetKit

/// Opens the compass for a spot. Used by Siri, Shortcuts, and every widget tap.
struct OpenSpotIntent: AppIntent {

    static var title: LocalizedStringResource = "Point Me To A Spot"
    static var description = IntentDescription(
        "Opens Tradewind's compass pointing at one of your saved spots.",
        categoryName: "Navigating"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Spot")
    var spot: SpotEntity

    init() {}

    init(spot: SpotEntity) {
        self.spot = spot
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Point me to \(\.$spot)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAction.set(.openSpot(spot.id))
        return .result()
    }
}

/// "How far to the waterfall?" — answers without opening anything.
struct DistanceToSpotIntent: AppIntent {

    static var title: LocalizedStringResource = "How Far To A Spot"
    static var description = IntentDescription(
        "Tells you how far away one of your saved spots is, and which way it lies.",
        categoryName: "Navigating"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Spot")
    var spot: SpotEntity

    init() {}

    init(spot: SpotEntity) {
        self.spot = spot
    }

    static var parameterSummary: some ParameterSummary {
        Summary("How far to \(\.$spot)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        guard let origin = await CurrentLocationProbe.coordinate() else {
            return .result(
                value: 0,
                dialog: IntentDialog("I can't tell where you are right now.")
            )
        }

        let metres = BearingMath.distance(from: origin, to: spot.coordinate)
        let bearing = BearingMath.initialBearing(from: origin, to: spot.coordinate)
        let units = SharedSnapshotStore.load()?.unitPreference ?? .automatic
        let distance = DistanceFormatting.string(metres: metres, preference: units)
        let compass = BearingMath.compassPoint(forBearing: bearing)

        let phrase: String
        if metres <= 30 {
            phrase = "You're basically at \(spot.name)."
        } else if let walk = DistanceFormatting.walkingTime(metres: metres) {
            phrase = "\(spot.name) is \(distance) away to the \(compass) — about a \(walk)."
        } else {
            phrase = "\(spot.name) is \(distance) away to the \(compass)."
        }

        return .result(value: metres, dialog: IntentDialog(stringLiteral: phrase))
    }
}

/// Opens the camera, ready to save wherever you are standing.
struct SaveThisPlaceIntent: AppIntent {

    static var title: LocalizedStringResource = "Save This Place"
    static var description = IntentDescription(
        "Opens Tradewind's camera so you can photograph where you are and save it as a spot.",
        categoryName: "Saving"
    )
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAction.set(.openCapture)
        return .result()
    }
}

/// Widget button: make the nearest spot the pinned one.
///
/// Runs in the widget's process, so it changes the pin in the shared snapshot. The app adopts
/// that change into its own store the next time it opens — see `SpotStore.adoptPinFromSnapshot`.
struct PinNearestSpotIntent: AppIntent {

    static var title: LocalizedStringResource = "Pin The Nearest Spot"
    static var description = IntentDescription(
        "Makes whichever spot is closest to you the one your widgets follow.",
        categoryName: "Widgets"
    )
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        let origin = await CurrentLocationProbe.coordinate()
        guard let snapshot = SharedSnapshotStore.load(),
              let nearest = snapshot.spotsByDistance(from: origin).first?.spot
        else { return .result() }

        SharedSnapshotStore.mutate(defaultThemeID: snapshot.themeID) { snapshot in
            snapshot.pinnedSpotID = nearest.id
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Widget button: move the pin to the next spot along, by distance. Lets a small widget cycle
/// through everything without opening the app.
struct NextSpotIntent: AppIntent {

    static var title: LocalizedStringResource = "Show My Next Spot"
    static var description = IntentDescription(
        "Moves your widgets on to the next spot by distance.",
        categoryName: "Widgets"
    )
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        let origin = await CurrentLocationProbe.coordinate()
        guard let snapshot = SharedSnapshotStore.load() else { return .result() }

        let ordered = snapshot.spotsByDistance(from: origin).map(\.spot)
        guard !ordered.isEmpty else { return .result() }

        let currentIndex = snapshot.pinnedSpotID.flatMap { id in
            ordered.firstIndex { $0.id == id }
        }
        let nextIndex = ((currentIndex ?? -1) + 1) % ordered.count

        SharedSnapshotStore.mutate(defaultThemeID: snapshot.themeID) { snapshot in
            snapshot.pinnedSpotID = ordered[nextIndex].id
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Widget configuration: which spot should this widget follow?
struct SelectSpotIntent: WidgetConfigurationIntent {

    static var title: LocalizedStringResource = "Choose A Spot"
    static var description = IntentDescription("Pick which spot this widget points at.")

    /// Nil means "follow whichever spot is pinned, or the nearest one", which is what most people
    /// want and what the widget does out of the box.
    @Parameter(title: "Spot")
    var spot: SpotEntity?

    init() {}

    init(spot: SpotEntity?) {
        self.spot = spot
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Point at \(\.$spot)")
    }
}

/// The spoken phrases. Every one includes the app name, which App Intents requires.
struct TradewindShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DistanceToSpotIntent(),
            phrases: [
                "How far in \(.applicationName)",
                "How far to my spot in \(.applicationName)",
                "\(.applicationName) distance",
            ],
            shortTitle: "How far",
            systemImageName: "ruler"
        )
        AppShortcut(
            intent: OpenSpotIntent(),
            phrases: [
                "Point me somewhere with \(.applicationName)",
                "Take me back with \(.applicationName)",
                "Open a spot in \(.applicationName)",
            ],
            shortTitle: "Point me there",
            systemImageName: "location.north.line.fill"
        )
        AppShortcut(
            intent: SaveThisPlaceIntent(),
            phrases: [
                "Save this place in \(.applicationName)",
                "Remember here with \(.applicationName)",
            ],
            shortTitle: "Save this place",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: PinNearestSpotIntent(),
            phrases: [
                "Pin the nearest spot in \(.applicationName)",
            ],
            shortTitle: "Pin nearest",
            systemImageName: "pin.fill"
        )
    }
}

import SwiftUI
import WidgetKit

@main
struct TradewindWidgetBundle: WidgetBundle {

    @WidgetBundleBuilder
    var body: some Widget {
        SpotCompassWidget()
        NearestSpotsWidget()
        HeadingLiveActivity()
        controls
    }

    /// Control Center and the Action button arrived in iOS 18, and the app supports iOS 17, so this
    /// is gated. On iOS 17 the bundle simply has one fewer member.
    @WidgetBundleBuilder
    private var controls: some Widget {
        if #available(iOS 18.0, *) {
            SaveThisPlaceControl()
            NextSpotControl()
        }
    }
}

/// Control Centre button: opens Tradewind's camera, ready to save where you are.
@available(iOS 18.0, *)
struct SaveThisPlaceControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SaveThisPlaceControl") {
            ControlWidgetButton(action: SaveThisPlaceIntent()) {
                Label("Save This Place", systemImage: "camera.fill")
            }
        }
        .displayName("Save This Place")
        .description("Open Tradewind's camera and save where you are.")
    }
}

/// Control Centre button: move your widgets on to the next spot.
@available(iOS 18.0, *)
struct NextSpotControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NextSpotControl") {
            ControlWidgetButton(action: NextSpotIntent()) {
                Label("Next Spot", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .displayName("Next Spot")
        .description("Point your widgets at the next spot along.")
    }
}

import CoreMotion
import SwiftUI

/// The dial as a physical object: a soft pool of light on the bezel that slides with the
/// device's tilt, the way light moves on a real compass's glass.
///
/// Lives in the app target on purpose — `Shared/` compiles into the widget extension, and
/// widgets get no motion updates.

/// Device attitude, reduced to two quantized numbers.
///
/// 15 Hz and a 0.05-step grid: the highlight is ambience, not instrumentation, and the grid
/// means a hand at rest publishes nothing — same discipline as `DialState`. A singleton so
/// the motion manager exists once (Apple's requirement) no matter how often the arrow screen
/// is opened and closed.
@Observable
final class TiltSource {

    static let shared = TiltSource()

    /// Unit offsets in -1...1: which way the light has slid off centre.
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    private let manager = CMMotionManager()

    private init() {}

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            // Half a radian of tilt sweeps the light fully across; beyond that it pins.
            let nx = (max(-0.5, min(0.5, attitude.roll)) / 0.5 * 20).rounded() / 20
            let ny = (max(-0.5, min(0.5, attitude.pitch)) / 0.5 * 20).rounded() / 20
            if nx != x { x = nx }
            if ny != y { y = ny }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

/// The light itself, sized to sit exactly over the rose. Draws nothing at all when
/// `MotionPolicy` rules decoration out — Reduce Motion readers should see a still dial, and
/// XCUITest must never wait out a motion-driven animation.
struct DialTiltHighlight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var diameter: CGFloat

    @State private var tilt = TiltSource.shared

    private var slide: CGSize {
        CGSize(
            width: CGFloat(tilt.x) * diameter * 0.08,
            height: CGFloat(tilt.y) * diameter * 0.08
        )
    }

    var body: some View {
        if MotionPolicy.allowsDecorativeMotion(
            reduceMotion: reduceMotion,
            isUITesting: AppSettings.isUITesting
        ) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.42
                    )
                )
                .frame(width: diameter, height: diameter)
                .offset(slide)
                .animation(.smooth(duration: 0.35), value: slide)
                .blendMode(.screen)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear { tilt.start() }
                .onDisappear { tilt.stop() }
        }
    }
}

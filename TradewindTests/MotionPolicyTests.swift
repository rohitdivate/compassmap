import Foundation
import Testing

@Suite("Motion policy")
struct MotionPolicyTests {

    @Test("Zoom transitions stop for Reduce Motion and for UI testing")
    func zoom() {
        #expect(MotionPolicy.allowsZoomTransition(reduceMotion: false, isUITesting: false))
        #expect(!MotionPolicy.allowsZoomTransition(reduceMotion: true, isUITesting: false))
        #expect(!MotionPolicy.allowsZoomTransition(reduceMotion: false, isUITesting: true))
        #expect(!MotionPolicy.allowsZoomTransition(reduceMotion: true, isUITesting: true))
    }

    @Test("Glass respects Reduce Transparency")
    func glass() {
        #expect(MotionPolicy.allowsGlass(reduceTransparency: false))
        #expect(!MotionPolicy.allowsGlass(reduceTransparency: true))
    }

    @Test("Decorative motion follows the same switches as zoom")
    func decoration() {
        #expect(MotionPolicy.allowsDecorativeMotion(reduceMotion: false, isUITesting: false))
        #expect(!MotionPolicy.allowsDecorativeMotion(reduceMotion: true, isUITesting: false))
        #expect(!MotionPolicy.allowsDecorativeMotion(reduceMotion: false, isUITesting: true))
    }
}

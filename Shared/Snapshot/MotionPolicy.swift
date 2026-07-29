import Foundation

/// Whether the expressive layer is allowed to move, in one place.
///
/// Three switches turn motion and glass down: the person's Reduce Motion setting, their
/// Reduce Transparency setting, and the UI-test seam — XCUITest waits for the app to idle
/// before every interaction, and a zoom transition it cannot see the end of stalls the whole
/// suite (the same lesson the overflow menu taught, generalized). Views ask this table
/// instead of re-deriving the rule, so the QA matrix can assert it directly.
enum MotionPolicy {

    /// The card-grows-into-the-arrow-screen transition, and its siblings.
    static func allowsZoomTransition(reduceMotion: Bool, isUITesting: Bool) -> Bool {
        !reduceMotion && !isUITesting
    }

    /// Liquid Glass chrome. Reduce Transparency means flat surfaces, not frosted ones.
    static func allowsGlass(reduceTransparency: Bool) -> Bool {
        !reduceTransparency
    }

    /// Decoration that moves on its own — parallax, tilt, breathing rings.
    static func allowsDecorativeMotion(reduceMotion: Bool, isUITesting: Bool) -> Bool {
        !reduceMotion && !isUITesting
    }
}

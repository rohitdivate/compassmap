import Testing
import Foundation

/// Guards the rule behind an empty photo picker.
///
/// The app presented `PhotosPicker(..., photoLibrary: .shared())` — which shows only photos the app is
/// already authorized to see — without ever having asked for authorization. The grid came up empty,
/// nothing could be selected, and the code that would have requested access only ran *after* a
/// selection. The permission prompt was unreachable by construction.
@Suite("Photo library access")
struct LibraryAccessTests {

    // MARK: - The regression

    @Test("Undetermined access presents no picker at all — it has to ask first")
    func undeterminedPresentsNothing() {
        // The bug was a default here. nil means "ask, then decide", and any non-nil answer for this
        // case would reintroduce an empty grid.
        #expect(LibraryAccess.notDetermined.picker == nil)
    }

    @Test("The shared-library picker is only ever used when it will show something")
    func sharedLibraryOnlyWhenAuthorized() {
        for access in LibraryAccess.allCases where access.picker == .sharedLibrary {
            #expect(access == .granted || access == .limited)
        }
    }

    // MARK: - The routes

    @Test("Full and limited access both use the shared library, so asset lookups keep working")
    func authorizedUsesSharedLibrary() {
        #expect(LibraryAccess.granted.picker == .sharedLibrary)
        #expect(LibraryAccess.limited.picker == .sharedLibrary)
    }

    @Test("Refused access still gets a working picker, not a dead end")
    func deniedFallsBackRatherThanBlocking() {
        // Importing must remain possible without library permission; only the location fallback is
        // lost. Returning nil here would turn a limitation into a broken button.
        #expect(LibraryAccess.denied.picker == .outOfProcess)
    }

    @Test("Only real library access can read a photo's stored location")
    func assetLocationsNeedAccess() {
        #expect(LibraryAccess.granted.canReadAssetLocations)
        #expect(LibraryAccess.limited.canReadAssetLocations)
        #expect(LibraryAccess.denied.canReadAssetLocations == false)
        #expect(LibraryAccess.notDetermined.canReadAssetLocations == false)
    }

    @Test("Every access level is decided, none left to chance")
    func allCasesHandled() {
        // Fails if a case is added without deciding what it means for either question.
        for access in LibraryAccess.allCases {
            _ = access.picker
            _ = access.canReadAssetLocations
        }
        #expect(LibraryAccess.allCases.count == 4)
    }
}

/// The widget's empty state used to name the wrong cause.
@Suite("Widget data state")
struct WidgetDataStateTests {

    @Test("Without an App Group the widget says so, even though the snapshot is also empty")
    func appGroupBeatsEmptiness() {
        // The misreporting being fixed: both conditions hold at once on a free build, and the useless
        // one was winning.
        #expect(WidgetDataState.state(hasAppGroup: false, snapshotIsEmpty: true) == .noAppGroup)
        #expect(WidgetDataState.state(hasAppGroup: false, snapshotIsEmpty: false) == .noAppGroup)
    }

    @Test("With an App Group, an empty snapshot really does mean nothing is saved")
    func emptyMeansEmpty() {
        #expect(WidgetDataState.state(hasAppGroup: true, snapshotIsEmpty: true) == .noSpots)
    }

    @Test("Data present and reachable means no message")
    func readyIsQuiet() {
        #expect(WidgetDataState.state(hasAppGroup: true, snapshotIsEmpty: false) == .ready)
        #expect(WidgetDataState.ready.message == nil)
    }

    @Test("The no-App-Group message must not ask for a spot that is already saved")
    func doesNotBlameTheUser() {
        let message = WidgetDataState.noAppGroup.message
        #expect(message != nil)
        #expect(message?.lowercased().contains("save a spot") == false)
    }

    @Test("Every state that has nothing to show explains itself")
    func degradedStatesSpeak() {
        #expect(WidgetDataState.noAppGroup.message?.isEmpty == false)
        #expect(WidgetDataState.noSpots.message?.isEmpty == false)
    }
}

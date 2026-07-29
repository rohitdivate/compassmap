import CoreLocation
import PhotosUI
import SwiftData
import SwiftUI

/// A photo waiting to be named and saved: the photo itself, where it was taken, and the few
/// details the review step lets you add.
struct PendingSpot {
    var photoData: Data
    var thumbnailData: Data?
    var coordinate: Coordinate?
    var altitude: Double?
    var horizontalAccuracy: Double?
    var capturedAt: Date
    var heading: Double?
    /// True when the coordinate came from the photo rather than from where you are now.
    var locationFromPhoto: Bool
    var name: String = ""
    var glyph: String?
    var kind: PlaceKind = .place
    var tripID: UUID?
    var saveToLibrary: Bool = false
}

/// Taking a photo, or picking one you already took, and turning it into a spot.
///
/// Two ways in, one way out. A fresh photo gets the location as of the shutter; an imported one
/// gets the location out of its own metadata, and if it has none, the flow says so and offers to
/// use where you are standing now rather than silently guessing.
struct CaptureFlowView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var camera = CameraController()
    @State private var location = LocationService.shared
    @State private var pending: PendingSpot?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var isImportingWithoutLibrary = false
    @State private var importProblem: ImportProblem?

    private var store: SpotStore { SpotStore(context: modelContext) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let pending {
                ReviewView(
                    pending: pending,
                    trips: trips,
                    unitPreference: settings.unitPreference,
                    currentCoordinate: location.coordinate,
                    onChange: { self.pending = $0 },
                    onCancel: {
                        self.pending = nil
                        camera.discardCapture()
                        camera.start()
                    },
                    onSave: { save($0) }
                )
            } else {
                cameraLayer
            }
        }
        .task {
            await camera.prepare()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedImageData) { _, data in
            guard let data else { return }
            camera.stop()
            Task { await handleCaptured(data) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-screen")
        // Two pickers, because the argument lists differ and the choice is not cosmetic. The
        // shared-library one shows only authorized photos; the other needs no permission but cannot
        // give us an asset identifier. LibraryAccess decides which is presented.
        .photosPicker(
            isPresented: $isImporting,
            selection: $pickerItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .photosPicker(
            isPresented: $isImportingWithoutLibrary,
            selection: $pickerItem,
            matching: .images
        )
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await handleImport(item) }
        }
        .alert(
            importProblem?.title ?? "",
            isPresented: Binding(
                get: { importProblem != nil },
                set: { if !$0 { importProblem = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importProblem = nil }
        } message: {
            Text(importProblem?.message ?? "")
        }
    }

    /// An import problem worth interrupting for. Carries its own title, because a single hardcoded
    /// one ("This photo has no location") was being shown over unrelated messages such as "that
    /// photo could not be read".
    private struct ImportProblem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Camera

    private var cameraLayer: some View {
        ZStack {
            switch camera.state {
            case .running, .preparing, .idle:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .overlay {
                        if camera.state != .running {
                            ProgressView().tint(.white)
                        }
                    }
            case .denied:
                CameraUnavailableView(
                    title: "Camera access is off",
                    message: "Tradewind needs the camera to photograph a place. You can turn it on in Settings › Tradewind.",
                    showsSettingsButton: true
                )
            case .unavailable(let message):
                CameraUnavailableView(title: "Camera unavailable", message: message, showsSettingsButton: false)
            }

            VStack {
                topControls
                Spacer()
                locationBadge
                shutterRow
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
    }

    private var topControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background { Circle().fill(.black.opacity(0.4)) }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close camera")

            Spacer()

            Button {
                camera.isFlashEnabled.toggle()
                FeedbackService.shared.lightTap()
            } label: {
                Image(systemName: camera.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(camera.isFlashEnabled ? theme.canvas : .white)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(camera.isFlashEnabled
                            ? AnyShapeStyle(theme.accent)
                            : AnyShapeStyle(.black.opacity(0.4)))
                    }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(camera.isFlashEnabled ? "Flash on" : "Flash off")
        }
        .padding(.top, 8)
    }

    /// Shows whether the fix is good enough to be worth saving. Taking the photo first and
    /// discovering the coordinate was 200 m out later is the one failure this app cannot recover
    /// from, so it is surfaced before the shutter, not after.
    @ViewBuilder
    private var locationBadge: some View {
        Group {
            if let accuracy = location.currentLocation?.horizontalAccuracy, accuracy >= 0 {
                fixBadge(accuracy: accuracy)
            } else if location.isAuthorized {
                searchingBadge
            } else {
                permissionBadge
            }
        }
        .padding(.bottom, 18)
    }

    private func fixBadge(accuracy: Double) -> some View {
        let isGood = accuracy <= 25
        let text = isGood ? "Good fix" : "Weak fix"
        return HStack(spacing: 6) {
            Image(systemName: isGood ? "location.fill" : "location.slash.fill")
                .font(.system(size: 11, weight: .bold))
            Text("\(text) · ±\(Int(accuracy)) m").font(theme.labelFont)
        }
        .foregroundStyle(isGood ? theme.canvas : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background { badgeShape(filled: isGood) }
    }

    private var searchingBadge: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini).tint(.white)
            Text("Finding you").font(theme.labelFont)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background { badgeShape(filled: false) }
    }

    private var permissionBadge: some View {
        Button {
            location.requestWhenInUseAuthorization()
        } label: {
            Text("Turn on location to save a spot")
                .font(theme.labelFont)
                .foregroundStyle(theme.canvas)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background { badgeShape(filled: true) }
        }
        .buttonStyle(PressableStyle())
    }

    private func badgeShape(filled: Bool) -> some View {
        Capsule().fill(
            filled ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.black.opacity(0.55))
        )
    }

    private var shutterRow: some View {
        HStack {
            libraryButton
            Spacer()
            shutterButton
            Spacer()
            headingIndicator
        }
    }

    private var libraryButton: some View {
        Button {
            Task { await presentLibrary() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 19, weight: .semibold))
                Text("Library").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 62, height: 56)
        }
        .buttonStyle(PressableStyle())
    }

    private var shutterButton: some View {
        Button {
            camera.capture(
                location: location.currentLocation,
                heading: location.headingDegrees(preferTrueNorth: settings.usesTrueNorth)
            )
            FeedbackService.shared.lightTap()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(theme.accent)
                    .frame(width: 62, height: 62)
                    .shadow(color: theme.glow.opacity(0.6), radius: 14)
                if camera.isCapturing {
                    ProgressView().tint(theme.canvas)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(camera.state != .running || camera.isCapturing)
        .accessibilityLabel("Take photo")
    }

    /// Balances the shutter, and shows which way you were facing when you pressed it.
    private var headingIndicator: some View {
        let heading = location.headingDegrees(preferTrueNorth: settings.usesTrueNorth) ?? 0
        return VStack(spacing: 4) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 17, weight: .semibold))
                .rotationEffect(.degrees(-heading))
            Text(headingLabel).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 62, height: 56)
        .accessibilityHidden(true)
    }

    private var headingLabel: String {
        guard let heading = location.headingDegrees(preferTrueNorth: settings.usesTrueNorth) else {
            return "—"
        }
        return BearingMath.compassPoint(forBearing: heading)
    }

    // MARK: - Handling photos

    private func handleCaptured(_ data: Data) async {
        // Two ImageIO downsamples and two JPEG encodes — off the main thread, so the shutter
        // button releases the moment it is pressed instead of after the encode.
        let prepared = await Task.detached(priority: .userInitiated) {
            PhotoService.prepare(imageData: data)
        }.value
        let fix = camera.captureLocation

        // A negative vertical accuracy means the altitude in the fix is meaningless.
        var altitude: Double?
        if let fix, fix.verticalAccuracy >= 0 { altitude = fix.altitude }

        pending = PendingSpot(
            photoData: prepared.photoData,
            thumbnailData: prepared.thumbnailData,
            coordinate: fix.map {
                Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            altitude: altitude,
            horizontalAccuracy: fix?.horizontalAccuracy,
            capturedAt: Date(),
            heading: camera.captureHeading,
            locationFromPhoto: false,
            saveToLibrary: true
        )
    }

    /// Asks for library access, then opens whichever picker will actually show photos.
    ///
    /// The order is the entire point. Presenting the shared-library picker first shows an empty grid
    /// when access is still undetermined, and an empty grid means nothing can be picked, which means
    /// the code that would have asked for access is never reached.
    private func presentLibrary() async {
        switch await PhotoService.resolveLibraryAccess().picker {
        case .some(.sharedLibrary):
            isImporting = true
        case .some(.outOfProcess):
            // Access was refused. The out-of-process picker still works and still shows everything,
            // so importing is not blocked — only the asset-location fallback is.
            isImportingWithoutLibrary = true
        case .none:
            // Only reachable if the prompt was dismissed without an answer. Asking again next tap is
            // better than opening a picker that would be empty.
            break
        }
    }

    private func handleImport(_ item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            importProblem = ImportProblem(
                title: "That photo could not be read",
                message: "Something went wrong loading it. Try another photo, or take a new one."
            )
            pickerItem = nil
            return
        }

        let prepared = await Task.detached(priority: .userInitiated) {
            PhotoService.prepare(imageData: raw)
        }.value

        // The picker sometimes strips GPS depending on library permissions, so fall back to the
        // Photos database before giving up on the location.
        var photoLocation = prepared.embeddedLocation
        if photoLocation == nil, let identifier = item.itemIdentifier {
            photoLocation = await PhotoService.location(forAssetIdentifier: identifier)
        }

        let fallback = location.coordinate
        if photoLocation == nil {
            importProblem = ImportProblem(
                title: "This photo has no location",
                message: noLocationMessage(hasFallback: fallback != nil)
            )
        }

        pending = PendingSpot(
            photoData: prepared.photoData,
            thumbnailData: prepared.thumbnailData,
            coordinate: photoLocation?.coordinate ?? fallback,
            altitude: photoLocation?.altitude,
            horizontalAccuracy: nil,
            capturedAt: photoLocation?.timestamp ?? prepared.captureDate ?? Date(),
            heading: nil,
            locationFromPhoto: photoLocation != nil,
            saveToLibrary: false
        )
        pickerItem = nil
    }

    /// Why there is no coordinate, and what happened instead.
    ///
    /// Without library access there is no `PHAsset` to fall back to, so a photo whose GPS the picker
    /// stripped has no second chance — worth saying, because that one is fixable in Settings whereas
    /// a photo genuinely taken without location is not.
    private func noLocationMessage(hasFallback: Bool) -> String {
        if !PhotoService.libraryAccess.canReadAssetLocations {
            return hasFallback
                ? "Tradewind has used where you are standing now. Allowing photo access in Settings lets it read the real location from photos that have one."
                : "Tradewind can't read the photo's location without photo access, and doesn't know where you are either. Allow both in Settings, or take a photo instead."
        }
        return hasFallback
            ? "It has no location saved, so Tradewind has used where you are standing now. You can pick a different photo if that's wrong."
            : "It has no location saved, and Tradewind doesn't know where you are either. Take a photo instead, or turn on location access."
    }

    private func save(_ spot: PendingSpot) {
        guard let coordinate = spot.coordinate else { return }

        let trip = spot.tripID.flatMap { id in trips.first { $0.id == id } }
        let created = store.createSpot(
            name: spot.name.trimmingCharacters(in: .whitespaces),
            coordinate: coordinate,
            altitude: spot.altitude,
            horizontalAccuracy: spot.horizontalAccuracy,
            capturedAt: spot.capturedAt,
            headingAtCapture: spot.heading,
            photoData: spot.photoData,
            thumbnailData: spot.thumbnailData,
            glyph: spot.glyph,
            kind: spot.kind,
            trip: trip
        )

        if spot.saveToLibrary {
            let photoData = spot.photoData
            let clLocation = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            Task { await PhotoService.saveToLibrary(imageData: photoData, location: clLocation) }
        }

        FeedbackService.shared.lightTap()
        pending = nil
        dismiss()
        router.openSpot(id: created.id)
    }
}

// MARK: - Review

/// Name it, mark it, file it. Everything here is optional except that it has a location.
private struct ReviewView: View {
    @Environment(\.theme) private var theme

    var pending: PendingSpot
    var trips: [Trip]
    var unitPreference: UnitPreference
    var currentCoordinate: Coordinate?
    var onChange: (PendingSpot) -> Void
    var onCancel: () -> Void
    var onSave: (PendingSpot) -> Void

    @FocusState private var isNameFocused: Bool

    // Split into small typed pieces on purpose: as one expression this screen was more than
    // the Swift type-checker would accept.
    var body: some View {
        ZStack {
            ThemedBackground(theme: theme)

            ScrollView {
                VStack(spacing: 18) {
                    photo
                    detailsCard
                    coordinateSummary
                    buttons
                }
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var photo: some View {
        PhotoView(data: pending.photoData, maxDimension: 1_200)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topLeading) { provenancePill.padding(14) }
            .padding(.horizontal, 18)
    }

    /// Says plainly where the coordinate came from. Someone importing an old photo needs to know
    /// whether Tradewind is using the photo's location or the one they are standing in.
    private var provenancePill: some View {
        PillLabel(
            text: pending.locationFromPhoto ? "Location from photo" : "Location from here",
            symbol: pending.locationFromPhoto ? "photo" : "location.fill",
            prominent: true
        )
    }

    private var detailsCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                nameField
                Divider().overlay(theme.textMuted.opacity(0.2))
                kindPicker
                Divider().overlay(theme.textMuted.opacity(0.2))
                glyphPicker
                if !trips.isEmpty {
                    Divider().overlay(theme.textMuted.opacity(0.2))
                    tripPicker
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Call it something").eyebrowStyle(theme: theme)
            TextField("The waterfall with the rope swing", text: nameBinding)
                .font(theme.bodyTextFont)
                .foregroundStyle(theme.text)
                .focused($isNameFocused)
                .submitLabel(.done)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { pending.name },
            set: { newValue in
                var copy = pending
                copy.name = newValue
                onChange(copy)
            }
        )
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is it").eyebrowStyle(theme: theme)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(PlaceKind.pickable) { candidate in
                        ChipButton(
                            title: candidate.label,
                            symbol: candidate.symbol,
                            isSelected: pending.kind == candidate
                        ) {
                            var copy = pending
                            copy.kind = candidate
                            onChange(copy)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var glyphPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mark").eyebrowStyle(theme: theme)
            GlyphPicker(selected: pending.glyph) { glyph in
                var copy = pending
                copy.glyph = glyph
                onChange(copy)
            }
        }
    }

    private var tripPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip").eyebrowStyle(theme: theme)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ChipButton(title: "None", isSelected: pending.tripID == nil) {
                        assign(tripID: nil)
                    }
                    ForEach(trips) { trip in
                        ChipButton(
                            title: trip.displayName,
                            symbol: "suitcase.fill",
                            isSelected: pending.tripID == trip.id
                        ) {
                            assign(tripID: trip.id)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func assign(tripID: UUID?) {
        var copy = pending
        copy.tripID = tripID
        onChange(copy)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if pending.coordinate != nil {
                PrimaryButton(title: "Save this spot", symbol: "checkmark") {
                    onSave(pending)
                }
            } else {
                Text("Tradewind can't save a spot without a location.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
            }
            SecondaryButton(title: "Retake", symbol: "arrow.counterclockwise", action: onCancel)
        }
        .padding(.horizontal, 18)
    }

    private var coordinateSummary: some View {
        Surface(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    if let coordinate = pending.coordinate {
                        Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(theme.captionFont)
                            .monospacedDigit()
                            .foregroundStyle(theme.text)
                    } else {
                        Text("No location")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondary)
                    }
                    if let accuracy = pending.horizontalAccuracy {
                        Text("Accurate to about \(Int(accuracy)) m")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textMuted)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
    }
}

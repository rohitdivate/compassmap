import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

/// Everything about one spot: the photo full-size, where it is, when you were there, when the
/// light will be good, and the handful of things you might want to do with it.
struct SpotDetailView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let spot: Spot
    /// When set, the delete confirmation defers to the presenter instead of deleting here —
    /// a sheet must not delete the very spot whose arrow screen is presenting it while the
    /// dismissal is still animating.
    var onDeleteConfirmed: (() -> Void)?

    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var location = LocationService.shared
    @State private var draftName: String = ""
    @State private var draftNote: String = ""
    @State private var isEditingName = false
    @State private var isConfirmingDelete = false
    @State private var shareImage: ShareablePostcard?
    /// The real walking route to this spot, fetched once on appear.
    @State private var walkingRoute: WalkingRouteService.Answer?

    private var store: SpotStore { SpotStore(context: modelContext) }

    private static let glyphs = ["📍", "🌊", "🏝️", "🌴", "🍹", "🛺", "⛩️", "🐘", "☕️", "🏛️", "🌅", "🥥"]

    var body: some View {
        content
            .alert("Rename spot", isPresented: $isEditingName) {
                TextField("Name", text: $draftName)
                Button("Save") { store.rename(spot, to: draftName) }
                Button("Cancel", role: .cancel) { draftName = spot.name }
            }
            .alert("Delete this spot?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) {
                    if let onDeleteConfirmed {
                        onDeleteConfirmed()
                    } else {
                        store.delete(spot)
                    }
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It moves to Recently Deleted, in Settings, for \(TrashPolicy.retentionDays) days — then it's gone for good.")
            }
            .sheet(item: $shareImage) { postcard in
                ShareSheet(items: shareItems(for: postcard))
            }
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photo
                    distanceRow
                    facts
                    glyphPicker
                    tripAssignment
                    noteField
                    kindSection
                    reminderSection
                    arrivalSection
                    actions
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background {
                ThemedBackground(theme: theme)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                        .accessibilityIdentifier("detail-done")
                }
            }
        }
        .tint(theme.accent)
        .onAppear {
            draftName = spot.name
            draftNote = spot.note ?? ""
            // Names written by the old geocoding rule preferred the nearest business; looking at
            // a spot quietly upgrades it to the street-or-district form.
            store.refreshPlaceName(for: spot)
            fetchWalkingRoute()
        }
    }

    /// The postcard image plus the deep link, so a recipient gets both the picture and a way in.
    private func shareItems(for postcard: ShareablePostcard) -> [Any] {
        var items: [Any] = [postcard.image]
        if let url = spot.deepLinkURL { items.append(url) }
        return items
    }

    // MARK: - Photo

    private var photo: some View {
        ZStack(alignment: .bottomLeading) {
            SpotPhotoView(spot: spot, sizeClass: .hero)
                .frame(height: 340)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: spot.capturedAt))
                    .eyebrowStyle(theme: theme)
                Button {
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(spot.displayName)
                            .font(theme.titleFont)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .buttonStyle(PressableStyle())
            }
            .padding(18)
        }
        .frame(height: 340)
        // The photo lends its colour to the bar region above rather than stopping at a hard
        // edge: the system mirrors and blurs it outward, and the Done capsule floats on it.
        .backgroundExtensionEffect()
    }

    // MARK: - Distance

    private var distanceRow: some View {
        Surface {
            HStack(spacing: 16) {
                if let bearing = bearingToSpot {
                    MiniArrow(theme: theme, angle: bearing, size: 40)
                }
                distanceBlock
                Spacer()
                if let bearing = bearingToSpot {
                    compassBlock(bearing)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // Coarse (~11 m) coordinate on purpose: reading the raw fix here re-rendered the whole
    // sheet every 3 m, and a static readout does not need that resolution.
    private var metresToSpot: Double? {
        location.coarseCoordinate.map { BearingMath.distance(from: $0, to: spot.coordinate) }
    }

    private var bearingToSpot: Double? {
        location.coarseCoordinate.map { BearingMath.initialBearing(from: $0, to: spot.coordinate) }
    }

    @ViewBuilder
    private var distanceBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let metres = metresToSpot {
                let readout = DistanceFormatting.readout(
                    metres: metres,
                    preference: settings.unitPreference
                )
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(readout.value)
                        .font(theme.readoutFont)
                        .monospacedDigit()
                    Text(readout.unit).font(theme.readoutUnitFont)
                }
                .foregroundStyle(theme.text)

                walkingLine(crowMetres: metres)
            } else {
                Text("No location fix")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    /// The routed walk when Apple's router has answered, the detour-factored estimate before —
    /// never the raw crow-flies time, which reads shorter than any street can deliver.
    @ViewBuilder
    private func walkingLine(crowMetres: Double) -> some View {
        switch RoutePolicy.readout(
            routeMetres: walkingRoute?.distanceMetres,
            routeSeconds: walkingRoute?.expectedSeconds,
            crowMetres: crowMetres
        ) {
        case .routed(let minutes, let metres):
            Text("\(minutes) min walk · \(DistanceFormatting.string(metres: metres, preference: settings.unitPreference)) on foot")
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
        case .estimated(let minutes):
            Text("~\(minutes) min walk")
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
        case .none:
            EmptyView()
        }
    }

    private func fetchWalkingRoute() {
        guard !AppSettings.isUITesting else { return }
        guard let origin = location.coordinate, let crow = metresToSpot,
              crow >= RoutePolicy.minimumUsefulCrowMetres else { return }
        let destination = spot.coordinate
        Task { @MainActor in
            walkingRoute = await WalkingRouteService.shared.walkingRoute(from: origin, to: destination)
        }
    }

    private func compassBlock(_ bearing: Double) -> some View {
        VStack(spacing: 0) {
            Text(BearingMath.compassPoint(forBearing: bearing))
                .font(theme.cardNumberFont)
                .foregroundStyle(theme.accent)
            Text("\(Int(bearing.rounded()))°")
                .font(theme.labelFont)
                .foregroundStyle(theme.textMuted)
        }
    }

    // MARK: - Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Where it is")
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    mapInset
                    factRows.padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// A rendered snapshot, not a live `MKMapView`: booting a whole map engine was the most
    /// expensive single part of opening this sheet, for 600 m of non-interactive context.
    private var mapInset: some View {
        SpotMapInset(
            spotID: spot.id,
            latitude: spot.latitude,
            longitude: spot.longitude,
            theme: theme
        )
        .frame(height: 160)
    }

    @ViewBuilder
    private var factRows: some View {
        VStack(spacing: 0) {
            if let area = spot.placeName, !area.isEmpty {
                // The line a person would say — "Baker Street, London" — above the raw numbers,
                // which stay for anyone who actually wants them.
                FactRow(symbol: "map.fill", label: "Area", value: area)
            }
            FactRow(
                symbol: "mappin.and.ellipse",
                label: "Coordinates",
                value: String(format: "%.5f, %.5f", spot.latitude, spot.longitude)
            )
            if let altitude = spot.altitude {
                FactRow(
                    symbol: "mountain.2.fill",
                    label: "Elevation",
                    value: DistanceFormatting.string(
                        metres: altitude,
                        preference: settings.unitPreference
                    )
                )
            }
            if let accuracy = spot.horizontalAccuracy {
                FactRow(symbol: "scope", label: "Fix accuracy", value: "±\(Int(accuracy)) m")
            }
            if let sun = SolarTimes.events(for: Date(), at: spot.coordinate) {
                FactRow(
                    symbol: "sun.horizon.fill",
                    label: "Best light",
                    value: SolarTimes.describeGoldenHour(sun)
                )
            }
        }
    }

    // MARK: - Glyph

    private var glyphPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "For when there's no photo", title: "Mark")
                .padding(.horizontal, 18)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.glyphs, id: \.self) { glyph in
                        glyphButton(glyph)
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func glyphButton(_ glyph: String) -> some View {
        let isSelected = spot.glyph == glyph
        return Button {
            store.update(spot, glyph: isSelected ? nil : glyph)
            FeedbackService.shared.lightTap()
        } label: {
            Text(glyph)
                .font(.system(size: 22))
                .frame(width: 46, height: 46)
                .background {
                    Circle().fill(isSelected ? theme.accent.opacity(0.28) : theme.surfaceRaised)
                }
                .overlay {
                    Circle().strokeBorder(
                        isSelected ? theme.accent : .white.opacity(0.12),
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Trip

    private var tripAssignment: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Trip")
                .padding(.horizontal, 18)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ChipButton(title: "None", isSelected: spot.trip == nil) {
                        store.assign(spot, to: nil)
                    }
                    ForEach(trips) { trip in
                        ChipButton(
                            title: trip.displayName,
                            symbol: "suitcase.fill",
                            isSelected: spot.trip?.id == trip.id
                        ) {
                            store.assign(spot, to: trip)
                            FeedbackService.shared.lightTap()
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Note

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "Optional", title: "Note")
            Surface {
                TextField(
                    "The one with the mango tree out front",
                    text: $draftNote,
                    axis: .vertical
                )
                .font(theme.bodyTextFont)
                .foregroundStyle(theme.text)
                .lineLimit(3...6)
                .onSubmit { saveNoteIfChanged() }
            }
        }
        .padding(.horizontal, 18)
        // Debounced, not per keystroke: `store.update` is a SwiftData save, and typing a
        // forty-character note used to mean forty disk commits. The id-task restarts on every
        // edit, so the save lands one second after the typing stops...
        .task(id: draftNote) {
            guard draftNote != (spot.note ?? "") else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNoteIfChanged()
        }
        // ...and closing the sheet mid-debounce must not eat the note.
        .onDisappear { saveNoteIfChanged() }
    }

    private func saveNoteIfChanged() {
        let note = draftNote.isEmpty ? nil : draftNote
        guard note != spot.note else { return }
        store.update(spot, note: note)
    }

    // MARK: - Kind and reminder

    /// What sort of place this is. Changing it re-badges the spot everywhere a photo is absent —
    /// cards, pins, widgets.
    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Kind")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(PlaceKind.pickable) { candidate in
                        ChipButton(
                            title: candidate.label,
                            symbol: candidate.symbol,
                            isSelected: spot.placeKind == candidate
                        ) {
                            store.update(spot, kind: candidate)
                            FeedbackService.shared.lightTap()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
    }

    /// The meter timer. Active shows a live countdown and a way out; inactive shows the presets.
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "Meters, check-outs, closing times", title: "Remind me")
            Surface(padding: 14) {
                if let fireDate = spot.reminderAt, MeterReminder.isActive(fireDate, now: Date()) {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.highlight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reminder set")
                                .font(theme.cardTitleFont)
                                .foregroundStyle(theme.text)
                            Text(fireDate, style: .relative)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textMuted)
                                .monospacedDigit()
                        }
                        Spacer()
                        Button("Cancel") { store.setReminder(spot, at: nil) }
                            .font(theme.sans(13, weight: .medium))
                            .foregroundStyle(theme.negative)
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(MeterReminder.presets, id: \.self) { preset in
                                ChipButton(
                                    title: MeterReminder.label(for: preset),
                                    symbol: "bell.fill",
                                    isSelected: false
                                ) {
                                    store.setReminder(
                                        spot,
                                        at: MeterReminder.fireDate(after: preset, from: Date())
                                    )
                                    FeedbackService.shared.lightTap()
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Arrival alert

    /// A geofence around this spot: come within 200 m and a notification names it. The honest
    /// caveat lives right under the toggle — without Always location access, iOS only delivers
    /// entry events while the app is open, which for an arrival alert is nearly useless.
    private var arrivalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "When you come within 200 m", title: "Arrival alert")
            Surface(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: alertsBinding) {
                        HStack(spacing: 10) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text("Alert me when I'm near")
                                .font(theme.cardTitleFont)
                                .foregroundStyle(theme.text)
                        }
                    }
                    .tint(theme.accent)
                    .accessibilityIdentifier("arrival-toggle")

                    if spot.alertsEnabled && location.authorizationStatus != .authorizedAlways {
                        arrivalCaveat
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { spot.alertsEnabled },
            set: { enabled in
                store.setAlertsEnabled(spot, enabled)
                FeedbackService.shared.lightTap()
            }
        )
    }

    @ViewBuilder
    private var arrivalCaveat: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Only fires while the app is open unless location access is set to Always.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if location.authorizationStatus == .authorizedWhenInUse {
                Button("Allow Always access") {
                    location.requestAlwaysAuthorization()
                }
                .font(theme.sans(13, weight: .medium))
                .foregroundStyle(theme.accent)
            }
        }
    }

    // MARK: - Actions

    /// System glass buttons rather than the design system's flat ones — this row is the
    /// sheet's chrome, the one place on it where glass belongs. The prominent style carries
    /// the accent; delete keeps its destructive role so the system colours it.
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                store.setPinned(spot.isPinned ? nil : spot)
                FeedbackService.shared.lightTap()
            } label: {
                Label(
                    spot.isPinned ? "Unpin from widgets" : "Pin to widgets",
                    systemImage: spot.isPinned ? "pin.slash.fill" : "pin.fill"
                )
                .font(theme.sans(15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.accent)

            Button {
                makePostcard()
            } label: {
                Label("Share as a postcard", systemImage: "square.and.arrow.up")
                    .font(theme.sans(14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glass)
            .tint(theme.text)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete spot", systemImage: "trash")
                    .font(theme.sans(14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("detail-delete")
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    /// Renders the share card on demand rather than keeping one around: it is a view snapshot,
    /// and the view it snapshots depends on the current theme.
    private func makePostcard() {
        let card = PostcardView(
            spot: spot,
            theme: theme,
            distanceText: location.coordinate.map { origin in
                DistanceFormatting.string(
                    metres: BearingMath.distance(from: origin, to: spot.coordinate),
                    preference: settings.unitPreference
                )
            }
        )
        guard let image = PostcardRenderer.render(card) else { return }
        shareImage = ShareablePostcard(image: image)
        FeedbackService.shared.lightTap()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Fact row

private struct FactRow: View {
    @Environment(\.theme) private var theme

    var symbol: String
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            Text(label)
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
            Spacer()
            Text(value)
                .font(theme.captionFont)
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Map inset

/// The 600 m context map as a cached image, with the pin drawn on top in SwiftUI so it stays
/// themable. The snapshot resolves async; until it does, the raised surface holds the space.
private struct SpotMapInset: View {
    var spotID: UUID
    var latitude: Double
    var longitude: Double
    var theme: Theme

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let key = MapSnapshotKey(
                spotID: spotID,
                latitude: latitude,
                longitude: longitude,
                pointWidth: proxy.size.width,
                pointHeight: proxy.size.height,
                scale: displayScale,
                themeID: theme.id
            )
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(theme.surfaceRaised)
                }
                pin
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: key) {
                guard proxy.size.width > 0 else { return }
                image = await MapSnapshotCache.shared.image(
                    for: key,
                    isDark: theme.colorScheme == .dark
                )
            }
        }
    }

    /// The region is centred on the spot, so the pin is simply centred.
    private var pin: some View {
        ZStack {
            Circle()
                .fill(theme.accent)
                .frame(width: 14, height: 14)
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

// MARK: - Sharing

struct ShareablePostcard: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

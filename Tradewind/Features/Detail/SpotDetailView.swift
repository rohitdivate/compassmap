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

    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var location = LocationService.shared
    @State private var draftName: String = ""
    @State private var draftNote: String = ""
    @State private var isEditingName = false
    @State private var isConfirmingDelete = false
    @State private var shareImage: ShareablePostcard?

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
                    store.delete(spot)
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("The photo goes with it. This cannot be undone.")
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
            PhotoView(data: spot.photoData, maxDimension: 1_600, glyph: spot.glyph)
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
        .clipShape(RoundedRectangle(cornerRadius: 0))
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

    private var metresToSpot: Double? {
        location.coordinate.map { BearingMath.distance(from: $0, to: spot.coordinate) }
    }

    private var bearingToSpot: Double? {
        location.coordinate.map { BearingMath.initialBearing(from: $0, to: spot.coordinate) }
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

                if let walk = DistanceFormatting.walkingTime(metres: metres) {
                    Text(walk)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                }
            } else {
                Text("No location fix")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textMuted)
            }
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

    private var mapInset: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            Marker(spot.displayName, coordinate: coordinate)
                .tint(theme.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 160)
        .allowsHitTesting(false)
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
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
                .onSubmit { store.update(spot, note: draftNote) }
            }
        }
        .padding(.horizontal, 18)
        .onChange(of: draftNote) { _, newValue in
            store.update(spot, note: newValue.isEmpty ? nil : newValue)
        }
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

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: spot.isPinned ? "Unpin from widgets" : "Pin to widgets",
                symbol: spot.isPinned ? "pin.slash.fill" : "pin.fill"
            ) {
                store.setPinned(spot.isPinned ? nil : spot)
                FeedbackService.shared.lightTap()
            }

            SecondaryButton(title: "Share as a postcard", symbol: "square.and.arrow.up") {
                makePostcard()
            }

            SecondaryButton(title: "Delete spot", symbol: "trash") {
                isConfirmingDelete = true
            }
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

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
                }
            }
        }
        .tint(theme.accent)
        .onAppear {
            draftName = spot.name
            draftNote = spot.note ?? ""
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

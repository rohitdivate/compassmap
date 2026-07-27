import CoreLocation
import SwiftData
import SwiftUI

/// One tap: save where you are standing, no photo, no ceremony.
///
/// This is the loop every parking app is built around — pin the car, the hotel door, the tent —
/// and it is deliberately not the capture flow. A photo is the right identity for a view worth
/// returning to; a parking bay needs a kind, maybe a floor note, maybe a meter timer, and to be
/// saved in under two seconds.
///
/// Everything on it is optional except the location. Tapping Save with nothing filled in produces
/// a spot named by date at your coordinate, which is already useful; the rest is refinement.
struct SaveHereView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var location = LocationService.shared
    @State private var kind: PlaceKind = .place
    @State private var name = ""
    @State private var note = ""
    @State private var reminderDuration: TimeInterval?
    @FocusState private var focused: Field?

    private enum Field { case name, note }

    private var store: SpotStore { SpotStore(context: modelContext) }

    /// The one seam for UI tests: the CI simulator has no location fix, and a save button that is
    /// always disabled there would make this flow untestable. Real builds never take this branch.
    private var coordinate: Coordinate? {
        location.coordinate ?? (AppSettings.isUITesting
            ? Coordinate(latitude: 51.5074, longitude: -0.1278)
            : nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    kindPicker
                    nameField
                    noteField
                    reminderPicker
                    fixSummary
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { ThemedBackground(theme: theme) }
            .navigationTitle("Save here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) { saveButton }
        }
        .tint(theme.accent)
        .presentationDetents([.large])
        .onAppear { location.requestOneShotLocation() }
        .accessibilityElement(children: .contain)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(theme.textMuted)
        }
    }

    // MARK: - Kind

    /// What sort of place, first — it drives the default name and the symbol everywhere the spot
    /// appears without a photo.
    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What is here?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(PlaceKind.pickable) { candidate in
                    kindTile(candidate)
                }
            }
            Text(kind.hint)
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
        }
    }

    private func kindTile(_ candidate: PlaceKind) -> some View {
        let isSelected = kind == candidate
        return Button {
            kind = candidate
            FeedbackService.shared.lightTap()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: candidate.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(candidate.label)
                    .font(theme.sans(11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? theme.onAccent : theme.text)
            .background {
                RoundedRectangle(cornerRadius: theme.radii.row, style: .continuous)
                    .fill(isSelected ? theme.accent : theme.surface)
            }
            .overlay {
                if !isSelected, theme.usesHairlines {
                    RoundedRectangle(cornerRadius: theme.radii.row, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("kind-\(candidate.rawValue)")
    }

    // MARK: - Name and note

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Name")
            Surface(padding: 14) {
                TextField(defaultName, text: $name)
                    .font(theme.bodyTextFont)
                    .focused($focused, equals: .name)
                    .submitLabel(.done)
                    .accessibilityIdentifier("save-here-name")
            }
        }
    }

    /// "Stay", "Transit" — the kind is a better blank name than a timestamp.
    private var defaultName: String {
        kind == .place ? "Name this place" : kind.label
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "Level 3, aisle F", title: "Note for later")
            Surface(padding: 14) {
                TextField("The detail you'll want when you're back", text: $note, axis: .vertical)
                    .font(theme.bodyTextFont)
                    .lineLimit(1...3)
                    .focused($focused, equals: .note)
            }
        }
    }

    // MARK: - Reminder

    private var reminderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "Meters, check-outs, closing times", title: "Remind me in")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MeterReminder.presets, id: \.self) { preset in
                        ChipButton(
                            title: MeterReminder.label(for: preset),
                            symbol: "bell.fill",
                            isSelected: reminderDuration == preset
                        ) {
                            reminderDuration = reminderDuration == preset ? nil : preset
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Fix

    @ViewBuilder
    private var fixSummary: some View {
        if let accuracy = location.currentLocation?.horizontalAccuracy, accuracy >= 0 {
            HStack(spacing: 7) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.positive)
                Text("Good fix — accurate to about \(Int(accuracy)) m")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
            }
        } else if coordinate == nil {
            HStack(spacing: 7) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                Text("Waiting for your location — Save switches on when there is a fix.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        PrimaryButton(title: "Save this spot", symbol: "mappin.and.ellipse") { save() }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .disabled(coordinate == nil)
            .opacity(coordinate == nil ? 0.5 : 1)
            .accessibilityIdentifier("save-here-confirm")
    }

    private func save() {
        guard let coordinate else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let fix = location.currentLocation
        let altitude: Double? = (fix?.verticalAccuracy ?? -1) >= 0 ? fix?.altitude : nil
        let spot = store.createSpot(
            // A non-.place kind makes a sensible name on its own; a bare date does not.
            name: trimmedName.isEmpty ? (kind == .place ? "" : kind.label) : trimmedName,
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: fix?.horizontalAccuracy,
            photoData: nil,
            thumbnailData: nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            kind: kind
        )
        if let reminderDuration {
            store.setReminder(spot, at: MeterReminder.fireDate(after: reminderDuration, from: Date()))
        }

        FeedbackService.shared.lightTap()
        dismiss()
    }
}

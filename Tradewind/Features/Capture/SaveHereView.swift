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
    @State private var search = PlaceSearchService()
    @State private var kind: PlaceKind = .place
    @State private var kindWasChosen = false
    @State private var name = ""
    @State private var note = ""
    @State private var reminderDuration: TimeInterval?
    @State private var mode: WhereMode = .here
    @State private var planned: PlannedPlace.Resolved?
    @FocusState private var focused: Field?

    private enum Field { case name, note, search }

    /// Standing here, or planning somewhere else — a booked hotel, tomorrow's restaurant.
    private enum WhereMode { case here, elsewhere }

    private var store: SpotStore { SpotStore(context: modelContext) }

    /// The one seam for UI tests: the CI simulator has no location fix, and a save button that is
    /// always disabled there would make this flow untestable. Real builds never take this branch.
    private var hereCoordinate: Coordinate? {
        location.coordinate ?? (AppSettings.isUITesting
            ? Coordinate(latitude: 51.5074, longitude: -0.1278)
            : nil)
    }

    /// What Save will actually write: where you stand, or the searched place.
    private var coordinate: Coordinate? {
        switch mode {
        case .here: return hereCoordinate
        case .elsewhere: return planned?.coordinate
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    whereSection
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

    // MARK: - Where

    /// Right here is the two-second path; Somewhere else is planning — search an address or a
    /// place by name, with Apple's own autocomplete, and save it before you have ever been.
    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Where?")
            HStack(spacing: 8) {
                ChipButton(title: "Right here", symbol: "location.fill", isSelected: mode == .here) {
                    mode = .here
                    FeedbackService.shared.lightTap()
                }
                ChipButton(
                    title: "Somewhere else",
                    symbol: "magnifyingglass",
                    isSelected: mode == .elsewhere
                ) {
                    mode = .elsewhere
                    focused = .search
                    FeedbackService.shared.lightTap()
                }
                .accessibilityIdentifier("where-elsewhere")
            }
            if mode == .elsewhere {
                if let planned {
                    plannedSummary(planned)
                } else {
                    addressSearch
                }
            }
        }
    }

    private var addressSearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            Surface(padding: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    TextField("Search an address or place", text: searchQuery)
                        .font(theme.bodyTextFont)
                        .focused($focused, equals: .search)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("address-search-field")
                }
            }
            ForEach(search.suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
    }

    private func suggestionRow(_ suggestion: PlaceSearchService.Suggestion) -> some View {
        Button {
            Task { @MainActor in
                guard let resolved = await search.resolve(suggestion) else { return }
                planned = resolved
                // The guess only fills a kind nobody has chosen — a chosen badge is not
                // second-guessed by a category lookup.
                if !kindWasChosen { kind = resolved.kindGuess }
                focused = nil
                FeedbackService.shared.lightTap()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: theme.radii.row, style: .continuous)
                    .fill(theme.surface)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .accessibilityIdentifier("address-result-\(suggestion.id)")
    }

    private func plannedSummary(_ place: PlannedPlace.Resolved) -> some View {
        Surface(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.positive)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .accessibilityIdentifier("planned-place-name")
                    if let area = place.areaLine {
                        Text(area)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Change") {
                    planned = nil
                    search.query = ""
                    focused = .search
                }
                .font(theme.sans(13, weight: .medium))
                .foregroundStyle(theme.accent)
            }
        }
    }

    private var searchQuery: Binding<String> {
        Binding(get: { search.query }, set: { search.query = $0 })
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
            kindWasChosen = true
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

    /// The searched place's own name, else "Stay", "Transit" — the kind is a better blank name
    /// than a timestamp.
    private var defaultName: String {
        if let planned, mode == .elsewhere { return planned.name }
        return kind == .place ? "Name this place" : kind.label
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
        if mode == .elsewhere {
            if planned == nil {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                    Text("Pick a place above — Save switches on once one is chosen.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                }
            }
        } else if let accuracy = location.currentLocation?.horizontalAccuracy, accuracy >= 0 {
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
        // A planned place has no fix of yours — its accuracy is the map's, not the GPS's.
        let fix = mode == .here ? location.currentLocation : nil
        let altitude: Double? = (fix?.verticalAccuracy ?? -1) >= 0 ? fix?.altitude : nil

        let fallbackName: String
        if mode == .elsewhere, let planned {
            fallbackName = planned.name
        } else {
            // A non-.place kind makes a sensible name on its own; a bare date does not.
            fallbackName = kind == .place ? "" : kind.label
        }

        let spot = store.createSpot(
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: fix?.horizontalAccuracy,
            photoData: nil,
            thumbnailData: nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            kind: kind,
            // The search already produced the area line; passing it skips a needless geocode.
            placeName: mode == .elsewhere ? planned?.areaLine : nil
        )
        if let reminderDuration {
            store.setReminder(spot, at: MeterReminder.fireDate(after: reminderDuration, from: Date()))
        }

        FeedbackService.shared.lightTap()
        dismiss()
    }
}

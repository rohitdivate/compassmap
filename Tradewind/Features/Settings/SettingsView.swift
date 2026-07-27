import SwiftUI
import UIKit

/// Preferences, and the theme picker — which is the part people will actually come here for.
struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var location = LocationService.shared
    @State private var liveActivity = LiveActivityService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ThemeGallery()
                    measurements
                    compassSection
                    feedbackSection
                    syncSection
                    widgetHelp
                    about
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)
            .background {
                ThemedBackground(theme: theme)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings-done")
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-screen")
    }

    // MARK: - Units

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Distances")
            Surface(padding: 14) {
                VStack(spacing: 4) {
                    ForEach(UnitPreference.allCases, id: \.rawValue) { preference in
                        SettingsRadioRow(
                            title: preference.label,
                            detail: sample(for: preference),
                            isSelected: settings.unitPreference == preference
                        ) {
                            settings.unitPreference = preference
                            FeedbackService.shared.lightTap()
                        }
                    }
                }
            }
        }
    }

    private func sample(for preference: UnitPreference) -> String {
        // Shows what the choice actually looks like, which beats explaining it.
        let near = DistanceFormatting.string(metres: 240, preference: preference)
        let far = DistanceFormatting.string(metres: 4_300, preference: preference)
        return "\(near) · \(far)"
    }

    // MARK: - Bindings
    //
    // Lifted out of the view bodies: an inline Binding(get:set:) is a closure pair the
    // type-checker has to work through, and several per section adds up fast.

    private var trueNorth: Binding<Bool> {
        Binding(get: { settings.usesTrueNorth }, set: { settings.usesTrueNorth = $0 })
    }

    private var haptics: Binding<Bool> {
        Binding(get: { settings.hapticsEnabled }, set: { settings.hapticsEnabled = $0 })
    }

    private var sound: Binding<Bool> {
        Binding(
            get: { settings.soundEnabled },
            set: { isOn in
                settings.soundEnabled = isOn
                // Play the chime as it is switched on, so the choice is audible immediately.
                if isOn { FeedbackService.shared.onTarget() }
            }
        )
    }

    private var cloudSync: Binding<Bool> {
        Binding(get: { settings.cloudSyncEnabled }, set: { settings.cloudSyncEnabled = $0 })
    }

    // MARK: - Compass

    private var compassSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Compass")
            Surface(padding: 14) {
                VStack(spacing: 10) {
                    SettingsToggleRow(
                        symbol: "location.north.line.fill",
                        title: "Point to true north",
                        detail: "Matches a map. Turn off to follow the magnetic pole instead.",
                        isOn: trueNorth
                    )
                    divider
                    locationRow
                    if location.authorizationStatus == .authorizedWhenInUse {
                        divider
                        backgroundRow
                    }
                }
            }
        }
    }

    private var locationRow: some View {
        SettingsInfoRow(
            symbol: location.isAuthorized ? "location.fill" : "location.slash.fill",
            title: "Location access",
            detail: locationStatusText,
            actionTitle: location.isAuthorized ? nil : "Allow"
        ) {
            if location.isDenied {
                openSystemSettings()
            } else {
                location.requestWhenInUseAuthorization()
            }
        }
    }

    private var backgroundRow: some View {
        SettingsInfoRow(
            symbol: "clock.arrow.circlepath",
            title: "Background updates",
            detail: "Allow 'Always' so widgets and the Lock Screen keep up while Tradewind is closed.",
            actionTitle: "Allow always"
        ) {
            location.requestAlwaysAuthorization()
        }
    }

    private var divider: some View {
        Divider().overlay(theme.textMuted.opacity(0.2))
    }

    private var locationStatusText: String {
        switch location.authorizationStatus {
        case .authorizedAlways: return "Always — widgets stay up to date"
        case .authorizedWhenInUse: return "While using Tradewind"
        case .denied: return "Denied. Distances and the arrow will not work."
        case .restricted: return "Restricted by device settings."
        default: return "Not asked yet"
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Feel")
            Surface(padding: 14) {
                VStack(spacing: 10) {
                    SettingsToggleRow(
                        symbol: "hand.tap.fill",
                        title: "Haptic pulse",
                        detail: "Taps you as you walk, faster the closer you get.",
                        isOn: haptics
                    )
                    divider
                    SettingsToggleRow(
                        symbol: "speaker.wave.2.fill",
                        title: "Sound",
                        detail: "A soft chime when you're facing the right way and when you arrive.",
                        isOn: sound
                    )
                }
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "iCloud")
            Surface(padding: 14) {
                VStack(spacing: 10) {
                    SettingsToggleRow(
                        symbol: "icloud.fill",
                        title: "Sync my spots",
                        detail: "Keeps spots and photos on all your devices.",
                        isOn: cloudSync
                    )
                    divider
                    persistenceStatus
                }
            }
        }
    }

    /// Reports what the store actually managed to open, not what the toggle above asked for.
    private var persistenceStatus: some View {
        let mode = settings.persistenceMode
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(mode.isHealthy ? theme.accent : theme.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.summary)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.text)
                explanation(for: mode)
                reopenHint(for: mode)
            }
            Spacer(minLength: 0)
        }
    }

    /// Why, not just what — "widgets unavailable" reads as something you did wrong otherwise, and on
    /// a free Apple ID it is nothing of the sort.
    @ViewBuilder
    private func explanation(for mode: PersistenceMode) -> some View {
        if let explanation = mode.explanation {
            Text(explanation)
                .font(theme.labelFont)
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Only worth saying when reopening could actually change the answer. Without an App Group it
    /// cannot, and promising otherwise sends someone to relaunch for nothing.
    @ViewBuilder
    private func reopenHint(for mode: PersistenceMode) -> some View {
        if settings.cloudSyncEnabled, mode != .syncing, mode.respondsToCloudToggle {
            Text("Changing this takes effect next time Tradewind opens.")
                .font(theme.labelFont)
                .foregroundStyle(theme.textMuted)
        }
    }

    // MARK: - Widgets

    private var widgetHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "Home screen", title: "Widgets")
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Touch and hold your home screen, tap the plus, and search for Tradewind.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                    ForEach(widgetLines, id: \.self) { line in
                        bullet(line)
                    }
                    Text("Pin a spot to choose which one the small widget follows — long-press any spot to pin it.")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textMuted)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(theme.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(theme.captionFont)
                .foregroundStyle(theme.text)
        }
    }

    private let widgetLines = [
        "Small — the arrow and distance to your pinned spot.",
        "Medium — your three nearest spots at once.",
        "Large — the photo, the arrow, and the nearest three.",
        "Lock Screen — distance in a circle, inline, or as a list.",
    ]

    // MARK: - About

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tradewind")
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                    Text("Photograph a place. Walk away. Come back to it.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                    Text(versionLine)
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textMuted)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Theme gallery

/// The theme picker. Each tile is a live miniature of the real backdrop and arrow, because a
/// row of colour swatches does not tell you what the app will feel like.
struct ThemeGallery: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(eyebrow: "Pick your weather", title: "Look")

            LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 12) {
                ForEach(ThemeCatalog.all) { candidate in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            settings.themeID = candidate.id
                        }
                        FeedbackService.shared.lightTap()
                    } label: {
                        ThemeTile(
                            candidate: candidate,
                            isSelected: settings.themeID == candidate.id
                        )
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .accessibilityLabel("\(candidate.name) theme")
                    .accessibilityAddTraits(settings.themeID == candidate.id ? [.isSelected] : [])
                }
            }
        }
    }
}

private struct ThemeTile: View {
    var candidate: Theme
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            swatch
            caption
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { border }
        .shadow(color: .black.opacity(0.3), radius: isSelected ? 14 : 6, y: 5)
    }

    /// A miniature of the mood rather than a colour chip: the real canvas, a card treated the way
    /// that mood treats cards, the arrow, and one pill in the accent. It shows how the app will
    /// *behave*, which two swatches of colour cannot.
    private var swatch: some View {
        ZStack {
            candidate.canvas
            if candidate.grainOpacity > 0 {
                FilmGrain(opacity: candidate.grainOpacity, tint: candidate.text, density: 260)
            }

            HStack(spacing: 10) {
                ArrowShape()
                    .fill(candidate.arrowGradient)
                    .frame(width: 22, height: 36)
                    .rotationEffect(.degrees(34))

                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(candidate.text.opacity(0.75))
                        .frame(width: 46, height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(candidate.textMuted.opacity(0.5))
                        .frame(width: 30, height: 4)
                    Capsule()
                        .fill(candidate.accent)
                        .frame(width: 34, height: 9)
                }
            }
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: candidate.radii.row, style: .continuous)
                    .fill(candidate.surface)
                    .overlay {
                        if candidate.usesHairlines {
                            RoundedRectangle(cornerRadius: candidate.radii.row, style: .continuous)
                                .strokeBorder(candidate.hairline, lineWidth: 1)
                        }
                    }
            }
        }
        .frame(height: 96)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: candidate.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(candidate.accent)
                Text(candidate.name)
                    .font(candidate.labelFont)
                    .foregroundStyle(candidate.text)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(candidate.accent)
                }
            }
            Text(candidate.tagline)
                .font(.system(size: 10))
                .foregroundStyle(candidate.textMuted)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(candidate.canvas)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                isSelected ? candidate.accent : candidate.hairline,
                lineWidth: isSelected ? 2 : 1
            )
    }
}

// MARK: - Rows

private struct SettingsToggleRow: View {
    @Environment(\.theme) private var theme

    var symbol: String
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyTextFont)
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.accent)
        }
    }
}

private struct SettingsRadioRow: View {
    @Environment(\.theme) private var theme

    var title: String
    var detail: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? theme.accent : theme.textMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(theme.bodyTextFont)
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(theme.labelFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsInfoRow: View {
    @Environment(\.theme) private var theme

    var symbol: String
    var title: String
    var detail: String
    var actionTitle: String?
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyTextFont)
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.canvas)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background { Capsule().fill(theme.accent) }
                    .buttonStyle(PressableStyle())
            }
        }
    }
}

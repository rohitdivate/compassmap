import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The "Your data" section of Settings: backup out, restore in, GPX for other apps, and the
/// door to Recently Deleted.
///
/// The copy here is deliberately blunt about durability. On a free Apple account nothing
/// survives deleting the app — so the export is not a power feature, it is the only backup that
/// is real, and the section says so instead of implying the phone keeps things safe.
struct DataSection: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var shareItems: ShareItems?
    @State private var isImporting = false
    @State private var restorePlan: BackupService.RestorePlan?
    @State private var restoreMessage: String?
    @State private var failureMessage: String?

    private var store: SpotStore { SpotStore(context: modelContext) }

    struct ShareItems: Identifiable {
        let id = UUID()
        let url: URL
        /// True for the backup archive — sharing it successfully counts as "backed up".
        let isBackup: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(eyebrow: "The only backup that survives deleting the app", title: "Your data")
            Surface(padding: 14) {
                VStack(spacing: 10) {
                    backupRow
                    divider
                    restoreRow
                    divider
                    gpxRow
                    divider
                    trashRow
                }
            }
        }
        .sheet(item: $shareItems) { items in
            ActivitySheet(url: items.url) { completed in
                if completed, items.isBackup {
                    settings.lastBackupExportAt = Date()
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Restore this backup?", isPresented: showingRestoreConfirm) {
            Button("Restore") { commitRestore() }
            Button("Cancel", role: .cancel) { restorePlan = nil }
        } message: {
            Text(restoreConfirmText)
        }
        .alert("Restored", isPresented: showingRestoreDone) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
        .alert("That didn't work", isPresented: showingFailure) {
            Button("OK") { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "")
        }
    }

    // MARK: - Rows

    private var backupRow: some View {
        SettingsActionRow(
            symbol: "arrow.down.doc.fill",
            title: "Back up now",
            detail: backupDetail,
            accessibilityID: "backup-now"
        ) {
            do {
                let url = try BackupService.shared.exportArchive(
                    spots: store.allSpots() + store.deletedSpots(),
                    trips: store.allTrips()
                )
                shareItems = ShareItems(url: url, isBackup: true)
            } catch {
                failureMessage = error.localizedDescription
            }
        }
    }

    private var backupDetail: String {
        if let last = settings.lastBackupExportAt {
            return "Last backed up \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date())). Save it to iCloud Drive in Files."
        }
        return "Makes one file with every spot and photo. Save it to iCloud Drive and it outlives this phone."
    }

    private var restoreRow: some View {
        SettingsActionRow(
            symbol: "arrow.up.doc.fill",
            title: "Restore from a backup",
            detail: "Adds what's missing, never duplicates. Safe to run twice.",
            accessibilityID: "restore-backup"
        ) {
            isImporting = true
        }
    }

    private var gpxRow: some View {
        SettingsActionRow(
            symbol: "map.fill",
            title: "Export GPX",
            detail: "Your spots as waypoints, for Organic Maps, Gaia, a Garmin — anything.",
            accessibilityID: "export-gpx"
        ) {
            exportGPX()
        }
    }

    private var trashRow: some View {
        NavigationLink {
            RecentlyDeletedView()
                .environment(settings)
                .environment(\.theme, theme)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recently Deleted")
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                    Text("Deleted spots wait here for \(TrashPolicy.retentionDays) days.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .accessibilityIdentifier("recently-deleted-link")
    }

    private var divider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - Behaviour

    private func exportGPX() {
        let waypoints = store.allSpots().map { spot in
            GPXCodec.Waypoint(
                latitude: spot.latitude,
                longitude: spot.longitude,
                elevation: spot.altitude,
                time: spot.capturedAt,
                name: spot.displayName,
                note: spot.note
            )
        }
        let document = GPXCodec.document(from: waypoints)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tradewind Spots")
            .appendingPathExtension("gpx")
        do {
            try Data(document.utf8).write(to: url)
            shareItems = ShareItems(url: url, isBackup: false)
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let picked = urls.first else { return }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        do {
            // Copied out first: the security scope ends with this call, the read happens later.
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString)")
                .appendingPathExtension(BackupService.fileExtension)
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: picked, to: local)
            restorePlan = try BackupService.shared.read(archiveAt: local)
        } catch {
            failureMessage = (error as? BackupService.Failure)?.localizedDescription
                ?? "That file could not be read as a Tradewind backup."
        }
    }

    private func commitRestore() {
        guard let plan = restorePlan else { return }
        let added = BackupService.shared.commit(plan, store: store)
        restorePlan = nil
        restoreMessage = added == 0
            ? "Everything in that backup was already here."
            : "Added \(added) \(added == 1 ? "spot" : "spots")."
    }

    private var restoreConfirmText: String {
        guard let plan = restorePlan else { return "" }
        let existing = Set((store.allSpots() + store.deletedSpots()).map(\.id))
        let skipped = plan.spots.filter { existing.contains($0.id) }.count
        return BackupArchive.restoreSummary(incoming: plan.spots.count, skipped: skipped)
    }

    private var showingRestoreConfirm: Binding<Bool> {
        Binding(get: { restorePlan != nil }, set: { if !$0 { restorePlan = nil } })
    }

    private var showingRestoreDone: Binding<Bool> {
        Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()
}

// MARK: - Recently Deleted

/// The trash. Restore is one tap; permanent deletion is the only thing in the app that asks
/// "are you sure", because it is the only thing that cannot be taken back.
struct RecentlyDeletedView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Spot> { $0.deletedAt != nil },
        sort: \Spot.capturedAt,
        order: .reverse
    ) private var deleted: [Spot]

    @State private var purgeCandidate: Spot?

    private var store: SpotStore { SpotStore(context: modelContext) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if deleted.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .background { ThemedBackground(theme: theme) }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            TrashPolicy.permanentDeleteTitle,
            isPresented: showingPurgeConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                if let spot = purgeCandidate { store.purge(spot) }
                purgeCandidate = nil
            }
            Button("Keep it", role: .cancel) { purgeCandidate = nil }
        } message: {
            Text(TrashPolicy.permanentDeleteMessage)
        }
        .accessibilityIdentifier("recently-deleted-screen")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.textFaint)
            Text("Nothing here")
                .font(theme.sectionTitleFont)
                .foregroundStyle(theme.text)
            Text("Deleted spots wait here for \(TrashPolicy.retentionDays) days before they're gone for good.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var rows: some View {
        VStack(spacing: 10) {
            ForEach(deleted) { spot in
                row(for: spot)
            }
        }
    }

    private func row(for spot: Spot) -> some View {
        Surface(padding: 12) {
            HStack(spacing: 12) {
                SpotPhotoView(spot: spot, sizeClass: .pin)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(spot.displayName)
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(TrashPolicy.remainingLabel(deletedAt: spot.deletedAt ?? Date(), now: Date()))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                }

                Spacer(minLength: 8)

                Button("Restore") {
                    store.restore(spot)
                    FeedbackService.shared.lightTap()
                }
                .font(theme.sans(13, weight: .bold))
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("restore-spot")

                Button {
                    purgeCandidate = spot
                } label: {
                    Image(systemName: "xmark.bin.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.negative)
                }
                .accessibilityLabel("Delete permanently")
            }
        }
    }

    private var showingPurgeConfirm: Binding<Bool> {
        Binding(get: { purgeCandidate != nil }, set: { if !$0 { purgeCandidate = nil } })
    }
}

// MARK: - Pieces

/// A tappable settings row with an icon, title and explanation.
struct SettingsActionRow: View {
    @Environment(\.theme) private var theme

    var symbol: String
    var title: String
    var detail: String
    var accessibilityID: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .accessibilityIdentifier(accessibilityID)
    }
}

/// A share sheet that reports whether the person actually completed an activity — the backup row
/// only counts an export as a backup when something was really saved or sent.
private struct ActivitySheet: UIViewControllerRepresentable {
    var url: URL
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

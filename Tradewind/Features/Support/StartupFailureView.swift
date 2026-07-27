import SwiftUI

/// Shown when the store could not be opened by any route.
///
/// Deliberately built out of nothing but system fonts and system colours — no `Theme`, no custom
/// typeface, no asset catalogue lookup. This is the screen that appears when the app is already
/// having a bad day, and every dependency it has is another thing that could be the reason it never
/// appears. The white screen it replaces was worse than any error message.
struct StartupFailureView: View {
    let report: StartupReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)

                Text("Tradewind could not open its store")
                    .font(.system(.title2, design: .default, weight: .semibold))

                Text("""
                Every way of saving your spots failed, so the app has stopped here rather than \
                showing you an empty screen with no explanation. This is a bug — the details below \
                say which attempts were made and what each one reported.
                """)
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)

                Text(report.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                Text("Touch and hold the block above to copy it.")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    StartupFailureView(
        report: {
            var report = StartupReport(
                appGroupIdentifier: "group.com.example.app",
                appGroupResolved: false,
                cloudSyncRequested: true
            )
            report.record("appLocal", failure: "The file couldn't be saved.")
            report.record("memoryOnly", failure: "The model configuration is invalid.")
            return report
        }()
    )
}

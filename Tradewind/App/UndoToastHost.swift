import SwiftData
import SwiftUI

/// The undo toast, in its own view so its observation of `UndoCenter` cannot be lost in a
/// bigger body's evaluation. Sits at the top of `RootView`'s ZStack, above the arrow overlay —
/// a deletion from the detail sheet collapses the arrow underneath, and the undo must survive
/// that collapse.
struct UndoToastHost: View {

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var undo = UndoCenter.shared

    private var store: SpotStore { SpotStore(context: modelContext) }

    var body: some View {
        VStack {
            Spacer()
            if let candidate = undo.candidate {
                toast(for: candidate)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: undo.candidate)
        // Keyed by the candidate so deleting a second spot restarts the five seconds. Under the
        // test seam the window stretches: a synthesized tap racing the auto-clear loses by
        // milliseconds and falls through a just-vanished toast.
        .task(id: undo.candidate) {
            guard undo.candidate != nil else { return }
            let window = AppSettings.isUITesting ? 30 : TrashPolicy.undoWindow
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            undo.clear()
        }
        .allowsHitTesting(undo.candidate != nil)
    }

    /// Delete needs no dialog because this is the net: five seconds of Undo, then Recently
    /// Deleted in Settings for thirty days after that.
    private func toast(for candidate: UndoCenter.Candidate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Text(TrashPolicy.undoMessage(spotName: candidate.name))
                .font(theme.captionFont)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if let spot = store.anySpot(id: candidate.spotID) {
                    store.restore(spot)
                    FeedbackService.shared.lightTap()
                }
                undo.clear()
            } label: {
                Text("Undo")
                    .font(theme.sans(13, weight: .bold))
                    .foregroundStyle(theme.accent)
                    // A 33×17pt text is a miserable target for a thumb and for a synthesized
                    // tap alike; the padded shape is the button.
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("undo-delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule().fill(theme.surfaceRaised)
                .overlay { Capsule().strokeBorder(theme.hairline, lineWidth: 1) }
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 96)
        // No identifier on the container: SwiftUI stamps a container's identifier onto every
        // child, which silently overwrote the Undo button's own — and made it unfindable.
    }
}

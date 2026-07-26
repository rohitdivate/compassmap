import SwiftUI
import UIKit

/// Shown in place of the viewfinder when there is no camera to show — access denied, or no
/// usable device (which is also what the simulator looks like).
struct CameraUnavailableView: View {
    @Environment(\.theme) private var theme

    var title: String
    var message: String
    var showsSettingsButton: Bool

    var body: some View {
        ZStack {
            ThemedBackground(theme: theme)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.14))
                        .frame(width: 96, height: 96)
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(theme.accent)
                }
                Text(title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                Text(message)
                    .font(theme.bodyTextFont)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if showsSettingsButton {
                    PrimaryButton(title: "Open Settings", symbol: "gear") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 6)
                }

                Text("You can still add a spot from your photo library.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
                    .padding(.top, 4)
            }
        }
    }
}

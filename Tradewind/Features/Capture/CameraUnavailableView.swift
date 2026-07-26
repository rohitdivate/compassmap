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
            ThemedBackground(theme: theme, timeTint: false)

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
                    .font(Typography.title)
                    .foregroundStyle(theme.text)
                Text(message)
                    .font(Typography.body)
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
                    .font(Typography.caption)
                    .foregroundStyle(theme.textMuted)
                    .padding(.top, 4)
            }
        }
    }
}

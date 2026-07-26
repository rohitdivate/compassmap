import SwiftUI
import UIKit

/// The image Tradewind produces when you share a spot.
///
/// Sharing a bare `tradewind://` link is useless to anyone who does not have the app, and a
/// bare photo loses the point. This is the photo *and* the coordinates, laid out like something
/// posted home — so the link that travels alongside it has context.
struct PostcardView: View {

    var spot: Spot
    var theme: Theme
    var distanceText: String?

    /// Fixed size: this is rendered to an image, not laid out in a window.
    static let size = CGSize(width: 1_080, height: 1_350)

    var body: some View {
        ZStack {
            theme.canvas

            VStack(spacing: 0) {
                photo
                caption
            }
            .padding(44)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var photo: some View {
        ZStack(alignment: .topTrailing) {
            image
                .frame(width: 992, height: 830)
                .clipped()
            stamp.padding(28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 2)
        }
    }

    @ViewBuilder
    private var image: some View {
        if let data = spot.photoData, let decoded = UIImage(data: data) {
            Image(uiImage: decoded)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [theme.surface, theme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay { Text(spot.glyph ?? "📍").font(.system(size: 120)) }
        }
    }

    /// A compass mark in the corner, sitting on the photo like an inked stamp.
    private var stamp: some View {
        ZStack {
            Circle().fill(theme.canvas.opacity(0.75))
            Circle().strokeBorder(theme.accent, lineWidth: 3)
            ArrowShape()
                .fill(theme.accent)
                .frame(width: 42, height: 68)
        }
        .frame(width: 118, height: 118)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tradewind")
                .font(.system(size: 26, weight: .bold))
                .textCase(.uppercase)
                .tracking(6)
                .foregroundStyle(theme.accent)
                .padding(.top, 34)

            Text(spot.displayName)
                .font(.system(size: 64, weight: .semibold, design: .serif))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(spacing: 18) {
                Text(String(format: "%.4f°, %.4f°", spot.latitude, spot.longitude))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textMuted)

                if let distanceText {
                    Text("·").foregroundStyle(theme.textMuted)
                    Text("\(distanceText) from me")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders a `PostcardView` to a shareable image.
enum PostcardRenderer {

    /// `ImageRenderer` is main-actor bound. Callers are already on the main thread — this is
    /// driven by a button tap — so the isolation is asserted rather than hopped, which keeps the
    /// call sites synchronous.
    static func render(_ view: PostcardView) -> UIImage? {
        MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: view)
            // 1x, because the view is already laid out at full pixel dimensions.
            renderer.scale = 1
            renderer.isOpaque = true
            return renderer.uiImage
        }
    }
}

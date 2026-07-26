import SwiftUI

/// Decoded-image cache.
///
/// Spot photos live in the database as JPEG data. Handing that data to `Image` inside a
/// scrolling grid re-decodes it on every pass, which is exactly the kind of thing that makes an
/// otherwise pretty app feel cheap. Decoding happens once per size here instead.
final class ImageCache {

    static let shared = ImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        // Roughly 80 MB of decoded pixels, which the system will evict from under us if it
        // needs to.
        cache.totalCostLimit = 80 * 1_024 * 1_024
        return cache
    }()

    private init() {}

    func image(for data: Data, maxDimension: CGFloat) -> UIImage? {
        let key = "\(data.count)-\(data.hashValue)-\(Int(maxDimension))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let resized = PhotoService.resizedJPEG(from: data, maxDimension: maxDimension),
              let image = UIImage(data: resized)
        else {
            guard let fallback = UIImage(data: data) else { return nil }
            cache.setObject(fallback, forKey: key, cost: data.count)
            return fallback
        }

        cache.setObject(image, forKey: key, cost: resized.count)
        return image
    }

    func image(atPath url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }
}

/// A spot's photo, decoded off the main thread and faded in.
///
/// The placeholder is a themed gradient with the spot's glyph rather than a grey box, so a
/// still-loading grid looks intentional.
struct PhotoView: View {
    @Environment(\.theme) private var theme

    var data: Data?
    var maxDimension: CGFloat = 900
    var glyph: String?

    @State private var image: UIImage?
    @State private var didAttempt = false

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: data?.count) {
            await load()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        LinearGradient(
            colors: [theme.surface, theme.canvas],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            if let glyph, !glyph.isEmpty {
                Text(glyph).font(.system(size: 34))
            } else if didAttempt, image == nil {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.textMuted.opacity(0.6))
            }
        }
    }

    private func load() async {
        guard let data, !data.isEmpty else {
            image = nil
            didAttempt = true
            return
        }
        let dimension = maxDimension
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageCache.shared.image(for: data, maxDimension: dimension)
        }.value

        withAnimation(.easeOut(duration: 0.25)) {
            image = decoded
        }
        didAttempt = true
    }
}

/// Same idea, for the widget-sized thumbnails stored as files in the App Group.
struct ThumbnailFileView: View {
    @Environment(\.theme) private var theme

    var url: URL?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.surface, theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached { ImageCache.shared.image(atPath: url) }.value
        }
    }
}

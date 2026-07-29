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

    // MARK: - Identity-keyed

    /// The stable key: who and at what size. The old key hashed the photo bytes, which meant
    /// the blob had to be faulted out of the database just to *ask* the cache — and two JPEGs
    /// of the same length could collide on `Data.hashValue`'s bounded prefix.
    private func key(spotID: UUID, sizeClass: PhotoSizeClass) -> NSString {
        "spot-\(spotID.uuidString)-\(sizeClass.rawValue)" as NSString
    }

    func cached(spotID: UUID, sizeClass: PhotoSizeClass) -> UIImage? {
        cache.object(forKey: key(spotID: spotID, sizeClass: sizeClass))
    }

    func store(_ image: UIImage, spotID: UUID, sizeClass: PhotoSizeClass) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
        cache.setObject(image, forKey: key(spotID: spotID, sizeClass: sizeClass), cost: cost)
    }
}

/// A spot's photo at one of the three canonical sizes, keyed by identity rather than bytes.
///
/// Constructing this view never touches the photo blob: `.pin` and `.card` decode the 480 px
/// App Group thumbnail file, and only `.hero` faults `photoData` — lazily, through the
/// closure, once per cache miss. The map tab used to fault every photo in the database the
/// moment it opened; now it reads a handful of small files.
struct SpotPhotoView: View {
    @Environment(\.theme) private var theme

    var spotID: UUID
    var thumbnailFilename: String?
    /// Placeholder hint. Deliberately from the thumbnail's presence, not `Spot.hasPhoto`,
    /// which faults the blob to answer.
    var likelyHasPhoto: Bool
    var sizeClass: PhotoSizeClass
    var glyph: String?
    var fallbackSymbol: String?
    /// Called on the main actor, only when the full photo is genuinely needed.
    var photoData: () -> Data?

    @State private var image: UIImage?
    @State private var didAttempt = false

    init(spot: Spot, sizeClass: PhotoSizeClass) {
        self.init(
            spotID: spot.id,
            thumbnailFilename: spot.thumbnailFilename,
            likelyHasPhoto: spot.thumbnailFilename != nil,
            sizeClass: sizeClass,
            glyph: spot.glyph,
            fallbackSymbol: spot.placeKind.symbol,
            photoData: { spot.photoData }
        )
    }

    init(
        spotID: UUID,
        thumbnailFilename: String?,
        likelyHasPhoto: Bool,
        sizeClass: PhotoSizeClass,
        glyph: String? = nil,
        fallbackSymbol: String? = nil,
        photoData: @escaping () -> Data?
    ) {
        self.spotID = spotID
        self.thumbnailFilename = thumbnailFilename
        self.likelyHasPhoto = likelyHasPhoto
        self.sizeClass = sizeClass
        self.glyph = glyph
        self.fallbackSymbol = fallbackSymbol
        self.photoData = photoData
    }

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
        .task(id: "\(spotID.uuidString)-\(sizeClass.rawValue)") {
            await load()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        theme.surfaceRaised
            .overlay {
                if let glyph, !glyph.isEmpty {
                    Text(glyph).font(.system(size: 34))
                } else if !likelyHasPhoto, let fallbackSymbol {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(theme.accent)
                } else if didAttempt, image == nil {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.textMuted.opacity(0.6))
                }
            }
    }

    private func load() async {
        if let cached = ImageCache.shared.cached(spotID: spotID, sizeClass: sizeClass) {
            image = cached
            didAttempt = true
            return
        }

        let dimension = CGFloat(sizeClass.maxDimension)
        let thumbnailURL = sizeClass.servedByThumbnail
            ? thumbnailFilename.flatMap { AppGroup.thumbnailsURL?.appendingPathComponent($0) }
            : nil
        // The blob fault happens here on the main actor (SwiftData models are not thread-safe)
        // — but only for `.hero`, or when a photo predates its thumbnail file.
        let fullData: Data? = thumbnailURL == nil ? photoData() : nil

        guard thumbnailURL != nil || fullData?.isEmpty == false else {
            image = nil
            didAttempt = true
            return
        }

        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let source: Data?
            if let thumbnailURL {
                source = try? Data(contentsOf: thumbnailURL)
            } else {
                source = fullData
            }
            guard let source, !source.isEmpty else { return nil }
            if let resized = PhotoService.resizedJPEG(from: source, maxDimension: dimension),
               let image = UIImage(data: resized) {
                return image
            }
            return UIImage(data: source)
        }.value

        if let decoded {
            ImageCache.shared.store(decoded, spotID: spotID, sizeClass: sizeClass)
        }
        withAnimation(.easeOut(duration: 0.25)) {
            image = decoded
        }
        didAttempt = true
    }
}

/// A spot's photo, decoded off the main thread and faded in.
///
/// The placeholder is a themed surface carrying whichever glyph you chose for the spot, rather than a
/// grey box, so a still-loading grid looks intentional. It was a gradient; neither mood spends its
/// gradient budget on a loading state.
struct PhotoView: View {
    @Environment(\.theme) private var theme

    var data: Data?
    var maxDimension: CGFloat = 900
    var glyph: String?
    /// Shown when there is neither a photo nor a glyph — a station saved from Save Here has no
    /// picture, and its kind's symbol is what makes the card read as that place.
    var fallbackSymbol: String?

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
        theme.surfaceRaised
        .overlay {
            if let glyph, !glyph.isEmpty {
                Text(glyph).font(.system(size: 34))
            } else if data == nil || data?.isEmpty == true, let fallbackSymbol {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(theme.accent)
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

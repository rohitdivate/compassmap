import SwiftUI

/// First run. Four pages: what it does, why it needs the camera and your location, what the
/// widgets do, and which look you want.
///
/// The permission asks come with a reason attached and only after you have seen what the app is
/// for — a cold system prompt on launch is how apps get denied.
struct OnboardingView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    @State private var page = 0
    @State private var location = LocationService.shared

    private let pageCount = 4

    var body: some View {
        ZStack {
            ThemedBackground(theme: theme)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    permissions.tag(1)
                    widgets.tag(2)
                    look.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: page)

                controls
            }
        }
    }

    // MARK: - Pages

    private var welcome: some View {
        OnboardingPage(
            eyebrow: "Tradewind",
            title: "Find your way back",
            message: "Photograph somewhere worth returning to. Tradewind remembers exactly where you were standing, and points you back whenever you want.",
            illustration: { CompassIllustration() }
        )
    }

    private var permissions: some View {
        OnboardingPage(
            eyebrow: "Two things it needs",
            title: "The camera and your location",
            message: "The camera takes the photo. Your location is what makes the arrow point and the distance count down. Nothing leaves your phone unless you turn on iCloud sync.",
            illustration: { PermissionIllustration() }
        ) {
            VStack(spacing: 10) {
                if location.isAuthorized {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Location allowed")
                    }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.accent)
                } else {
                    PrimaryButton(title: "Allow location", symbol: "location.fill") {
                        location.requestWhenInUseAuthorization()
                    }
                }
                Text("The camera is asked for the first time you take a photo.")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
        }
    }

    private var widgets: some View {
        OnboardingPage(
            eyebrow: "On your home screen",
            title: "Distances, without opening anything",
            message: "Widgets show how far away your spots are at a glance. Pin one and the small widget follows it; the medium one shows your three nearest.",
            illustration: { WidgetIllustration() }
        )
    }

    private var look: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last thing").eyebrowStyle(theme: theme)
                    Text("Pick your weather")
                        .font(theme.displayTitleFont)
                        .foregroundStyle(theme.text)
                    Text("Six looks, and you can change your mind whenever. Your widgets follow along.")
                        .font(theme.bodyTextFont)
                        .foregroundStyle(theme.textMuted)
                }
                ThemeGallery()
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? theme.accent : theme.textMuted.opacity(0.3))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }

            if page == pageCount - 1 {
                PrimaryButton(title: "Start exploring", symbol: "arrow.right") {
                    finish()
                }
                .padding(.horizontal, 30)
            } else {
                PrimaryButton(title: "Next", symbol: "arrow.right") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        page += 1
                    }
                    FeedbackService.shared.lightTap()
                }
                .padding(.horizontal, 30)

                Button("Skip") { finish() }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.bottom, 26)
    }

    private func finish() {
        FeedbackService.shared.lightTap()
        settings.hasCompletedOnboarding = true
    }
}

// MARK: - Page scaffold

private struct OnboardingPage<Illustration: View, Extra: View>: View {
    @Environment(\.theme) private var theme

    var eyebrow: String
    var title: String
    var message: String
    @ViewBuilder var illustration: () -> Illustration
    @ViewBuilder var extra: () -> Extra

    init(
        eyebrow: String,
        title: String,
        message: String,
        @ViewBuilder illustration: @escaping () -> Illustration,
        @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.illustration = illustration
        self.extra = extra
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            illustration()
                .frame(height: 240)
            VStack(spacing: 10) {
                Text(eyebrow).eyebrowStyle(theme: theme)
                Text(title)
                    .font(theme.displayTitleFont)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(theme.bodyTextFont)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            extra()
            Spacer(minLength: 12)
        }
    }
}

// MARK: - Illustrations
//
// Drawn rather than shipped as images: they inherit the theme, so the onboarding restyles with
// the picker on the last page.

private struct CompassIllustration: View {
    @Environment(\.theme) private var theme
    @State private var spin: Double = -220

    var body: some View {
        ZStack {
            RadarRings(theme: theme, ringCount: 3, diameter: 230)
            CompassRose(
                theme: theme,
                heading: spin,
                targetBearing: 36,
                onTarget: false,
                diameter: 200
            )
            DirectionArrow(theme: theme, angle: 36 - spin, onTarget: false, proximity: 0.4, size: 118)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).delay(0.3)) { spin = 0 }
        }
    }
}

private struct PermissionIllustration: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            // A photo frame with a location pin dropping into it.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(theme.surface.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
                .frame(width: 190, height: 150)
                .rotationEffect(.degrees(-6))

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.5), theme.secondary.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(theme.canvas.opacity(0.7))
                }
                .frame(width: 190, height: 150)
                .rotationEffect(.degrees(5))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(theme.accent)
                .background { Circle().fill(theme.canvas).padding(6) }
                .offset(x: 84, y: -66)
                .shadow(color: theme.glow.opacity(0.6), radius: 12)
        }
    }
}

private struct WidgetIllustration: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            smallWidget
            mediumWidget
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            MiniArrow(theme: theme, angle: 28, size: 30)
            Spacer(minLength: 0)
            Text("240")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(theme.text)
            Text("m to Waterfall")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.textMuted)
        }
        .padding(12)
        .frame(width: 108, height: 108, alignment: .topLeading)
        .modifier(FakeWidgetChrome())
    }

    private var mediumWidget: some View {
        VStack(spacing: 8) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, entry in
                row(name: entry.0, distance: entry.1, index: index)
            }
        }
        .padding(12)
        .frame(width: 150, height: 108)
        .modifier(FakeWidgetChrome())
    }

    private func row(name: String, distance: String, index: Int) -> some View {
        HStack(spacing: 8) {
            MiniArrow(theme: theme, angle: Double(index) * 74 - 40, size: 16)
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
            Text(distance)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accent)
        }
    }

    static let rows: [(String, String)] = [
        ("Waterfall", "240 m"),
        ("Beach shack", "1.4 km"),
        ("Tea room", "3.8 km"),
    ]
}

/// The rounded, tinted plate that makes the mock widgets read as widgets.
private struct FakeWidgetChrome: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background { plate }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(theme.canvas)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.surface.opacity(0.6))
            }
    }
}

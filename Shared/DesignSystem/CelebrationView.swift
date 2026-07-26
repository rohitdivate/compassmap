import SwiftUI

/// The arrival burst.
///
/// Particles are generated from a seeded PRNG and positioned by elapsed time, so the whole
/// effect is a pure function of `(startedAt, now)` — nothing to keep in sync, nothing to
/// leak, and it looks identical every time it fires.
struct CelebrationView: View {
    var theme: Theme
    /// When the burst started. Change this to fire it again.
    var startedAt: Date
    var particleCount: Int = 90
    var duration: Double = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            Canvas { canvas, size in
                guard elapsed >= 0, elapsed <= duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.46)
                var rng = SplitMix64(seed: 0xC0FFEE)

                for index in 0..<particleCount {
                    let angle = rng.next(in: 0...(2 * .pi))
                    let speed = rng.next(in: 90...460)
                    let spin = rng.next(in: 0.4...1.0)
                    let side = rng.next(in: 3...9)
                    let lifetime = duration * rng.next(in: 0.55...1.0)
                    guard elapsed <= lifetime else { continue }

                    let t = elapsed
                    // Ballistic, with drag so it settles instead of flying off screen.
                    let drag = 1 - exp(-t * 1.6)
                    let x = origin.x + cos(angle) * speed * drag
                    let y = origin.y + sin(angle) * speed * drag + 190 * t * t

                    let progress = t / lifetime
                    let opacity = (1 - progress) * (1 - progress)
                    let colour = theme.celebration[index % max(theme.celebration.count, 1)]

                    let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side * spin)
                    var transform = CGAffineTransform(translationX: x, y: y)
                    transform = transform.rotated(by: angle + t * 5 * spin)

                    let confetto = Path(roundedRect: rect, cornerRadius: side * 0.28)
                        .applying(transform)
                    canvas.fill(confetto, with: .color(colour.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The stamp that lands on the photo when you arrive: rotated, letterpressed, slightly
/// off-centre, like something inked onto a postcard.
struct ArrivalStamp: View {
    var theme: Theme
    var title: String
    var subtitle: String

    @State private var landed = false

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .serif))
                .tracking(1.2)
            Text(subtitle)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(2.2)
        }
        .foregroundStyle(theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.85), lineWidth: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 5)
                .blur(radius: 3)
        }
        .rotationEffect(.degrees(-7))
        .scaleEffect(landed ? 1 : 2.1)
        .opacity(landed ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { landed = true }
        }
    }
}

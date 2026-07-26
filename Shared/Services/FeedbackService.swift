import AVFoundation
import Foundation
import UIKit

/// Haptics and, if asked for, sound.
///
/// The pulse is the point: while you are walking toward a spot the phone taps you, and the
/// gaps between taps shorten as you get closer. It is a "warmer / colder" game you can play
/// with the phone in your pocket, which is the only way to navigate that does not involve
/// staring at a screen.
final class FeedbackService {

    static let shared = FeedbackService()

    private var pulseTimer: Timer?
    private var lastPulseAt: Date?
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let notice = UINotificationFeedbackGenerator()

    private var audioEngine: AVAudioEngine?
    private var tonePlayer: AVAudioPlayerNode?

    private var settings: AppSettings { .shared }

    private init() {}

    // MARK: - Discrete events

    /// Fires when the phone comes onto the bearing. Deliberately crisp and short.
    func onTarget() {
        guard settings.hapticsEnabled else { return }
        impact.prepare()
        impact.impactOccurred(intensity: 0.85)
        playTone(frequency: 987.77, duration: 0.16)  // B5
    }

    /// Fires on arrival, with two ascending notes so it sounds like an ending.
    func arrived() {
        if settings.hapticsEnabled {
            notice.prepare()
            notice.notificationOccurred(.success)
        }
        playTone(frequency: 1_318.51, duration: 0.18)  // E6
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.playTone(frequency: 1_567.98, duration: 0.30)  // G6
        }
    }

    func lightTap() {
        guard settings.hapticsEnabled else { return }
        impact.impactOccurred(intensity: 0.5)
    }

    func warn() {
        guard settings.hapticsEnabled else { return }
        notice.notificationOccurred(.warning)
    }

    // MARK: - Proximity pulse

    /// Starts pulsing. Call `updatePulse(proximity:)` as the distance changes.
    func startPulsing() {
        guard settings.hapticsEnabled, pulseTimer == nil else { return }
        impact.prepare()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pulseTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        lastPulseAt = nil
        currentProximity = 0
    }

    /// 0 far away, 1 practically there.
    private var currentProximity: Double = 0

    func updatePulse(proximity: Double) {
        currentProximity = max(0, min(1, proximity))
    }

    private func pulseTick() {
        guard settings.hapticsEnabled, currentProximity > 0.02 else { return }
        // Two seconds between taps at the far edge, a fifth of a second when you are on top
        // of it. Interpolated on a curve so most of the change happens close in, where it is
        // useful.
        let eased = pow(currentProximity, 0.6)
        let interval = 2.0 - eased * 1.8
        if let lastPulseAt, Date().timeIntervalSince(lastPulseAt) < interval { return }
        lastPulseAt = Date()
        impact.impactOccurred(intensity: 0.35 + currentProximity * 0.5)
    }

    // MARK: - Sound

    /// A short struck tone, synthesised rather than shipped as an audio file — it keeps the
    /// bundle small and lets the pitch change with the event.
    func playTone(frequency: Double, duration: Double) {
        guard settings.soundEnabled else { return }

        let engine: AVAudioEngine
        let player: AVAudioPlayerNode

        if let audioEngine, let tonePlayer {
            engine = audioEngine
            player = tonePlayer
        } else {
            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            audioEngine = engine
            tonePlayer = player
        }

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = makeToneBuffer(
                  frequency: frequency,
                  duration: duration,
                  format: format
              )
        else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func makeToneBuffer(
        frequency: Double,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount

        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            // Fast attack, exponential decay: the shape of something struck.
            let envelope = exp(-t * 11) * min(1, t * 400)
            // A touch of second harmonic keeps it from sounding like a test tone.
            let sample = sin(2 * .pi * frequency * t) * 0.7
                + sin(4 * .pi * frequency * t) * 0.2
            let value = Float(sample * envelope * 0.28)
            for channel in 0..<channelCount {
                channels[channel][frame] = value
            }
        }
        return buffer
    }
}

import AVFoundation
import CoreLocation
import Observation
import UIKit

/// The in-app camera.
///
/// A custom camera rather than `UIImagePickerController` for one reason that matters: the
/// coordinate and heading are read at the exact moment the shutter fires and travel with the
/// image. Going through the system picker means capturing a photo, then asking where you are,
/// and being slightly wrong if you have started walking.
@Observable
final class CameraController: NSObject {

    enum State: Equatable {
        case idle
        case preparing
        case running
        case denied
        case unavailable(String)
    }

    let session = AVCaptureSession()

    private(set) var state: State = .idle
    /// Set when a photo has been taken and is waiting to be reviewed.
    private(set) var capturedImageData: Data?
    /// Where the phone was, and which way it was facing, when the shutter fired.
    private(set) var captureLocation: CLLocation?
    private(set) var captureHeading: Double?
    private(set) var isCapturing = false
    var isFlashEnabled = false

    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.tradewind.camera")
    @ObservationIgnored private var isConfigured = false

    // MARK: - Lifecycle

    func prepare() async {
        guard state != .running, state != .preparing else { return }
        state = .preparing

        let granted = await Self.requestCameraAccess()
        guard granted else {
            state = .denied
            return
        }

        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.configureIfNeeded()
                continuation.resume()
            }
        }

        guard isConfigured else {
            state = .unavailable("This device has no usable camera.")
            return
        }
        start()
    }

    func start() {
        guard isConfigured else { return }
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
        state = .running
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        if state == .running { state = .idle }
    }

    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Capture

    /// Takes the photo, stamping it with the location and heading as of this instant.
    func capture(location: CLLocation?, heading: Double?) {
        guard state == .running, !isCapturing else { return }
        isCapturing = true
        captureLocation = location
        captureHeading = heading

        let settings = AVCapturePhotoSettings(format: [
            AVVideoCodecKey: AVVideoCodecType.jpeg,
        ])
        settings.flashMode = isFlashEnabled ? .on : .off

        queue.async { [weak self] in
            guard let self else { return }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Clears the pending photo, e.g. after the review sheet is cancelled.
    func discardCapture() {
        capturedImageData = nil
        captureLocation = nil
        captureHeading = nil
    }

    // MARK: - Configuration

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced

        session.commitConfiguration()
        isConfigured = true
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCapturing = false
            guard error == nil, let data else {
                self.state = .unavailable("The photo could not be saved. Try again.")
                return
            }
            self.capturedImageData = data
        }
    }
}

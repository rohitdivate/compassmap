import AVFoundation
import SwiftUI
import UIKit

/// Live camera feed.
///
/// The preview layer has to be resized by the view that owns it — SwiftUI will not do it — so
/// this uses a `UIView` subclass whose `layerClass` *is* the preview layer, which makes layout
/// automatic and avoids the usual frame-syncing bugs.
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` above guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

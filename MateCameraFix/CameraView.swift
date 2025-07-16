import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        return cameraManager.setupCamera()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

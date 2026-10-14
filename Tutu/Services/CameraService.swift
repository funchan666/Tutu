import SwiftUI
import AVFoundation

@MainActor final class CameraService: ObservableObject {
    let capture = AVCaptureSession()
    @Published private(set) var status = "Camera is off"
    @Published private(set) var ready = false
    @Published private(set) var microphoneEnabled = false
    private let queue = DispatchQueue(label: "com.tutu.camera")
    private var generation = UUID()
    private var front = true
    func start(video: Bool = true) async {
        let ticket = UUID(); generation = ticket; ready = false
        if video {
            guard await AVCaptureDevice.requestAccess(for: .video) else { if generation == ticket { status = "Allow Camera access in Settings to continue." }; return }
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { if generation == ticket { status = "Allow Microphone access in Settings to continue." }; return }
        guard generation == ticket, !Task.isCancelled else { return }
        let session = capture; let front = front
        let message: String? = await withCheckedContinuation { continuation in
            queue.async {
                session.beginConfiguration(); session.sessionPreset = .medium
                for input in session.inputs { session.removeInput(input) }
                for output in session.outputs { session.removeOutput(output) }
                if video {
                    let position: AVCaptureDevice.Position = front ? .front : .back
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { session.commitConfiguration(); continuation.resume(returning: "This camera is unavailable."); return }
                    session.addInput(input)
                }
                if let microphone = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    let output = AVCaptureAudioDataOutput()
                    if session.canAddOutput(output) { session.addOutput(output) }
                } else {
                    session.commitConfiguration(); continuation.resume(returning: "This microphone is unavailable."); return
                }
                session.commitConfiguration(); session.startRunning(); continuation.resume(returning: nil)
            }
        }
        // stop() and new starts are ordered on the queue. A stale completion must
        // never enqueue a stop that could tear down a newer capture session.
        guard generation == ticket, !Task.isCancelled else { return }
        ready = message == nil; microphoneEnabled = ready
        status = message ?? (video ? "Camera ready. Calling is unavailable." : "Microphone ready. Calling is unavailable.")
    }
    func setMicrophoneEnabled(_ enabled: Bool) {
        guard ready else { return }
        microphoneEnabled = enabled
        let session = capture
        queue.async { for connection in session.connections where connection.inputPorts.contains(where: { $0.mediaType == .audio }) { connection.isEnabled = enabled } }
    }
    func flip() async { front.toggle(); stop(); await start() }
    func stop() {
        generation = UUID(); ready = false; microphoneEnabled = false; status = "Camera is off"
        let session = capture
        queue.async {
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            for output in session.outputs { session.removeOutput(output) }
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
        }
    }
}
struct CameraSurface: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraLayerView { let v = CameraLayerView(); v.preview.videoGravity = .resizeAspectFill; v.preview.session = session; return v }
    func updateUIView(_ uiView: CameraLayerView, context: Context) { uiView.preview.session = session }
}
final class CameraLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

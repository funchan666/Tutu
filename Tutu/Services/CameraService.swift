import SwiftUI
@preconcurrency import AVFoundation

@MainActor final class CameraService: ObservableObject {
    let capture = AVCaptureSession()
    @Published private(set) var status = "Camera is off"
    @Published private(set) var ready = false
    @Published private(set) var microphoneEnabled = false
    @Published private(set) var microphoneAvailable = false
    private let queue = DispatchQueue(label: "com.tutu.camera")
    private var generation = UUID()
    private var front = true
    func start(video: Bool = true, previewWithoutMicrophone: Bool = false) async {
        let ticket = UUID(); generation = ticket; ready = false; microphoneEnabled = false; microphoneAvailable = false
        status = "Preparing…"
        if video {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard generation == ticket, !Task.isCancelled else { return }
            guard allowed else { status = "Allow Camera access in Settings to continue."; return }
        }
        guard generation == ticket, !Task.isCancelled else { return }
        let audioAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == ticket, !Task.isCancelled else { return }
        guard audioAllowed || (video && previewWithoutMicrophone) else {
            status = "Allow Microphone access in Settings to continue."; return
        }
        let session = capture; let front = front
        let result: (error: String?, audio: Bool) = await withCheckedContinuation { continuation in
            queue.async {
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration(); session.sessionPreset = .medium
                for input in session.inputs { session.removeInput(input) }
                for output in session.outputs { session.removeOutput(output) }
                if video {
                    let position: AVCaptureDevice.Position = front ? .front : .back
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                        session.commitConfiguration(); continuation.resume(returning: ("This camera is unavailable.", false)); return
                    }
                    session.addInput(input)
                }
                var audioReady = false
                if audioAllowed, let microphone = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    let output = AVCaptureAudioDataOutput()
                    if session.canAddOutput(output) { session.addOutput(output); audioReady = true }
                    else { session.removeInput(audioInput) }
                }
                guard audioReady || (video && previewWithoutMicrophone) else {
                    for input in session.inputs { session.removeInput(input) }
                    session.commitConfiguration(); continuation.resume(returning: ("This microphone is unavailable.", false)); return
                }
                session.commitConfiguration(); session.startRunning()
                continuation.resume(returning: (session.isRunning ? nil : "Couldn't start capture. Please try again.", audioReady))
            }
        }
        guard generation == ticket, !Task.isCancelled else { return }
        ready = result.error == nil; microphoneAvailable = ready && result.audio; microphoneEnabled = microphoneAvailable
        if let error = result.error { status = error }
        else if !audioAllowed { status = "Allow Microphone access in Settings to continue." }
        else if !result.audio { status = "This microphone is unavailable." }
        else { status = video ? "Camera ready. Calling is unavailable." : "Microphone ready. Calling is unavailable." }
    }
    func setMicrophoneEnabled(_ enabled: Bool) {
        guard ready, microphoneAvailable else { return }
        microphoneEnabled = enabled
        let session = capture
        queue.async { for connection in session.connections where connection.inputPorts.contains(where: { $0.mediaType == .audio }) { connection.isEnabled = enabled } }
    }
    func flip(previewWithoutMicrophone: Bool = false) async {
        let wasMuted = !microphoneEnabled
        front.toggle(); stop(); await start(previewWithoutMicrophone: previewWithoutMicrophone)
        if wasMuted { setMicrophoneEnabled(false) }
    }
    func stop() {
        generation = UUID(); ready = false; microphoneEnabled = false; microphoneAvailable = false; status = "Camera is off"
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
    func updateUIView(_ uiView: CameraLayerView, context: Context) {
        uiView.preview.session = session
        if let connection = uiView.preview.connection {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = true }
        }
    }
}
final class CameraLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

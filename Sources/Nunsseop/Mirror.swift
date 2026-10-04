@preconcurrency import AVFoundation
import SwiftUI

/// Camera preview for the Mirror tab. The session only runs while the tab is visible.
@MainActor
final class MirrorModel: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access = MirrorModel.currentAccess
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nunsseop.mirror")
    private var configuredDeviceID: String?

    private static var currentAccess: Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .unknown
        }
    }

    nonisolated static var cameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    func requestAccess() {
        if access == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async { self?.access = granted ? .granted : .denied }
        }
    }

    /// `deviceID` empty means the system default camera.
    func start(deviceID: String) {
        access = Self.currentAccess
        guard access == .granted else { return }
        let session = session
        let needsConfigure = configuredDeviceID != deviceID
        configuredDeviceID = deviceID
        queue.async {
            if needsConfigure {
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }
                let device = Self.cameras.first { $0.uniqueID == deviceID } ?? AVCaptureDevice.default(for: .video)
                if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
}

private final class PreviewView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        // Mirror the image like a real mirror.
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
}

struct MirrorTab: View {
    @ObservedObject var mirror: MirrorModel
    let deviceID: String

    var body: some View {
        Group {
            switch mirror.access {
            case .granted:
                CameraPreview(session: mirror.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onAppear { mirror.start(deviceID: deviceID) }
                    .onDisappear { mirror.stop() }
                    .onChange(of: deviceID) { _, id in mirror.start(deviceID: id) }
            case .unknown, .denied:
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                    Text(mirror.access == .denied
                         ? String(localized: "Camera access is off")
                         : String(localized: "Use your camera as a mirror"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Button(mirror.access == .denied ? String(localized: "Open System Settings") : String(localized: "Allow Camera")) {
                        mirror.requestAccess()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.15)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .surface(RoundedRectangle(cornerRadius: 14), opacity: 0.04)
            }
        }
        .foregroundStyle(.white)
    }
}

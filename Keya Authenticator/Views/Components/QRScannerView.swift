import AudioToolbox
import AVFoundation
import SwiftUI

struct QRScannerView: View {
    let onResult: (Result<String, Error>) -> Void
    var isEmbedded: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var cameraManager = CameraManager()

    var body: some View {
        if isEmbedded {
            scannerContent
        } else {
            NavigationStack {
                scannerContent
                    .navigationTitle("Scan")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                cameraManager.stop()
                                dismiss()
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }

    // MARK: - Scanner content (shared)

    private var scannerContent: some View {
        ZStack {
            CameraPreviewLayer(cameraManager: cameraManager)
                .ignoresSafeArea()

            ScannerOverlayView()
                .ignoresSafeArea()

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .overlay(alignment: .topLeading) { cornerAccent().padding(8) }
                    .overlay(alignment: .topTrailing) { cornerAccent().rotationEffect(.degrees(90)).padding(8) }
                    .overlay(alignment: .bottomLeading) { cornerAccent().rotationEffect(.degrees(270)).padding(8) }
                    .overlay(alignment: .bottomTrailing) { cornerAccent().rotationEffect(.degrees(180)).padding(8) }
                    .offset(y: 40)
                Spacer().frame(minHeight: 100)

                VStack(spacing: 12) {
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.white)
                            Text(errorMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.white)
                            Text("Point camera at a QR code")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            cameraManager.onCodeScanned = { code in handleScannedCode(code) }
            cameraManager.onError = { error in errorMessage = error }
            cameraManager.start()
        }
        .onDisappear { cameraManager.stop() }
    }

    private func cornerAccent() -> some View {
        VStack(spacing: 0) {
            Rectangle().frame(width: 3, height: 20)
            HStack(spacing: 0) {
                Rectangle().frame(width: 20, height: 3)
                Spacer()
            }
        }
        .foregroundColor(.white)
    }

    private func handleScannedCode(_ code: String) {
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

        if code.hasPrefix("otpauth://") || code.hasPrefix("otpauth-migration://") {
            onResult(.success(code))
            dismiss()
        } else if code.isValidOTPSecret {
            onResult(.success(code))
            dismiss()
        } else {
            errorMessage = String(localized: "Invalid QR code")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                errorMessage = nil
                cameraManager.resumeScanning()
            }
        }
    }
}

// MARK: - Scanner Overlay

struct ScannerOverlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Camera Manager

final class CameraManager: NSObject {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.es.keya.camera")
    private let metadataDelegate = MetadataDelegate()
    private var isConfigured = false

    var onCodeScanned: ((String) -> Void)? {
        didSet { metadataDelegate.onCodeScanned = onCodeScanned }
    }

    var onError: ((String) -> Void)?
    var captureSession: AVCaptureSession {
        session
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStart()
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Camera access is required to scan QR codes. Enable it in Settings.")
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Camera access denied. Enable it in Settings > Privacy > Camera.")
            }
        @unknown default: break
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
    }

    func resumeScanning() {
        metadataDelegate.isPaused = false
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            session.startRunning()
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if isConfigured {
                session.startRunning()
                return
            }
            session.beginConfiguration()
            guard let device = AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async { self.onError?("No camera available") }
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    DispatchQueue.main.async { self.onError?("Could not configure camera") }
                    return
                }
                session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    DispatchQueue.main.async { self.onError?("Could not configure scanner") }
                    return
                }
                session.addOutput(output)

                let weakSession = session
                let weakSessionQueue = sessionQueue

                DispatchQueue.main.async {
                    self.metadataDelegate.session = weakSession
                    self.metadataDelegate.sessionQueue = weakSessionQueue
                    output.setMetadataObjectsDelegate(self.metadataDelegate, queue: .main)
                    output.metadataObjectTypes = [.qr]
                    self.session.commitConfiguration()
                    self.isConfigured = true
                    weakSessionQueue.async {
                        weakSession.startRunning()
                    }
                }
            } catch {
                DispatchQueue.main.async { self.onError?("Failed to setup camera: \(error.localizedDescription)") }
            }
        }
    }
}

final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    var isPaused = false
    weak var session: AVCaptureSession?
    var sessionQueue: DispatchQueue?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isPaused,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }

        isPaused = true

        if let sessionQueue, let session {
            sessionQueue.async {
                session.stopRunning()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.onCodeScanned?(value)
        }
    }
}

struct CameraPreviewLayer: UIViewRepresentable {
    let cameraManager: CameraManager
    func makeUIView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.previewLayer.session = cameraManager.captureSession
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraHostView, context: Context) {}
}

final class CameraHostView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CameraHostView.layerClass must return AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}

#Preview { QRScannerView { _ in } }

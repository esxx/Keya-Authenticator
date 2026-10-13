import Accessibility
import AVFoundation
import Combine
import SwiftUI

struct QRScannerView: View {
    let onResult: (Result<String, Error>) -> Void
    var isActive: Bool = true

    @State private var errorMessage: String?
    @State private var cameraAccessDenied = false
    @State private var lastRejectedCode: String?
    @StateObject private var cameraManager = CameraManager()
    @State private var isOnScreen = false
    @State private var isUncovered = true

    var body: some View {
        scannerContent
    }

    // MARK: - Scanner content

    private var scannerContent: some View {
        ZStack {
            CameraPreviewLayer(cameraManager: cameraManager)
                .ignoresSafeArea()

            ScannerOverlayView()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white, lineWidth: 3)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .overlay(alignment: .topLeading) { cornerAccent().padding(8) }
                    .overlay(alignment: .topTrailing) { cornerAccent().rotationEffect(.degrees(90)).padding(8) }
                    .overlay(alignment: .bottomLeading) { cornerAccent().rotationEffect(.degrees(270)).padding(8) }
                    .overlay(alignment: .bottomTrailing) { cornerAccent().rotationEffect(.degrees(180)).padding(8) }

                VStack(spacing: 12) {
                    if cameraAccessDenied {
                        VStack(spacing: 12) {
                            Text("Camera access is required to scan QR codes. Enable it in Settings.")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                    } else if let errorMessage {
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
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
        }
        .onAppear {
            isOnScreen = true
            cameraManager.onCodeScanned = { code in handleScannedCode(code) }
            cameraManager.onError = { error in
                errorMessage = error
                AccessibilityNotification.Announcement(error).post()
            }
            cameraManager.onAccessDenied = {
                cameraAccessDenied = true
                AccessibilityNotification.Announcement(
                    String(localized: "Camera access is required to scan QR codes. Enable it in Settings.")
                ).post()
            }
            cameraManager.start()
        }
        .onDisappear {
            isOnScreen = false
            cameraManager.stop()
        }
        .onChange(of: isActive) { _, active in
            isUncovered = active
            if active, isOnScreen {
                cameraManager.resumeScanning()
            } else if !active {
                cameraManager.stop()
            }
        }
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
        if TokenIntake.hasScheme(code, TokenIntake.otpAuthScheme) || TokenIntake.hasScheme(
            code,
            TokenIntake.migrationScheme
        )
            || code.isValidOTPSecret
        {
            ClipboardManager.shared.provideHapticFeedback(.success)
            lastRejectedCode = nil
            onResult(.success(code))
            cameraManager.resumeScanning()
        } else {
            ClipboardManager.shared.provideHapticFeedback(.error)
            errorMessage = String(localized: "Invalid QR code")
            if code != lastRejectedCode {
                lastRejectedCode = code
                AccessibilityNotification.Announcement(String(localized: "Invalid QR code")).post()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                errorMessage = nil
                guard isOnScreen, isUncovered else { return }
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

final class CameraManager: NSObject, ObservableObject {
    nonisolated deinit {}

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.es.keya.camera")
    private let metadataDelegate = MetadataDelegate()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var isConfigured = false

    override init() {
        super.init()
        metadataDelegate.session = session
        metadataDelegate.sessionQueue = sessionQueue
        metadataOutput.setMetadataObjectsDelegate(metadataDelegate, queue: .main)
    }

    var onCodeScanned: ((String) -> Void)? {
        didSet { metadataDelegate.onCodeScanned = onCodeScanned }
    }

    var onError: ((String) -> Void)?
    var onAccessDenied: (() -> Void)?
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
                        self?.onAccessDenied?()
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.onAccessDenied?()
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

    // MARK: - Device selection

    private static func scanningDevice() -> AVCaptureDevice? {
        let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        let virtualTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera]

        for type in virtualTypes {
            guard let virtualDevice = AVCaptureDevice.default(type, for: .video, position: .back) else { continue }
            guard let wide else { return virtualDevice }
            let virtualMinimum = virtualDevice.minimumFocusDistance
            let wideMinimum = wide.minimumFocusDistance
            if virtualMinimum > 0, wideMinimum > 0, virtualMinimum < wideMinimum {
                return virtualDevice
            }
        }
        return wide ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Close-range focus

    private static func configureForCloseRangeScanning(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
        } catch {
            return
        }
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = false
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isVirtualDevice {
            device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
        }

        applyRecommendedZoom(for: device)
    }

    // MARK: - Zoom compensation (adapted from Apple's AVCamBarcode sample)

    private static func applyRecommendedZoom(for device: AVCaptureDevice, minimumCodeSize: Float = 20) {
        let deviceMinimumFocusDistance = Float(device.minimumFocusDistance)
        guard deviceMinimumFocusDistance > 0 else { return }

        let fieldOfView = device.activeFormat.videoFieldOfView
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard dimensions.width > 0 else { return }
        let previewFillPercentage = Float(dimensions.height) / Float(dimensions.width)
        guard previewFillPercentage > 0 else { return }

        let radians = (fieldOfView / 2) * Float.pi / 180
        let filledCodeSize = minimumCodeSize / previewFillPercentage
        let minimumSubjectDistance = filledCodeSize / tan(radians)
        guard minimumSubjectDistance > 0, minimumSubjectDistance < deviceMinimumFocusDistance else { return }

        let zoomFactor = CGFloat(deviceMinimumFocusDistance / minimumSubjectDistance)
        device.videoZoomFactor = min(
            max(zoomFactor, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if isConfigured {
                session.startRunning()
                return
            }
            session.beginConfiguration()
            guard let device = CameraManager.scanningDevice() else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.onError?(String(localized: "No camera available")) }
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { self.onError?(String(localized: "Could not configure camera")) }
                    return
                }
                session.addInput(input)
                let output = metadataOutput
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { self.onError?(String(localized: "Could not configure scanner")) }
                    return
                }
                session.addOutput(output)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                isConfigured = true
                CameraManager.configureForCloseRangeScanning(device)
                session.startRunning()
            } catch {
                session.commitConfiguration()
                DispatchQueue.main
                    .async { self.onError?(String(localized: "Failed to set up camera: \(error.localizedDescription)"))
                    }
            }
        }
    }
}

final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    nonisolated deinit {}

    var onCodeScanned: ((String) -> Void)?
    var isPaused = false
    weak var session: AVCaptureSession?
    var sessionQueue: DispatchQueue?
    private var lastDeliveredValue: String?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isPaused,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              value != lastDeliveredValue else { return }

        isPaused = true
        lastDeliveredValue = value

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
    nonisolated deinit {}

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

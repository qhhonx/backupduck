import AVFoundation
import SwiftUI

/// Camera failures belong to the pairing window, not a hidden alert on its parent.
enum PairingCameraFailure: Equatable {
  case permission, unavailable
}

struct PairingScanner: UIViewControllerRepresentable {
  let scanned: (String) -> Void
  var failed: (PairingCameraFailure) -> Void = { _ in }
  func makeUIViewController(context: Context) -> ScannerController {
    ScannerController(scanned: scanned, failed: failed)
  }
  func updateUIViewController(_ controller: ScannerController, context: Context) {}
  static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) {
    controller.stop()
  }
}

private final class CameraPreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  #if targetEnvironment(simulator)
  static var simulatedPreview: ((AVCaptureVideoPreviewLayer) -> Void)?
  #endif
  private let session = AVCaptureSession()
  private let worker = DispatchQueue(label: "app.backupduck.camera")
  private let scanned: (String) -> Void
  private let failed: (PairingCameraFailure) -> Void
  private var graphReady: Bool?
  private var finished = false
  private var visit: UUID?
  private let cameraView = CameraPreviewView()
  private var observers: [NSObjectProtocol] = []
  private var previewCheck: Task<Void, Never>?
  init(scanned: @escaping (String) -> Void, failed: @escaping (PairingCameraFailure) -> Void) {
    self.scanned = scanned
    self.failed = failed
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func loadView() {
    cameraView.backgroundColor = DuckMedia.backgroundUIColor
    cameraView.layer.cornerRadius = DuckRadius.card
    cameraView.layer.masksToBounds = true
    cameraView.accessibilityLabel = NSLocalizedString("apple_scan_frame_note", comment: "")
    cameraView.previewLayer.videoGravity = .resizeAspectFill
    cameraView.previewLayer.setSessionWithNoConnection(session)
    view = cameraView
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
      object: session, queue: .main) { [weak self] _ in self?.report(.unavailable) })
    observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
      object: session, queue: .main) { [weak self] note in
        let reason = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
        if reason?.intValue != AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground.rawValue {
          self?.report(.unavailable)
        }
      })
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard visit == nil, !finished else { return }
    let current = UUID()
    visit = current
    #if BACKUPDUCK_TEST_SCAN && targetEnvironment(simulator)
    // Test-only decoded camera result; all connection handling remains unchanged.
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "-BackupDuckTestScan"), index + 1 < arguments.count {
      let value = arguments[index + 1]
      let payload = value.hasPrefix("/") ? (try? String(contentsOfFile: value, encoding: .utf8)) : value
      if let payload {
        DispatchQueue.main.async { [weak self] in self?.deliver(payload) }
        return
      }
    }
    #endif
    #if targetEnvironment(simulator)
    if let simulatedPreview = Self.simulatedPreview {
      simulatedPreview(cameraView.previewLayer)
      return
    }
    #endif
    guard BackupEnvironment.usesCamera else { report(.unavailable); return }
    #if targetEnvironment(simulator)
    // No camera hardware exists here; do not ask for an unusable permission.
    report(.unavailable)
    #else
    AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
      // A permission reply may arrive after Cancel has dismantled the scanner.
      // Serialize the visibility check with stop() on the main thread before
      // enqueueing configuration; otherwise an invisible session could start.
      DispatchQueue.main.async {
        guard let self, self.visit == current, !self.finished else { return }
        if allowed {
          let preview = self.cameraView.previewLayer
          self.worker.async { self.start(preview, visit: current) }
        } else { self.report(.permission, for: current) }
      }
    }
    #endif
  }
  private func report(_ failure: PairingCameraFailure, for expectedVisit: UUID? = nil) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let visit = self.visit, !self.finished,
        expectedVisit == nil || expectedVisit == visit else { return }
      self.finished = true
      self.failed(failure)
    }
  }
  #if !targetEnvironment(simulator)
  // Session graph changes and start/stop all run on the camera queue.
  private func start(_ preview: AVCaptureVideoPreviewLayer, visit current: UUID) {
    if graphReady == nil { graphReady = configure(preview) }
    guard graphReady == true, preview.connection?.isEnabled == true else {
      report(.unavailable, for: current)
      return
    }
    session.startRunning()
    guard session.isRunning else { report(.unavailable, for: current); return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.visit == current else { return }
      self.previewCheck = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(10))
        guard !Task.isCancelled, let self, self.visit == current, !self.finished,
          self.view.window?.windowScene?.activationState == .foregroundActive,
          !self.session.isInterrupted, !preview.isPreviewing else { return }
        self.report(.unavailable)
      }
    }
  }
  private func configure(_ preview: AVCaptureVideoPreviewLayer) -> Bool {
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        ?? AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input),
      let port = input.ports.first(where: { $0.mediaType == .video }) else { return false }
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.addInputWithNoConnections(input)
    let video = AVCaptureConnection(inputPort: port, videoPreviewLayer: preview)
    guard session.canAddConnection(video) else { return false }
    session.addConnection(video)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return false }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    guard output.availableMetadataObjectTypes.contains(.qr) else { return false }
    output.metadataObjectTypes = [.qr]
    return true
  }
  #endif
  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stop()
  }
  func stop() {
    guard visit != nil else { return }
    visit = nil
    previewCheck?.cancel()
    worker.async { self.session.stopRunning() }
  }
  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard visit != nil, !finished,
      let payload = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
    else { return }
    deliver(payload)
  }
  private func deliver(_ payload: String) {
    guard visit != nil, !finished else { return }
    finished = true
    worker.async { self.session.stopRunning() }
    scanned(payload)
  }
}

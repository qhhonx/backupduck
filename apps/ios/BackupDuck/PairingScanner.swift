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

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let session = AVCaptureSession()
  private let worker = DispatchQueue(label: "app.backupduck.camera")
  private let scanned: (String) -> Void
  private let failed: (PairingCameraFailure) -> Void
  private var finished = false
  private var visible = true
  private var preview: AVCaptureVideoPreviewLayer?
  private var errorObserver: NSObjectProtocol?
  init(scanned: @escaping (String) -> Void, failed: @escaping (PairingCameraFailure) -> Void) {
    self.scanned = scanned
    self.failed = failed
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    view.accessibilityLabel = NSLocalizedString("apple_scan_frame_note", comment: "")
    errorObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError,
      object: session, queue: nil) { [weak self] _ in self?.report(.unavailable) }
    AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
      // A permission reply may arrive after Cancel has dismantled the scanner.
      // Serialize the visibility check with stop() on the main thread before
      // enqueueing configuration; otherwise an invisible session could start.
      DispatchQueue.main.async {
        guard let self, self.visible, !self.finished else { return }
        if allowed { self.worker.async { self.configure() } }
        else { self.report(.permission) }
      }
    }
  }
  private func report(_ failure: PairingCameraFailure) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.visible, !self.finished else { return }
      self.finished = true
      self.failed(failure)
    }
  }
  private func configure() {
    #if targetEnvironment(simulator)
      // A simulator has no physical QR scanning camera. Keep the same recovery
      // UI used when camera hardware is absent instead of a black preview.
      report(.unavailable)
      return
    #else
    guard let camera = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input)
    else { report(.unavailable); return }
    session.beginConfiguration()
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      report(.unavailable)
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    guard output.availableMetadataObjectTypes.contains(.qr) else {
      session.commitConfiguration()
      report(.unavailable)
      return
    }
    output.metadataObjectTypes = [.qr]
    session.commitConfiguration()
    DispatchQueue.main.async { [weak self] in
      guard let self, self.visible else { return }
      let layer = AVCaptureVideoPreviewLayer(session: self.session)
      layer.videoGravity = .resizeAspectFill
      layer.frame = self.view.bounds
      self.view.layer.addSublayer(layer)
      self.preview = layer
    }
    session.startRunning()
    if !session.isRunning { report(.unavailable) }
    #endif
  }
  deinit {
    if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stop()
  }
  func stop() {
    visible = false
    worker.async { self.session.stopRunning() }
  }
  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard visible, !finished,
      let payload = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
    else { return }
    finished = true
    worker.async { self.session.stopRunning() }
    scanned(payload)
  }
}

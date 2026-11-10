import Photos
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class SourceVacancyTransitionTests: XCTestCase {
  func testInteractiveReversalKeepsTheSourceVacantUntilActualClose() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    let source = UIViewController(); source.view.backgroundColor = DuckRole.backgroundUIColor
    let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
      DuckRole.accentUIColor.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    }
    let asset = VacancyAsset(image: image), library = PhotoLibraryModel()
    let frame = CGRect(x: 118.5, y: 310, width: 100.5, height: 100.5)
    let tile = UIImageView(image: image); tile.frame = frame; source.view.addSubview(tile)
    library.previewOwnsVacancy = true
    library.previewFrame = { _ in frame }
    library.previewVisibility = { tile.isHidden = $0 != nil }
    let session = MediaPreviewSession(asset: asset, library: library, poster: image, reviewAssets: [asset])
    let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: asset, frame: frame, poster: image, background: DuckRole.backgroundUIColor), session: session, close: {})
    window.rootViewController = source; window.makeKeyAndVisible()
    defer { viewer.releasePreviewSource(); window.isHidden = true; previous?.makeKeyAndVisible() }
    presentMediaViewer(viewer, from: source, poster: image)
    try await wait { source.presentedViewController != nil && !viewer.openingTransition }
    XCTAssertTrue(tile.isHidden)
    let pan = VacancyPan()
    pan.phase = .began; pan.speed = CGPoint(x: 0, y: 200); viewer.vertical(pan)
    try await Task.sleep(for: .milliseconds(60))
    pan.phase = .changed; pan.delta = CGPoint(x: 0, y: 180); viewer.vertical(pan)
    try await Task.sleep(for: .milliseconds(100))
    pan.delta = CGPoint(x: 0, y: 0); pan.speed = CGPoint(x: 0, y: -250); viewer.vertical(pan)
    pan.phase = .ended; viewer.vertical(pan)
    try await wait { !viewer.closing }
    XCTAssertNotNil(source.presentedViewController, "A reversal returns to the same open viewer")
    XCTAssertTrue(tile.isHidden, "The viewer still owns the thumbnail after cancelling its return")
    XCTAssertEqual(viewer.mediaSurface()?.alpha, 1)
    viewer.dismissViewer()
    try await wait { source.presentedViewController == nil }
    XCTAssertFalse(tile.isHidden, "Only a completed close releases the source pixels")
    XCTAssertEqual(tile.frame, frame)
  }

  private func wait(_ predicate: () -> Bool) async throws {
    for _ in 0..<150 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("The source/viewer transition did not settle")
  }
}

private final class VacancyAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let image: UIImage
  init(image: UIImage) { self.image = image; super.init() }
  override var localIdentifier: String { "source-vacancy-reversal" }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
  var previewImage: UIImage? { image }
  var previewFilename: String { "synthetic.jpg" }
  var previewMetadata: [(String, String)] { [] }
}

private final class VacancyPan: UIPanGestureRecognizer {
  var phase: UIGestureRecognizer.State = .possible
  var delta = CGPoint.zero, speed = CGPoint.zero
  override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
  override func translation(in view: UIView?) -> CGPoint { delta }
  override func velocity(in view: UIView?) -> CGPoint { speed }
  override func location(in view: UIView?) -> CGPoint { CGPoint(x: 220, y: 400) }
}

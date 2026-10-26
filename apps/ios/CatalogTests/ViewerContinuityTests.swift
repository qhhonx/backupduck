import Photos
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class ViewerContinuityTests: XCTestCase {
  func testPreparedRenditionsRejectLateLowerQualityAndCroppedResults() async throws {
    let old = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = old }
    let manager = ViewerImageRequests()
    let poster = bitmap(80, 60)
    let model = MediaPreviewModel(asset: ViewerRequestAsset(), poster: poster, manager: manager)
    model.load(promptForCloud: false)
    manager.results[1](bitmap(800, 600), [:])
    try await wait { model.image?.size.width == 800 && !model.loading }
    manager.results[0](bitmap(160, 120), [PHImageResultIsDegradedKey: true])
    manager.results[1](bitmap(1200, 1200), [PHImageResultIsDegradedKey: true])
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(model.image?.size, CGSize(width: 800, height: 600))
    model.load(promptForCloud: false)
    manager.results[3](bitmap(1600, 1200), [:])
    model.cancel()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(model.image?.size, CGSize(width: 800, height: 600), "Cancelled preparation cannot publish over the retained pixels")
  }

  func testSessionPreparesTwoLocalNeighboursWithoutDiscardingTheirModels() async throws {
    let assets = (0..<7).map { ViewerImageAsset("neighbour-\($0)", date: Double($0)) }
    let session = MediaPreviewSession(asset: assets[3], library: PhotoLibraryModel(), reviewAssets: assets)
    session.start()
    try await wait { assets[1...5].allSatisfy { $0.loads > 0 } }
    XCTAssertEqual(assets[0].loads, 0)
    XCTAssertEqual(assets[6].loads, 0)
    let retained = session.model(for: assets[2])
    session.activate(assets[4])
    try await wait { assets[6].loads > 0 }
    XCTAssertTrue(session.model(for: assets[2]) === retained)
    session.stop()
  }

  func testLoadingWaitBeginsAtSettlementAndCancelsAcrossIdentityChanges() async throws {
    let ring = MediaLoadingIndicator(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
    ring.update(loading: true, progress: 0, cloud: false, failure: false, identity: "first", settled: false)
    try await Task.sleep(for: .milliseconds(650))
    XCTAssertEqual(ring.appearance.alpha, 0)
    ring.update(loading: true, progress: 0, cloud: false, failure: false, identity: "first", settled: true)
    try await Task.sleep(for: .milliseconds(350))
    XCTAssertEqual(ring.appearance.alpha, 0)
    ring.update(loading: true, progress: 0, cloud: false, failure: false, identity: "second", settled: true)
    try await Task.sleep(for: .milliseconds(350))
    XCTAssertEqual(ring.appearance.alpha, 0, "The first page's timer must not reveal the second page's ring")
    try await wait { ring.appearance.alpha == 1 }
    let geometry = ring.frame
    ring.update(loading: false, progress: 0, cloud: false, failure: false, identity: "second", settled: true)
    XCTAssertEqual(ring.appearance.alpha, 0)
    XCTAssertEqual(ring.frame, geometry)
    ring.update(loading: true, progress: 0.4, cloud: false, failure: false, identity: "second", settled: false)
    XCTAssertEqual(ring.appearance.alpha, 1, "Recorded cloud-download progress keeps its existing meaning")
  }

  func testFilmstripRetainsUnchangedVisibleCellsAndTheirPixels() async throws {
    let (window, viewer, assets) = try makeViewer()
    defer { window.isHidden = true; viewer.session.stop() }
    try await Task.sleep(for: .milliseconds(300))
    func pictures() -> [Int: UIImage] {
      Dictionary(uniqueKeysWithValues: viewer.strip.indexPathsForVisibleItems.compactMap { path in
        guard let cell = viewer.strip.cellForItem(at: path),
          let photo = cell.contentView.subviews.first as? UIImageView, let image = photo.image else { return nil }
        return (path.item, image)
      })
    }
    let before = pictures()
    XCTAssertGreaterThan(before.count, 5)
    let loads = assets.map(\.loads)
    viewer.currentChanged(viewer.session.current); viewer.strip.layoutIfNeeded()
    XCTAssertEqual(assets.map(\.loads), loads, "Focus-only delivery must not request the filmstrip again")
    let repeated = pictures()
    for (index, image) in before { XCTAssertTrue(repeated[index] === image) }
    viewer.session.activate(assets[21])
    try await Task.sleep(for: .milliseconds(100))
    let paged = pictures()
    for (index, image) in before where paged[index] != nil {
      XCTAssertTrue(paged[index] === image, "An unchanged visible thumbnail keeps its exact bitmap across a page change")
    }
  }

  func testSyntheticDownwardReversalRestoresPhotoAndChrome() async throws {
    let (window, viewer, _) = try makeViewer()
    defer { window.isHidden = true; viewer.session.stop() }
    try await Task.sleep(for: .milliseconds(300))
    let pan = ViewerPanFixture()
    let probe = ViewerOpacityProbe(viewer); probe.start()
    defer { probe.stop() }
    pan.phase = .began; pan.speed = CGPoint(x: 0, y: 200); viewer.vertical(pan)
    for y in stride(from: 16, through: 160, by: 16) {
      pan.phase = .changed; pan.delta = CGPoint(x: 0, y: y); viewer.vertical(pan)
      try await Task.sleep(for: .milliseconds(17))
    }
    try await Task.sleep(for: .milliseconds(400))
    for y in stride(from: 144, through: 64, by: -16) {
      pan.delta = CGPoint(x: 0, y: y); pan.speed = CGPoint(x: 0, y: -200); viewer.vertical(pan)
      try await Task.sleep(for: .milliseconds(17))
    }
    pan.phase = .ended; viewer.vertical(pan)
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertFalse(viewer.closing)
    XCTAssertEqual(viewer.mediaSurface()?.transform, .identity)
    XCTAssertEqual(viewer.backdrop.alpha, 1)
    XCTAssertEqual(viewer.header.alpha, 1)
    XCTAssertEqual(viewer.footer.alpha, 1)
    XCTAssertFalse(viewer.pages[1].flightLocked)
  }

  func testSyntheticOpeningOpacityTimeline() async throws {
    let assets = (0..<9).map { ViewerImageAsset("opening-\($0)", date: Double($0)) }
    let session = MediaPreviewSession(asset: assets[4], library: PhotoLibraryModel(), poster: bitmap(800, 600), reviewAssets: assets)
    let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: assets[4], frame: CGRect(x: 20, y: 200, width: 120, height: 120), poster: bitmap(800, 600)), session: session, close: {})
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    window.rootViewController = MediaViewerNavigationController(rootViewController: viewer)
    let probe = ViewerOpacityProbe(viewer, phase: "V1"); probe.start()
    defer { probe.stop(); window.isHidden = true; session.stop() }
    window.makeKeyAndVisible()
    try await Task.sleep(for: .milliseconds(1300))
    XCTAssertFalse(viewer.flying)
    XCTAssertEqual(viewer.header.alpha, 1)
    XCTAssertEqual(viewer.footer.alpha, 1)
    XCTAssertEqual(viewer.backdrop.alpha, 1)
  }

  private func makeViewer() throws -> (UIWindow, NativeMediaViewer, [ViewerImageAsset]) {
    let assets = (0..<40).map { ViewerImageAsset("visible-\($0)", date: Double($0)) }
    let library = PhotoLibraryModel()
    let session = MediaPreviewSession(asset: assets[20], library: library, poster: bitmap(800, 600), reviewAssets: assets)
    let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: assets[20], frame: CGRect(x: 20, y: 200, width: 120, height: 120), poster: bitmap(800, 600)), session: session, close: {})
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    window.rootViewController = MediaViewerNavigationController(rootViewController: viewer)
    viewer.loadViewIfNeeded(); viewer.flying = false
    window.makeKeyAndVisible(); viewer.layoutMedia(); session.start()
    return (window, viewer, assets)
  }

  private func bitmap(_ width: CGFloat, _ height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      DuckRole.accentUIColor.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
  }
  private func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("The asynchronous viewer state did not settle")
  }
}

private final class ViewerImageRequests: PHImageManager, @unchecked Sendable {
  var results: [(UIImage?, [AnyHashable: Any]?) -> Void] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    results.append(resultHandler); return PHImageRequestID(results.count)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
}
private final class ViewerImageAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let identifier: String, timestamp: Double
  var loads = 0
  init(_ identifier: String, date: Double = 0) { self.identifier = identifier; timestamp = date; super.init() }
  override var localIdentifier: String { identifier }
  override var creationDate: Date? { Date(timeIntervalSince1970: timestamp) }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
  var previewFilename: String { "synthetic.jpg" }
  var previewMetadata: [(String, String)] { [] }
  var previewImage: UIImage? { loads += 1; return UIImage(systemName: "photo") }
}

private final class ViewerRequestAsset: PHAsset, @unchecked Sendable {
  override var localIdentifier: String { "quality" }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
}

private final class ViewerPanFixture: UIPanGestureRecognizer {
  var phase: UIGestureRecognizer.State = .possible
  var delta = CGPoint.zero, speed = CGPoint.zero
  override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
  override func translation(in view: UIView?) -> CGPoint { delta }
  override func velocity(in view: UIView?) -> CGPoint { speed }
  override func location(in view: UIView?) -> CGPoint { CGPoint(x: 180, y: 350) }
}
@MainActor private final class ViewerOpacityProbe: NSObject {
  weak var viewer: NativeMediaViewer?
  var link: CADisplayLink?
  let phase: String
  init(_ viewer: NativeMediaViewer, phase: String = "V3") { self.viewer = viewer; self.phase = phase }
  func start() {
    let link = CADisplayLink(target: self, selector: #selector(sample)); self.link = link
    link.add(to: .main, forMode: .common)
  }
  func stop() { link?.invalidate(); link = nil }
  @objc private func sample() {
    guard let viewer else { return }
    let header = viewer.header.layer.presentation()?.opacity ?? Float(viewer.header.alpha)
    let footer = viewer.footer.layer.presentation()?.opacity ?? Float(viewer.footer.alpha)
    let background = viewer.backdrop.layer.presentation()?.opacity ?? Float(viewer.backdrop.alpha)
    let frame = viewer.mediaSurface()?.layer.presentation()?.frame ?? .zero
    print(phase + "_SAMPLE", ProcessInfo.processInfo.systemUptime, header, footer, background,
      viewer.flying, frame.origin.x, frame.origin.y, frame.width, frame.height)
  }
}

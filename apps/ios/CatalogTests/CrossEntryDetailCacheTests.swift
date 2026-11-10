import Combine
import Photos
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class CrossEntryDetailCacheTests: XCTestCase {
  func testOwnersShareOneBoundWithoutSharingBrowsingOrClearingEachOther() {
    let store = fixtureStore(budget: 4 * 1024 * 1024)
    let owners = (0..<3).map { _ in PhotoLibraryModel(thumbnails: ThumbnailPipeline(detailStore: store)) }
    let assets = (0..<3).map { CrossEntryAsset("budget-\($0)") }
    let image = bitmap(800, 600)
    owners[0].selection = ["main-only"]
    XCTAssertTrue(owners[1].selection.isEmpty)
    XCTAssertTrue(owners[2].selection.isEmpty)
    for (owner, asset) in zip(owners, assets) { owner.thumbnails.retainDetailPoster(image, for: asset) }
    for owner in owners {
      XCTAssertNil(owner.thumbnails.detailPoster(for: assets[0]), "The byte bound is shared across all owners")
      XCTAssertTrue(owner.thumbnails.detailPoster(for: assets[1]) === image)
      XCTAssertTrue(owner.thumbnails.detailPoster(for: assets[2]) === image)
    }
    let otherEpoch = owners[1].thumbnails.epoch
    owners[0].thumbnails.clear()
    XCTAssertEqual(owners[1].thumbnails.epoch, otherEpoch, "Grid cancellation stays source-owned")
    XCTAssertNotNil(owners[1].thumbnails.detailPoster(for: assets[2]), "Leaving Photos does not discard another entry's prepared face")
  }

  func testExplicitRemovalAndRevocationRejectOldPublishersAcrossOwners() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    var access = PHAuthorizationStatus.authorized
    let store = DetailPosterStore(disk: nil, authorization: { access }, assetRevision: { PhotoLibraryModel.revision($0) })
    let main = ThumbnailPipeline(detailStore: store), recent = ThumbnailPipeline(detailStore: store)
    let asset = CrossEntryAsset("clear-publisher"), requests = CrossEntryRequests()
    let model = MediaPreviewModel(asset: asset, manager: requests, renditions: main)
    model.load()
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    requests.results[1](bitmap(1600, 1200), [:])
    try await wait { model.image?.size.width == 1600 }
    XCTAssertNil(recent.detailPoster(for: asset), "A pre-clear display decode cannot repopulate shared memory")
    model.load()
    requests.results[3](bitmap(1600, 1200), [:])
    try await wait { recent.detailPoster(for: asset) != nil }
    access = .denied
    XCTAssertNil(recent.detailPoster(for: asset))
    access = .authorized
    _ = recent.detailAccessGeneration
    requests.results[3](bitmap(2400, 1800), [:])
    try await wait { model.image?.size.width == 2400 }
    XCTAssertNil(recent.detailPoster(for: asset), "Regranting access does not revive an old publication token")
    model.cancel()
  }

  func testLimitedScopeAndEditsRejectStalePixelsWhileOtherAssetsSurvive() {
    var revisions = ["limited-a": "1000", "limited-b": "1000"]
    let store = DetailPosterStore(disk: nil, authorization: { .limited }, assetRevision: { revisions[$0.localIdentifier] })
    let main = ThumbnailPipeline(detailStore: store), history = ThumbnailPipeline(detailStore: store)
    let a = CrossEntryAsset("limited-a"), b = CrossEntryAsset("limited-b"), image = bitmap(800, 600)
    main.retainDetailPoster(image, for: a); history.retainDetailPoster(image, for: b)
    let oldGeneration = main.detailAccessGeneration
    revisions.removeValue(forKey: a.localIdentifier)
    XCTAssertNil(history.detailPoster(for: a))
    XCTAssertNotNil(history.detailPoster(for: b))
    main.retainDetailPoster(image, for: a, generation: oldGeneration)
    XCTAssertNil(history.detailPoster(for: a))
    revisions[a.localIdentifier] = "2000"
    let edited = CrossEntryAsset("limited-a", revision: 2)
    history.retainDetailPoster(image, for: edited)
    XCTAssertNotNil(main.detailPoster(for: edited))
    XCTAssertNil(main.detailPoster(for: a))
    XCTAssertNotNil(history.detailPoster(for: edited), "An old asset handle must not evict the current revision")
  }

  func testActualPhotosLibraryRecentAndHistoryReuseThePreparedDisplayFace() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Synthetic PhotoKit imports run only in a dedicated simulator")
    #else
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    let data = try XCTUnwrap(bitmap(4032, 3024).jpegData(compressionQuality: 0.95))
    var identifier = ""
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .photo, data: data, options: nil)
      identifier = request.placeholderForCreatedAsset!.localIdentifier
    }
    let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject)
    let main = PhotoLibraryModel(), recent = BackupPhotoRouter(), history = BackupPhotoRouter()
    XCTAssertFalse(main === recent.library); XCTAssertFalse(recent.library === history.library)
    XCTAssertFalse(main.thumbnails === recent.library.thumbnails)
    let row: [String: Any] = ["id": 1, "state": "received", "processing": "complete", "confirmed_bytes": 0,
      "asset": ["kind": "photo", "source_id": identifier, "revision": PhotoLibraryModel.revision(asset), "resources": []]]
    let job = try JSONDecoder().decode(BackupJob.self, from: JSONSerialization.data(withJSONObject: row))
    let photo = HistoryPhoto(job: job)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    let source = UIViewController(); source.view.backgroundColor = .systemBackground
    window.rootViewController = source; window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let scope = "native-hdr-v1|\(window.screen.traitCollection.displayGamut.rawValue)|\(window.screen.scale)"
    let target = DetailPosterTarget(pixels: CGSize(width: ceil(window.bounds.width * window.screen.scale),
      height: ceil(window.bounds.height * window.screen.scale)), screen: "\(ObjectIdentifier(window.screen))", displayProfile: scope)
    let frame = CGRect(x: 20, y: 180, width: 100, height: 100)
    for step in 0..<6 {
      let owner: PhotoLibraryModel, item: IOSPreviewItem, collection: [PHAsset]
      switch step % 3 {
      case 1:
        recent.open(photo, collection: [photo], frame: frame, surface: .page, ownsSourceVacancy: true)
        owner = recent.library; item = try XCTUnwrap(recent.preview); collection = recent.assets
      case 2:
        history.open(photo, collection: [photo], frame: frame)
        owner = history.library; item = try XCTUnwrap(history.preview); collection = history.assets
      default:
        owner = main; item = IOSPreviewItem(asset: asset, frame: frame, poster: nil); collection = [asset]
      }
      let session = MediaPreviewSession(asset: item.asset, library: owner, poster: item.poster, reviewAssets: collection)
      session.setDisplayViewport(window.bounds.size, screen: window.screen)
      if step > 0 {
        let initial = try XCTUnwrap(session.current.image)
        XCTAssertTrue(target.isSatisfied(by: initial, asset: asset), "Every source reuses the already prepared fit pixels")
        XCTAssertTrue(initial === main.thumbnails.detailPoster(for: asset, target: target))
      }
      var edges: [CGFloat] = []
      let observation = session.current.$image.sink { image in
        if let image { edges.append(max(image.size.width, image.size.height) * image.scale) }
      }
      let viewer = NativeMediaViewer(item: item, session: session, close: {})
      window.overrideUserInterfaceStyle = step % 2 == 0 ? .light : .dark
      presentMediaViewer(viewer, from: source, poster: item.poster)
      try await wait { !session.current.loading && owner.thumbnails.detailPoster(for: asset, target: target) != nil }
      try await Task.sleep(for: .milliseconds(650))
      let displayed = try XCTUnwrap(viewer.pages[1].scroll.photo.image)
      XCTAssertTrue(target.isSatisfied(by: displayed, asset: asset))
      if step > 0 {
        let minimum = max(target.fittedPixels(for: asset).width, target.fittedPixels(for: asset).height) - 1
        XCTAssertTrue(edges.allSatisfy { $0 >= minimum }, "A different source must not fall back to a grid or local small rendition")
      }
      print("CROSS_ENTRY_NATIVE", step, step % 3, edges, displayed.size)
      if step == 1 || step == 2 {
        let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: capture); attachment.name = "cross-entry-\(step)"; attachment.lifetime = .keepAlways; add(attachment)
      }
      viewer.dismissViewer(); try await Task.sleep(for: .milliseconds(600)); viewer.releasePreviewSource()
      observation.cancel(); owner.thumbnails.clear()
      XCTAssertNotNil(main.thumbnails.detailPoster(for: asset, target: target))
    }
    let removed = await ThumbnailDiskCache.shared.removeAll()
    XCTAssertTrue(removed)
    XCTAssertNil(main.thumbnails.detailPoster(for: asset, target: target))
    XCTAssertNil(recent.library.thumbnails.detailPoster(for: asset, target: target))
    XCTAssertNil(history.library.thumbnails.detailPoster(for: asset, target: target))
    #endif
  }

  private func fixtureStore(budget: Int = 48 * 1024 * 1024) -> DetailPosterStore {
    DetailPosterStore(budget: budget, disk: nil, authorization: { .authorized }, assetRevision: { PhotoLibraryModel.revision($0) })
  }
  private func bitmap(_ width: CGFloat, _ height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      UIColor.white.setFill()
      for x in stride(from: CGFloat(0), through: width, by: 80) { context.fill(CGRect(x: x, y: 0, width: 2, height: height)) }
    }
  }
  private func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<250 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
    XCTFail("Cross-entry display state did not become ready")
  }
}

private final class CrossEntryAsset: PHAsset, @unchecked Sendable {
  let identifier: String, revision: Double
  init(_ identifier: String, revision: Double = 1) { self.identifier = identifier; self.revision = revision; super.init() }
  override var localIdentifier: String { identifier }
  override var modificationDate: Date? { Date(timeIntervalSince1970: revision) }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 2400 }
  override var pixelHeight: Int { 1800 }
}
private final class CrossEntryRequests: PHImageManager, @unchecked Sendable {
  var results: [(UIImage?, [AnyHashable: Any]?) -> Void] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    results.append(resultHandler); return PHImageRequestID(results.count)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
}

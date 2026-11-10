import Photos
import SwiftUI
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class MediaGridSurfaceTests: XCTestCase {
  func testSparseCollectionsShareCanvasAndVerticalBounce() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    defer { window.isHidden = true; previous?.makeKeyAndVisible() }
    let history = IOSHistoryGridController()
    let library = CalendarGridController()
    let review = CalendarSelectedController()
    for controller in [history, library, review] as [UIViewController] {
      controller.loadViewIfNeeded()
      window.rootViewController = UINavigationController(rootViewController: controller)
      window.makeKeyAndVisible(); window.layoutIfNeeded()
      let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
      XCTAssertTrue(collection.alwaysBounceVertical, "Sparse photo collections retain native vertical rubber-banding")
      XCTAssertEqual(collection.backgroundColor, UIColor.clear)
      for style in [UIUserInterfaceStyle.light, .dark] {
        window.overrideUserInterfaceStyle = style
        window.layoutIfNeeded()
        XCTAssertEqual(controller.view.backgroundColor?.resolvedColor(with: window.traitCollection),
          MediaGridSurface.background.resolvedColor(with: window.traitCollection))
      }
    }
  }

  func testSparseHistoryRetainsOneCanvasAcrossSupportHeaderAndFooter() async throws {
    let oldCore = BackupEnvironment.core
    let oldPhotos = BackupEnvironment.usesPhotoLibrary
    let oldSample = BackupEnvironment.sampleThumbnail
    let core = ScenarioCore()
    BackupEnvironment.core = core; BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = { _ in Image(systemName: "photo") }
    defer {
      BackupEnvironment.core = oldCore; BackupEnvironment.usesPhotoLibrary = oldPhotos
      BackupEnvironment.sampleThumbnail = oldSample
    }
    let row: [String: Any] = ["id": "job-1", "cursor": 1, "sort_value": 1792300000000,
      "job": ["id": 1, "state": "received", "processing": "complete", "confirmed_bytes": 0,
        "asset": ["kind": "motion", "source_id": "synthetic", "revision": "1",
          "resources": [["filename": "synthetic.heic", "size": 10]]]]]
    let summary: [String: Any] = ["total": 1, "received": 1, "published": 1,
      "publication_failed": 0, "waiting": 0, "failed": 0, "queued": 0, "running": 0,
      "paused": 0, "confirmed_bytes": 0, "active": 0, "attention": 0]
    core.setValue(["items": [row], "summary": summary], for: "backup_tasks")
    core.setValue(["items": [], "summary": summary], for: "backup_tasks", when: ["state": "attention"])
    let history = BackupHistoryModel(); await history.reload(receiver: "synthetic")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("grid-surface-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    let model = BackupModel(root: root)
    defer { model.stop(); try? FileManager.default.removeItem(at: root) }
    let controller = IOSHistoryGridController()
    controller.update(IOSHistoryGrid(history: history, router: BackupPhotoRouter(), model: model,
      columns: 4, focus: nil, support: AnyView(Text("1 photo backed up to Pixel").padding(16)),
      dayTitle: { _ in "Today" }, presented: { _ in }))
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    controller.title = "Backup History"
    window.rootViewController = UINavigationController(rootViewController: controller)
    window.makeKeyAndVisible(); window.layoutIfNeeded()
    defer { window.isHidden = true; previous?.makeKeyAndVisible() }
    let grid = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
    XCTAssertEqual(grid.numberOfItems(inSection: 1), 1)
    XCTAssertLessThan(grid.contentSize.height, grid.bounds.height)
    XCTAssertTrue(grid.alwaysBounceVertical)
    for (style, name) in [(UIUserInterfaceStyle.light, "history-sparse-canvas-light"), (.dark, "history-sparse-canvas-dark")] {
      window.overrideUserInterfaceStyle = style; window.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      for header in grid.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
        XCTAssertEqual(header.backgroundColor?.resolvedColor(with: window.traitCollection),
          MediaGridSurface.background.resolvedColor(with: window.traitCollection))
      }
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
      let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
  }

  func testRecentThumbnailUsesTheNativeLibraryMarksAndKeepsTinyCoversUnmarked() async throws {
    let originalPhotos = BackupEnvironment.usesPhotoLibrary
    let originalThumbnail = BackupEnvironment.sampleThumbnail
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = { _ in Image(systemName: "photo") }
    defer { BackupEnvironment.usesPhotoLibrary = originalPhotos; BackupEnvironment.sampleThumbnail = originalThumbnail }
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    let host = UIHostingController(rootView: VStack {
      HStack {
        AssetThumbnail(sourceID: "synthetic-video", size: 100, cornerRadius: 0, mediaKind: "video")
        AssetThumbnail(sourceID: "synthetic-motion", size: 100, cornerRadius: 0, mediaKind: "motion")
      }
      AssetThumbnail(sourceID: "synthetic-cover", size: 40, cornerRadius: 0)
    })
    window.rootViewController = host; window.makeKeyAndVisible()
    defer { window.isHidden = true; previous?.makeKeyAndVisible() }
    try await Task.sleep(for: .milliseconds(100))
    window.layoutIfNeeded()
    let marks = descendants(host.view).compactMap { $0 as? CalendarTileDecorations }
    XCTAssertEqual(marks.count, 2, "Only browsable recent thumbnails opt into the shared media marks")
    let video = try XCTUnwrap(marks.first { $0.videoMark.image != nil })
    let live = try XCTUnwrap(marks.first { $0.liveMark.image != nil })
    XCTAssertNil(video.duration.text, "Recorded video type alone cannot invent its duration")
    XCTAssertFalse(video.videoMark.isHidden)
    XCTAssertFalse(live.liveMark.isHidden)
    for (style, name) in [(UIUserInterfaceStyle.light, "recent-native-marks-light"), (.dark, "recent-native-marks-dark")] {
      window.overrideUserInterfaceStyle = style; window.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
      let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
  }

  func testResolvedVideoAndLivePhotoMarksMatchNativeCellGeometry() throws {
    for (type, subtype, seconds) in [(PHAssetMediaType.video, PHAssetMediaSubtype(), 12.75), (.image, .photoLive, 0)] {
      let asset = GridMarkAsset(type: type, subtype: subtype, seconds: seconds)
      let recent = CalendarTileDecorations(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
      recent.thumbnail(hasImage: true, cloud: false); recent.media(asset: asset); recent.layoutIfNeeded()
      let cell = CalendarGridCell(frame: recent.bounds)
      cell.decorations.thumbnail(hasImage: true, cloud: false)
      cell.decorations.media(kind: type == .video ? "video" : "motion", duration: type == .video ? seconds : nil)
      cell.layoutIfNeeded()
      XCTAssertEqual(recent.duration.text, cell.duration.text)
      XCTAssertEqual(recent.duration.frame, cell.duration.frame)
      XCTAssertEqual(recent.liveMark.frame, cell.liveMark.frame)
      XCTAssertEqual(recent.videoMark.frame, cell.decorations.videoMark.frame)
      XCTAssertEqual(recent.duration.isHidden, cell.duration.isHidden)
      XCTAssertEqual(recent.liveMark.isHidden, cell.liveMark.isHidden)
      XCTAssertEqual(recent.videoMark.isHidden, cell.decorations.videoMark.isHidden)
      if type == .video { XCTAssertEqual(recent.duration.text, "0:13") }
      recent.frame.size = CGSize(width: 40, height: 40); recent.layoutIfNeeded()
      XCTAssertTrue(recent.duration.isHidden); XCTAssertTrue(recent.liveMark.isHidden); XCTAssertTrue(recent.videoMark.isHidden)
    }
  }

  private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

private final class GridMarkAsset: PHAsset, @unchecked Sendable {
  let type: PHAssetMediaType, subtype: PHAssetMediaSubtype, seconds: TimeInterval
  init(type: PHAssetMediaType, subtype: PHAssetMediaSubtype, seconds: TimeInterval) {
    self.type = type; self.subtype = subtype; self.seconds = seconds; super.init()
  }
  override var mediaType: PHAssetMediaType { type }
  override var mediaSubtypes: PHAssetMediaSubtype { subtype }
  override var duration: TimeInterval { seconds }
  override var burstIdentifier: String? { nil }
}

import Photos
import UIKit
import SwiftUI
import XCTest
@testable import BackupDuckCatalog

@MainActor final class ViewerContinuityTests: XCTestCase {
  func testNativeHistoryRetainsSecondPageAndMissingSourcesOnRefresh() async throws {
    let oldCore = BackupEnvironment.core
    let oldPhotos = BackupEnvironment.usesPhotoLibrary
    let oldSample = BackupEnvironment.sampleThumbnail
    let oldAsset = BackupEnvironment.sampleAsset
    let core = ScenarioCore()
    BackupEnvironment.core = core; BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = nil; BackupEnvironment.sampleAsset = nil
    defer {
      BackupEnvironment.core = oldCore; BackupEnvironment.usesPhotoLibrary = oldPhotos
      BackupEnvironment.sampleThumbnail = oldSample; BackupEnvironment.sampleAsset = oldAsset
    }
    let rows: [[String: Any]] = (1...240).map { id in
      ["id": "job-\(id)", "cursor": id, "sort_value": 1792300000000,
        "job": ["id": id, "state": "received", "processing": "complete", "confirmed_bytes": 0,
          "asset": ["kind": id % 2 == 0 ? "video" : "motion", "source_id": "missing-\(id)",
            "revision": "1", "resources": [["filename": "example.heic", "size": 10]]]]]
    }
    let summary: [String: Any] = ["total": 240, "received": 240, "published": 240,
      "publication_failed": 0, "waiting": 0, "failed": 0, "queued": 0, "running": 0,
      "paused": 0, "confirmed_bytes": 0, "active": 0, "attention": 0]
    core.setValue(["items": Array(rows.prefix(200)), "summary": summary], for: "backup_tasks")
    core.setValue(["items": Array(rows.suffix(40)), "summary": summary], for: "backup_tasks", when: ["after": "200"])
    core.setValue(["items": [], "summary": summary], for: "backup_tasks", when: ["state": "attention"])
    let history = BackupHistoryModel()
    await history.reload(receiver: "synthetic")
    XCTAssertEqual(history.photos.count, 200)
    await history.loadMore()
    XCTAssertEqual(history.photos.count, 240)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-grid-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    let model = BackupModel(root: root)
    defer { model.stop(); try? FileManager.default.removeItem(at: root) }
    let controller = IOSHistoryGridController()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    let adapter = IOSHistoryGrid(history: history, router: BackupPhotoRouter(), model: model,
      columns: 4, focus: "job-225", support: AnyView(EmptyView()), dayTitle: { _ in "Today" }, presented: { _ in })
    controller.update(adapter); controller.view.layoutIfNeeded()
    let grid = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
    XCTAssertEqual((0..<grid.numberOfSections).reduce(0) { $0 + grid.numberOfItems(inSection: $1) }, 242)
    let anchor = grid.contentOffset.y
    XCTAssertTrue(grid.visibleCells.contains { $0 is CalendarGridCell && $0.accessibilityIdentifier == "history.photo.job-225" })
    await history.reload(receiver: "synthetic")
    XCTAssertEqual(history.photos.count, 240, "An observation preserves the loaded window even without accessible sources")
    controller.update(adapter); controller.view.layoutIfNeeded()
    XCTAssertEqual(grid.contentOffset.y, anchor, accuracy: 1)
    let video = try XCTUnwrap(grid.visibleCells.compactMap { $0 as? CalendarGridCell }.first { $0.assetID == "job-226" })
    XCTAssertNil(video.duration.text, "A missing source does not invent a duration")
    XCTAssertNotNil(video.decorations.videoMark.image)
    XCTAssertTrue(grid.visibleCells.compactMap { $0 as? CalendarGridCell }.allSatisfy { $0.image.image == nil })

    BackupEnvironment.sampleAsset = { job in job.id % 5 == 0 ? nil : HistoryGridSampleAsset(job) }
    let illustrated = IOSHistoryGridController()
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    let navigation = UINavigationController(rootViewController: illustrated)
    illustrated.title = "Backup History"
    window.rootViewController = navigation; window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let preview = IOSHistoryGrid(history: history, router: BackupPhotoRouter(), model: model, columns: 4, focus: nil,
      support: AnyView(Text("240 photos backed up to Pixel").font(.subheadline).padding(16)), dayTitle: { _ in "Today" }, presented: { _ in })
    illustrated.update(preview); illustrated.view.layoutIfNeeded()
    let nativeGrid = try XCTUnwrap(illustrated.view.subviews.compactMap { $0 as? UICollectionView }.first)
    try await Task.sleep(for: .milliseconds(100))
    for (style, name) in [(UIUserInterfaceStyle.light, "history-native-light"), (.dark, "history-native-dark")] {
      window.overrideUserInterfaceStyle = style
      window.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
      let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    let duration = try XCTUnwrap(nativeGrid.visibleCells.compactMap { $0 as? CalendarGridCell }.first { $0.assetID == "job-2" })
    XCTAssertEqual(duration.duration.text, videoDurationLabel(12.75))
    let live = try XCTUnwrap(nativeGrid.visibleCells.compactMap { $0 as? CalendarGridCell }.first { $0.assetID == "job-1" })
    XCTAssertNotNil(live.liveMark.image)
    illustrated.collectionView(nativeGrid, didSelectItemAt: IndexPath(item: 0, section: 1))
    try await wait { illustrated.presentedViewController != nil }
    let viewer = try XCTUnwrap((illustrated.presentedViewController as? UINavigationController)?.viewControllers.first as? NativeMediaViewer)
    XCTAssertEqual(viewer.session.count, 192, "Only accessible originals enrich viewer media; all 240 recorded tiles remain")
    if let next = viewer.session.adjacent(to: viewer.session.current.asset, direction: 1) { viewer.session.activate(next) }
    try await Task.sleep(for: .milliseconds(700))
    viewer.dismissViewer()
    try await wait { illustrated.presentedViewController == nil }
    XCTAssertEqual((0..<nativeGrid.numberOfSections).reduce(0) { $0 + nativeGrid.numberOfItems(inSection: $1) }, 242)
    illustrated.collectionView(nativeGrid, didSelectItemAt: IndexPath(item: 4, section: 1))
    try await wait { illustrated.presentedViewController != nil }
    let fallback = try XCTUnwrap((illustrated.presentedViewController as? UINavigationController)?.viewControllers.first as? NativeMediaViewer)
    XCTAssertEqual(fallback.recordedPhoto?.id, "job-5")
    try await Task.sleep(for: .milliseconds(700))
    fallback.dismissViewer()
    try await wait { illustrated.presentedViewController == nil }
    let cardPhoto = try XCTUnwrap(history.photos.first)
    let cardFrame = CGRect(x: 30, y: 120, width: 40, height: 40)
    preview.router.frames[cardPhoto.source] = cardFrame
    // A local problem-card route installs its own return providers before the
    // published preview makes the surrounding timeline update.
    preview.router.library.previewFrame = { [weak router = preview.router] in router?.frames[$0] }
    preview.router.library.previewVisibility = nil
    preview.router.library.previewOwnsVacancy = false
    illustrated.update(preview)
    illustrated.view.setNeedsLayout(); illustrated.view.layoutIfNeeded()
    let offset = nativeGrid.contentOffset
    nativeGrid.setContentOffset(CGPoint(x: offset.x, y: offset.y + 1), animated: false)
    nativeGrid.setContentOffset(offset, animated: false)
    XCTAssertEqual(preview.router.library.previewFrame?(cardPhoto.source), cardFrame,
      "Refreshing the timeline must not steal the return anchor from a problem-card photo")
    XCTAssertFalse(preview.router.library.previewOwnsVacancy,
      "A timeline refresh cannot replace the card's source-vacancy ownership")
    XCTAssertNil(preview.router.library.previewVisibility)
    preview.router.preview = nil
  }

  func testInfoProjectsObservedStagesWithoutInventingReceiptOrGalleryCompletion() async throws {
    let previousPhotos = BackupEnvironment.usesPhotoLibrary
    let previousNetwork = BackupEnvironment.usesNetwork
    let previousRestore = BackupEnvironment.restoresSenderNetwork
    let previousModel = BackupEnvironment.activeModel
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.usesNetwork = false
    BackupEnvironment.restoresSenderNetwork = { false }
    defer {
      BackupEnvironment.usesPhotoLibrary = previousPhotos
      BackupEnvironment.usesNetwork = previousNetwork
      BackupEnvironment.restoresSenderNetwork = previousRestore
      BackupEnvironment.activeModel = previousModel
    }
    let model = BackupModel(root: FileManager.default.temporaryDirectory
      .appendingPathComponent("viewer-info-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"))
    BackupEnvironment.activeModel = { model }
    let asset = ViewerImageAsset("info-stage")
    func makeViewer(state: String, processing: String? = nil,
      progress: TransferProgress? = nil, confirmed: UInt64? = nil) throws -> (NativeMediaViewer, UIView) {
      let job = BackupJob(id: 1, asset: .init(kind: "photo", source_id: asset.localIdentifier, revision: "0",
        resources: [.init(filename: "first.jpg", size: 100), .init(filename: "second.jpg", size: 100)]),
        state: state, confirmedBytes: confirmed ?? (state == "received" ? 200 : 0), errorCode: state == "failed" ? "network" : nil,
        processing: processing)
      // No receiver means the real viewer uses its recorded observation without
      // asking the core or starting any receiver/network work.
      model.transferProgress = progress.map { [job.id: $0] } ?? [:]
      let session = MediaPreviewSession(asset: asset, library: PhotoLibraryModel(), reviewAssets: [asset])
      let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: asset, frame: .zero, poster: nil), session: session, close: {})
      viewer.backupModel = model; viewer.recordedPhoto = HistoryPhoto(job: job)
      viewer.loadViewIfNeeded()
      let info = try XCTUnwrap(viewer.toolbarItems?.compactMap(\.customView)
        .first { $0.accessibilityIdentifier == "library.preview.info" })
      return (viewer, info)
    }
    let stages: [(String, String?, String)] = [
      ("queued", nil, "state_queued"),
      ("waiting", nil, "state_waiting"),
      ("paused", nil, "state_paused"),
      ("failed", nil, "photo_viewer_failed"),
      ("received", "failed", "photo_viewer_failed"),
      ("received", nil, "photo_viewer_confirming_photos"),
      ("received", "unknown", "photo_viewer_confirming_photos"),
      ("received", "not_requested", "photo_viewer_confirming_photos"),
      ("received", "pending", "records_fact_saving"),
      ("received", "complete", "photo_viewer_saved"),
    ]
    for (state, processing, expected) in stages {
      let (viewer, info) = try makeViewer(state: state, processing: processing)
      defer { viewer.releasePreviewSource() }
      let label = try XCTUnwrap(info.accessibilityLabel)
      if expected == "photo_viewer_saved" {
        XCTAssertEqual(label, NSLocalizedString("photo_viewer_info", comment: ""), "Only confirmed gallery completion clears the working state")
      } else {
        XCTAssertTrue(label.localizedCaseInsensitiveContains(NSLocalizedString(expected, comment: "")),
          "\(state)/\(processing ?? "nil") must expose its observed stage, got \(label)")
        XCTAssertNotEqual(label, NSLocalizedString("photo_viewer_info", comment: ""))
      }
    }

    let (viewer, info) = try makeViewer(state: "running",
      progress: TransferProgress(sent: 100, expected: 200, baseline: 0, phase: "upload"))
    defer { viewer.releasePreviewSource() }
    XCTAssertTrue(try XCTUnwrap(info.accessibilityLabel).contains(0.5.formatted(.percent.precision(.fractionLength(0)))))
    model.transferProgress = [1: .init(sent: 200, expected: 200, baseline: 0, phase: "upload")]
    let waitingText = NSLocalizedString("photo_viewer_confirming_receipt", comment: "")
    try await wait { info.accessibilityLabel?.localizedCaseInsensitiveContains(waitingText) == true }
    XCTAssertTrue(viewer.toolbarItems?.compactMap(\.customView).contains { $0 === info } == true,
      "The same Info control remains available across the ring-to-status handoff")
    XCTAssertFalse(try XCTUnwrap(info.accessibilityLabel).contains("%"))
    let completedObservations: [TransferProgress?] = [nil,
      .init(sent: 0, expected: 0, baseline: 0, phase: "commit", waitingForNetwork: true)]
    for progress in completedObservations {
      let (snapshot, button) = try makeViewer(state: "running", progress: progress, confirmed: 200)
      defer { snapshot.releasePreviewSource() }
      XCTAssertTrue(try XCTUnwrap(button.accessibilityLabel).localizedCaseInsensitiveContains(waitingText),
        "Acknowledged whole-job bytes remain a confirmation wait even when live request progress has ended")
    }
    let transfers: [(TransferProgress, String)] = [
      // A completed resource is not a completed two-resource job.
      (.init(sent: 100, expected: 100, baseline: 0, phase: "upload"), "photo_viewer_backing_up"),
      (.init(sent: 100, expected: 100, baseline: 100, phase: "upload"), "photo_viewer_confirming_receipt"),
      (.init(sent: 200, expected: 200, baseline: 0, phase: "bundle"), "photo_viewer_confirming_receipt"),
      (.init(sent: 0, expected: 0, baseline: 0, phase: "commit"), "photo_viewer_confirming_receipt"),
      (.init(sent: 200, expected: 200, baseline: 0, phase: "upload", waitingForNetwork: true), "photo_viewer_backing_up"),
      (.init(sent: 0, expected: 0, baseline: 0, phase: "upload"), "photo_viewer_backing_up"),
    ]
    for (progress, expected) in transfers {
      let (snapshot, button) = try makeViewer(state: "running", progress: progress)
      defer { snapshot.releasePreviewSource() }
      let expectedText = NSLocalizedString(expected, comment: "")
      let label = try XCTUnwrap(button.accessibilityLabel)
      XCTAssertTrue(label.localizedCaseInsensitiveContains(expectedText), "Transport observation must not claim receipt or gallery completion: \(label)")
      XCTAssertFalse(label.contains("%"), "A completed request or unknown fraction must replace the old byte percentage")
      XCTAssertNotEqual(label, NSLocalizedString("photo_viewer_info", comment: ""))
    }
  }

  func testReceiptFactsProjectWaitingWithoutChangingObservedReceiptOrSupportingSlots() {
    func facts(_ state: String, bytes: UInt64, processing: String? = nil, liveWait: Bool = false, needsYou: Bool = false) -> PhotoBackupFacts {
      let job = BackupJob(id: 1, asset: .init(kind: "photo", source_id: "synthetic", revision: "1",
        resources: [.init(filename: "synthetic.jpg", size: 200)]), state: state, confirmedBytes: bytes,
        errorCode: nil, processing: processing)
      return PhotoBackupFacts(job: job, receiverName: "Pixel", needsYou: needsYou, awaitingReceipt: liveWait)
    }
    for state in ["queued", "running"] {
      let complete = facts(state, bytes: 200)
      XCTAssertTrue(complete.isAwaitingReceipt)
      XCTAssertEqual(complete.job?.state, state)
      XCTAssertNil(complete.job?.processing); XCTAssertNil(complete.job?.receivedAt); XCTAssertNil(complete.job?.publishedAt)
      XCTAssertFalse(facts(state, bytes: 100).isAwaitingReceipt)
      XCTAssertFalse(facts(state, bytes: 0).isAwaitingReceipt)
      XCTAssertTrue(facts(state, bytes: 0, liveWait: true).isAwaitingReceipt,
        "The viewer may supply the observed final-body/commit wait without changing durable facts")
      XCTAssertFalse(facts(state, bytes: 200, needsYou: true).isAwaitingReceipt)
      XCTAssertFalse(facts(state, bytes: 200, processing: "failed").isAwaitingReceipt)
    }
    for state in ["waiting", "paused", "failed", "received"] {
      XCTAssertFalse(facts(state, bytes: 200, liveWait: true).isAwaitingReceipt,
        "Retry, pause, failure and receipt retain their own observed wording")
    }
    for size in [DynamicTypeSize.large, .xLarge, .accessibility3] {
      func height(_ value: PhotoBackupFacts) -> CGFloat {
        UIHostingController(rootView: value.dynamicTypeSize(size))
          .sizeThatFits(in: CGSize(width: 1200, height: CGFloat.greatestFiniteMagnitude)).height
      }
      XCTAssertEqual(height(facts("queued", bytes: 200)), height(facts("queued", bytes: 0)), accuracy: 0.5,
        "The wait uses the same fact and reserved supporting slot")
      XCTAssertEqual(height(facts("paused", bytes: 200)), height(facts("paused", bytes: 0)), accuracy: 0.5)
    }
  }

  func testInfoRemainsUnmarkedAcrossNativeRequestRequeueAndReceiptRefresh() async throws {
    let oldCore = BackupEnvironment.core, oldModel = BackupEnvironment.activeModel
    let oldPhotos = BackupEnvironment.usesPhotoLibrary, oldNetwork = BackupEnvironment.usesNetwork
    let oldRestore = BackupEnvironment.restoresSenderNetwork
    let core = ScenarioCore()
    BackupEnvironment.core = core; BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.usesNetwork = false; BackupEnvironment.restoresSenderNetwork = { false }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("info-handoff-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    let model = BackupModel(root: root)
    BackupEnvironment.activeModel = { model }
    defer {
      model.stop(); try? FileManager.default.removeItem(at: root)
      BackupEnvironment.core = oldCore; BackupEnvironment.activeModel = oldModel
      BackupEnvironment.usesPhotoLibrary = oldPhotos; BackupEnvironment.usesNetwork = oldNetwork
      BackupEnvironment.restoresSenderNetwork = oldRestore
    }
    model.pairing = Pairing(version: 2, receiverID: "synthetic", endpoint: "https://127.0.0.1:1", certificate: "fixture", token: "fixture")
    let asset = ViewerImageAsset("info-native-handoff")
    var revision: Int64 = 0
    func observe(_ state: String, bytes: UInt64, processing: String? = nil) {
      core.setValue(["id": 1, "asset": ["kind": "photo", "source_id": asset.localIdentifier,
        "revision": PhotoLibraryModel.revision(asset), "resources": [["filename": "first.jpg", "size": 100], ["filename": "second.jpg", "size": 100]]],
        "state": state, "confirmed_bytes": bytes, "processing": processing as Any? ?? NSNull(),
        "error_code": state == "failed" ? "network" : NSNull()], for: "source_job")
      let tile = state == "failed" || processing == "failed" ? "needs_you"
        : state == "received" ? (processing == "complete" ? "saved" : "saving") : "sending"
      core.setValue([asset.localIdentifier: ["revision": PhotoLibraryModel.revision(asset),
        "preparing": false, "tile_state": tile]], for: "library_source_states")
      revision += 1; model.queueRevision = revision
    }
    observe("running", bytes: 0)
    model.transferProgress = [1: .init(sent: 100, expected: 200, baseline: 0, phase: "bundle")]
    let session = MediaPreviewSession(asset: asset, library: PhotoLibraryModel(), reviewAssets: [asset])
    let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: asset, frame: .zero, poster: asset.previewImage), session: session, close: {})
    viewer.backupModel = model
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    let navigation = UINavigationController(rootViewController: viewer)
    window.rootViewController = navigation; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
    defer { viewer.releasePreviewSource(); window.isHidden = true }
    let button = try XCTUnwrap(viewer.toolbarItems?.compactMap(\.customView).first { $0.accessibilityIdentifier == "library.preview.info" })
    try await wait { button.accessibilityLabel?.contains("50%") == true }
    try await Task.sleep(for: .milliseconds(500))
    window.layoutIfNeeded()
    let frame = button.convert(button.bounds, to: window)
    let ring = try XCTUnwrap(button.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
    XCTAssertFalse(ring.isHidden, "The initial partial body has a real byte-progress ring")
    let dot = try XCTUnwrap(button.subviews.compactMap { $0 as? UIImageView }.first { $0.bounds.width == 6 })
    func check(_ key: String, name: String, marked: Bool = false) async throws {
      let expected = NSLocalizedString(key, comment: "")
      try await wait { key == "photo_viewer_saved" ? button.accessibilityLabel == NSLocalizedString("photo_viewer_info", comment: "")
        : button.accessibilityLabel?.localizedCaseInsensitiveContains(expected) == true }
      // Sample through subsequent display opportunities, including progress
      // publication after the asynchronous source-job observation has returned.
      for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(16))
        XCTAssertEqual(button.convert(button.bounds, to: window), frame)
        XCTAssertTrue(ring.isHidden, "\(name) must not keep a progress track")
        let label = button.accessibilityLabel ?? ""
        XCTAssertTrue(key == "photo_viewer_saved" ? label == NSLocalizedString("photo_viewer_info", comment: "")
          : label.localizedCaseInsensitiveContains(expected), "\(name): \(label)")
      }
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
      let attachment = XCTAttachment(image: image); attachment.name = "info-handoff-" + name; attachment.lifetime = .keepAlways; add(attachment)
      // Inspect the rendered native dot, including symbol effects; a state
      // label alone cannot prove that normal waiting is visually unmarked.
      let rect = dot.convert(dot.bounds, to: window)
      let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: rect.minX * image.scale,
        y: rect.minY * image.scale, width: rect.width * image.scale, height: rect.height * image.scale)))
      var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
      let context = try XCTUnwrap(CGContext(data: &pixels, width: crop.width, height: crop.height,
        bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
      let color = (key == "photo_viewer_failed" ? DuckRole.attentionGlyphUIColor : DuckRole.accentUIColor)
        .resolvedColor(with: button.traitCollection)
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      let colored = stride(from: 0, to: pixels.count, by: 4).filter { i in
        abs(Double(pixels[i]) / 255 - red) < 0.15 && abs(Double(pixels[i+1]) / 255 - green) < 0.15
          && abs(Double(pixels[i+2]) / 255 - blue) < 0.15
      }.count
      XCTAssertEqual(colored > 0, marked, "\(name): rendered mark pixels=\(colored)")
    }
    for (style, theme) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
      window.overrideUserInterfaceStyle = style
      // Original preparation has no transfer job or byte fraction yet.
      // Exercise the actual asynchronous source observation before a job exists.
      core.setValue(NSNull(), for: "source_job")
      core.setValue([asset.localIdentifier: ["revision": PhotoLibraryModel.revision(asset),
        "preparing": true, "tile_state": "sending"]], for: "library_source_states")
      model.transferProgress = [:]
      revision += 1; model.queueRevision = revision
      try await check("photo_viewer_backing_up", name: theme + "-original-preparation-before-job")
      XCTAssertTrue(model.jobs.isEmpty, "Preparation must not invent a transfer job")
      core.setValue([asset.localIdentifier: ["revision": PhotoLibraryModel.revision(asset),
        "preparing": false, "tile_state": "needs_you"]], for: "library_source_states")
      revision += 1; model.queueRevision = revision
      try await check("photo_viewer_failed", name: theme + "-original-preparation-failed", marked: true)
      // URLSession finishes its body before Rust has observed a receipt.
      observe("running", bytes: 0)
      model.transferProgress = [1: .init(sent: 200, expected: 200, baseline: 0, phase: "bundle")]
      try await check("photo_viewer_confirming_receipt", name: theme + "-body-ended")
      // complete_native checkpoints bytes, releases the task, and requeues
      // the job before the next commit request is claimed.
      observe("queued", bytes: 200)
      try await check("photo_viewer_confirming_receipt", name: theme + "-checkpoint-requeued")
      model.transferProgress = [:]
      try await check("photo_viewer_confirming_receipt", name: theme + "-progress-cleared")
      (button as? UIControl)?.sendActions(for: .touchUpInside)
      try await Task.sleep(for: .milliseconds(400))
      observe("running", bytes: 200)
      model.transferProgress = [1: .init(sent: 0, expected: 0, baseline: 0, phase: "commit")]
      try await check("photo_viewer_confirming_receipt", name: theme + "-commit")
      // A connectivity wait after acknowledged whole-job bytes is still a
      // receipt wait; this does not manufacture a received or saved fact.
      observe("waiting", bytes: 200)
      model.transferProgress = [1: .init(sent: 0, expected: 0, baseline: 0, phase: "commit", waitingForNetwork: true)]
      try await check("state_waiting", name: theme + "-receipt-network-wait")
      observe("paused", bytes: 200)
      model.transferProgress = [:]
      try await check("state_paused", name: theme + "-post-transfer-paused")
      observe("received", bytes: 200)
      model.transferProgress = [:]
      try await check("photo_viewer_confirming_photos", name: theme + "-gallery-unknown")
      observe("received", bytes: 200, processing: "pending")
      try await check("records_fact_saving", name: theme + "-saving")
      observe("received", bytes: 200, processing: "failed")
      try await check("photo_viewer_failed", name: theme + "-gallery-failed", marked: true)
      observe("queued", bytes: 200)
      try await check("photo_viewer_confirming_receipt", name: theme + "-retry-confirmation")
      observe("queued", bytes: 200, processing: "failed")
      try await check("photo_viewer_failed", name: theme + "-queued-processing-failed", marked: true)
      observe("failed", bytes: 200)
      try await check("photo_viewer_failed", name: theme + "-transfer-failed", marked: true)
      observe("received", bytes: 200, processing: "complete")
      try await check("photo_viewer_saved", name: theme + "-saved")
      // A different attempt with only one resource sent must retain its
      // ordinary queued state rather than inheriting the completed attempt.
      observe("queued", bytes: 100)
      try await check("state_queued", name: theme + "-partial-resource-requeued")
      observe("queued", bytes: 0)
      try await check("state_queued", name: theme + "-unknown-byte-requeued")
      observe("waiting", bytes: 100)
      try await check("state_waiting", name: theme + "-partial-waiting")
      observe("paused", bytes: 100)
      try await check("state_paused", name: theme + "-partial-paused")
      (button as? UIControl)?.sendActions(for: .touchUpInside)
      try await Task.sleep(for: .milliseconds(400))
    }
    XCTAssertFalse(core.commands.filter { $0.contains("source_job") }.isEmpty)
  }

  func testSharedPresentationKeepsSourceVisibleUntilTheFlightStarts() async throws {
    let asset = ViewerOpeningAsset(image: bitmap(352, 352))
    let library = PhotoLibraryModel()
    var sourceHidden = false
    let frame = CGRect(x: 20, y: 200, width: 120, height: 120)
    let item = IOSPreviewItem(asset: asset, frame: frame, poster: asset.previewImage)
    let session = MediaPreviewSession(asset: asset, library: library, poster: item.poster, reviewAssets: [asset])
    let viewer = NativeMediaViewer(item: item, session: session, close: {})
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    let source = UIViewController(); source.view.backgroundColor = .systemBackground
    let tile = UIImageView(image: asset.previewImage); tile.frame = frame; source.view.addSubview(tile)
    library.previewVisibility = { sourceHidden = $0 != nil; tile.isHidden = sourceHidden }
    window.rootViewController = source; window.makeKeyAndVisible()
    defer { viewer.releasePreviewSource(); window.isHidden = true }
    try await Task.sleep(for: .milliseconds(50))
    presentMediaViewer(viewer, from: source, poster: item.poster)
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertNil(source.presentedViewController, "A cropped seed is still preparing its full-aspect rendition")
    XCTAssertFalse(sourceHidden, "Preparing an offscreen viewer must not blank the live source before its snapshot exists")
    try await wait { source.presentedViewController != nil }
    XCTAssertEqual(viewer.loadingIndicator.alpha, 0, "Media loading remains hidden while the shared transition flies")
    try await Task.sleep(for: .milliseconds(700))
    XCTAssertTrue(sourceHidden, "The covered source stays owned by the open viewer")
    source.dismiss(animated: false)
    try await Task.sleep(for: .milliseconds(50))
  }

  func testReopeningRetainsPreparedDetailPixelsUntilTheSourceRevisionOrCacheChanges() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let library = cacheLibrary(), asset = ViewerRequestAsset()
    let manager = ViewerImageRequests()
    let model = MediaPreviewModel(asset: asset, poster: bitmap(80, 60), manager: manager, renditions: library.thumbnails)
    model.load()
    manager.results[1](bitmap(1600, 1200), [:])
    try await wait { model.image?.size.width == 1600 && !model.loading }
    model.cancel()
    let reopened = MediaPreviewSession(asset: asset, library: library, poster: bitmap(352, 352), reviewAssets: [asset])
    XCTAssertTrue(reopened.current.image === model.image, "A new viewer uses the already prepared uncropped detail pixels")
    let changed = MediaPreviewSession(asset: ViewerRequestAsset(revision: 1), library: library, poster: bitmap(352, 352))
    XCTAssertEqual(changed.current.image?.size.width, 352, "An edited asset must not reopen an obsolete revision")
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    let cleared = MediaPreviewSession(asset: asset, library: library, poster: bitmap(352, 352))
    XCTAssertEqual(cleared.current.image?.size.width, 352, "Explicit cache removal releases shared detail pixels")
  }

  func testRepeatedDetailRetainsForegroundPixelsAfterNeighbourPreparation() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let library = cacheLibrary(), asset = ViewerRequestAsset()
    for attempt in 0..<3 {
      let manager = ViewerImageRequests()
      let model = MediaPreviewModel(asset: asset, poster: bitmap(352, 352), manager: manager, renditions: library.thumbnails)
      if attempt > 0 { XCTAssertEqual(model.image?.size.width, 2400, "Reopening must start with the detail that was already viewed") }
      model.load()
      manager.results[1](bitmap(2400, 1800), [:])
      try await wait { model.image?.size.width == 2400 && !model.loading }
      var neighbours: [MediaPreviewModel] = []
      for offset in 0..<4 {
        let neighbourManager = ViewerImageRequests()
        let neighbour = MediaPreviewModel(asset: ViewerRequestAsset(identifier: "neighbour-\(offset)"), manager: neighbourManager, renditions: library.thumbnails)
        neighbour.load(promptForCloud: false)
        neighbourManager.results[1](bitmap(2400, 1800), [:])
        try await wait { neighbour.image?.size.width == 2400 && !neighbour.loading }
        neighbours.append(neighbour)
      }
      model.cancel(); neighbours.forEach { $0.cancel() }
      XCTAssertNotNil(library.thumbnails.detailPoster(for: asset), "Local neighbours must not evict the detail the person just viewed")
    }
  }

  func testLocalLivePreparationKeepsThePosterWithoutDownloadProgress() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let manager = ViewerLiveRequests()
    let model = MediaPreviewModel(asset: ViewerRequestAsset(live: true), poster: bitmap(800, 600), manager: manager)
    model.load()
    XCTAssertEqual(manager.options.map(\.isNetworkAccessAllowed), [false])
    XCTAssertNil(manager.options[0].progressHandler, "Local Live Photo assembly is not download progress")
    manager.images[1](bitmap(1600, 1200), [:])
    try await wait { model.image?.size.width == 1600 }
    XCTAssertTrue(model.loading, "Still readiness must not claim that Live Photo motion is ready")
    XCTAssertNil(model.progress)
    XCTAssertEqual(model.indicatorState, .hidden)
    manager.live[0](nil, [PHImageErrorKey: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.internalError.rawValue)])
    try await wait { !model.loading }
    XCTAssertTrue(model.failure); XCTAssertEqual(model.image?.size.width, 1600)
    model.cancel()
  }

  func testPosterAndReportedProgressShareOneLoadingPhaseUntilFinalImage() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let manager = ViewerImageRequests(), poster = bitmap(800, 600)
    let model = MediaPreviewModel(asset: ViewerRequestAsset(), poster: poster, manager: manager)
    model.load()
    defer { model.cancel() }
    XCTAssertTrue(model.loading)
    XCTAssertTrue(model.image === poster)
    XCTAssertEqual(model.indicatorState, .hidden)
    var stop: ObjCBool = false
    let handler = try XCTUnwrap(manager.options[1].progressHandler)
    handler(0, nil, &stop, nil)
    try await wait { model.indicatorState == .progress(0) }
    handler(0.4, nil, &stop, nil)
    try await wait { model.indicatorState == .progress(0.4) }
    handler(1, nil, &stop, nil)
    try await wait { model.indicatorState == .progress(1) }
    XCTAssertTrue(model.loading, "A complete fraction is not a completed image request")
    manager.results[1](bitmap(1600, 1200), [:])
    try await wait { !model.loading }
    XCTAssertEqual(model.indicatorState, .hidden)
  }

  func testLibraryWaitsForAccessResolutionBeforePermissionOrEmptyState() {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let model = PhotoLibraryModel()
    guard case .loading? = model.placeholder else { return XCTFail("Unresolved access must not claim a permission or empty state") }
    XCTAssertFalse(model.applyAuthorization(.denied))
    guard case .permission(.denied)? = model.placeholder else { return XCTFail("Resolved denial needs the permission state") }
    XCTAssertTrue(model.applyAuthorization(.authorized))
    guard case .loading? = model.placeholder else { return XCTFail("Authorized access still needs a completed fetch") }
  }

  func testLiveCloudFallbackPreservesNetworkPolicyAndRejectsCancelledCallbacks() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    for visible in [false, true] {
      let manager = ViewerLiveRequests()
      let model = MediaPreviewModel(asset: ViewerRequestAsset(live: true), poster: bitmap(800, 600), manager: manager)
      model.load(promptForCloud: visible)
      manager.live[0](nil, [PHImageResultIsInCloudKey: true, PHImageResultIsDegradedKey: true])
      try await wait { visible ? manager.live.count == 2 : !model.loading }
      XCTAssertEqual(manager.options.map(\.isNetworkAccessAllowed), visible ? [false, true] : [false])
      if visible {
        var stop: ObjCBool = false
        manager.options[1].progressHandler?(0.4, nil, &stop, nil)
        try await wait { model.progress == 0.4 }
        XCTAssertTrue(model.loading)
        // A degraded PhotoKit result cannot end the motion request.
        manager.live[1](nil, [PHImageResultIsDegradedKey: true])
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.loading); XCTAssertFalse(model.failure)
        model.cancel()
        manager.live[1](nil, [PHImageErrorKey: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.internalError.rawValue)])
        manager.options[1].progressHandler?(0.9, nil, &stop, nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(model.loading); XCTAssertFalse(model.failure); XCTAssertEqual(model.progress, 0.4)
      } else {
        XCTAssertTrue(model.cloudNeeded); XCTAssertTrue(model.failure)
      }
      model.cancel()
    }
  }

  func testReturnVacancyKeepsItsSourceSurfaceInLightAndDark() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let original = scene.windows.first { $0.isKeyWindow }
    for style: UIUserInterfaceStyle in [.light, .dark] {
      for background in [DuckRole.backgroundUIColor, DuckRole.groupedSurfaceUIColor] {
        let asset = ViewerOpeningAsset(image: bitmap(800, 600)), library = PhotoLibraryModel()
        let frame = CGRect(x: 20.25, y: 200.5, width: 91.75, height: 91.75)
        let item = IOSPreviewItem(asset: asset, frame: frame, poster: asset.previewImage, background: background)
        let session = MediaPreviewSession(asset: asset, library: library, poster: item.poster, reviewAssets: [asset])
        let viewer = NativeMediaViewer(item: item, session: session, close: {})
        let source = UIViewController(); source.view.backgroundColor = background
        let tile = UIImageView(image: item.poster); tile.frame = frame; source.view.addSubview(tile)
        library.previewFrame = { _ in frame }
        library.previewVisibility = { tile.isHidden = $0 != nil }
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style; window.rootViewController = source; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(100))
        presentMediaViewer(viewer, from: source, poster: item.poster)
        try await wait { source.presentedViewController != nil && viewer.openingTransition == false }
        viewer.dismissViewer()
        try await Task.sleep(for: .milliseconds(60))
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let slot = descendants(window).first {
          abs($0.bounds.width-frame.width) < 0.01 && abs($0.bounds.height-frame.height) < 0.01 && $0.backgroundColor != nil
        }
        let actual = try XCTUnwrap(slot?.backgroundColor).resolvedColor(with: window.traitCollection)
        XCTAssertEqual(actual, background.resolvedColor(with: window.traitCollection), "The source's own semantic surface covers the landing tile")
        try await wait { source.presentedViewController == nil }
        XCTAssertFalse(tile.isHidden, "The source pixels return after the flyer lands")
        viewer.releasePreviewSource(); window.isHidden = true
      }
    }
    original?.makeKeyAndVisible()
  }

  func testFlyingPageRetainsItsDisplayedPixelsUntilTheHandoff() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let manager = ViewerImageRequests(), asset = ViewerRequestAsset()
    let model = MediaPreviewModel(asset: asset, poster: bitmap(80, 60), manager: manager)
    let session = MediaPreviewSession(asset: asset, library: PhotoLibraryModel(), reviewAssets: [asset])
    let page = NativeMediaPage(model: model, session: session)
    page.loadViewIfNeeded(); page.flightLocked = true
    model.load(promptForCloud: false)
    manager.results[1](bitmap(800, 600), [:])
    try await wait { model.image?.size.width == 800 && !model.loading }
    XCTAssertEqual(page.scroll.photo.image?.size.width, 80, "An in-flight page cannot independently replace the flying bitmap")
    page.flightLocked = false
    XCTAssertEqual(page.scroll.photo.image?.size.width, 800, "The ready rendition is adopted when the flight releases ownership")
    model.cancel()
  }

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

  func testLocalRenditionsStayQuietAndRealDownloadProgressRemainsAvailable() async throws {
    let ring = MediaLoadingIndicator(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
    let geometry = ring.frame
    ring.update(state: .hidden, identity: "first")
    XCTAssertTrue(ring.accessibilityElementsHidden)
    ring.update(state: .progress(0), identity: "first")
    XCTAssertEqual(ring.arc.strokeEnd, 0)
    XCTAssertEqual(ring.accessibilityValue, "0%")
    XCTAssertFalse(ring.accessibilityElementsHidden)
    ring.update(state: .progress(0.4), identity: "first")
    XCTAssertEqual(ring.arc.strokeEnd, 0.4, accuracy: 0.001)
    XCTAssertEqual(ring.frame, geometry)
    ring.update(state: .hidden, identity: "first")
    XCTAssertTrue(ring.accessibilityElementsHidden)
    XCTAssertEqual(ring.frame, geometry)
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
    XCTAssertEqual(viewer.header?.alpha, 1)
    XCTAssertEqual(viewer.footer.alpha, 1)
    XCTAssertFalse(viewer.pages[1].flightLocked)
  }

  func testHistoryReturnKeepsActualHostedGridGeometryThroughCancellationAndLanding() async throws {
    for immersive in [false, true] {
      for edge in ["middle", "newest", "oldest"] { try await exerciseHostedReturn(album: false, immersive: immersive, edge: edge) }
    }
  }

  func testAlbumReturnKeepsActualHostedNavigationAndGridThroughCancellationAndLanding() async throws {
    for immersive in [false, true] {
      for edge in ["middle", "newest", "oldest"] { try await exerciseHostedReturn(album: true, immersive: immersive, edge: edge) }
      try await exerciseHostedReturn(album: true, immersive: immersive, edge: "oldest", count: 6)
    }
  }

  func testHostedReturnKeepsNativeSourceChromeAndEdgePixelsThroughHandoff() async throws {
    for appearance in [UIUserInterfaceStyle.light, .dark] {
      for album in [false, true] {
        for immersive in [false, true] {
          try await exerciseHostedReturn(album: album, immersive: immersive, edge: "middle", verifyPixels: true, appearance: appearance)
        }
      }
    }
  }

  private func exerciseHostedReturn(album: Bool, immersive: Bool, edge: String, count: Int = 120,
    verifyPixels: Bool = false, appearance: UIUserInterfaceStyle = .light) async throws {
    let oldCore = BackupEnvironment.core, oldAsset = BackupEnvironment.sampleAsset
    let oldPhotos = BackupEnvironment.usesPhotoLibrary, oldNetwork = BackupEnvironment.usesNetwork
    let oldAlbums = BackupEnvironment.albumSamples
    let core = ScenarioCore()
    BackupEnvironment.core = core; BackupEnvironment.usesPhotoLibrary = false; BackupEnvironment.usesNetwork = false
    BackupEnvironment.sampleAsset = { HistoryGridSampleAsset($0) }
    BackupEnvironment.albumSamples = { _ in CatalogLibraryFixture(count: count).fetch(filter: .all, view: .all) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hosted-return-\(UUID().uuidString)")
    let model = BackupModel(root: root), history = BackupHistoryModel()
    model.pairing = Pairing(version: 2, receiverID: "synthetic", endpoint: "https://127.0.0.1:1", certificate: "fixture", token: "fixture")
    let rows: [[String: Any]] = (1...120).map { id in
      ["id": "job-\(id)", "cursor": id, "sort_value": 1792300000000,
       "job": ["id": id, "state": "received", "processing": "complete", "confirmed_bytes": 0,
         "asset": ["kind": "photo", "source_id": "hosted-photo-\(id)", "revision": "1",
           "resources": [["filename": "example.heic", "size": 10]]]]]
    }
    core.setValue(["items": rows, "summary": ["total": 120, "received": 120, "published": 120,
      "publication_failed": 0, "waiting": 0, "failed": 0, "queued": 0, "running": 0, "paused": 0,
      "confirmed_bytes": 0, "active": 0, "attention": 0]], for: "backup_tasks")
    await history.reload(receiver: "synthetic")
    let navigation = IOSNativeNavigationController()
    navigation.installRoot(title: "Root", content: AnyView(Text("Root")))
    let tabs = UITabBarController()
    navigation.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 0)
    tabs.viewControllers = [navigation, UIViewController(), UIViewController()]
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousWindow = scene.windows.first { $0.isKeyWindow }, animations = UIView.areAnimationsEnabled
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    window.overrideUserInterfaceStyle = appearance
    window.rootViewController = MediaStatusBarRootController(content: tabs); window.makeKeyAndVisible()
    let scope = ScopeCatalogFixture(id: "settings.scope.albums")
    defer {
      model.stop(); window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible()
      BackupEnvironment.core = oldCore; BackupEnvironment.sampleAsset = oldAsset
      BackupEnvironment.usesPhotoLibrary = oldPhotos; BackupEnvironment.usesNetwork = oldNetwork
      BackupEnvironment.albumSamples = oldAlbums; UIView.setAnimationsEnabled(animations)
      try? FileManager.default.removeItem(at: root)
    }
    try await Task.sleep(for: .milliseconds(150)); UIView.setAnimationsEnabled(true)
    if album {
      navigation.pushPage(DuckSettingsPage(title: Text("Trip album"), content: AnyView(ScopeAlbumBrowser(
        album: ScopeAlbum(id: "test", name: "Trip album", count: count, system: false, cover: nil), store: scope.store))), animated: false)
    } else {
      // Match the Hub route: the history page is directly hosted, with its
      // production safe-area behavior and state-driven support content.
      let controller = UIHostingController(rootView: BackupHistoryView(model: model,
        initialFocus: history.photos.first { $0.id == "job-60" }))
      controller.navigationItem.title = NSLocalizedString("records_title", comment: "")
      controller.navigationItem.largeTitleDisplayMode = .never
      navigation.pushViewController(controller, animated: false)
    }
    try await Task.sleep(for: .milliseconds(500))
    let source = try XCTUnwrap(navigation.topViewController)
    func find<T>(_ parent: UIViewController, _ type: T.Type) -> T? {
      (parent as? T) ?? parent.children.compactMap { find($0, type) }.first
    }
    let calendar = find(source, CalendarGridController.self)
    let recorded = find(source, IOSHistoryGridController.self)
    if let calendar { try await wait { calendar.assets.count == count } }
    if let recorded {
      let collection = try XCTUnwrap(recorded.view.subviews.compactMap { $0 as? UICollectionView }.first)
      try await wait {
        guard let data = collection.dataSource as? UICollectionViewDiffableDataSource<String, String>,
          let focus = data.indexPath(for: "job-60"), let attributes = collection.layoutAttributesForItem(at: focus) else { return false }
        return abs(collection.contentOffset.y - (attributes.frame.minY - collection.adjustedContentInset.top)) < 1
      }
    }
    if let calendar { calendar.locateAsset(min(60, count - 1)) }
    let grid = try XCTUnwrap(calendar?.grid ?? recorded?.view.subviews.compactMap { $0 as? UICollectionView }.first)
    grid.layoutIfNeeded()
    if edge == "newest" {
      grid.setContentOffset(CGPoint(x: 0, y: max(-grid.adjustedContentInset.top,
        grid.contentSize.height - grid.bounds.height + grid.adjustedContentInset.bottom)), animated: false)
    } else if edge == "oldest" { grid.setContentOffset(CGPoint(x: 0, y: -grid.adjustedContentInset.top), animated: false) }
    grid.layoutIfNeeded()
    let paths = grid.indexPathsForVisibleItems.sorted().filter { album || $0.section > 0 }
    let path = try XCTUnwrap(paths.dropFirst(paths.count / 2).first)
    let cell = try XCTUnwrap(grid.cellForItem(at: path) as? CalendarGridCell)
    let original = cell.convert(cell.bounds, to: window), offset = grid.contentOffset
    let originalViewport = grid.convert(grid.bounds, to: window), originalInsets = grid.adjustedContentInset
    XCTAssertEqual(originalViewport.minY, 0, accuracy: 1, "The native collection owns the full viewport")
    XCTAssertEqual(originalViewport.height, window.bounds.height, accuracy: 1)
    XCTAssertGreaterThan(originalInsets.top, 0, "Native insets still reserve the source navigation bar")
    XCTAssertGreaterThan(originalInsets.bottom, window.safeAreaInsets.bottom)
    // Keep deterministic fixture positioning separate from the entry footage.
    try await Task.sleep(for: .milliseconds(250))
    if let calendar { calendar.collectionView(grid, didSelectItemAt: path) }
    else { recorded?.collectionView(grid, didSelectItemAt: path) }
    func presentedNavigation() -> UINavigationController? {
      var owner: UIViewController? = source
      while let current = owner {
        if let presented = current.presentedViewController as? UINavigationController { return presented }
        owner = current.parent
      }
      return nil
    }
    try await wait { presentedNavigation()?.topViewController is NativeMediaViewer }
    let viewerNavigation = try XCTUnwrap(presentedNavigation())
    let viewer = try XCTUnwrap(viewerNavigation.topViewController as? NativeMediaViewer)
    defer { viewer.releasePreviewSource() }
    XCTAssertFalse(viewerNavigation === navigation)
    XCTAssertTrue(navigation.topViewController === source, "The source stack retains its native chrome owner")
    try await wait { !viewer.openingTransition && viewerNavigation.transitionCoordinator == nil }
    XCTAssertFalse(tabs.isTabBarHidden, "Source tabs remain in their source presentation plane")
    viewer.setChrome(!immersive, animated: false)
    @discardableResult func capture(_ phase: String) -> UIImage {
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
      let attachment = XCTAttachment(image: image); attachment.name = "hosted-\(album ? "album" : "history")-\(immersive ? "immersive" : "normal")-\(phase)"
      attachment.lifetime = .keepAlways; add(attachment)
      return image
    }
    func assertPosition(_ phase: String) {
      let frame = cell.convert(cell.bounds, to: window)
      XCTAssertEqual(frame.minY, original.minY, accuracy: 1, "\(phase): source cell retains its screen-space anchor")
      XCTAssertEqual(frame.minX, original.minX, accuracy: 1, "\(phase): source cell retains its horizontal anchor")
      XCTAssertEqual(grid.contentOffset.y, offset.y, accuracy: 1, "\(phase): source scroll remains unchanged")
    }
    capture("open")
    let viewerParent = viewer.view.superview, viewerFrame = viewer.view.frame
    let mediaFrame = viewer.mediaSurface().map { $0.convert($0.bounds, to: window) }
    let footerFrame = viewer.footer.frame
    for commit in [false, true] {
      var heldPixels: UIImage?
      let probe = ViewerSourceGeometryProbe(cell: cell, grid: grid, window: window)
      probe.start()
      defer { probe.stop() }
      let pan = ViewerPanFixture(); pan.phase = .began; pan.speed = CGPoint(x: 0, y: 200); viewer.vertical(pan)
      try await wait { viewerNavigation.transitionCoordinator != nil && viewer.closing && viewer.mediaSurface()?.alpha == 0 }
      XCTAssertEqual(viewer.footer.frame, footerFrame, "Changing the presentation plane cannot resize viewer chrome")
      XCTAssertEqual(viewer.mediaSurface().map { $0.convert($0.bounds, to: window) }, mediaFrame,
        "Native safe-area changes cannot reframe the live media during source exposure")
      XCTAssertTrue(viewerNavigation.childForStatusBarHidden === viewer)
      XCTAssertEqual(viewerNavigation.childForStatusBarHidden?.prefersStatusBarHidden, immersive)
      pan.phase = .changed; pan.delta = CGPoint(x: 12, y: 132); viewer.vertical(pan)
      XCTAssertEqual(viewer.backdrop.alpha, 0.45, accuracy: 0.001)
      try await Task.sleep(for: .milliseconds(250))
      XCTAssertEqual(scene.statusBarManager?.isStatusBarHidden, immersive,
        "The real system status bar follows the departing viewer through the held return")
      assertPosition("held"); capture(commit ? "held-commit" : "held-cancel")
      XCTAssertNotNil(viewerNavigation.presentingViewController)
      XCTAssertTrue(navigation.topViewController === source)
      XCTAssertTrue(viewer.view.superview === viewerParent, "Native presentation retains the viewer's hierarchy during the gesture")
      let hit = window.hitTest(CGPoint(x: window.bounds.midX, y: window.bounds.height - 50), with: nil)
      XCTAssertTrue(hit == nil || hit === viewer.view.superview || hit === viewer.view || hit?.isDescendant(of: viewer.view) == true,
        "Revealed source controls cannot take input from the ongoing viewer gesture: \(String(describing: hit))")
      if commit {
        pan.delta = CGPoint(x: 12, y: 260); viewer.vertical(pan)
        try await Task.sleep(for: .milliseconds(250)); heldPixels = capture("full-drag")
      }
      pan.delta = CGPoint(x: 8, y: commit ? 260 : 24); pan.speed = CGPoint(x: 0, y: commit ? 350 : -250)
      pan.phase = .ended; viewer.vertical(pan)
      try await wait { commit ? viewerNavigation.presentingViewController == nil : viewerNavigation.transitionCoordinator == nil && !viewer.closing }
      try await Task.sleep(for: .milliseconds(150))
      probe.stop()
      let samples = probe.samples
      print("SOURCE_GEOMETRY", album ? "album" : "history", count, immersive ? "immersive" : "normal", edge,
        commit ? "commit" : "cancel", "frames", samples.count, "changes", probe.changes)
      XCTAssertGreaterThan(samples.count, 4)
      XCTAssertTrue(samples.allSatisfy { abs($0.y - original.minY) <= 1 }, "Every displayed source frame retains its anchor: \(probe.changes)")
      XCTAssertTrue(samples.allSatisfy { abs($0.gridY - originalViewport.minY) <= 1 && abs($0.height - originalViewport.height) <= 1 },
        "The native viewport stays fixed: \(probe.changes)")
      XCTAssertTrue(samples.allSatisfy { abs($0.offset - offset.y) <= 1 && abs($0.top - originalInsets.top) <= 1 && abs($0.bottom - originalInsets.bottom) <= 1 },
        "Bars cannot rewrite source reservations during a return: \(probe.changes)")
      let finalPixels = capture(commit ? "landed" : "cancelled")
      if verifyPixels, let heldPixels {
        // At full reveal the source is already the final composition. The
        // flying photo stays away from these native chrome and side regions.
        let width = window.bounds.width, height = window.bounds.height
        let regions = [CGRect(x: 0, y: window.safeAreaInsets.top, width: width, height: 44),
          CGRect(x: 0, y: height - originalInsets.bottom, width: 12, height: originalInsets.bottom),
          CGRect(x: width - 12, y: height - originalInsets.bottom, width: 12, height: originalInsets.bottom)]
        for (index, region) in regions.enumerated() {
          let difference = meanPixelDifference(heldPixels, finalPixels, in: region)
          print("SOURCE_PIXELS", album ? "album" : "history", immersive ? "immersive" : "normal", index, difference)
          XCTAssertLessThan(difference, 0.025, "Source chrome and content must already match the live handoff in region \(index)")
        }
      }
      if commit { assertPosition("landed") }
      else {
        XCTAssertTrue(viewerNavigation.topViewController === viewer)
        XCTAssertTrue(viewer.view.superview === viewerParent)
        XCTAssertEqual(viewer.view.frame, viewerFrame)
        XCTAssertTrue(viewerNavigation.childForStatusBarHidden === viewer)
        XCTAssertEqual(viewer.footer.alpha, immersive ? 0 : 1); XCTAssertFalse(viewerNavigation.isNavigationBarHidden)
      }
    }
    XCTAssertTrue(navigation.topViewController === source)
    XCTAssertNil(navigation.presentedViewController)
    XCTAssertTrue(navigation.childForStatusBarHidden === source)
    XCTAssertFalse(cell.contentView.isHidden)
    XCTAssertFalse(tabs.isTabBarHidden)
    // The transition releases ownership after handoff; subsequent native bar
    // reservations must still reach the source's live layout.
    let previousAdditional = source.additionalSafeAreaInsets
    source.additionalSafeAreaInsets.bottom += 20
    source.view.setNeedsLayout(); source.view.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(grid.adjustedContentInset.bottom, originalInsets.bottom + 20, accuracy: 1)
    source.additionalSafeAreaInsets = previousAdditional
    source.view.setNeedsLayout(); source.view.layoutIfNeeded()
  }

  private func meanPixelDifference(_ before: UIImage, _ after: UIImage, in region: CGRect) -> Double {
    let width = Int(region.width), height = Int(region.height)
    func pixels(_ image: UIImage) -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: width * height * 4)
      let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      let crop = image.cgImage!.cropping(to: region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)))!
      context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
      return bytes
    }
    let a = pixels(before), b = pixels(after)
    return zip(a, b).enumerated().filter { $0.offset % 4 != 3 }
      .reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(width * height * 3 * 255)
  }

  func testImmersiveNativeReturnKeepsFlightVisibleThroughReversalAndReleasesSource() async throws {
    try await exerciseReturnChrome(immersive: true, sharedNavigation: true)
  }

  func testNativeReturnChromeFollowsHeldDragAndRestoresSource() async throws {
    try await exerciseReturnChrome(immersive: false, sharedNavigation: true)
  }

  func testModalReturnChromeFollowsHeldDragAndPreservesImmersion() async throws {
    for immersive in [false, true] {
      try await exerciseReturnChrome(immersive: immersive, sharedNavigation: false)
    }
  }

  private func exerciseReturnChrome(immersive: Bool, sharedNavigation: Bool) async throws {
    let oldAnimations = UIView.areAnimationsEnabled
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    let picture = bitmap(800, 600), asset = ViewerOpeningAsset(image: bitmap(800, 600))
    let source = CalendarGridController()
    source.columns = 3
    source.assets = (0..<90).map {
      CalendarGridAsset(id: $0 == 50 ? asset.localIdentifier : "immersive-source-\($0)", date: nil, aspect: 1)
    }
    source.requestImage = { _, _, done in done(picture, false); return {} }
    source.prefetchImage = { _, _, _ in {} }
    let sourceNavigation = CalendarNavigationController(rootViewController: sharedNavigation ? source : UIViewController())
    // Exercise the Library's actual navigation/tab composition and the plain
    // recent-media presenter through the same independent viewer presentation.
    let tabs = UITabBarController()
    sourceNavigation.tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "photo.on.rectangle"), tag: 0)
    tabs.viewControllers = [sourceNavigation, UIViewController(), UIViewController()]
    window.rootViewController = MediaStatusBarRootController(content: sharedNavigation ? tabs : source)
    window.makeKeyAndVisible()
    try await wait { source.active && source.transitionCoordinator == nil }
    UIView.setAnimationsEnabled(true)
    XCTAssertTrue(UIView.areAnimationsEnabled)
    source.locateAsset(50)
    let library = PhotoLibraryModel()
    library.previewOwnsVacancy = true
    library.previewFrame = { _ in source.grid.convert(source.layout.frame(50), to: nil) }
    library.previewVisibility = { source.setPreviewHidden($0) }
    let item = IOSPreviewItem(asset: asset, frame: source.grid.convert(source.layout.frame(50), to: nil), poster: picture)
    let session = MediaPreviewSession(asset: asset, library: library, poster: picture, reviewAssets: [asset])
    let viewer = NativeMediaViewer(item: item, session: session, close: {})
    defer {
      viewer.releasePreviewSource(); window.isHidden = true; window.rootViewController = nil
      previousWindow?.makeKeyAndVisible(); UIView.setAnimationsEnabled(oldAnimations)
    }
    presentMediaViewer(viewer, from: source, poster: picture)
    try await wait { !viewer.openingTransition && viewer.navigationController?.transitionCoordinator == nil }
    let navigation = try XCTUnwrap(viewer.navigationController)
    XCTAssertFalse(navigation === sourceNavigation)
    viewer.setChrome(!immersive, animated: false)
    XCTAssertEqual(viewer.view.alpha, 1)
    let tile = try XCTUnwrap(source.grid.cellForItem(at: IndexPath(item: 50, section: 0)) as? CalendarGridCell)
    XCTAssertTrue(tile.contentView.isHidden)
    let sourceFrame = tile.convert(tile.bounds, to: window), sourceOffset = source.grid.contentOffset
    let sourceInsets = source.grid.adjustedContentInset
    // A release can arrive before UIKit calls startInteractiveTransition.
    let immediate = ViewerPanFixture()
    immediate.phase = .began; immediate.speed = CGPoint(x: 0, y: 200); viewer.vertical(immediate)
    immediate.phase = .cancelled; viewer.vertical(immediate)
    try await wait { navigation.topViewController === viewer && navigation.transitionCoordinator == nil && !viewer.closing }
    XCTAssertFalse(viewer.view.isHidden); XCTAssertEqual(viewer.view.alpha, 1)
    XCTAssertTrue(viewer.returnChromeViews.isEmpty)
    XCTAssertTrue(navigation.topViewController === viewer)
    XCTAssertEqual(navigation.isToolbarHidden, immersive)
    let zoom = viewer.pages[1].scroll
    zoom.setZoomScale(2, animated: false)
    try await wait { session.zoomed && !viewer.pager.isScrollEnabled }
    let ownershipPan = ViewerPanFixture(); ownershipPan.speed = CGPoint(x: 0, y: 200)
    XCTAssertFalse(viewer.gestureRecognizerShouldBegin(ownershipPan), "Zoomed media retains vertical input")
    zoom.setZoomScale(1, animated: false)
    try await wait { !session.zoomed && viewer.pager.isScrollEnabled }
    XCTAssertTrue(viewer.gestureRecognizerShouldBegin(ownershipPan), "Fitted media regains downward return input")
    func assertReturnChrome(_ visibility: CGFloat) {
      XCTAssertTrue(navigation.isNavigationBarHidden, "Live viewer groups must stay below their fading pixels")
      XCTAssertTrue(navigation.isToolbarHidden)
      XCTAssertEqual(viewer.returnChromeViews.count, immersive ? 0 : 2)
      for strip in viewer.returnChromeViews {
        XCTAssertTrue(strip.superview === viewer.view)
        XCTAssertEqual(strip.alpha, visibility, accuracy: 0.001)
        XCTAssertGreaterThan(strip.bounds.height, 0)
        XCTAssertLessThan(strip.bounds.height, viewer.view.bounds.height / 2)
      }
    }
    for commit in [false, true] {
      let pan = ViewerPanFixture()
      let originalSubviews = Set(viewer.view.subviews.map(ObjectIdentifier.init))
      pan.phase = .began; pan.speed = CGPoint(x: 0, y: 200); viewer.vertical(pan)
      try await wait {
        navigation.transitionCoordinator != nil && viewer.closing
          && viewer.view.subviews.contains { !originalSubviews.contains(ObjectIdentifier($0)) }
      }
      viewer.view.setNeedsLayout(); viewer.view.layoutIfNeeded(); viewer.layoutMedia()
      XCTAssertEqual(viewer.view.alpha, 1, "Immersive chrome cannot hide the root containing the flying photo during a native pop")
      let flight = try XCTUnwrap(viewer.view.subviews.first { !originalSubviews.contains(ObjectIdentifier($0)) })
      pan.phase = .changed; pan.delta = CGPoint(x: 25, y: 160); viewer.vertical(pan)
      XCTAssertEqual(tile.convert(tile.bounds, to: window), sourceFrame)
      XCTAssertEqual(source.grid.contentOffset, sourceOffset)
      XCTAssertEqual(source.grid.adjustedContentInset, sourceInsets)
      if sharedNavigation { XCTAssertFalse(tabs.isTabBarHidden) }
      XCTAssertEqual(viewer.view.alpha, 1)
      XCTAssertFalse(flight.transform.isIdentity, "The native return must retain a photo that follows the held drag")
      XCTAssertEqual(viewer.backdrop.alpha, 1 - 160.0 / 240, accuracy: 0.001)
      assertReturnChrome(1 - 160.0 / 240)
      XCTAssertTrue(tile.contentView.isHidden)
      if !commit {
        pan.delta = CGPoint(x: 8, y: 35); pan.speed = CGPoint(x: 0, y: -250); viewer.vertical(pan)
        assertReturnChrome(1 - 35.0 / 240)
      } else { pan.speed = CGPoint(x: 0, y: 350) }
      pan.phase = .ended; viewer.vertical(pan)
      if immersive {
        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertTrue(viewer.returnChromeViews.isEmpty)
      }
      try await wait { navigation.transitionCoordinator == nil }
      if !commit {
        XCTAssertTrue(navigation.topViewController === viewer)
        XCTAssertFalse(viewer.closing); XCTAssertEqual(viewer.chrome, !immersive)
        XCTAssertEqual(viewer.view.alpha, 1); XCTAssertEqual(viewer.mediaSurface()?.alpha, 1)
        XCTAssertEqual(viewer.backdrop.alpha, 1); XCTAssertEqual(viewer.footer.alpha, immersive ? 0 : 1)
        XCTAssertEqual(navigation.navigationBar.alpha, immersive ? 0 : 1)
        XCTAssertEqual(navigation.toolbar.alpha, immersive ? 0 : 1)
        XCTAssertEqual(navigation.isToolbarHidden, immersive, "Cancelling preserves the viewer's actual immersive chrome state")
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertTrue(viewer.returnChromeViews.isEmpty)
        XCTAssertEqual(viewer.toolbarItems?.count, 3)
        XCTAssertTrue(viewer.toolbarItems?.allSatisfy { $0.isHidden == immersive } == true)
        XCTAssertTrue(tile.contentView.isHidden, "Cancellation retains source ownership with the immersive viewer")
      }
    }
    XCTAssertNil(navigation.presentingViewController)
    if sharedNavigation { XCTAssertTrue(sourceNavigation.topViewController === source) }
    else { XCTAssertNil(source.presentedViewController) }
    XCTAssertFalse(tile.contentView.isHidden, "The completed return must reveal the real source photo in the same handoff")
    XCTAssertEqual(tile.convert(tile.bounds, to: window), sourceFrame)
    XCTAssertEqual(source.grid.contentOffset, sourceOffset)
    XCTAssertEqual(source.view.alpha, 1)
    if sharedNavigation {
      XCTAssertEqual(sourceNavigation.navigationBar.alpha, 1)
      XCTAssertTrue(sourceNavigation.navigationBar.isUserInteractionEnabled)
    }
    XCTAssertNotNil(tile.image.image)
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
    XCTAssertEqual(viewer.header?.alpha, 1)
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

  private func cacheLibrary() -> PhotoLibraryModel {
    let store = DetailPosterStore(disk: nil, authorization: { .authorized }, assetRevision: { PhotoLibraryModel.revision($0) })
    return PhotoLibraryModel(thumbnails: ThumbnailPipeline(detailStore: store))
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
  var options: [PHImageRequestOptions] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    results.append(resultHandler); if let options { self.options.append(options) }; return PHImageRequestID(results.count)
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
  let revision: TimeInterval, identifier: String, live: Bool
  init(revision: TimeInterval = 0, identifier: String = "quality", live: Bool = false) { self.revision = revision; self.identifier = identifier; self.live = live; super.init() }
  override var localIdentifier: String { identifier }
  override var modificationDate: Date? { Date(timeIntervalSince1970: revision) }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { live ? .photoLive : [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
}

private final class ViewerOpeningAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let image: UIImage
  init(image: UIImage) { self.image = image; super.init() }
  override var localIdentifier: String { "opening-cropped-seed" }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
  var previewImage: UIImage? { image }
  var previewFilename: String { "opening.jpg" }
  var previewMetadata: [(String, String)] { [] }
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
    let header = viewer.header?.layer.presentation()?.opacity ?? Float(viewer.header?.alpha ?? 0)
    let footer = viewer.footer.layer.presentation()?.opacity ?? Float(viewer.footer.alpha)
    let background = viewer.backdrop.layer.presentation()?.opacity ?? Float(viewer.backdrop.alpha)
    let frame = viewer.mediaSurface()?.layer.presentation()?.frame ?? .zero
    print(phase + "_SAMPLE", ProcessInfo.processInfo.systemUptime, header, footer, background,
      viewer.flying, frame.origin.x, frame.origin.y, frame.width, frame.height)
  }
}

private final class ViewerLiveRequests: PHImageManager, @unchecked Sendable {
  var images: [(UIImage?, [AnyHashable: Any]?) -> Void] = []
  var live: [(PHLivePhoto?, [AnyHashable: Any]?) -> Void] = []
  var options: [PHLivePhotoRequestOptions] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    images.append(resultHandler); return PHImageRequestID(images.count)
  }
  override func requestLivePhoto(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHLivePhotoRequestOptions?, resultHandler: @escaping (PHLivePhoto?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    self.options.append(options!); live.append(resultHandler); return PHImageRequestID(100 + live.count)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
}

/// Synthetic source observations exercise the real native cell and viewer pipelines.
private final class HistoryGridSampleAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let job: BackupJob
  init(_ job: BackupJob) { self.job = job; super.init() }
  override var localIdentifier: String { job.asset.source_id }
  override var creationDate: Date? { Date(timeIntervalSince1970: Double(job.id)) }
  override var modificationDate: Date? { creationDate }
  override var mediaType: PHAssetMediaType { job.asset.kind == "video" ? .video : .image }
  override var mediaSubtypes: PHAssetMediaSubtype { job.asset.kind == "motion" ? .photoLive : [] }
  override var duration: TimeInterval { mediaType == .video ? 12.75 : 0 }
  override var pixelWidth: Int { 180 }
  override var pixelHeight: Int { 180 }
  override var burstIdentifier: String? { nil }
  override var location: CLLocation? { nil }
  var previewFilename: String { "Synthetic.heic" }
  var previewMetadata: [(String, String)] { [] }
  var previewImage: UIImage? {
    UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180)).image { context in
      DuckRole.accentUIColor.setFill(); context.fill(CGRect(x: 0, y: 0, width: 180, height: 180))
      DuckRole.groupedSurfaceUIColor.setFill(); context.fill(CGRect(x: 20, y: 30, width: 60, height: 80))
    }
  }
}

/// Samples native geometry at display cadence without driving product layout.
@MainActor private final class ViewerSourceGeometryProbe: NSObject {
  struct Sample: CustomStringConvertible {
    let y: CGFloat, gridY: CGFloat, height: CGFloat, offset: CGFloat, top: CGFloat, bottom: CGFloat
    var description: String { "(y:\(y),grid:\(gridY),height:\(height),offset:\(offset),inset:\(top)/\(bottom))" }
  }
  let cell: UIView, grid: UICollectionView, window: UIWindow
  var samples: [Sample] = []
  var changes: [String] {
    samples.reduce(into: []) { result, sample in
      if result.last != sample.description { result.append(sample.description) }
    }
  }
  private var display: CADisplayLink?
  init(cell: UIView, grid: UICollectionView, window: UIWindow) { self.cell = cell; self.grid = grid; self.window = window }
  func start() {
    display = CADisplayLink(target: self, selector: #selector(sample))
    display?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    display?.add(to: .main, forMode: .common)
  }
  func stop() { display?.invalidate(); display = nil }
  @objc private func sample() {
    guard grid.window === window else { return }
    samples.append(Sample(y: cell.convert(cell.bounds, to: window).minY,
      gridY: grid.convert(grid.bounds, to: window).minY, height: grid.bounds.height,
      offset: grid.contentOffset.y, top: grid.adjustedContentInset.top, bottom: grid.adjustedContentInset.bottom))
  }
}

import AppKit
import Photos
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class MacGridTimingTests: XCTestCase {
  func testWindowWidthDoesNotChangeTheRequestedGridDensity() {
    let size = MacGridSize()
    let original = size.columns
    defer { size.columns = original }
    size.columns = 4
    for width in [CGFloat(1000), 800, 600, 400, 600, 800, 1000] {
      XCTAssertEqual(size.resolve(4, width: width, stops: [3, 4, 6, 9], active: true), 4)
      XCTAssertEqual(size.columns, 4)
    }
    XCTAssertEqual(size.resolve(6, width: 400, stops: [3, 4, 6, 9], active: true), 6,
      "An explicit density request remains independent of the viewport width")
  }

  func testResizeReflowsWithoutStartingOrRestartingZoom() async {
    let source = ResizeGridSource()
    let size = MacGridSize()
    let original = size.columns
    defer { size.columns = original }
    size.columns = 4
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4, sharedSize: size)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 248)
    layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection
    mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection)
    coordinator.viewportResized(layout: layout)
    coordinator.syncDensity(columns: 4, layout: layout)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    coordinator.pinnedToNewest = false
    source.scroll.anchor = "item-20"; source.scroll.inset = 12
    scroll.contentView.scroll(to: CGPoint(x: 0, y: layout.frame(at: 20).minY + 12))
    scroll.reflectScrolledClipView(scroll.contentView)

    for width in [CGFloat(800), 600, 400, 600, 800] {
      scroll.setFrameSize(NSSize(width: width, height: 600))
      for _ in 0..<3 {
        coordinator.contentResized()
        let requested = size.resolve(4, width: scroll.contentSize.width, stops: source.zoomStops, active: true)
        coordinator.syncDensity(columns: requested, layout: layout)
        XCTAssertNil(coordinator.zoomStage)
        XCTAssertNil(coordinator.animationTarget)
        XCTAssertEqual(layout.requestedColumns, 4)
        XCTAssertEqual(source.selection, ["item-20", "item-21"])
        XCTAssertEqual(scroll.contentView.bounds.minY - layout.frame(at: 20).minY, 12, accuracy: 2)
      }
    }

    // An explicit zoom starts a stage. Resizing interrupts the stale stage and
    // adopts the requested density, without another animation on later events.
    coordinator.parent.columns = 6
    coordinator.syncDensity(columns: 6, layout: layout)
    XCTAssertNotNil(coordinator.zoomStage)
    scroll.setFrameSize(NSSize(width: 500, height: 600))
    for _ in 0..<3 {
      coordinator.contentResized()
      coordinator.syncDensity(columns: 6, layout: layout)
      XCTAssertNil(coordinator.zoomStage)
      XCTAssertNil(coordinator.animationTarget)
      XCTAssertEqual(layout.requestedColumns, 6)
      XCTAssertEqual(source.selection, ["item-20", "item-21"])
    }
    XCTAssertEqual(size.columns, 4, "Viewport reflow must not write the shared preference")
  }

  func testPreparedReleaseHoldsItsOriginBeforeStartWithoutRetainingItsEnd() {
    let layer = CALayer()
    layer.bounds.size.width = 146
    let move = CABasicAnimation(keyPath: "bounds.size.width")
    move.fromValue = 97; move.toValue = 146; move.duration = 0.5
    let batch = MacGridAnimationBatch()
    MacGridAnimationBatch.schedule(move, on: layer, key: "zoom.bounds.size.width", batch: batch)
    XCTAssertNil(layer.animation(forKey: "zoom.bounds.size.width"), "Preparation must not install a partial batch")
    batch.install()
    let installed = layer.animation(forKey: "zoom.bounds.size.width") as! CABasicAnimation
    XCTAssertEqual(layer.bounds.width, 146, "The model holds the destination")
    XCTAssertEqual((installed.fromValue as? NSNumber)?.doubleValue, 97)
    XCTAssertEqual((installed.toValue as? NSNumber)?.doubleValue, 146)
    XCTAssertEqual(installed.beginTime, 0, "Core Animation chooses the actual start")
    XCTAssertEqual(installed.fillMode, .backwards,
      "The pending interval must display fromValue rather than the destination model")
    XCTAssertTrue(installed.isRemovedOnCompletion, "Completion must expose the settled model normally")
  }

  func testPendingReleaseDoesNotAdvanceBeforeTheNativeStartEvent() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 9, pitch: 97, focus: CGPoint(x: 440, y: 344))
    stage.frame = CGRect(x: 0, y: 0, width: 880, height: 688)
    stage.makeTile = { _, _ in NSView() }
    stage.referenceSide = { $0 == 9 ? 95 : 144 }
    stage.ensureFace(9, opacity: 1); stage.ensureFace(6, opacity: 0)
    let model = GridZoom.Settle(start: CACurrentMediaTime() - 0.4, pitch: stage.pitch,
      focus: stage.focus, velocity: 0, targetPitch: 146, targetFocus: CGPoint(x: 440, y: 300))
    stage.settle(with: model) {}
    let clock = stage.layer!.animation(forKey: "zoom.settleClock")!
    XCTAssertEqual(clock.beginTime, 0, "The system chooses the commitment epoch")
    stage.freeze(at: CACurrentMediaTime() + 10)
    XCTAssertEqual(stage.pitch, model.pitch, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.x, model.focus.x, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.y, model.focus.y, accuracy: 0.000001)
    stage.stop()
  }

  func testResolvedNativeStartDefinesTheInterruptionPose() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 9, pitch: 97, focus: CGPoint(x: 440, y: 344))
    stage.frame = CGRect(x: 0, y: 0, width: 880, height: 688)
    stage.makeTile = { _, _ in NSView() }
    stage.referenceSide = { $0 == 9 ? 95 : 144 }
    stage.ensureFace(9, opacity: 1); stage.ensureFace(6, opacity: 0)
    let model = GridZoom.Settle(start: CACurrentMediaTime() - 0.4, pitch: stage.pitch,
      focus: stage.focus, velocity: 0, targetPitch: 146, targetFocus: CGPoint(x: 440, y: 300))
    stage.settle(with: model) {}
    let resolved = CACurrentMediaTime() + 0.25
    stage.releaseAnimationStarted(at: resolved)
    let pose = model.state(at: model.start + 0.12)
    stage.freeze(at: resolved + 0.12)
    XCTAssertEqual(stage.pitch, pose.pitch, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.x, pose.focus.x, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.y, pose.focus.y, accuracy: 0.000001)
    stage.stop()
  }

  func testLateStartAndStopFromAnInterruptedGenerationCannotStartOrCompleteTheNextRelease() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 9, pitch: 97, focus: CGPoint(x: 440, y: 344))
    stage.frame = CGRect(x: 0, y: 0, width: 880, height: 688)
    stage.makeTile = { _, _ in NSView() }
    stage.referenceSide = { $0 == 9 ? 95 : 144 }
    stage.ensureFace(9, opacity: 1); stage.ensureFace(6, opacity: 0)
    let initial = stage.pitch, focus = stage.focus
    stage.settle(with: GridZoom.Settle(start: CACurrentMediaTime(), pitch: initial, focus: focus,
      velocity: 0, targetPitch: 146, targetFocus: focus)) {}
    // Installed animations are immutable. A delegate receives a callback
    // snapshot; copy it before simulating the system's resolved start time.
    let old = stage.layer!.animation(forKey: "zoom.settleClock")!.copy() as! CAAnimation
    let delegate = old.delegate
    stage.freeze(at: CACurrentMediaTime() + 10)
    var completed = false
    stage.settle(with: GridZoom.Settle(start: CACurrentMediaTime(), pitch: initial, focus: focus,
      velocity: 0, targetPitch: 200, targetFocus: focus)) { completed = true }
    old.beginTime = stage.layer!.convertTime(CACurrentMediaTime() - 5, from: nil)
    delegate?.animationDidStart?(old)
    delegate?.animationDidStop?(old, finished: true)
    let delivered = expectation(description: "The queued native callbacks have been delivered")
    // Delegate events enqueue work on the main actor. Check on the following
    // main-queue turn, after both callbacks, without an async XCTest invocation.
    DispatchQueue.main.async {
      XCTAssertFalse(completed)
      stage.freeze(at: CACurrentMediaTime() + 10)
      XCTAssertEqual(stage.pitch, initial, accuracy: 0.000001,
        "A stale event must leave the new generation pending at its origin")
      XCTAssertEqual(stage.focus, focus)
      stage.stop()
      delivered.fulfill()
    }
    wait(for: [delivered], timeout: 1)
  }

  func testPhotoFadeGeometryCaptionsAndFooterShareThePreparedClock() {
    let stage = MacGridZoomStage(count: 90, anchor: 10, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 4, pitch: 200, focus: CGPoint(x: 250, y: 300))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 700)
    let geometry: (Int) -> LibraryTimelineGeometry = {
      MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"], columns: $0, width: 804)
    }
    stage.groupedGeometry = geometry
    stage.referenceSide = { geometry($0).items[0].width }
    stage.makeTile = { _, _ in
      let tile = MacZoomMediaTile(); tile.show(NSImage(size: NSSize(width: 8, height: 8))); return tile
    }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    let footer = NSTextField(labelWithString: "90 photos"); footer.frame.size.height = 20
    stage.attachFooter(footer, columns: [4, 6]) { columns in
      (geometry(columns).items[10].origin, geometry(columns).height + 14, 0)
    }
    stage.show(6, animated: true); stage.hurryBlend(within: GridZoom.releaseFadeDuration)
    stage.settle(with: GridZoom.Settle(start: CACurrentMediaTime() - 0.1, pitch: stage.pitch,
      focus: stage.focus, velocity: 0, targetPitch: 134, targetFocus: stage.focus)) {}
    let clock = stage.layer!.animation(forKey: "zoom.settleClock")!
    XCTAssertEqual(clock.beginTime, 0)
    var seen = Set<ObjectIdentifier>(), keys = Set<String>()
    func inspectLayer(_ layer: CALayer) {
      guard seen.insert(ObjectIdentifier(layer)).inserted else { return }
      for key in layer.animationKeys() ?? [] where key.hasPrefix("zoom.") {
        let animation = layer.animation(forKey: key)!
        XCTAssertEqual(animation.beginTime, 0,
          "Every release participant lets the system choose the transaction epoch")
        XCTAssertEqual(animation.fillMode, .backwards,
          "Every release participant must hold its origin until the system starts it")
        XCTAssertTrue(animation.isRemovedOnCompletion,
          "Release participants must not retain presentation overrides after completion")
        keys.insert(key)
      }
      for child in layer.sublayers ?? [] { inspectLayer(child) }
    }
    func inspectView(_ view: NSView) {
      if let layer = view.layer { inspectLayer(layer) }
      for child in view.subviews { inspectView(child) }
    }
    inspectView(stage)
    for key in ["zoom.settleClock", "zoom.fade", "zoom.caption", "zoom.footer", "zoom.bounds.size.width"] {
      XCTAssertTrue(keys.contains(key), "Missing clock participant: \(key)")
    }
    stage.stop()
  }
}

@MainActor private final class ResizeGridSource: MacGridSource {
  let identifiers = (0..<120).map { "item-\($0)" }
  let contextID = "resize-test"
  let contentRevision = "1"
  var selection: Set<String> = ["item-20", "item-21"]
  let scroll = MacGridScrollState()
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  func date(_ id: String) -> Date? { nil }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    cell.configureUnavailable(id: id, label: id, video: false)
  }
}

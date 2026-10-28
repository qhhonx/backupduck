import AppKit
import Photos
import SwiftUI
import XCTest
@testable import BackupDuck

@MainActor final class MacGridTests: XCTestCase {
  func testFirstDisplayedPixelsReleaseTheHoldWithoutAdvancingAnIdleMagnify() async {
    let stage = MacGridZoomStage(count: 16, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { _, _ in MacZoomMediaTile() }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    stage.show(6, animated: true)
    let incoming = stage.subviews.last!
    XCTAssertNil(incoming.layer?.animation(forKey: "zoom.fade"), "Blank pixels hold the composite")
    for tile in incoming.subviews.compactMap({ $0 as? MacZoomMediaTile }) {
      tile.show(NSImage(size: NSSize(width: 8, height: 8)))
    }
    let fade = incoming.layer?.animation(forKey: "zoom.fade") as? CAKeyframeAnimation
    XCTAssertNotNil(fade, "Displayed pixels schedule the curve through an event")
    XCTAssertEqual(fade?.speed, 0, "A magnify held without events retains its paused blend")
    let opacity = incoming.alphaValue
    try? await Task.sleep(for: .milliseconds(180))
    XCTAssertEqual(incoming.alphaValue, opacity)
    stage.stop()
  }

  func testGroupedCaptionUsesOnlyNativeSizePositionKeyframes() {
    let stage = MacGridZoomStage(count: 90, anchor: 30, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 4, pitch: 200, focus: CGPoint(x: 250, y: 300))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    let geometry: (Int) -> LibraryTimelineGeometry = { MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"], columns: $0, width: 804) }
    stage.groupedGeometry = geometry
    stage.referenceSide = { geometry($0).items[0].width }
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    let now = CACurrentMediaTime()
    stage.show(6, animated: true, at: now); stage.hurryBlend(within: 0.15, at: now)
    stage.settle(with: GridZoom.Settle(start: now, pitch: 200, focus: stage.focus, velocity: 0,
      targetPitch: 134, targetFocus: CGPoint(x: 250, y: 300))) {}
    let captions = stage.subviews.compactMap { $0 as? MacGridSectionHeader }
    XCTAssertFalse(captions.isEmpty)
    for caption in captions {
      let move = caption.layer?.animation(forKey: "zoom.caption") as? CAKeyframeAnimation
      XCTAssertEqual(move?.keyPath, "position.y")
      XCTAssertEqual(move?.values?.count, 73)
      XCTAssertTrue(CATransform3DIsIdentity(caption.layer!.transform))
      XCTAssertEqual(caption.frame.height, MacGridSectionHeader.dateHeight)
    }
    stage.stop()
  }

  func testSettleUsesSystemSpringsAndFreezesAtTheSharedAnalyticPose() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.3, y: 0.7),
      columns: 4, pitch: 200, focus: CGPoint(x: 250, y: 320))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 1)
    let now = CACurrentMediaTime()
    let model = GridZoom.Settle(start: now, pitch: stage.pitch, focus: stage.focus, velocity: -10000,
      targetPitch: 134, targetFocus: CGPoint(x: 250, y: 280))
    var completed = false
    stage.settle(with: model) { completed = true }
    XCTAssertEqual(stage.pitch, model.targetPitch, "The model layout is committed once at the destination")
    let clock = stage.layer?.animation(forKey: "zoom.settleClock") as? CABasicAnimation
    XCTAssertEqual(clock?.keyPath, "opacity")
    XCTAssertEqual(clock?.fromValue as? Int, 1)
    XCTAssertEqual(clock?.toValue as? Int, 1)
    XCTAssertNotNil(clock?.delegate, "Completion must not wait on virtualized off-screen tiles")
    let tiles = stage.subviews.flatMap(\.subviews)
    let springs = tiles.compactMap { $0.layer?.animation(forKey: "zoom.bounds.size.width") as? CASpringAnimation }
    XCTAssertFalse(springs.isEmpty)
    for spring in springs {
      XCTAssertEqual(spring.stiffness, GridZoom.settleOmega * GridZoom.settleOmega)
      XCTAssertEqual(spring.damping, 2 * GridZoom.settleOmega)
      XCTAssertEqual(spring.mass, 1)
    }
    let interrupt = now + 0.12, pose = model.state(at: interrupt)
    stage.freeze(at: interrupt)
    XCTAssertEqual(stage.pitch, pose.pitch, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.x, pose.focus.x, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.y, pose.focus.y, accuracy: 0.000001)
    XCTAssertFalse(completed)
    XCTAssertNil(stage.layer?.animation(forKey: "zoom.settleClock"))
    XCTAssertTrue(stage.subviews.flatMap(\.subviews).allSatisfy { $0.layer?.animation(forKey: "zoom.bounds.size.width") == nil })
    stage.stop()
  }

  func testSourceTileSpringsKeepNativeBadgeBoundsAndTwoPointGaps() {
    let source = GridTestSource()
    let stage = MacGridZoomStage(count: 16, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { index, _ in
      let tile = MacSourceZoomTile()
      source.configure(tile.cell, id: "item-\(index)", pixels: 400, originalAspect: false)
      tile.cell.setState("needs_you")
      return tile
    }
    stage.ensureFace(4, opacity: 1)
    let now = CACurrentMediaTime()
    stage.settle(with: GridZoom.Settle(start: now, pitch: 200, focus: .zero, velocity: 0,
      targetPitch: 268, targetFocus: .zero)) {}
    let tiles = stage.subviews.flatMap(\.subviews).compactMap { $0 as? MacSourceZoomTile }.sorted { $0.frame.minX < $1.frame.minX }
    let row = tiles.filter { $0.frame.minY == 0 }
    XCTAssertGreaterThanOrEqual(row.count, 2)
    for pair in zip(row, row.dropFirst()) {
      XCTAssertEqual(pair.1.frame.minX - pair.0.frame.maxX, 2, accuracy: 0.000001)
      let a = pair.0.layer!, b = pair.1.layer!
      let ax = a.animation(forKey: "zoom.position.x") as? CASpringAnimation
      let bx = b.animation(forKey: "zoom.position.x") as? CASpringAnimation
      let width = a.animation(forKey: "zoom.bounds.size.width") as! CASpringAnimation
      let x0 = (ax?.fromValue as? CGFloat) ?? a.position.x
      let x1 = (bx?.fromValue as? CGFloat) ?? b.position.x
      XCTAssertEqual(x1 - x0 - (width.fromValue as! CGFloat), 2, accuracy: 0.000001)
    }
    var checkedMarks = 0
    func verifyMarks(_ layer: CALayer) {
      if layer is MacBadgeLayer {
        checkedMarks += 1
        XCTAssertNil(layer.animation(forKey: "zoom.bounds.size.width"), "Native-size marks must not scale")
        XCTAssertNil(layer.animation(forKey: "zoom.transform.scale.x"))
      }
      for child in layer.sublayers ?? [] { verifyMarks(child) }
    }
    for tile in tiles { verifyMarks(tile.cell.view.layer!) }
    XCTAssertGreaterThan(checkedMarks, 0, "Check the source marks before AppKit attaches their backing view")
    stage.stop()
  }

  func testSourcePhotoSpringIncludesBackingLayersBeforeTheirAppKitCommit() {
    let tile = MacSourceZoomTile(); tile.wantsLayer = true
    tile.cell.configureUnavailable(id: "photo", label: "photo", video: false)
    tile.frame = CGRect(x: 20, y: 40, width: 198, height: 198)
    tile.layoutSubtreeIfNeeded(); tile.cell.viewDidLayout()
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 300, focus: .zero, velocity: 0,
      targetPitch: 200, targetFocus: .zero)
    MacGridSpring.animate(tile, from: CGRect(x: 20, y: 40, width: 298, height: 298),
      derivative: CGRect(x: 0, y: 0, width: 1, height: 1), model: model, duration: 0.6)
    let photo = tile.cell.view.layer!.sublayers!.first!
    let width = photo.animation(forKey: "zoom.bounds.size.width") as? CASpringAnimation
    XCTAssertEqual((width?.fromValue as? NSNumber)?.doubleValue, 298)
    XCTAssertEqual((width?.toValue as? NSNumber)?.doubleValue, 198)
    XCTAssertEqual(photo.bounds.width, 198)
    XCTAssertNil(photo.animation(forKey: "zoom.transform.scale.x"))
    tile.cancel()
  }

  func testReleaseCompletesOnlyAfterFadeAndAdoptsExactTargetPose() {
    let stage = MacGridZoomStage(count: 16, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { _, _ in
      let tile = MacZoomMediaTile(); tile.show(NSImage(size: NSSize(width: 8, height: 8))); return tile
    }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    let now = CACurrentMediaTime()
    stage.show(6, animated: true, at: now); stage.hurryBlend(within: 0.15, at: now)
    let model = GridZoom.Settle(start: now, pitch: 200, focus: .zero, velocity: 0,
      targetPitch: 200, targetFocus: .zero)
    var completed = false
    stage.settle(with: model) { completed = true }
    XCTAssertTrue(stage.subviews.contains { $0.layer?.animation(forKey: "zoom.fade") is CAKeyframeAnimation })
    stage.advance(to: now + 0.05); XCTAssertFalse(completed)
    stage.advance(to: now + 1); XCTAssertTrue(completed)
    XCTAssertFalse(stage.isBlending); XCTAssertEqual(stage.pitch, 200); XCTAssertEqual(stage.focus, .zero)
    XCTAssertEqual(stage.subviews.count, 1, "Prune outgoing faces only after the fade")
    stage.stop()
  }

  func testDensePhotosShareOneSpringAndKeepQuantizedTargetsAndNativePeriodText() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 2000
    canvas.factAt = { .init(key: "dense-\($0)", date: Date(timeIntervalSince1970: 1792495800 - Double($0) * 3600)) }
    let now = CACurrentMediaTime()
    let model = GridZoom.Settle(start: now, pitch: 44.5, focus: CGPoint(x: 472, y: 200), velocity: -300,
      targetPitch: 22, targetFocus: CGPoint(x: 472, y: 100))
    let columns = 42, leading = 5, anchor = 52
    func origin(_ pitch: CGFloat, _ focus: CGPoint) -> CGPoint {
      CGPoint(x: focus.x - CGFloat((anchor + leading) % columns) * pitch,
        y: focus.y - CGFloat((anchor + leading) / columns) * pitch)
    }
    canvas.render(columns: columns, origin: origin(model.targetPitch, model.targetFocus),
      pitch: model.targetPitch, visible: canvas.bounds, leading: leading)
    let photos = canvas.layer!.sublayers!.first!
    let rectangles = photos.sublayers!.map(\.frame)
    XCTAssertGreaterThan(rectangles.count, 500)
    canvas.animateZoom(model, duration: 0.6, origin: origin)
    XCTAssertEqual(Set(photos.animationKeys() ?? []), ["zoom.position.x", "zoom.position.y", "zoom.transform.scale.x", "zoom.transform.scale.y"])
    XCTAssertTrue(photos.sublayers!.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    XCTAssertEqual(photos.sublayers!.map(\.frame), rectangles, "The quantized target layout must not be changed by the transform")
    for label in canvas.layer!.sublayers!.dropFirst() {
      XCTAssertTrue(CATransform3DIsIdentity(label.transform))
      XCTAssertNil(label.animation(forKey: "zoom.transform.scale.x"))
      XCTAssertTrue(label.animation(forKey: "zoom.pill") is CAKeyframeAnimation)
    }
    canvas.removeZoomAnimations()
    XCTAssertTrue((photos.animationKeys() ?? []).isEmpty)
    XCTAssertTrue(CATransform3DIsIdentity(photos.transform))
    XCTAssertEqual(photos.position, .zero)
    XCTAssertEqual(photos.sublayers!.map(\.frame), rectangles)
    canvas.reset()
  }

  func testDensePeriodCaptionUsesItsRenderedPinDuringSettle() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 90
    canvas.factAt = { .init(key: "pin-\($0)", date: Date(timeIntervalSince1970: 1792495800)) }
    canvas.render(columns: 21, origin: .zero, pitch: 22, visible: canvas.bounds, pinTop: 6)
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 44, focus: .zero, velocity: 0,
      targetPitch: 22, targetFocus: .zero)
    canvas.animateZoom(model, duration: 0.6) { _, _ in .zero }
    let labels = canvas.layer!.sublayers!.dropFirst()
    XCTAssertFalse(labels.isEmpty)
    for label in labels {
      let move = label.animation(forKey: "zoom.pill") as! CAKeyframeAnimation
      let first = (move.values!.first as! NSValue).pointValue
      XCTAssertEqual(first.y - label.bounds.height * label.anchorPoint.y, 6)
      XCTAssertEqual(label.frame.minY, 6)
    }
    canvas.removeZoomAnimations(); canvas.reset()
  }

  func testFractionalDenseReleaseKeepsExactPixelEdgesWithTileSprings() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 120
    canvas.render(columns: 21, origin: .zero, pitch: 22, visible: canvas.bounds)
    let photos = canvas.layer!.sublayers!.first!
    let target = photos.sublayers!.map(\.frame)
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 44.37, focus: .zero, velocity: -200,
      targetPitch: 22, targetFocus: .zero)
    canvas.animateZoom(model, duration: 0.6) { _, focus in focus }
    XCTAssertTrue((photos.animationKeys() ?? []).isEmpty, "Alternating quantized widths cannot share a scale")
    XCTAssertTrue(photos.sublayers!.contains { $0.animation(forKey: "zoom.transform.scale.x") is CASpringAnimation })
    XCTAssertEqual(photos.sublayers!.map(\.frame), target)
    canvas.removeZoomAnimations()
    XCTAssertTrue(photos.sublayers!.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    canvas.reset()
  }

  func testDenseHandoffRetainsPixelsOnlyForTheSameLattice() {
    let source = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    let destination = MacDenseCanvas(frame: source.frame)
    for canvas in [source, destination] {
      canvas.pipeline = ThumbnailPipeline()
      canvas.factAt = { .init(key: "maczoom-handoff-test-\($0)", date: nil) }
      canvas.count = 90; canvas.render(columns: 21, origin: .zero, pitch: 45, visible: canvas.bounds)
    }
    let image = NSImage(size: CGSize(width: 8, height: 8))
    for tile in source.layer!.sublayers!.first!.sublayers! { tile.contents = image }
    XCTAssertEqual(destination.loadedFraction, 0)
    destination.retainDisplayedPixels(from: source)
    XCTAssertEqual(destination.loadedFraction, 1)
    destination.reset()
    destination.factAt = { .init(key: "different-handoff-test-\($0)", date: nil) }
    destination.render(columns: 21, origin: .zero, pitch: 45, visible: destination.bounds)
    destination.retainDisplayedPixels(from: source)
    XCTAssertEqual(destination.loadedFraction, 0, "Equal indexes must not substitute different assets")
    destination.reset()
    destination.render(columns: 43, origin: .zero, pitch: 22, visible: destination.bounds)
    destination.retainDisplayedPixels(from: source)
    XCTAssertEqual(destination.loadedFraction, 0, "A different lattice must load its own pixels")
    source.reset(); destination.reset()
  }

  func testCompletedZoomReleasesStageSoTheNextToolbarDensityCanApply() async {
    let source = GridTestSource(); source.identifiers = (0..<30).map { "item-\($0)" }
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
    let collection = NSCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 88); layout.requestedColumns = 9
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection; coordinator.collection = collection
    coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    for columns in [6, 4, 3, 4, 6, 9, 3] {
      coordinator.parent.columns = columns
      coordinator.animateLayout(columns: columns)
      guard let stage = coordinator.zoomStage else { XCTFail("Missing zoom stage"); continue }
      stage.advance(to: CACurrentMediaTime() + 2)
      try? await Task.sleep(for: .milliseconds(20))
      XCTAssertNil(coordinator.zoomStage, "Cleanup must not depend on a display clock in an inactive window")
      XCTAssertNil(coordinator.animationTarget)
      XCTAssertEqual(layout.columns, columns)
    }
    coordinator.removeZoomStage()
  }

  func testGroupedZoomHasOneNativeSizeHeaderAndExactSettledGeometry() {
    for count in [1, 2, 5, 12, 90] {
      let groups = Dictionary(uniqueKeysWithValues: stride(from: 0, to: count, by: 3).map { ($0, "Section \($0)") })
      let width: CGFloat = 804
      func geometry(_ columns: Int) -> LibraryTimelineGeometry {
        MacGridGeometry.make(count: count, groups: groups, columns: columns, width: width, headerHeights: [0: 138])
      }
      func pitch(_ columns: Int) -> CGFloat { geometry(columns).items[0].width + 2 }
      let g = geometry(3), anchor = g.items[0]
      let stage = MacGridZoomStage(count: count, anchor: 0, fraction: CGPoint(x: 0.5, y: 0.5),
        columns: 3, pitch: pitch(3), focus: CGPoint(x: anchor.midX, y: anchor.midY))
      stage.frame = CGRect(x: 0, y: 0, width: width, height: 1200)
      stage.referenceSide = { geometry($0).items[0].width }
      stage.groupedGeometry = geometry
      stage.makeTile = { _, _ in NSView() }
      stage.ensureFace(3, opacity: 1)
      for columns in [4, 6, 9, 6, 4, 3] {
        stage.ensureFace(columns, opacity: 0)
        let now = CACurrentMediaTime()
        stage.show(columns, animated: true, at: now)
        for frame in 0...60 {
          stage.advance(to: now + Double(frame) / 60)
          let captions = stage.subviews.compactMap { $0 as? MacGridSectionHeader }
          XCTAssertEqual(captions.count, Set(captions.map { ObjectIdentifier($0) }).count)
          for h in geometry(columns).headers {
            if let rect = stage.headerFrame(at: h.firstItem) { XCTAssertEqual(rect.height, h.frame.height) }
          }
          XCTAssertFalse(stage.subviews.contains { face in face.subviews.contains { $0 is MacGridSectionHeader } }, "Caption must not belong to a crossfading face")
        }
        let destination = geometry(columns)
        stage.pitch = pitch(columns)
        stage.focus = CGPoint(x: destination.items[0].midX, y: destination.items[0].midY)
        stage.show(columns, animated: false); stage.render()
        for header in destination.headers {
          if let rect = stage.headerFrame(at: header.firstItem) {
            XCTAssertEqual(rect.minY, header.frame.minY, accuracy: 0.001)
            XCTAssertEqual(rect.height, header.frame.height)
            XCTAssertEqual(rect.minX, MacGridSectionHeader.inset)
          }
        }
      }
      stage.stop()
    }
  }

  func testToolbarStageStartsWithinDisplayPixelOfClampedPhotoPointInShortGrid() async {
    for count in [1, 2, 5, 12] {
      for grouped in [false, true] {
        let source = GridTestSource(); source.identifiers = (0..<count).map { "item-\($0)" }
        if grouped { source.introduction = AnyView(Text("Folder summary")) }
        let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: 9)
        let coordinator = MacMediaGrid.Coordinator(grid)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
        let collection = NSCollectionView(frame: scroll.bounds)
        let layout = LibraryTimelineLayout(mode: .all, target: 88); layout.requestedColumns = 9
        collection.collectionViewLayout = layout
        collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
        collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
        scroll.documentView = collection; coordinator.collection = collection
        coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
        try? await Task.sleep(for: .milliseconds(50))
        collection.layoutSubtreeIfNeeded()
        coordinator.animateLayout(columns: 6)
        guard let stage = coordinator.zoomStage else { XCTFail("Missing live zoom stage"); continue }
        // A system animation commits destination frames immediately. Interrupt
        // at release time to inspect the exact entry pose without polling CA.
        stage.freeze(at: 0)
        var compared = 0
        for index in 0..<count {
          let settled = collection.convert(layout.frame(at: index), to: scroll)
          // The lattice also carries chronological neighbours outside its
          // natural columns. Compare the canonical on-screen copy.
          let copies = stage.subviews.flatMap(\.subviews).compactMap { $0 as? MacSourceZoomTile }
            .filter { ($0.cell.presentationID ?? $0.cell.assetID) == source.identifiers[index] }
            .map { $0.convert($0.bounds, to: scroll) }
          if let rendered = copies.min(by: {
            hypot($0.minX - settled.minX, $0.minY - settled.minY) < hypot($1.minX - settled.minX, $1.minY - settled.minY)
          }) {
            XCTAssertEqual(rendered.minY, settled.minY, accuracy: 0.5)
            compared += 1
          }
        }
        XCTAssertGreaterThan(compared, 0)
        coordinator.removeZoomStage()
      }
    }
  }

  func testOverviewStageStartsWithTheSettledGaplessPitch() async {
    for count in [1, 2, 5, 12] {
      for columns in MacLibraryDensity.overview(forWidth: 804) + [20, 40] {
        let source = GridTestSource(); source.identifiers = (0..<count).map { "item-\($0)" }
        let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: columns)
        let coordinator = MacMediaGrid.Coordinator(grid)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
        let collection = NSCollectionView(frame: scroll.bounds)
        let layout = LibraryTimelineLayout(mode: .all, target: 20)
        layout.requestedColumns = columns; layout.denseThreshold = MacLibraryDensity.denseThreshold
        collection.collectionViewLayout = layout
        collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
        scroll.documentView = collection; coordinator.collection = collection
        coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
        try? await Task.sleep(for: .milliseconds(50))
        collection.layoutSubtreeIfNeeded()
        coordinator.animateLayout(columns: 9)
        guard let stage = coordinator.zoomStage else { XCTFail("Missing overview stage"); continue }
        stage.freeze(at: 0)
        XCTAssertEqual(stage.pitch, layout.frame(at: 0).width, "A gapless overview must not gain an ordinary-grid gap on entry")
        coordinator.removeZoomStage()
      }
    }
  }

  func testAspectAvailabilityAtEveryDensityAndPlaceholder() {
    for columns in MacLibraryDensity.grid {
      XCTAssertTrue(MacLibraryDensity.canChangeAspect(level: .all, columns: columns, hasPhotos: true))
    }
    for columns in [12, 14, 20, 40, 80] {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: .all, columns: columns, hasPhotos: true))
    }
    for level in MacLibraryLevel.allCases {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: level, columns: 3, hasPhotos: false))
    }
    for level in [MacLibraryLevel.years, .months] {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: level, columns: 3, hasPhotos: true))
    }
  }

  func testFolderSummaryHeightMatchesLaidOutHostingView() {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = []
    let folder = FolderSource(id: "folder", name: String(repeating: "Long folder name ", count: 8),
      bookmark: Data(), automatic: false, enabled: true, receiver: nil, lastCheck: nil)
    let summary = AnyView(FolderSectionHeader(folders: folders, source: folder, settings: { _ in }, stop: { _ in }))
    var previous: CGFloat = .greatestFiniteMagnitude
    for gridWidth: CGFloat in [320, 460, 760, 1180] {
      let width = MacGridSectionHeader.contentWidth(for: gridWidth)
      let measured = MacGridSectionHeader.fittingHeight(introduction: summary, width: width)
      let header = MacGridSectionHeader(frame: CGRect(x: 2, y: 0, width: width, height: measured))
      header.configure(title: "October 26, 2026", introduction: summary)
      header.layoutSubtreeIfNeeded()
      guard let host = header.summary else { XCTFail("Missing folder summary"); return }
      XCTAssertEqual(host.frame.width, width)
      XCTAssertEqual(host.frame.height, ceil(host.fittingSize.height), accuracy: 1)
      XCTAssertEqual(measured, ceil(host.fittingSize.height) + MacGridSectionHeader.dateHeight, accuracy: 1)
      XCTAssertLessThanOrEqual(measured, previous)
      previous = measured
    }
  }

  func testFirstLayoutDefersHeaderMeasurementUntilViewportHasWidth() async {
    let source = GridTestSource()
    source.introduction = AnyView(Text(String(repeating: "Wrapped folder summary ", count: 20)))
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: .zero)
    let collection = NSCollectionView(frame: .zero)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; coordinator.collection = collection
    coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(coordinator.dataSource!.snapshot().itemIdentifiers.isEmpty)
    scroll.setFrameSize(NSSize(width: 804, height: 600))
    coordinator.contentResized()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(coordinator.dataSource!.snapshot().itemIdentifiers, source.identifiers)
    XCTAssertEqual(layout.headerHeights, source.headerHeights(width: scroll.contentSize.width))
    scroll.setFrameSize(NSSize(width: 460, height: 600))
    coordinator.contentResized()
    XCTAssertEqual(layout.headerHeights, source.headerHeights(width: scroll.contentSize.width))
  }

  func testReadOnlyAlbumCannotEnterSelection() {
    let source = GridTestSource()
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4, selecting: false, readOnly: true)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let collection = NSCollectionView(); coordinator.collection = collection
    coordinator.ids = source.identifiers
    coordinator.beginSelection(at: IndexPath(item: 0, section: 0))
    coordinator.toggleSelection(at: IndexPath(item: 0, section: 0))
    XCTAssertTrue(source.selection.isEmpty)
  }

  func testSourceSectionsShareTileGeometryAndPreservePartialRows() {
    let geometry = MacGridGeometry.make(count: 8, groups: [0: "Today", 3: "Yesterday"], columns: 4, width: 804)
    XCTAssertEqual(geometry.headers.map(\.firstItem), [0, 3])
    XCTAssertEqual(geometry.items[0].size, geometry.items[3].size)
    XCTAssertGreaterThan(geometry.items[3].minY, geometry.items[0].maxY)
    XCTAssertEqual(geometry.items[3].minX, geometry.items[0].minX)
    let summary = MacGridGeometry.make(count: 8, groups: [0: "Today", 3: "Yesterday"], columns: 4, width: 804, headerHeights: [0: 150])
    XCTAssertEqual(summary.items[0].minY - geometry.items[0].minY, 106)
    XCTAssertEqual(summary.items[0].width, geometry.items[0].width)
  }

  func testMarkRefreshKeepsNativeCellAndSelection() async {
    let source = GridTestSource()
    let navigation = MacLibraryNavigation()
    let grid = MacMediaGrid(source: source, navigation: navigation, queueRevision: 0, receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 804, height: 600))
    let collection = NSCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; coordinator.collection = collection
    coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(100))
    collection.layoutSubtreeIfNeeded()
    let path = IndexPath(item: 0, section: 0)
    guard let before = collection.item(at: path) as? PhotoCell else { XCTFail("No visible native cell"); return }
    source.mark = "needs_you"; source.selection = ["a"]
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(collection.item(at: path) === before, "A mark observation cannot replace the cell")
    XCTAssertEqual(coordinator.dataSource?.snapshot().itemIdentifiers, ["a", "b", "c"])
    XCTAssertEqual(coordinator.selectedPaths(), [path])
    source.identifiers = ["c", "a", "new"]
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(400))
    XCTAssertEqual(coordinator.dataSource?.snapshot().itemIdentifiers, ["c", "a", "new"])
    XCTAssertEqual(coordinator.selectedPaths(), [IndexPath(item: 1, section: 0)])
    XCTAssertEqual(source.selection, ["a"])
  }

  func testHistoryRefreshKeepsLoadedPagesAndSourceIdentity() async {
    let previous = BackupEnvironment.core
    defer { BackupEnvironment.core = previous }
    let core = GridHistoryCore(); BackupEnvironment.core = core
    let model = BackupHistoryModel()
    await model.reload(receiver: "test-receiver")
    await model.loadMore()
    XCTAssertEqual(model.photos.count, 220)
    core.reordered = true
    await model.reload(receiver: "test-receiver")
    XCTAssertEqual(model.photos.count, 220, "Observations must retain the loaded browsing window")
    XCTAssertEqual(model.photos.first?.id, "job-219")
    XCTAssertFalse(model.hasMore)
    let state = MacHistoryGridState()
    let source = MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "")
    XCTAssertEqual(source.identifiers.count, 220)
    XCTAssertEqual(source.identifiers.first, "job-7", "Needs You precedes day groups")
    XCTAssertEqual(source.identifiers.filter { $0 == "job-7" }.count, 1)
    let video = MacHistoryGridSource(history: model, state: state, filter: "all", type: .video, search: "")
    XCTAssertEqual(video.identifiers.count, 110)
    XCTAssertFalse(video.identifiers.contains("job-7"))
    source.scroll.anchor = "job-200"
    XCTAssertEqual(MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "").scroll.anchor, "job-200")
    XCTAssertNil(video.scroll.anchor, "Each browse view owns its anchor")
  }

  func testFolderResizeRetainsDisplayedPixelsUntilReplacementArrives() {
    let cell = PhotoCell()
    let folder = FolderSource(id: "folder", name: "Synthetic", bookmark: Data(), automatic: false,
      enabled: true, receiver: nil, lastCheck: nil)
    let photo = FolderPhoto(relative: "photo.jpg", source_id: "file", revision: "1", size: 100,
      media_type: "image/jpeg", modified_ms: 1000, folder_id: "folder", capture_ms: 1000,
      date_source: "embedded", backup: "not_backed_up", saved_at_ms: nil)
    let image = NSImage(size: NSSize(width: 32, height: 32))
    cell.configureFolder(photo, source: folder, pixels: 100, synthetic: image)
    XCTAssertTrue(cell.displayedImage === image)
    // The deliberately invalid bookmark makes the larger request unavailable.
    cell.configureFolder(photo, source: folder, pixels: 200)
    XCTAssertTrue(cell.displayedImage === image, "Resizing an unchanged file must never blank its cover")
    cell.cancel()
  }

  func testSupplementaryDiffProbesAcceptSectionOnlyPaths() {
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind, at: IndexPath(index: 0)))
    XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind, at: IndexPath()))
  }

  func testRegistrationFeedbackExpires() async {
    let action = SelectionBackupAction()
    await action.perform({ true }, failure: { nil })
    XCTAssertTrue(action.added)
    try? await Task.sleep(for: .milliseconds(2150))
    XCTAssertFalse(action.added)
  }
}

@MainActor private final class GridTestSource: MacGridSource {
  var identifiers = ["a", "b", "c"]
  var contextID = "test"
  var contentRevision = "1"
  var selection = Set<String>()
  let scroll = MacGridScrollState()
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  var mark: String?
  var introduction: AnyView?
  var groups: [Int: String] { introduction == nil ? [:] : [0: "Today"] }
  func introduction(at index: Int) -> AnyView? { index == 0 ? introduction : nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    introduction.map { [0: MacGridSectionHeader.fittingHeight(introduction: $0,
      width: MacGridSectionHeader.contentWidth(for: width))] } ?? [:]
  }
  func date(_ id: String) -> Date? { nil }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    cell.configureUnavailable(id: id, label: id, video: false)
    cell.setState(mark)
  }
}

private final class GridHistoryCore: CoreTransport, @unchecked Sendable {
  var reordered = false
  func call(_ command: String) async throws -> Data {
    let query = try JSONSerialization.jsonObject(with: Data(command.utf8)) as! [String: Any]
    var ordered = Array(0..<220)
    if reordered { ordered.insert(ordered.removeLast(), at: 0) }
    if query["state"] as? String == "attention" { ordered = [7] }
    let start = (query["after"] as? Int).flatMap { ordered.firstIndex(of: $0).map { $0 + 1 } } ?? 0
    let page = ordered.dropFirst(start).prefix(200)
    let items: [[String: Any]] = page.map { id in
      ["id": "job-\(id)", "cursor": id, "sort_value": 1_792_495_800_000 - id * 1000,
        "job": ["id": id, "receiver_id": "test-receiver", "state": id == 7 ? "failed" : "received",
          "processing": "complete", "confirmed_bytes": 100,
          "asset": ["kind": id % 2 == 0 ? "video" : "photo", "source_id": "source-\(id)", "revision": "1",
            "metadata": ["source_type": id % 3 == 0 ? "folder" : "library"],
            "resources": [["filename": "sample-\(id).jpg", "size": 100]]]]]
    }
    let summary: [String: Any] = ["total": 220, "attention": 1, "received": 219, "published": 219,
      "publication_failed": 0, "waiting": 0, "failed": 1, "queued": 0, "running": 0, "paused": 0, "confirmed_bytes": 21900]
    return try JSONSerialization.data(withJSONObject: ["ok": true, "value": ["items": items, "summary": summary]])
  }
}

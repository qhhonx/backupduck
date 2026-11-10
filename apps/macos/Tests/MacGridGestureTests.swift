import AppKit
import SwiftUI
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class MacGridGestureTests: XCTestCase {
  private let width: CGFloat = 804

  func testShiftClickAndArrowKeysShareOneContiguousRangeAnchor() async {
    let source = GestureGridSource(); source.grouped = false
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 230))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
    collection.collectionViewLayout = layout; collection.isSelectable = true; collection.allowsMultipleSelection = true
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self,
      forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
    await drainMainQueue()
    collection.selectItems(at: [IndexPath(item: 1, section: 0)], scrollPosition: [])
    XCTAssertGreaterThan(layout.frame(at: 11).minY, collection.visibleRect.maxY,
      "A range must include items beyond the mounted viewport")
    collection.extendSelection(to: IndexPath(item: 11, section: 0))
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...11),
      "Shift-click selects every item between its endpoints, including partial endpoint rows")
    func arrow(_ key: UInt16) {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
        timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: key)!
      collection.keyDown(with: event)
    }
    arrow(124)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...12),
      "Shift-Right continues into the next row")
    arrow(123)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...11))
    arrow(126)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...7),
      "Shift-Up contracts the contiguous range while retaining the mouse anchor")
    arrow(123); arrow(123)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...5))
    arrow(123)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...4))
    arrow(126)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), [0, 1])
    arrow(124)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), [1], "Crossing the anchor contracts to one item")
    arrow(124)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), [1, 2])
    collection.selectItems(at: [IndexPath(item: 20, section: 0)], scrollPosition: [])
    collection.extendSelection(to: IndexPath(item: 11, section: 0), additive: true)
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), Array(1...11) + [20],
      "Command-Shift adds the range while preserving a disjoint selection")
    collection.extendSelection(to: IndexPath(item: 0, section: 0))
    XCTAssertEqual(collection.selectionIndexPaths.map(\.item).sorted(), [0, 1],
      "A new Shift endpoint replaces the extended range and retains its anchor")
    coordinator.removeZoomStage()
  }

  private func groupedStage(pitch: CGFloat = 200) -> MacGridZoomStage {
    let stage = MacGridZoomStage(count: 90, anchor: 28, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 4, pitch: pitch, focus: CGPoint(x: 250, y: 320))
    stage.frame = CGRect(x: 0, y: 0, width: width, height: 700)
    let geometry: (Int) -> LibraryTimelineGeometry = {
      MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"],
        columns: $0, width: 804)
    }
    stage.groupedGeometry = geometry
    stage.referenceSide = { geometry($0).items[0].width }
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 0.6); stage.ensureFace(6, opacity: 0.4)
    return stage
  }

  private func photoViews(_ stage: MacGridZoomStage) -> [NSView] {
    stage.subviews.filter { !($0 is MacGridSectionHeader) }.flatMap(macGridPhotoChildren)
  }

  private func frames(_ views: [NSView]) -> [ObjectIdentifier: CGRect] {
    Dictionary(uniqueKeysWithValues: views.map { (ObjectIdentifier($0), $0.frame) })
  }

  private func assertFrames(_ before: [ObjectIdentifier: CGRect], equalAfter views: [NSView],
    file: StaticString = #filePath, line: UInt = #line) {
    let after = frames(views)
    for (id, rect) in before {
      guard let actual = after[id] else {
        XCTFail("An already visible photo was discarded at input takeover", file: file, line: line)
        continue
      }
      XCTAssertEqual(actual.minX, rect.minX, accuracy: 0.001, file: file, line: line)
      XCTAssertEqual(actual.minY, rect.minY, accuracy: 0.001, file: file, line: line)
      XCTAssertEqual(actual.width, rect.width, accuracy: 0.001, file: file, line: line)
      XCTAssertEqual(actual.height, rect.height, accuracy: 0.001, file: file, line: line)
    }
  }

  func testGroupedReanchorPreservesAllFacesAndCaptionsAcrossPartialSectionRows() {
    for pitch: CGFloat in [200, 160, 270] {
      let stage = groupedStage(pitch: pitch)
      let photos = frames(photoViews(stage))
      let captions = frames(stage.subviews.compactMap { $0 as? MacGridSectionHeader })
      XCTAssertGreaterThan(photos.count, 20, "Both partially blended densities must be covered")
      let item = stage.tile(at: 30)!
      let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
      stage.reanchor(to: point)
      XCTAssertEqual(stage.anchor, 30, "A section header and a partial previous row must not change hit identity")
      assertFrames(photos, equalAfter: photoViews(stage))
      assertFrames(captions, equalAfter: stage.subviews.compactMap { $0 as? MacGridSectionHeader })
      stage.stop()
    }
  }

  func testOrdinaryReanchorPreservesBothFacesAndFixedGaps() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.3, y: 0.7),
      columns: 4, pitch: 176.25, focus: CGPoint(x: 250, y: 320))
    stage.frame = CGRect(x: 0, y: 0, width: width, height: 700)
    stage.referenceSide = { columns in floor((804 - 4 - CGFloat(columns - 1) * 2) / CGFloat(columns)) }
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 0.6, leading: 1)
    stage.ensureFace(6, opacity: 0.4, leading: 3)
    let before = frames(photoViews(stage))
    XCTAssertGreaterThan(before.count, 20)
    stage.reanchor(to: CGPoint(x: 530, y: 440))
    assertFrames(before, equalAfter: photoViews(stage))
    stage.stop()
  }

  func testOrdinaryReanchorUsesTheActualLeftAndRightChronologicalPhotoCopies() {
    for right in [false, true] {
      let geometry: (Int) -> LibraryTimelineGeometry = {
        MacGridGeometry.make(count: 30, groups: [:], columns: $0, width: 804)
      }
      let stage = MacGridZoomStage(count: 30, anchor: 20, fraction: CGPoint(x: 0.3, y: 0.7),
        columns: 4, pitch: 400 / 3, focus: CGPoint(x: 250, y: 320))
      stage.frame = CGRect(x: 0, y: 0, width: width, height: 700)
      stage.referenceSide = { geometry($0).items[0].width }
      stage.makeTile = { index, _ in
        let tile = NSView(); tile.identifier = NSUserInterfaceItemIdentifier("photo-\(index)")
        return tile
      }
      stage.ensureFace(4, opacity: 0.6); stage.ensureFace(6, opacity: 0.4)
      let shownFace = stage.subviews.first!
      let expectedIndex = right ? 20 : 15
      let copy = macGridPhotoChildren(shownFace).first {
        $0.identifier?.rawValue == "photo-\(expectedIndex)" && $0.frame.minY > 0 && $0.frame.maxY < 300
          && (right ? $0.frame.minX > 700 : $0.frame.minX > 0 && $0.frame.maxX < 210)
      }!
      XCTAssertTrue(stage.bounds.intersects(copy.frame))
      // These are row 4, columns -1 and 4, outside the native four-column face.
      // Their canonical copies are on another row, so matching identity alone
      // cannot provide the in-photo fraction at this displayed rectangle.
      let expectedFraction = CGPoint(x: right ? 0.27 : 0.63, y: right ? 0.41 : 0.74)
      let point = CGPoint(x: copy.frame.minX + copy.frame.width * expectedFraction.x,
        y: copy.frame.minY + copy.frame.height * expectedFraction.y)
      let label = NSTextField(labelWithString: "30 items")
      label.frame = CGRect(x: 0, y: 0, width: width, height: 20)
      stage.attachFooter(label, columns: [3, 4, 6, 9]) { columns in
        let g = geometry(columns), anchor = g.items[20]
        return (CGPoint(x: anchor.minX + anchor.width * 0.3, y: anchor.minY + anchor.height * 0.7),
          g.height + 14, 0)
      }
      XCTAssertTrue(stage.bounds.intersects(label.frame), "The count label must be visibly covered by this regression")
      let faces = stage.subviews.filter { !($0 is NSTextField) && !($0 is MacGridSectionHeader) }
      XCTAssertEqual(faces.count, 2)
      let before = frames(faces.flatMap(macGridPhotoChildren)), reading = label.frame
      XCTAssertGreaterThan(before.count, 30)
      stage.reanchor(to: point)
      XCTAssertEqual(stage.anchor, expectedIndex)
      XCTAssertEqual(stage.fraction.x, expectedFraction.x, accuracy: 0.000001)
      XCTAssertEqual(stage.fraction.y, expectedFraction.y, accuracy: 0.000001)
      assertFrames(before, equalAfter: faces.flatMap(macGridPhotoChildren))
      XCTAssertEqual(label.frame.minX, reading.minX, accuracy: 0.001)
      XCTAssertEqual(label.frame.minY, reading.minY, accuracy: 0.001)
      XCTAssertEqual(label.frame.size, reading.size)
      stage.stop()
    }
  }

  func testReanchoredGroupedFacesStillLandOnTheirNativeGeometry() {
    for destination in [6, 9] {
      let stage = groupedStage(pitch: 160)
      let tile = stage.tile(at: 30)!
      stage.reanchor(to: CGPoint(x: tile.frame.midX, y: tile.frame.midY))
      stage.ensureFace(destination, opacity: 0)
      let reference = stage.contentFocus(columns: destination)!
      let geometry = MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"],
        columns: destination, width: width)
      let offset: CGFloat = 150, now = CACurrentMediaTime()
      stage.show(destination, animated: true, at: now)
      stage.hurryBlend(within: GridZoom.releaseFadeDuration, at: now)
      let model = GridZoom.Settle(start: now, pitch: stage.pitch, focus: stage.focus, velocity: 0,
        targetPitch: geometry.items[0].width + 2,
        targetFocus: CGPoint(x: reference.x, y: reference.y - offset))
      var done = false
      stage.settle(with: model) { done = true }
      stage.advance(to: now + 3)
      XCTAssertTrue(done)
      var checked = 0
      for index in geometry.items.indices {
        guard let view = stage.tile(at: index) else { continue }
        let expected = geometry.items[index].offsetBy(dx: 0, dy: -offset)
        XCTAssertEqual(view.frame.minX, expected.minX, accuracy: 0.001)
        XCTAssertEqual(view.frame.minY, expected.minY, accuracy: 0.001)
        XCTAssertEqual(view.frame.size, expected.size)
        checked += 1
      }
      XCTAssertGreaterThan(checked, 10)
      for (i, header) in geometry.headers.enumerated() {
        guard let actual = stage.headerFrame(at: header.firstItem) else { continue }
        let next = i + 1 < geometry.headers.count ? geometry.headers[i + 1].frame.minY - offset : .greatestFiniteMagnitude
        let expected = min(max(header.frame.minY - offset, 0), next - header.frame.height)
        XCTAssertEqual(actual.minY, expected, accuracy: 0.001)
      }
      stage.stop()
    }
  }

  func testRapidToolbarRetargetKeepsTheFrozenStageAndItsAnimationStarts() async {
    let source = GestureGridSource()
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self,
      forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 400)); scroll.reflectScrolledClipView(scroll.contentView)
    coordinator.syncDensity(columns: 4, layout: layout)
    coordinator.parent.columns = 6; coordinator.syncDensity(columns: 6, layout: layout)
    guard let stage = coordinator.zoomStage else { XCTFail("Missing partial transition"); return }
    let releaseStart = CACurrentMediaTime()
    stage.releaseAnimationStarted(at: releaseStart)
    stage.freeze(at: releaseStart + 0.1)
    let oldPitch = stage.pitch, velocity = stage.frozenPitchVelocity
    XCTAssertLessThan(oldPitch, 199); XCTAssertGreaterThan(oldPitch, 134)
    XCTAssertLessThan(velocity, 0)
    let keys = ["position.x", "position.y", "bounds.size.width", "bounds.size.height"]
    let starts = photoViews(stage).compactMap { view -> (NSView, [CGFloat])? in
      guard let layer = view.layer else { return nil }
      return (view, keys.map { CGFloat((layer.value(forKeyPath: $0) as? NSNumber)?.doubleValue ?? 0) })
    }
    let captions = stage.subviews.compactMap { $0 as? MacGridSectionHeader }.map { ($0, $0.layer!.position.y) }
    coordinator.parent.columns = 9; coordinator.syncDensity(columns: 9, layout: layout)
    XCTAssertTrue(coordinator.zoomStage === stage, "A new command must retarget the frozen pose, not rebuild from the old collection")
    var moving = 0
    for (view, start) in starts where view.superview != nil {
      guard let layer = view.layer else { continue }
      for (index, key) in keys.enumerated() {
        let animation = layer.animation(forKey: "zoom." + key) as? CASpringAnimation
        let current = CGFloat((layer.value(forKeyPath: key) as? NSNumber)?.doubleValue ?? 0)
        let initial: CGFloat
        if animation?.isAdditive == true {
          let other = layer.animation(forKey: "zoom.velocity." + key) as? CASpringAnimation
          initial = current + CGFloat((animation?.fromValue as? NSNumber)?.doubleValue ?? 0)
            + CGFloat((other?.fromValue as? NSNumber)?.doubleValue ?? 0)
        } else { initial = CGFloat((animation?.fromValue as? NSNumber)?.doubleValue ?? Double(current)) }
        XCTAssertEqual(initial, start[index], accuracy: 0.001)
        if key == "bounds.size.width", let animation {
          XCTAssertNotEqual(animation.initialVelocity, 0, "The interrupted spring velocity must continue")
          moving += 1
        }
      }
    }
    XCTAssertGreaterThan(moving, 0)
    for (caption, y) in captions where caption.superview != nil {
      let move = caption.layer!.animation(forKey: "zoom.caption") as? CAKeyframeAnimation
      XCTAssertEqual((move?.values?.first as? NSNumber)?.doubleValue ?? Double(caption.layer!.position.y),
        Double(y), accuracy: 0.001)
    }
    coordinator.removeZoomStage()
  }

  func testTopGroupedToolbarZoomKeepsBothPhotoFacesAtTheCaptionEdge() async {
    let source = GestureGridSource(); source.introduction = AnyView(Text("Folder summary"))
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 6)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 540, height: 700))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 6
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind,
      withIdentifier: .init("timeline"))
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    let edge = layout.frame(at: 0).minY
    coordinator.parent.columns = 4; coordinator.animateLayout(columns: 4)
    guard let stage = coordinator.zoomStage else { XCTFail("Missing zoom stage"); return }
    XCTAssertEqual(stage.anchor, 0)
    let firstPhotos = stage.subviews.flatMap(macGridPhotoChildren).compactMap { $0 as? MacSourceZoomTile }
      .filter { $0.cell.presentationID == "gesture-0" }
    XCTAssertEqual(firstPhotos.count, 2)
    for tile in firstPhotos {
      let layer = tile.layer!
      let position = (layer.animation(forKey: "zoom.position.y") as? CASpringAnimation)?.fromValue as? NSNumber
      let height = (layer.animation(forKey: "zoom.bounds.size.height") as? CASpringAnimation)?.fromValue as? NSNumber
      let initial = (position.map { CGFloat($0.doubleValue) } ?? layer.position.y)
        - (height.map { CGFloat($0.doubleValue) } ?? layer.bounds.height) * layer.anchorPoint.y
      XCTAssertEqual(initial, edge, accuracy: 0.5)
      XCTAssertEqual(tile.frame.minY, edge, accuracy: 0.5,
        "Both photo faces stay attached to the caption throughout the release")
    }
    coordinator.removeZoomStage()
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  func testWheelTakesNativeOwnershipBeforeMovingDuringDenseZoom() async {
    for awaitingAdoption in [false, true] {
      let source = GestureGridSource(); source.grouped = false; source.includesOverview = true
      source.identifiers = (0..<6000).map { "gesture-\($0)" }
      let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
        receiverID: nil, columns: 20)
      let coordinator = MacMediaGrid.Coordinator(grid)
      let scroll = LibraryScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
      let collection = LibraryCollectionView(frame: scroll.bounds)
      let layout = LibraryTimelineLayout(mode: .all, target: 40); layout.requestedColumns = 20
      collection.collectionViewLayout = layout; scroll.documentView = collection
      collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
      mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
      let window = hostNativeGrid(scroll)
      defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
      coordinator.applyItems(scroll: scroll, layout: layout)
      try? await Task.sleep(for: .milliseconds(50))
      coordinator.syncDensity(columns: 20, layout: layout)
      coordinator.pinnedToNewest = true
      coordinator.ensureDocumentHeight(); collection.layoutSubtreeIfNeeded()
      scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, coordinator.settledContentHeight - scroll.contentSize.height)))
      coordinator.parent.columns = 40; coordinator.syncDensity(columns: 40, layout: layout)
      guard let stage = coordinator.zoomStage else { XCTFail("Missing density release"); continue }
      let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.setFillColor(CGColor(gray: 0.25, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      let image = context.makeImage()!
      for canvas in stage.subviews.flatMap(macGridPhotoChildren).compactMap({ $0 as? MacDenseCanvas }) {
        for tile in canvas.photoContentLayer.sublayers ?? [] { tile.contents = image }
      }
      if awaitingAdoption {
        stage.advance(to: CACurrentMediaTime() + 3)
        XCTAssertTrue(coordinator.zoomStage === stage, "Exercise the queued native-adoption window")
      } else {
        XCTAssertLessThan(collection.alphaValue, 0.01)
      }
      let handoff = scroll.willScroll
      var offsetBeforeNativeScroll: CGFloat?
      scroll.willScroll = {
        handoff?()
        XCTAssertNil(coordinator.zoomStage, "The native wheel must never move a viewport still owned by the zoom stage")
        XCTAssertEqual(collection.alphaValue, 1)
        XCTAssertEqual(layout.columns, 40); XCTAssertEqual(layout.requestedColumns, 40)
        XCTAssertFalse(coordinator.restoring)
        XCTAssertGreaterThan(coordinator.denseCanvas!.loadedFraction, 0,
          "The shown density's already displayed pixels must survive the synchronous handoff")
        offsetBeforeNativeScroll = scroll.contentView.bounds.minY
        XCTAssertEqual(offsetBeforeNativeScroll!, max(0, coordinator.settledContentHeight - scroll.contentSize.height), accuracy: 0.5,
          "The latest density must keep the chosen newest edge before applying the scroll delta")
      }
      let update = scroll.didScroll
      let moved = expectation(description: "Native wheel applies its complete pixel delta")
      var didMove = false
      scroll.didScroll = {
        update?()
        guard let before = offsetBeforeNativeScroll else { return }
        let offset = scroll.contentView.bounds.minY
        XCTAssertNil(coordinator.zoomStage); XCTAssertEqual(collection.alphaValue, 1)
        XCTAssertEqual(layout.columns, 40)
        let canvas = coordinator.denseCanvas!
        XCTAssertFalse(canvas.isHidden)
        for y in [offset + 1, offset + scroll.contentSize.height / 2] {
          let point = CGPoint(x: self.width / 2, y: y)
          XCTAssertTrue(canvas.photoContentLayer.sublayers!.contains { $0.frame.contains(point) },
            "Each actual native bounds change must populate its photo coverage before display")
        }
        if abs(offset - (before - 120)) < 0.5, !didMove { didMove = true; moved.fulfill() }
      }
      let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
        wheel1: 120, wheel2: 0, wheel3: 0)!
      scroll.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
      guard let before = offsetBeforeNativeScroll else { XCTFail("Wheel did not invoke native handoff"); continue }
      XCTAssertNil(coordinator.zoomStage); XCTAssertNil(coordinator.animationTarget)
      // Retired CA delegates and queued adoption callbacks cannot restore the
      // pre-wheel offset or hide the native collection after this input.
      stage.advance(to: CACurrentMediaTime() + 10)
      // AppKit can defer applying a pixel wheel until its next native update.
      // Keep the synchronous ownership assertions above, then observe movement.
      await fulfillment(of: [moved], timeout: 2)
      let after = scroll.contentView.bounds.minY
      XCTAssertEqual(after, before - 120, accuracy: 0.5,
        "The original wheel event must continue scrolling after it takes ownership")
      XCTAssertFalse(coordinator.pinnedToNewest)
      await drainMainQueue()
      XCTAssertNil(coordinator.zoomStage); XCTAssertEqual(layout.columns, 40)
      XCTAssertEqual(collection.alphaValue, 1)
      XCTAssertEqual(scroll.contentView.bounds.minY, after, accuracy: 0.5)
      XCTAssertEqual(coordinator.ids, source.identifiers)
    }
  }

  func testQueuedNativeHandoffCannotRemoveTheSameStageRetargetedByNewToolbarInput() async {
    let source = GestureGridSource(); source.grouped = false
    source.includesOverview = true; source.footer = "72 photos, 18 videos"
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 86); layout.requestedColumns = 9
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    // The race crosses a CA transaction commit. An unattached NSView has no
    // render host and may discard its animations at that commit, independently
    // of the coordinator's queued cleanup. Keep the release in a real window.
    let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = scroll
    window.orderFront(nil)
    defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
    XCTAssertTrue(window.isVisible)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    coordinator.syncDensity(columns: 9, layout: layout)
    coordinator.pinnedToNewest = true
    let initialMaximum = max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: initialMaximum))

    coordinator.parent.columns = 4; coordinator.syncDensity(columns: 4, layout: layout)
    guard let stage = coordinator.zoomStage else { XCTFail("Missing first release"); return }
    stage.advance(to: CACurrentMediaTime() + 3)
    collection.layoutSubtreeIfNeeded()
    // Completion adopts four columns synchronously, but its native cleanup is
    // still queued. Inject the next real input before allowing that queue to run.
    XCTAssertEqual(layout.columns, 4)
    XCTAssertEqual(coordinator.leading, 0)
    XCTAssertTrue(coordinator.zoomStage === stage)
    XCTAssertFalse(coordinator.restoring)
    coordinator.parent.columns = 6; coordinator.syncDensity(columns: 6, layout: layout)
    XCTAssertTrue(coordinator.zoomStage === stage)
    XCTAssertEqual(stage.shown, 6)
    XCTAssertTrue(coordinator.restoring)
    let target = coordinator.animationTarget!
    XCTAssertTrue(stage.window === window)
    XCTAssertNotNil(stage.layer?.animation(forKey: "zoom.settleClock"))
    await drainMainQueue()
    XCTAssertTrue(coordinator.zoomStage === stage,
      "The old four-column cleanup must not remove a newer release using the same stage instance")
    XCTAssertTrue(stage.window === window)
    XCTAssertTrue(window.isVisible)
    XCTAssertNotNil(stage.layer?.animation(forKey: "zoom.settleClock"))
    XCTAssertEqual(stage.shown, 6)
    XCTAssertTrue(coordinator.restoring)
    XCTAssertEqual(coordinator.animationTarget?.0, target.0)
    XCTAssertEqual(coordinator.animationTarget?.1, target.1)
    XCTAssertEqual(layout.columns, 4, "The native collection stays at its last adoption while the new stage runs")
    XCTAssertEqual(coordinator.leading, 0)
    XCTAssertTrue(coordinator.pinnedToNewest)

    // The newer completion owns its cleanup and must still finish normally.
    stage.advance(to: CACurrentMediaTime() + 3)
    collection.layoutSubtreeIfNeeded()
    await drainMainQueue()
    XCTAssertNil(coordinator.zoomStage)
    XCTAssertNil(coordinator.animationTarget)
    XCTAssertFalse(coordinator.restoring)
    XCTAssertEqual(layout.columns, 6)
    XCTAssertEqual(coordinator.leading, 0)
    XCTAssertTrue(coordinator.pinnedToNewest)

    // Continue through a fitting overview and return to the original nine
    // columns: no stale leading slots, missing stage, or lost newest intent.
    for columns in [MacLibraryDensity.overview[0], 9] {
      coordinator.parent.columns = columns; coordinator.syncDensity(columns: columns, layout: layout)
      guard let next = coordinator.zoomStage else { XCTFail("Every subsequent toolbar request must animate"); return }
      XCTAssertTrue(coordinator.restoring)
      next.advance(to: CACurrentMediaTime() + 3)
      collection.layoutSubtreeIfNeeded()
      await drainMainQueue()
      XCTAssertNil(coordinator.zoomStage, "An unretargeted native handoff must remove its completed stage")
      XCTAssertFalse(coordinator.restoring)
      XCTAssertNil(coordinator.animationTarget)
    }
    XCTAssertEqual(layout.columns, 9)
    XCTAssertEqual(layout.requestedColumns, 9)
    XCTAssertEqual(coordinator.leading, 0)
    XCTAssertTrue(coordinator.pinnedToNewest)
    let finalMaximum = max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)
    XCTAssertGreaterThan(finalMaximum, 0)
    XCTAssertEqual(scroll.contentView.bounds.minY, finalMaximum, accuracy: 0.5)
    coordinator.removeZoomStage()
  }

  private func hostNativeGrid(_ scroll: NSScrollView) -> NSWindow {
    let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = scroll; window.orderFront(nil)
    return window
  }

  private func waitForNativeAdoption(_ coordinator: MacMediaGrid.Coordinator, context: String = "",
    file: StaticString = #filePath, line: UInt = #line) async -> Bool {
    // Observe the native event-driven result; this wait neither changes layout
    // nor retries the product's adoption check.
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      guard Thread.isMainThread else { return false }
      return MainActor.assumeIsolated { coordinator.zoomStage == nil }
    }, object: nil)
    let result = await XCTWaiter.fulfillment(of: [ready], timeout: 2)
    if result != .completed, let collection = coordinator.collection,
      let layout = collection.collectionViewLayout as? LibraryTimelineLayout {
      let expected = layout.layoutAttributesForElements(in: collection.visibleRect).filter { $0.frame.intersects(collection.visibleRect) }
      let elements = expected.map { attributes -> [String: Any] in
        let path = attributes.indexPath
        let item = path.flatMap { collection.item(at: $0) as? PhotoCell }
        let view: NSView? = attributes.representedElementCategory == .item ? item?.view
          : path.flatMap { collection.supplementaryView(forElementKind: attributes.representedElementKind ?? LibraryTimelineLayout.headerKind, at: $0) }
        return ["index": path?.item ?? -1, "item": attributes.representedElementCategory == .item,
          "expected": NSStringFromRect(attributes.frame), "actual": view.map { NSStringFromRect($0.convert($0.bounds, to: collection)) } ?? "missing",
          "attached": view?.isDescendant(of: collection) ?? false, "hidden": view?.isHidden ?? true,
          "alpha": view?.alphaValue ?? -1, "idMatches": item.map { $0.presentationID == path.flatMap { coordinator.dataSource?.itemIdentifier(for: $0) } } ?? false]
      }
      var row: [String: Any] = ["context": context, "columns": layout.columns, "leading": coordinator.leading,
        "count": coordinator.count, "viewport": NSStringFromRect(collection.visibleRect),
        "collection": NSStringFromRect(collection.frame), "restoring": coordinator.restoring,
        "elements": elements]
      if let canvas = coordinator.denseCanvas {
        row["dense"] = ["frame": NSStringFromRect(canvas.frame), "hidden": canvas.isHidden,
          "attached": canvas.isDescendant(of: collection), "photos": canvas.photoContentLayer.sublayers?.count ?? 0,
          "loaded": canvas.loadedFraction] as [String: Any]
      }
      if let stage = coordinator.zoomStage {
        row["stage"] = ["shown": stage.shown, "focus": NSStringFromPoint(stage.focus), "pitch": stage.pitch,
          "faces": stage.subviews.map { ["frame": NSStringFromRect($0.frame), "alpha": $0.alphaValue] as [String: Any] }]
      }
      if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
        fputs("HandoffFixtureFailure \(text)\n", stderr)
      }
    }
    XCTAssertEqual(result, .completed, "The native viewport did not complete its adoption: \(context)", file: file, line: line)
    return result == .completed
  }

  func testNativeAdoptionRetainsTheStageUntilActualViewportCellsArriveAndReceiveItsPixels() async {
    let source = GestureGridSource(); source.grouped = false
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32)!
    bitmap.bitmapData!.initialize(repeating: 255, count: 256)
    let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: 8, height: 8))
    source.zoomImage = image
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
    let collection = DeferredGridCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 86); layout.requestedColumns = 9
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection)
    let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = scroll; window.orderFront(nil)
    defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    coordinator.syncDensity(columns: 9, layout: layout); coordinator.pinnedToNewest = true
    scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)))
    collection.layoutSubtreeIfNeeded()
    collection.defersNativeLayout = true
    coordinator.parent.columns = 6; coordinator.syncDensity(columns: 6, layout: layout)
    guard let stage = coordinator.zoomStage else { XCTFail("Missing displayed cover"); return }
    stage.advance(to: CACurrentMediaTime() + 3)
    let expected = layout.layoutAttributesForElements(in: collection.visibleRect).filter {
      $0.representedElementCategory == .item && $0.frame.intersects(collection.visibleRect)
    }
    XCTAssertFalse(expected.isEmpty)
    guard !expected.isEmpty else { return }
    XCTAssertTrue(expected.allSatisfy { attributes in
      guard let path = attributes.indexPath else { return false }
      return collection.item(at: path) == nil
    }, "The deferred fixture must make expected native items genuinely unavailable")
    let beforeCheck = collection.deferredItemQueries
    await drainMainQueue()
    XCTAssertGreaterThan(collection.deferredItemQueries, beforeCheck, "The real adoption predicate must encounter the unavailable item")
    XCTAssertTrue(coordinator.zoomStage === stage, "A queue turn cannot replace native viewport readiness")
    XCTAssertTrue(stage.superview === scroll)
    guard coordinator.zoomStage === stage else { return }
    XCTAssertFalse(coordinator.restoring)

    collection.defersNativeLayout = false
    layout.invalidateLayout(); collection.needsLayout = true
    collection.layoutSubtreeIfNeeded()
    let arriving = expected.compactMap { attributes -> (Int, PhotoCell)? in
      guard let path = attributes.indexPath, let cell = collection.item(at: path) as? PhotoCell else { return nil }
      // A newly materialized native rendition has no bitmap yet. Its existing
      // stage rendition must transfer before removing the visible cover.
      cell.prepareForReuse()
      source.configure(cell, id: source.identifiers[path.item], pixels: 288, originalAspect: false)
      XCTAssertNil(cell.displayedImage)
      XCTAssertFalse(cell.hasPhotoContents)
      XCTAssertNotNil(stage.displayedImage(at: path.item))
      return (path.item, cell)
    }
    XCTAssertEqual(arriving.count, expected.count)
    XCTAssertTrue(coordinator.zoomStage === stage)
    guard await waitForNativeAdoption(coordinator) else { return }
    XCTAssertNil(coordinator.zoomStage, "The real completed layout event releases a ready native viewport")
    for (_, cell) in arriving {
      XCTAssertTrue(cell.displayedImage === image)
      XCTAssertTrue(cell.hasPhotoContents)
    }
    XCTAssertEqual(layout.columns, 6)
    XCTAssertTrue(coordinator.pinnedToNewest)
  }

  func testNonzeroInsetStageAndNativeFolderCaptionsShareTheSamePinLine() async {
    let source = HierarchyGridSource()
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentInsets = NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0)
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    let window = hostNativeGrid(scroll)
    defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 220))
    collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
    coordinator.parent.columns = 6; coordinator.animateLayout(columns: 6)
    guard let stage = coordinator.zoomStage else { XCTFail("Missing inset hierarchy stage"); return }
    XCTAssertEqual(scroll.contentInsets.top, 32, "The native inset fixture must remain nonzero")
    XCTAssertGreaterThan(stage.groupedPinTop, 0)
    stage.advance(to: CACurrentMediaTime() + 3)
    let expected = layout.layoutAttributesForElements(in: collection.visibleRect).filter {
      $0.representedElementCategory == .supplementaryView && $0.frame.intersects(collection.visibleRect)
    }
    XCTAssertTrue(expected.contains { $0.representedElementKind == MacTimelineCaption.Kind.folder.rawValue })
    for attributes in expected {
      guard let kind = attributes.representedElementKind, let path = attributes.indexPath,
        let caption = layout.caption(kind: kind, at: path.item), let actual = stage.captionFrame(caption.id) else {
        XCTFail("The stage must carry every expected caption role"); return
      }
      let target = stage.convert(attributes.frame, from: collection)
      XCTAssertEqual(actual.minY, target.minY, accuracy: 0.5)
      XCTAssertEqual(actual.height, target.height, accuracy: 0.5)
      XCTAssertEqual(actual.minX, target.minX, accuracy: 0.5)
      XCTAssertEqual(actual.width, target.width, accuracy: 0.5)
    }
    collection.layoutSubtreeIfNeeded()
    _ = await waitForNativeAdoption(coordinator, context: "nonzero-inset")
  }

  func testHierarchyAdoptionWaitsForEveryNativeSummaryFolderAndDateRole() async {
    for role in MacTimelineCaption.Kind.allCases {
      let source = HierarchyGridSource()
      let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
        receiverID: nil, columns: 4)
      let coordinator = MacMediaGrid.Coordinator(grid)
      let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
      let collection = DeferredCaptionCollectionView(frame: scroll.bounds)
      let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
      collection.collectionViewLayout = layout; scroll.documentView = collection
      collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
      mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
      let window = hostNativeGrid(scroll)
      defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
      coordinator.applyItems(scroll: scroll, layout: layout)
      try? await Task.sleep(for: .milliseconds(50))
      collection.blockedKind = role.rawValue
      coordinator.parent.columns = 6; coordinator.animateLayout(columns: 6)
      guard let stage = coordinator.zoomStage else { XCTFail("Missing hierarchy zoom cover"); return }
      stage.advance(to: CACurrentMediaTime() + 3)
      collection.layoutSubtreeIfNeeded()
      let expected = layout.layoutAttributesForElements(in: collection.visibleRect).filter {
        $0.representedElementKind == role.rawValue && $0.frame.intersects(collection.visibleRect)
      }
      XCTAssertFalse(expected.isEmpty, "The unavailable role must actually be expected in this native viewport")
      let queries = collection.blockedQueries
      await drainMainQueue()
      XCTAssertGreaterThan(collection.blockedQueries, queries)
      XCTAssertTrue(coordinator.zoomStage === stage,
        "Neither ready photos nor the other caption roles may release a missing \(role) cover")
      collection.blockedKind = nil
      // Only the retained caption lays out here. A collection-wide layout is
      // not guaranteed when a source changes content without changing geometry.
      coordinator.refreshVisibleHeaders()
      for attributes in expected {
        if let path = attributes.indexPath,
          let header = collection.supplementaryView(forElementKind: role.rawValue, at: path) {
          header.needsLayout = true; header.layoutSubtreeIfNeeded()
        }
      }
      guard await waitForNativeAdoption(coordinator, context: "hierarchy-\(role)") else { return }
      for attributes in layout.layoutAttributesForElements(in: collection.visibleRect)
        where attributes.representedElementCategory == .supplementaryView && attributes.frame.intersects(collection.visibleRect) {
        guard let kind = attributes.representedElementKind, let path = attributes.indexPath,
          let caption = layout.caption(kind: kind, at: path.item),
          let header = collection.supplementaryView(forElementKind: kind, at: path) as? MacGridSectionHeader else {
          XCTFail("Every expected native caption must be materialized"); return
        }
        XCTAssertEqual(header.captionID, caption.id)
        XCTAssertTrue(header.isReady(for: caption, revision: source.contentRevision))
        let actual = header.convert(header.bounds, to: collection)
        XCTAssertEqual(actual.minY, attributes.frame.minY, accuracy: 0.5)
        XCTAssertEqual(actual.height, attributes.frame.height, accuracy: 0.5)
        XCTAssertEqual(actual.minX, 0)
        XCTAssertEqual(actual.width, scroll.contentSize.width)
      }
    }
  }

  func testNewestToolbarKeepsLeadingEdgeDuringRapidRetarget() async {
    let source = GestureGridSource(); source.grouped = false; source.footer = "90 items"
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 86); layout.requestedColumns = 9
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    let window = hostNativeGrid(scroll)
    defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    coordinator.syncDensity(columns: 9, layout: layout); coordinator.pinnedToNewest = true
    scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)))
    coordinator.parent.columns = 4; coordinator.syncDensity(columns: 4, layout: layout)
    coordinator.zoomStage!.advance(to: CACurrentMediaTime() + 3)
    collection.layoutSubtreeIfNeeded()
    guard await waitForNativeAdoption(coordinator) else { return }
    XCTAssertNil(coordinator.zoomStage)
    XCTAssertEqual(coordinator.leading, 0)

    // Start a fresh six-column stage from the settled four-column grid and
    // retarget it to nine columns without losing the newest edge.
    coordinator.parent.columns = 6; coordinator.syncDensity(columns: 6, layout: layout)
    let stage = coordinator.zoomStage!
    coordinator.parent.columns = 9; coordinator.syncDensity(columns: 9, layout: layout)
    XCTAssertTrue(coordinator.zoomStage === stage)
    stage.advance(to: CACurrentMediaTime() + 3)
    collection.layoutSubtreeIfNeeded()
    guard await waitForNativeAdoption(coordinator) else { return }
    XCTAssertNil(coordinator.zoomStage)
    XCTAssertEqual(layout.columns, 9)
    XCTAssertEqual(coordinator.leading, 0)
    XCTAssertEqual((source.identifiers.count + coordinator.leading) % 9, 0)
    XCTAssertTrue(coordinator.pinnedToNewest)
    XCTAssertEqual(scroll.contentView.bounds.minY,
      max(0, layout.collectionViewContentSize.height - scroll.contentSize.height), accuracy: 0.5)
    // An old in-memory layout can still have a leading gap. Retargeting back to
    // nine columns must settle at the canonical leading edge.
    coordinator.leading = 8; layout.leadingSlots = 8; layout.adopt(mode: .all, columns: 9)
    coordinator.ensureDocumentHeight(); collection.layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)))
    coordinator.parent.columns = 6; coordinator.syncDensity(columns: 6, layout: layout)
    let retained = coordinator.zoomStage!
    coordinator.parent.columns = 9; coordinator.syncDensity(columns: 9, layout: layout)
    XCTAssertTrue(coordinator.zoomStage === retained)
    retained.advance(to: CACurrentMediaTime() + 3)
    collection.layoutSubtreeIfNeeded()
    guard await waitForNativeAdoption(coordinator) else { return }
    XCTAssertNil(coordinator.zoomStage)
    XCTAssertEqual(coordinator.leading, 0, "The settled grid starts at the leading edge")
    coordinator.removeZoomStage()
  }

  func testToolbarRetainsTheChosenEdgeWhenAnIntermediateDensityFitsTheViewport() async {
    for newest in [false, true] {
      let source = GestureGridSource(); source.grouped = false; source.footer = "72 photos, 18 videos"
      let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
        receiverID: nil, columns: 4)
      let coordinator = MacMediaGrid.Coordinator(grid)
      let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 1100))
      let collection = LibraryCollectionView(frame: scroll.bounds)
      let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
      collection.collectionViewLayout = layout; scroll.documentView = collection
      collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
      mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
      let window = hostNativeGrid(scroll)
      defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
      coordinator.applyItems(scroll: scroll, layout: layout)
      try? await Task.sleep(for: .milliseconds(50))
      coordinator.pinnedToNewest = newest
      let initialMaximum = max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)
      scroll.contentView.scroll(to: CGPoint(x: 0, y: newest ? initialMaximum : 0))
      for columns in [9, 3] {
        coordinator.parent.columns = columns; coordinator.animateLayout(columns: columns)
        coordinator.zoomStage?.advance(to: CACurrentMediaTime() + 3)
        collection.layoutSubtreeIfNeeded()
        guard await waitForNativeAdoption(coordinator) else { return }
        XCTAssertNil(coordinator.zoomStage)
        let maximum = max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)
        XCTAssertEqual(scroll.contentView.bounds.minY, newest ? maximum : 0, accuracy: 0.5)
        XCTAssertEqual(coordinator.pinnedToNewest, newest,
          "Zero scroll offset in a fitting document does not change which edge the zoom retains")
      }
      coordinator.removeZoomStage()
    }
  }

  private func animationStart(_ layer: CALayer, key: String) -> CGFloat {
    let current = CGFloat((layer.value(forKeyPath: key) as? NSNumber)?.doubleValue ?? 0)
    guard let animation = layer.animation(forKey: "zoom." + key) as? CABasicAnimation else { return current }
    let from = CGFloat((animation.fromValue as? NSNumber)?.doubleValue ?? Double(current))
    if animation.isAdditive {
      let second = layer.animation(forKey: "zoom.velocity." + key) as? CABasicAnimation
      return current + from + CGFloat((second?.fromValue as? NSNumber)?.doubleValue ?? 0)
    }
    return from
  }

  private func lastPhotoEdges(_ stage: MacGridZoomStage, identifier: String) -> [(start: CGFloat, end: CGFloat)] {
    var result: [(CGFloat, CGFloat)] = []
    for face in stage.subviews where !(face is MacGridSectionHeader) && !(face is NSTextField) {
      if let canvas = face.subviews.first(where: { $0 is MacDenseCanvas }) as? MacDenseCanvas,
        let tiles = canvas.photoContentLayer.sublayers, !tiles.isEmpty {
        let photos = canvas.photoContentLayer
        let origin = animationStart(photos, key: "position.y")
        let scale = animationStart(photos, key: "transform.scale.y")
        let start = tiles.map { tile -> CGFloat in
          let position = animationStart(tile, key: "position.y")
          let tileScale = animationStart(tile, key: "transform.scale.y")
          return origin + (position + (1 - tile.anchorPoint.y) * tile.bounds.height * tileScale) * scale
        }.max()!
        result.append((start, tiles.map(\.frame.maxY).max()!))
      } else if let tile = macGridPhotoChildren(face).compactMap({ $0 as? MacSourceZoomTile })
        .first(where: {
          // Horizontal fill can contain another copy of this item on a nearby
          // row. Identify the focal copy by x, leaving its y independently tested.
          $0.cell.presentationID == identifier
          && $0.frame.minX <= stage.focus.x && $0.frame.maxX >= stage.focus.x }), let layer = tile.layer {
        let start = animationStart(layer, key: "position.y")
          + (1 - layer.anchorPoint.y) * animationStart(layer, key: "bounds.size.height")
        result.append((start, tile.frame.maxY))
      }
    }
    return result
  }

  private func animatedValue(_ layer: CALayer, key: String, elapsed: CFTimeInterval) -> CGFloat {
    let current = CGFloat((layer.value(forKeyPath: key) as? NSNumber)?.doubleValue ?? 0)
    func sample(_ animation: CASpringAnimation) -> CGFloat {
      let from = CGFloat((animation.fromValue as? NSNumber)?.doubleValue ?? 0)
      let to = CGFloat((animation.toValue as? NSNumber)?.doubleValue ?? 0)
      let rate = CGFloat(sqrt(animation.stiffness / animation.mass)), time = CGFloat(elapsed)
      let speed = CGFloat(animation.initialVelocity) * (to - from)
      return to + (from - to + (speed + rate * (from - to)) * time) * exp(-rate * time)
    }
    guard let first = layer.animation(forKey: "zoom." + key) as? CASpringAnimation else { return current }
    if first.isAdditive {
      let second = layer.animation(forKey: "zoom.velocity." + key) as? CASpringAnimation
      return current + sample(first) + (second.map(sample) ?? 0)
    }
    return sample(first)
  }

  private func photoEnvelope(_ stage: MacGridZoomStage, elapsed: CFTimeInterval) -> [CGFloat] {
    var result: [CGFloat] = []
    for face in stage.subviews where !(face is MacGridSectionHeader) && !(face is NSTextField) {
      if let canvas = face.subviews.first(where: { $0 is MacDenseCanvas }) as? MacDenseCanvas,
        let tiles = canvas.photoContentLayer.sublayers, !tiles.isEmpty {
        let photos = canvas.photoContentLayer
        let origin = animatedValue(photos, key: "position.y", elapsed: elapsed)
        let scale = animatedValue(photos, key: "transform.scale.y", elapsed: elapsed)
        result.append(tiles.map { tile in
          let position = animatedValue(tile, key: "position.y", elapsed: elapsed)
          let tileScale = animatedValue(tile, key: "transform.scale.y", elapsed: elapsed)
          return origin + (position + (1 - tile.anchorPoint.y) * tile.bounds.height * tileScale) * scale
        }.max()!)
      } else {
        let photos = macGridPhotoChildren(face).compactMap { $0 as? MacSourceZoomTile }
        if let bottom = photos.compactMap({ tile -> CGFloat? in
          guard let layer = tile.layer else { return nil }
          let position = animatedValue(layer, key: "position.y", elapsed: elapsed)
          let height = animatedValue(layer, key: "bounds.size.height", elapsed: elapsed)
          return position + (1 - layer.anchorPoint.y) * height
        }).max() { result.append(bottom) }
      }
    }
    return result
  }

  func testNewestToolbarKeepsEveryLastRowClearOfTheFooterThroughOverviewAndFitReturn() async {
    let previousOverview = MacLibraryDensity.overview
    defer { MacLibraryDensity.overview = previousOverview }
    for grouped in [false, true] {
      for count in [90, 91] {
        let source = GestureGridSource(); source.grouped = grouped
        source.identifiers = (0..<count).map { "gesture-\($0)" }
        source.footer = "\(count) items"; source.includesOverview = !grouped
        let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
          receiverID: nil, columns: 4)
        let coordinator = MacMediaGrid.Coordinator(grid)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 1100))
        let collection = LibraryCollectionView(frame: scroll.bounds)
        let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
        layout.denseThreshold = MacLibraryDensity.denseThreshold
        collection.collectionViewLayout = layout; scroll.documentView = collection
        collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
        collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind,
          withIdentifier: .init("timeline"))
        mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
        let window = hostNativeGrid(scroll)
        defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
        coordinator.applyItems(scroll: scroll, layout: layout)
        try? await Task.sleep(for: .milliseconds(50))
        coordinator.updateFooter(); coordinator.pinnedToNewest = true
        scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, layout.collectionViewContentSize.height - 1100)))
        MacLibraryDensity.overview = MacLibraryDensity.overview(forWidth: scroll.contentSize.width)
        let destinations = grouped ? [6, 9, 3, 4] : [6, MacLibraryDensity.overview[0], 3, MacLibraryDensity.overview[1], 4]
        for columns in destinations {
          let startBottom = layout.frame(at: count - 1).maxY - scroll.contentView.bounds.minY
          coordinator.parent.columns = columns; coordinator.animateLayout(columns: columns)
          guard let stage = coordinator.zoomStage else { XCTFail("Missing newest-edge zoom"); continue }
          XCTAssertEqual(stage.anchor, count - 1)
          XCTAssertEqual(stage.fraction, CGPoint(x: 0.5, y: 1))
          let edges = lastPhotoEdges(stage, identifier: "gesture-\(count - 1)")
          XCTAssertEqual(edges.count, 2, "Both outgoing and incoming last rows must be measured")
          let label = stage.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == source.footer }!
          let footerMove = label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
          let footerStart = CGFloat((footerMove.values!.first as! NSNumber).doubleValue)
            - label.layer!.position.y + label.frame.minY
          for edge in edges {
            let context = "grouped=\(grouped), count=\(count), target=\(columns)"
            XCTAssertEqual(edge.start, startBottom, accuracy: 0.5, context)
            XCTAssertEqual(edge.end, stage.focus.y, accuracy: 0.5, context)
            XCTAssertGreaterThanOrEqual(footerStart - edge.start, 29.5)
            XCTAssertGreaterThanOrEqual(label.frame.minY - edge.end, 29.5)
          }
          let positions = footerMove.values as! [NSNumber]
          for (step, position) in positions.enumerated() {
            let elapsed = footerMove.duration * Double(step) / Double(positions.count - 1)
            let footerY = CGFloat(position.doubleValue) - label.layer!.position.y + label.frame.minY
            let envelopes = photoEnvelope(stage, elapsed: elapsed)
            XCTAssertEqual(envelopes.count, 2)
            for bottom in envelopes {
              XCTAssertGreaterThanOrEqual(footerY - bottom, 29.5,
                "All photo copies, not only the focal last item, must remain above the footer: grouped=\(grouped), count=\(count), target=\(columns), step=\(step)")
            }
          }
          stage.advance(to: CACurrentMediaTime() + 3)
          collection.layoutSubtreeIfNeeded()
          guard await waitForNativeAdoption(coordinator, context: "grouped=\(grouped),count=\(count),target=\(columns),viewport=\(scroll.contentSize)") else { return }
          XCTAssertNil(coordinator.zoomStage)
          if grouped {
            let captions = layout.layoutAttributesForElements(in: collection.visibleRect).filter {
              $0.representedElementKind == LibraryTimelineLayout.headerKind && $0.frame.intersects(collection.visibleRect)
            }
            XCTAssertFalse(captions.isEmpty)
            if count == 90, columns == 6 {
              XCTAssertTrue(captions.contains { $0.indexPath?.item == 48 }, "The formerly pinned caption must be covered")
            }
            for attributes in captions {
              guard let path = attributes.indexPath,
                let header = collection.supplementaryView(forElementKind: LibraryTimelineLayout.headerKind, at: path) else {
                XCTFail("A ready native viewport must contain every expected caption"); return
              }
              let actual = header.convert(header.bounds, to: collection)
              XCTAssertEqual(actual.minX, attributes.frame.minX, accuracy: 0.5)
              XCTAssertEqual(actual.minY, attributes.frame.minY, accuracy: 0.5)
              XCTAssertEqual(actual.width, attributes.frame.width, accuracy: 0.5)
              XCTAssertEqual(actual.height, attributes.frame.height, accuracy: 0.5)
            }
          }
          XCTAssertTrue(coordinator.pinnedToNewest)
          let maximum = max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)
          XCTAssertEqual(scroll.contentView.bounds.minY, maximum, accuracy: 0.5)
          XCTAssertTrue(label.superview === collection)
          XCTAssertGreaterThanOrEqual(label.frame.minY - layout.frame(at: count - 1).maxY, 29.5)
        }
        coordinator.removeZoomStage()
      }
    }
  }

  func testLiveMembershipWaitsForNativeScrollingAndPreservesTheReadingRow() async throws {
    let source = GestureGridSource()
    source.grouped = false
    source.preservesViewportDuringLiveUpdates = true
    source.identifiers = (0..<200).map { "record-\($0)" }
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = LibraryScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 420))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 198)
    layout.requestedColumns = 4
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection)
    let window = hostNativeGrid(scroll)
    defer { window.orderOut(nil); window.close() }
    coordinator.applyItems(scroll: scroll, layout: layout)
    try await Task.sleep(for: .milliseconds(50))
    coordinator.pinnedToNewest = true
    let bottom = coordinator.settledContentHeight - scroll.contentSize.height
    scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
    scroll.reflectScrolledClipView(scroll.contentView)
    coordinator.rememberScroll()

    let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
      wheel1: 290, wheel2: 0, wheel3: 0))
    scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
    source.identifiers.append(contentsOf: (200..<208).map { "record-\($0)" })
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(scroll.isUserScrolling)
    XCTAssertEqual(coordinator.ids.count, 200)
    for _ in 0..<80 where scroll.isUserScrolling || coordinator.ids.count != 208 {
      try await Task.sleep(for: .milliseconds(10))
    }
    let readingOffset = scroll.contentView.bounds.minY
    XCTAssertEqual(readingOffset, bottom - 290, accuracy: 1)
    XCTAssertFalse(coordinator.pinnedToNewest)
    XCTAssertEqual(coordinator.ids.count, 208)
    source.identifiers.append("record-208")
    coordinator.applyItems(scroll: scroll, layout: layout)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(scroll.contentView.bounds.minY, readingOffset, accuracy: 1)
  }

  func testNativeFooterSurvivesZoomRetargetAdoptionAndForcedCleanup() async {
    let source = GestureGridSource(); source.grouped = false
    source.footer = "72 photos, 18 videos"
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 1100))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 198); layout.requestedColumns = 4
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    let window = hostNativeGrid(scroll)
    defer { coordinator.removeZoomStage(); window.orderOut(nil); window.close() }
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    coordinator.updateFooter()
    let label = collection.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == source.footer }!
    let font = label.font, color = label.textColor
    scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, layout.collectionViewContentSize.height - 1100)))
    scroll.reflectScrolledClipView(scroll.contentView); coordinator.pinnedToNewest = true
    let initialInScroll = label.convert(label.bounds, to: scroll)
    coordinator.parent.columns = 9; coordinator.animateLayout(columns: 9)
    guard let stage = coordinator.zoomStage else { XCTFail("Missing zoom stage"); return }
    XCTAssertTrue(label.superview === stage)
    XCTAssertFalse(label.isHidden); XCTAssertEqual(label.stringValue, source.footer)
    XCTAssertEqual(label.font, font); XCTAssertEqual(label.textColor, color)
    let initial = stage.convert(initialInScroll, from: scroll)
    let animation = label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
    let initialY = (animation.values!.first as! NSNumber).doubleValue
      - Double(label.layer!.position.y - label.frame.minY)
    XCTAssertEqual(initialY, Double(initial.minY), accuracy: 0.001)
    XCTAssertGreaterThan(abs(label.frame.minY - initial.minY), 20,
      "A shorter document moves its footer with the content, rather than pinning it to the screen")
    coordinator.updateFooter()
    XCTAssertTrue(label.superview === stage, "An ordinary host update cannot move the label into the hidden collection")
    let releaseStart = CACurrentMediaTime()
    stage.releaseAnimationStarted(at: releaseStart)
    stage.freeze(at: releaseStart + 0.1)
    let interruptedY = label.frame.minY
    coordinator.parent.columns = 3; coordinator.animateLayout(columns: 3)
    XCTAssertTrue(coordinator.zoomStage === stage)
    let continued = label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
    let continuedY = (continued.values!.first as! NSNumber).doubleValue
      - Double(label.layer!.position.y - label.frame.minY)
    XCTAssertEqual(continuedY, Double(interruptedY), accuracy: 0.001)
    stage.advance(to: CACurrentMediaTime() + 3)
    collection.layoutSubtreeIfNeeded()
    guard await waitForNativeAdoption(coordinator) else { return }
    XCTAssertNil(coordinator.zoomStage)
    XCTAssertTrue(label.superview === collection)
    XCTAssertEqual(label.font, font); XCTAssertEqual(label.textColor, color)
    XCTAssertEqual(label.frame.minY, layout.collectionViewContentSize.height - 56 + 14, accuracy: 0.001)
    XCTAssertNil(label.layer!.animation(forKey: "zoom.footer"))
    coordinator.parent.columns = 4; coordinator.animateLayout(columns: 4)
    let replaced = coordinator.zoomStage!
    coordinator.forcedAnchor = true
    coordinator.parent.columns = 6; coordinator.animateLayout(columns: 6)
    XCTAssertFalse(coordinator.zoomStage === replaced)
    XCTAssertTrue(label.superview === coordinator.zoomStage)
    XCTAssertFalse(replaced.ownsFooter(label))
    coordinator.removeZoomStage()
    XCTAssertTrue(label.superview === collection)
    XCTAssertEqual(label.stringValue, source.footer)
  }

  func testFooterReadingPathIgnoresPhotoFadeAndPreservesReanchorAndNativeLanding() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.3, y: 0.7),
      columns: 4, pitch: 176.25, focus: CGPoint(x: 250, y: 320))
    stage.frame = CGRect(x: 0, y: 0, width: width, height: 1100)
    let geometry: (Int) -> LibraryTimelineGeometry = {
      MacGridGeometry.make(count: 90, groups: [:], columns: $0, width: 804)
    }
    stage.referenceSide = { geometry($0).items[0].width }
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 0.6); stage.ensureFace(6, opacity: 0.4)
    let label = NSTextField(labelWithString: "72 photos, 18 videos")
    label.frame = CGRect(x: 0, y: 0, width: width, height: 20)
    let font = label.font
    stage.attachFooter(label, columns: [3, 4, 6, 9]) { columns in
      let g = geometry(columns), anchor = g.items[20]
      return (CGPoint(x: anchor.minX + anchor.width * 0.3, y: anchor.minY + anchor.height * 0.7),
        g.height + 14, 0)
    }
    let before = label.frame, photos = frames(photoViews(stage).filter { $0 !== label })
    stage.reanchor(to: CGPoint(x: 530, y: 440))
    XCTAssertEqual(label.frame.minY, before.minY, accuracy: 0.001)
    assertFrames(photos, equalAfter: photoViews(stage).filter { $0 !== label })
    stage.ensureFace(3, opacity: 0)
    XCTAssertEqual(label.frame.minY, before.minY, accuracy: 0.001)
    let now = CACurrentMediaTime()
    stage.show(3, animated: true, at: now)
    stage.advance(to: now + 0.1)
    XCTAssertEqual(label.frame.minY, before.minY, accuracy: 0.001,
      "Timed photo blending must not move or fade the independent count label")
    XCTAssertEqual(label.alphaValue, 1)
    XCTAssertEqual(label.font, font)
    let reference = stage.contentFocus(columns: 3)!, offset: CGFloat = 100
    stage.hurryBlend(within: GridZoom.releaseFadeDuration, at: now + 0.1)
    stage.settle(with: GridZoom.Settle(start: now + 0.1, pitch: stage.pitch, focus: stage.focus, velocity: 0,
      targetPitch: geometry(3).items[0].width + 2,
      targetFocus: CGPoint(x: reference.x, y: reference.y - offset))) {}
    stage.advance(to: now + 3)
    XCTAssertEqual(label.frame.minY, geometry(3).height + 14 - offset, accuracy: 0.001)
    XCTAssertEqual(label.font, font)
    XCTAssertTrue(CATransform3DIsIdentity(label.layer!.transform))
    stage.stop()
    XCTAssertNil(label.superview)
  }

  func testInterruptedPitchVelocityMatchesTheContinuousSpringDerivative() {
    for velocity: CGFloat in [-500, 0, 300] {
      let model = GridZoom.Settle(start: 10, pitch: 200, focus: .zero, velocity: velocity,
        targetPitch: 134, targetFocus: .zero)
      for elapsed in [0.01, 0.1, 0.3, 0.7] {
        let time = model.start + elapsed, dt = 0.00001
        let derivative = (model.state(at: time + dt).pitch - model.state(at: time - dt).pitch) / CGFloat(2 * dt)
        XCTAssertEqual(model.pitchVelocity(at: time), derivative, accuracy: 0.0001)
      }
    }
  }

  func testFooterWithEqualEndpointsStaysStillDespiteCarriedPhotoVelocityAndIntermediateGaps() {
    for velocity: CGFloat in [-700, 400] {
      let geometry: (Int) -> LibraryTimelineGeometry = {
        MacGridGeometry.make(count: 91, groups: [:], columns: $0, width: 804)
      }
      let stage = MacGridZoomStage(count: 91, anchor: 90, fraction: CGPoint(x: 0.5, y: 1),
        columns: 4, pitch: geometry(4).items[0].width + 2, focus: CGPoint(x: 400, y: 600))
      stage.frame = CGRect(x: 0, y: 0, width: width, height: 1100)
      stage.referenceSide = { geometry($0).items[0].width }
      stage.makeTile = { _, _ in NSView() }
      stage.ensureFace(4, opacity: 0.6); stage.ensureFace(9, opacity: 0.4)
      let label = NSTextField(labelWithString: "91 items")
      label.frame = CGRect(x: 0, y: 0, width: width, height: 20)
      stage.attachFooter(label, columns: [3, 4, 6, 9]) { columns in
        let last = geometry(columns).items[90]
        // Crossing the middle density must not send an otherwise stationary
        // reading label through its different natural photo-to-text gap.
        return (CGPoint(x: last.midX, y: last.maxY), last.maxY + (columns == 6 ? 32 : 30), 0)
      }
      let initialY = label.frame.minY
      XCTAssertEqual(initialY, 630, accuracy: 0.001)
      let requestedStart = CACurrentMediaTime(), releaseStart = requestedStart + 0.2
      stage.settle(with: GridZoom.Settle(start: requestedStart, pitch: stage.pitch,
        focus: stage.focus, velocity: velocity, targetPitch: geometry(9).items[0].width + 2,
        targetFocus: stage.focus)) {}
      stage.releaseAnimationStarted(at: releaseStart)
      let layer = label.layer!, move = layer.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      for value in move.values as! [NSNumber] {
        XCTAssertEqual(CGFloat(value.doubleValue) - layer.position.y + label.frame.minY,
          initialY, accuracy: 0.001)
      }
      stage.freeze(at: releaseStart + 0.08)
      XCTAssertGreaterThan(abs(stage.frozenPitchVelocity), 1)
      XCTAssertEqual(label.frame.minY, initialY, accuracy: 0.001)
      stage.reanchor(to: CGPoint(x: 530, y: 440))
      stage.ensureFace(3, opacity: 0)
      XCTAssertEqual(label.frame.minY, initialY, accuracy: 0.001)

      // A later release starts at that retained reading pose, then lands on
      // the new density's actual document position without retaining an offset.
      let targetY: CGFloat = 780
      let reference = stage.contentFocus(columns: 3)!
      let offset = geometry(3).items[90].maxY + 30 - targetY
      stage.show(3, animated: true)
      let retargetRequest = CACurrentMediaTime(), retargetStart = retargetRequest + 0.35
      stage.settle(with: GridZoom.Settle(start: retargetRequest, pitch: stage.pitch,
        focus: stage.focus, velocity: stage.frozenPitchVelocity,
        targetPitch: geometry(3).items[0].width + 2,
        targetFocus: CGPoint(x: reference.x, y: reference.y - offset))) {}
      stage.releaseAnimationStarted(at: retargetStart)
      let continued = layer.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      let positions = continued.values as! [NSNumber]
      let layerOffset = layer.position.y - label.frame.minY
      XCTAssertEqual(CGFloat(positions.first!.doubleValue) - layerOffset, initialY, accuracy: 0.001)
      XCTAssertEqual(CGFloat(positions.last!.doubleValue) - layerOffset, targetY, accuracy: 0.001)
      let step = 19
      let expected = CGFloat(positions[step].doubleValue) - layerOffset
      stage.freeze(at: retargetStart
        + continued.duration * Double(step) / Double(positions.count - 1))
      XCTAssertEqual(label.frame.minY, expected, accuracy: 0.001,
        "Freeze must use the reading spring's shifted clock, rather than the photo pitch path")
      stage.reanchor(to: CGPoint(x: 250, y: 520))
      stage.render()
      XCTAssertEqual(label.frame.minY, expected, accuracy: 0.001)
      let finalReference = stage.contentFocus(columns: 3)!
      stage.settle(with: GridZoom.Settle(start: CACurrentMediaTime(), pitch: stage.pitch,
        focus: stage.focus, velocity: 0, targetPitch: geometry(3).items[0].width + 2,
        targetFocus: CGPoint(x: finalReference.x, y: finalReference.y - offset))) {}
      stage.advance(to: CACurrentMediaTime() + 3)
      XCTAssertEqual(label.frame.minY, targetY, accuracy: 0.001)
      stage.render()
      XCTAssertEqual(label.frame.minY, targetY, accuracy: 0.001)
      stage.stop()
      XCTAssertNil(label.superview)
    }
  }
}

@MainActor private final class GestureGridSource: MacDenseGridSource {
  var identifiers = (0..<90).map { "gesture-\($0)" }
  var fetchResult: MacGridFetchResult { MacGridFetchResult(identifiers: identifiers) }
  var contextID = "gesture-test"
  var contentRevision = "1"
  var preservesViewportDuringLiveUpdates = false
  var selection = Set<String>()
  var introduction: AnyView?
  var grouped = true
  var footer = ""
  var includesOverview = false
  var zoomImage: NSImage?
  var zoomStops: [Int] { includesOverview ? MacLibraryDensity.columns : MacLibraryDensity.grid }
  let scroll = MacGridScrollState()
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  var groups: [Int: String] { grouped ? [0: "First", 12: "Second", 24: "Third", 36: "Fourth", 48: "Fifth"] : [:] }
  func introduction(at index: Int) -> AnyView? { index == 0 ? introduction : nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    introduction.map { [0: MacGridSectionHeader.fittingHeight(introduction: $0, width: width)] } ?? [:]
  }
  func date(_ id: String) -> Date? { nil }
  func fact(_ id: String) -> MacThumbnailTables.Fact? {
    includesOverview ? .init(key: id, date: nil) : nil
  }
  func zoomTile(_ id: String, side: CGFloat, scale: CGFloat, originalAspect: Bool) -> NSView {
    let tile = MacSourceZoomTile(frame: CGRect(x: 0, y: 0, width: side, height: side))
    configure(tile.cell, id: id, pixels: side * scale, originalAspect: originalAspect)
    if let zoomImage { tile.cell.retainDisplayedImage(zoomImage) }
    return tile
  }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    cell.configureUnavailable(id: id, label: id, video: false)
  }
}

@MainActor private final class DeferredGridCollectionView: LibraryCollectionView {
  var defersNativeLayout = false
  private(set) var deferredItemQueries = 0
  override func item(at indexPath: IndexPath) -> NSCollectionViewItem? {
    if defersNativeLayout { deferredItemQueries += 1; return nil }
    return super.item(at: indexPath)
  }
  override func layout() { if !defersNativeLayout { super.layout() } }
}

@MainActor private final class DeferredCaptionCollectionView: LibraryCollectionView {
  var blockedKind: String?
  private(set) var blockedQueries = 0
  override func supplementaryView(forElementKind elementKind: NSCollectionView.SupplementaryElementKind,
    at indexPath: IndexPath) -> (NSView & NSCollectionViewElement)? {
    if elementKind == blockedKind { blockedQueries += 1; return nil }
    return super.supplementaryView(forElementKind: elementKind, at: indexPath)
  }
}

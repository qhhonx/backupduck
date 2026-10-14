import XCTest

@testable import BackupDuck

final class CalendarGridTests: XCTestCase {
  @MainActor func testMediaPosterReplacementKeepsAssetFittedRectangle() {
    let media = MediaZoomScroll(frame: CGRect(x: 0,y: 0,width: 390,height: 650))
    media.mediaSize = CGSize(width: 3024,height: 4032)
    media.photo.image = UIGraphicsImageRenderer(size: CGSize(width: 128,height: 128)).image { _ in }
    media.layoutIfNeeded()
    let original = media.media.frame, originalInset = media.contentInset
    media.photo.image = UIGraphicsImageRenderer(size: CGSize(width: 600,height: 800)).image { _ in }
    media.setNeedsLayout(); media.layoutIfNeeded()
    XCTAssertEqual(media.media.frame,original,"The cropped grid poster cannot determine the detail aspect ratio")
    XCTAssertEqual(media.contentInset,originalInset)
    XCTAssertEqual(media.media.bounds.width/media.media.bounds.height,0.75,accuracy: 0.001)
    media.media.transform = CGAffineTransform(translationX: 30,y: 80).scaledBy(x: 0.92,y: 0.92)
    XCTAssertEqual(media.frame,CGRect(x: 0,y: 0,width: 390,height: 650),"Only media moves; the letterboxed viewport stays fixed")
    XCTAssertEqual(media.media.transform.ty,80)
  }
  func testCalendarHierarchyKeepsEveryMemberAndCoverWithinItsPeriod() {
    let calendar = Calendar(identifier: .gregorian)
    let assets = (0..<120).map { i in
      CalendarGridAsset(
        id: "asset-\(i)",
        date: calendar.date(
          from: DateComponents(year: 2023 + i / 60, month: 1 + i % 60 / 10, day: 1 + i % 10 / 2)),
        aspect: 1.5)
    }
    for level in [CalendarGridLevel.years, .months, .all] {
      let g = CalendarGridGeometry(
        assets: assets, level: level, width: 390, columns: 5, originalAspect: false)
      XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(), Array(assets.indices))
      XCTAssertTrue(g.tiles.allSatisfy { $0.members.contains($0.asset) })
      XCTAssertTrue(g.tiles.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= 391 })
      for y in stride(from: 0.0, to: Double(g.height), by: 500) {
        let viewport = CGRect(x: 0, y: y, width: 390, height: 500)
        let range = g.visible(in: viewport)
        for i in g.tiles.indices where g.tiles[i].frame.intersects(viewport) {
          XCTAssertTrue(
            range.contains(i), "A tall hero tile must remain visible alongside shorter mosaic tiles"
          )
        }
      }
    }
  }
  func testMonthSamplingCapsCoversAndRetainsEveryDayMember() {
    let calendar = Calendar(identifier:.gregorian)
    let assets = (0..<62).map { i in CalendarGridAsset(id:"day-\(i)",
      date:calendar.date(from:DateComponents(year:2026,month:1+6*(i/31),day:1+i%31)),aspect:1) }
    let g = CalendarGridGeometry(assets:assets,level:.months,width:402,columns:3,originalAspect:false)
    XCTAssertEqual(g.tiles.count,12)
    XCTAssertEqual(g.headings.count,2)
    XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(),Array(assets.indices))
    XCTAssertTrue(g.tiles.allSatisfy { $0.members.contains($0.asset) })
    XCTAssertTrue(g.tiles.contains { $0.members.contains(61) })
  }
  @MainActor func testPeriodButtonsAdoptDestinationSizeBeforeLatestAnchor() {
    let c = CalendarGridController()
    let calendar = Calendar(identifier:.gregorian)
    c.assets = (0..<7000).map { i in CalendarGridAsset(id:"day-\(i)",
      date:calendar.date(byAdding:.day,value:i,to:Date(timeIntervalSince1970:1200000000)),aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    for level in [CalendarGridLevel.months,.years,.all,.years] {
      c.changeLevel(level,asset:6990,from:nil)
      c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
      let tile = c.layout.geometry.tiles.firstIndex { $0.members.contains(6990) }!
      let frame = c.layout.frame(tile).offsetBy(dx:0,dy:-c.grid.contentOffset.y)
      XCTAssertTrue(frame.intersects(c.grid.frame),"Period controls keep the recent photo's period visible")
      XCTAssertGreaterThan(c.grid.contentOffset.y,1000)
      XCTAssertEqual(c.grid.contentSize.height,c.layout.geometry.height,accuracy:0.1)
    }
  }
  @MainActor func testButtonChainKeepsItsFocalPhotoWhenYearCardsCannotCenterAtEnd() {
    let c = CalendarGridController()
    c.assets = (0..<55000).map { i in CalendarGridAsset(id:"photo-\(i)",
      date:Date(timeIntervalSince1970:1577836800+Double(i)*2700),aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let focal = c.focusedAsset()
    c.dock.selectedSegmentIndex = CalendarGridLevel.months.rawValue; c.levelChosen()
    c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertEqual(c.focusedAsset(),focal)
    c.dock.selectedSegmentIndex = CalendarGridLevel.years.rawValue; c.levelChosen()
    c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertEqual(c.focusedAsset(),focal,"End-clamped year cards must not replace the navigation context with the previous year")
    c.dock.selectedSegmentIndex = CalendarGridLevel.all.rawValue; c.levelChosen()
    c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertTrue(c.grid.indexPathsForVisibleItems.contains { c.layout.geometry.tiles[$0.item].asset > 54000 })
  }
  @MainActor func testLoadingHeaderAdoptsMediaContrastWithoutWaitingForResize() {
    let c = CalendarGridController(); c.loadViewIfNeeded()
    c.view.frame = CGRect(x:0,y:0,width:402,height:874); c.view.layoutIfNeeded()
    c.replaceAssets([CalendarGridAsset(id:"photo",date:nil,aspect:1)])
    XCTAssertEqual(c.titleLabel.textColor,UIColor.white)
    XCTAssertEqual(c.subtitleLabel.textColor,UIColor.white.withAlphaComponent(0.92))
    c.view.layoutIfNeeded()
    XCTAssertEqual(c.subtitleLabel.frame.minX,c.titleLabel.convert(c.titleLabel.bounds,to:c.view).minX,accuracy:0.1)
  }
  func testDensityChangesKeepIdentityAndOriginalAspectDoesNotChangeMembership() {
    let assets = (0..<900).map {
      CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: $0 % 2 == 0 ? 0.7 : 1.8)
    }
    for columns in [1, 3, 5, 10, 20, 30] {
      for aspect in [false, true] {
        let g = CalendarGridGeometry(
          assets: assets, level: .all, width: 390, columns: columns, originalAspect: aspect)
        XCTAssertEqual(g.tiles.map(\.id), assets.map(\.id))
        XCTAssertEqual(g.tiles.map(\.members.lowerBound), Array(assets.indices))
        XCTAssertTrue(g.height > 0)
      }
    }
  }
  func testAnchoredColumnsRetainEveryAssetAndBoundHorizontalTravel() {
    let assets = (0..<1200).map { CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: 1) }
    let anchor = 609
    let width: CGFloat = 402
    let source = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: 3, originalAspect: false)
    let point = source.tiles[anchor].frame.midX
    let side = (width - 8) / 5
    let column = Int(round((point - side * 0.5) / (side + 2)))
    let leading = (column - anchor % 5 + 5) % 5
    let destination = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: 5, originalAspect: false,
      leadingSlots: leading)
    XCTAssertEqual(destination.tiles.map(\.id), assets.map(\.id))
    XCTAssertLessThanOrEqual(abs(destination.tiles[anchor].frame.midX - point), side * 0.5 + 2)
    XCTAssertNotEqual(
      CalendarGridController.geometryKey(.all, width: width, columns: 5, aspect: false),
      CalendarGridController.geometryKey(
        .all, width: width, columns: 5, aspect: false, leading: leading))
  }
  @MainActor func testSelectionMarksOnlySelectedMediaAndKeepsZeroPromptCompact() {
    let cell = CalendarGridCell(frame: CGRect(x: 0, y: 0, width: 130, height: 130))
    cell.selection(false, enabled: true)
    XCTAssertTrue(cell.check.isHidden)
    cell.selection(true, enabled: true)
    XCTAssertFalse(cell.check.isHidden)
    cell.selection(true, enabled: false)
    XCTAssertTrue(cell.check.isHidden)
    let controls = CalendarSelectionControls(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
    controls.countButton.setTitle("Select Items", for: .normal)
    controls.layoutIfNeeded()
    XCTAssertLessThan(controls.countButton.frame.width, 300)
    XCTAssertEqual(controls.countButton.frame.midX, 201)
  }
  @MainActor func testSnapshotSettlePreservesPreparedDestinationCellAndPixels() throws {
    let c = CalendarGridController()
    c.assets = (0..<100).map { CalendarGridAsset(id: "test-\($0)", date: nil, aspect: 1) }
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
      UIColor.systemBlue.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    c.requestImage = { _, _, done in
      done(image, false)
      return {}
    }
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout()
    c.view.layoutIfNeeded()
    c.beginSceneZoom(point: CGPoint(x: 201, y: c.grid.bounds.midY))
    c.prepareZoomDestination(.all, columns: 5)
    let path = try XCTUnwrap(c.grid.indexPathsForVisibleItems.first)
    let cell = try XCTUnwrap(c.grid.cellForItem(at: path) as? CalendarGridCell)
    XCTAssertNotNil(cell.image.image)
    c.zoomSourceColumns = 3
    c.zoomDestinationColumns = 5
    c.zoomProgress = 1
    c.zoomReleaseColumns = 5
    c.finishSceneZoom(commit: true)
    c.spring?.stopAnimation(false)
    c.spring?.finishAnimation(at: .end)
    XCTAssertTrue(
      c.grid.cellForItem(at: path) === cell,
      "Snapshot settling must not replace prepared media cells")
    XCTAssertTrue(cell.image.image === image)

  }
  @MainActor func testDestinationSnapshotKeepsLatestWindowBeforeAndAfterNativeReload() throws {
    let c = CalendarGridController()
    c.assets = (0..<10000).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let red = UIGraphicsImageRenderer(size: CGSize(width:64,height:64),format: format).image { ctx in
      UIColor.red.setFill(); ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    }
    let green = UIGraphicsImageRenderer(size: CGSize(width:64,height:64),format: format).image { ctx in
      UIColor.green.setFill(); ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    }
    var requested: [Int] = []
    c.requestImage = { asset,_,done in
      let i = Int(asset.id.dropFirst(6))!; requested.append(i)
      done(i < 5000 ? red : green,false); return {}
    }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded(); c.locateAsset(9970)
    c.beginSceneZoom(item:9970)
    requested.removeAll()
    c.continuousZoom(scale:0.6)
    let target = try XCTUnwrap(c.zoomFrames[5])
    XCTAssertGreaterThan(target.viewport.minY,100000)
    XCTAssertTrue(requested.allSatisfy { $0 > 9000 },"Warm only the destination near the focal photo")
    // A delayed native reload may temporarily expose a different window. The
    // canonical scene still resolves its own rectangle and stable photo IDs.
    c.grid.setContentOffset(.zero,animated:false); c.grid.layoutIfNeeded()
    let image = c.sceneImage(viewport:target.viewport)
    let pixel = image.cgImage!.dataProvider!.data! as Data
    let cg = image.cgImage!, x = cg.width/2, y = cg.height/2
    let offset = y*cg.bytesPerRow+x*4
    let channels = Array(pixel[offset..<offset+3])
    XCTAssertGreaterThan(channels[1],240)
    XCTAssertLessThan(channels[0],15)
    c.finishSceneZoom(commit:true)
    c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertEqual(c.columns,5)
    XCTAssertGreaterThan(c.grid.contentOffset.y,100000)
  }

  @MainActor func testBriefPinchConsumesScaleAtRecognitionBeforeRelease() {
    let c = CalendarGridController()
    c.assets = (0..<1000).map { CalendarGridAsset(id:"asset-\($0)",date:nil,aspect:1) }
    c.columns = 1
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    c.beginSceneZoom(item:990)
    c.updatePinch(scale:0.8)
    c.finishSceneZoom(commit:true)
    c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertEqual(c.columns,3,"A recognized short pinch must adopt its already-visible destination")
  }

  @MainActor func testSlowPinchDirectionDoesNotDependOnDisplayCallbackCadence() {
    let c = CalendarGridController()
    c.assets = (0..<1000).map { CalendarGridAsset(id:"asset-\($0)",date:nil,aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    c.beginSceneZoom(item:990)
    for i in 1...200 { c.continuousZoom(scale:1+CGFloat(i)/1000) }
    XCTAssertEqual(c.zoomReleaseColumns,1,"Slow outward movement accumulates across frames")
    c.finishSceneZoom(commit:true); c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertEqual(c.columns,1)
    c.beginSceneZoom(item:990)
    for i in 1...200 { c.continuousZoom(scale:1-CGFloat(i)/1000) }
    XCTAssertEqual(c.zoomReleaseColumns,3,"The next gesture cannot inherit the preceding outward direction")
    c.finishSceneZoom(commit:true); c.spring?.stopAnimation(false); c.spring?.finishAnimation(at:.end)
    XCTAssertEqual(c.columns,3)
  }

  @MainActor func testSnapshotPaintsResolvedImagesBeforeHiddenLayersCommit() throws {
    let c = CalendarGridController()
    c.assets = (0..<100).map { CalendarGridAsset(id:"asset-\($0)",date:nil,aspect:1) }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let green = UIGraphicsImageRenderer(size:CGSize(width:64,height:64),format:format).image { ctx in
      UIColor.green.setFill(); ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    }
    c.requestImage = { _,_,done in done(green,false); return {} }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    c.beginSceneZoom(item:90); c.prepareZoomDestination(.all,columns:5)
    for case let cell as CalendarGridCell in c.grid.visibleCells {
      cell.image.layer.contents = nil
      XCTAssertNotNil(cell.image.image)
    }
    let image = c.sceneImage().cgImage!, bytes = image.dataProvider!.data! as Data
    let offset = image.height/2*image.bytesPerRow+image.width/2*4
    XCTAssertGreaterThan(bytes[offset+1],240,"Snapshot pixels do not depend on a hidden view's pending layer display")
    XCTAssertLessThan(bytes[offset],15)
    c.stopMotion()
  }

  func testMonthMosaicsCoverOneThroughSixAndMirrorWithoutOverlap() {
    let calendar = Calendar(identifier: .gregorian)
    for month in [1, 2] {
      for count in 1...31 {
        let assets = (1...count).map { day in
          CalendarGridAsset(
            id: "day-\(day)",
            date: calendar.date(from: DateComponents(year: 2026, month: month, day: day)), aspect: 1
          )
        }
        let g = CalendarGridGeometry(
          assets: assets, level: .months, width: 402, columns: 3, originalAspect: false)
        XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(), Array(assets.indices))
        for (i, tile) in g.tiles.enumerated() {
          XCTAssertGreaterThanOrEqual(tile.frame.minX, 19.999)
          XCTAssertLessThanOrEqual(tile.frame.maxX, 382.1)
          for other in g.tiles.dropFirst(i + 1) {
            XCTAssertFalse(tile.frame.intersects(other.frame))
          }
        }
        if count == 2 {
          XCTAssertEqual(g.tiles[0].frame.height / g.tiles[0].frame.width, 4.0 / 3, accuracy: 0.01)
        }
        if count == 3 {
          let hero = g.tiles.max { $0.frame.width < $1.frame.width }!
          XCTAssertEqual(hero.asset, month == 1 ? 0 : 2)
        }
      }
    }
  }
  @MainActor func testDensePeriodCaptionsAvoidOverlapAtShortBoundaries() {
    let assets = (0..<100).map { i in
      CalendarGridAsset(
        id: "year-\(i)",
        date: Calendar.current.date(from: DateComponents(year: 2000 + i / 5, month: 1, day: 1)),
        aspect: 1)
    }
    let layout = CalendarGridLayout()
    layout.geometry = CalendarGridGeometry(
      assets: assets, level: .all, width: 402, columns: 20, originalAspect: false)
    let grid = UICollectionView(
      frame: CGRect(x: 0, y: 0, width: 402, height: 874), collectionViewLayout: layout)
    _ = grid
    let captions = layout.visibleHeadings(in: CGRect(x: 0, y: 0, width: 402, height: 874))
      .compactMap { layout.heading($0)?.frame }
    for i in 1..<captions.count {
      XCTAssertGreaterThanOrEqual(captions[i].minY, captions[i - 1].maxY + 10)
    }
    XCTAssertLessThan(captions.count, layout.geometry.headings.count)
  }
  @MainActor func testSnapshotZoomKeepsDestinationGeometryFixedAndCancelRestoresContext() throws {
    let c = CalendarGridController()
    c.assets = (0..<300).map { CalendarGridAsset(id: "photo-\($0)", date: nil, aspect: 1) }
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout()
    c.view.layoutIfNeeded()
    let offset = c.grid.contentOffset
    c.beginSceneZoom(point: CGPoint(x: 201, y: c.grid.bounds.midY))
    c.prepareZoomDestination(.all, columns: 5)
    let frame = c.layout.frame(200)
    let scene = try XCTUnwrap(c.zoomScene)
    scene.apply(0.2)
    let startScale = scene.source.transform.a
    scene.apply(0.8)
    XCTAssertNotEqual(scene.source.transform.a, startScale)
    XCTAssertEqual(
      c.layout.frame(200), frame, "Held scale changes snapshots, not individual photo positions")
    c.finishSceneZoom(commit: false)
    c.spring?.stopAnimation(false)
    c.spring?.finishAnimation(at: .end)
    XCTAssertEqual(c.columns, 3)
    XCTAssertEqual(c.grid.contentOffset, offset)
    XCTAssertNil(c.zoomScene)
    XCTAssertTrue(c.grid.panGestureRecognizer.isEnabled)
    XCTAssertEqual(c.columnStops.last, 20, "The year overview is the terminal zoom level")
  }
  @MainActor func testHeldPinchCrossesSeveralStopsAndReversesAroundOneAsset() throws {
    let c = CalendarGridController()
    c.assets = (0..<500).map { CalendarGridAsset(id: "photo-\($0)", date: nil, aspect: 1) }
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout()
    c.view.layoutIfNeeded()
    c.beginSceneZoom(point: CGPoint(x: 201, y: c.grid.bounds.midY))
    let focus = c.anchorPoint
    let photo = c.zoomStartAsset
    c.continuousZoom(scale: 0.2)
    XCTAssertEqual(c.zoomDestinationColumns, 20)
    XCTAssertEqual(c.zoomStartAsset, photo)
    XCTAssertEqual(c.anchorPoint, focus)
    c.continuousZoom(scale: 0.65)
    XCTAssertEqual(c.zoomSourceColumns, 3)
    XCTAssertEqual(c.zoomDestinationColumns, 5)
    XCTAssertEqual(c.zoomStartAsset, photo)
    XCTAssertEqual(c.anchorPoint, focus)
    XCTAssertLessThanOrEqual(c.zoomFrames.count, 3)
    c.finishSceneZoom(commit: false)
    c.spring?.stopAnimation(false)
    c.spring?.finishAnimation(at: .end)
    XCTAssertEqual(c.columns, 3)
    XCTAssertNil(c.zoomScene)
  }

  @MainActor func testVisiblePinchDestinationSettlesWithoutRevertingAndKeepsFocalPhoto() throws {
    for scale in [CGFloat(1.2),CGFloat(0.9)] {
      let c = CalendarGridController()
      c.assets = (0..<500).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
      c.loadViewIfNeeded(); c.view.frame = CGRect(x: 0,y: 0,width: 402,height: 874)
      c.view.setNeedsLayout(); c.view.layoutIfNeeded()
      c.grid.contentOffset.y = c.clampedOffset(6000)
      c.beginSceneZoom(point: CGPoint(x: 201,y: c.grid.contentOffset.y+400))
      let photo = c.zoomStartAsset
      c.continuousZoom(scale: scale)
      XCTAssertEqual(c.zoomReleaseColumns,scale > 1 ? 1 : 5)
      c.finishSceneZoom(commit: true); c.spring?.stopAnimation(false); c.spring?.finishAnimation(at: .end)
      XCTAssertEqual(c.columns,scale > 1 ? 1 : 5)
      let tile = try XCTUnwrap(c.layout.geometry.tiles.firstIndex { $0.asset == photo })
      let f = c.layout.frame(tile)
      XCTAssertEqual(f.minY+f.height*c.anchorFraction.y-c.grid.contentOffset.y,400,accuracy: 1)
      XCTAssertNil(c.zoomScene); XCTAssertEqual(c.grid.transform,.identity)
    }
  }
  @MainActor func testSelectionKeepsHierarchyAndPinchInputOwnership() {
    let c = CalendarGridController(); c.assets = (0..<60).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x: 0,y: 0,width: 402,height: 874); c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    c.level = .months; c.toggleSelection()
    XCTAssertEqual(c.level,.months); XCTAssertTrue(c.selecting)
    c.level = .all; c.columns = 20; c.toggleSelection(); c.toggleSelection()
    XCTAssertEqual(c.columns,20); XCTAssertTrue(c.selecting)
    XCTAssertTrue(c.gestureRecognizerShouldBegin(UIPinchGestureRecognizer()))
    c.density(columns: 5,at: 30); c.spring?.stopAnimation(false); c.spring?.finishAnimation(at: .end)
    XCTAssertEqual(c.columns,5); XCTAssertTrue(c.selecting)
  }

}

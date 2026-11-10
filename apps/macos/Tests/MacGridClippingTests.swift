import AppKit
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class MacGridClippingTests: XCTestCase {
  private struct Fixture {
    let stage: MacGridZoomStage
    let label: NSTextField
    let geometry: (Int) -> LibraryTimelineGeometry
    let pitch: (Int) -> CGFloat
  }
  private struct PillPose {
    let layer: CALayer
    let parent: CALayer?
    let position: CGPoint
    let bounds: CGRect
    let opacity: Float
  }

  private func fixture(count: Int, width: CGFloat, columns: Int, sourceMarks: Bool? = nil,
    fitted: Bool = false) -> Fixture {
    let geometry: (Int) -> LibraryTimelineGeometry = { columns in
      let dense = MacLibraryDensity.isDense(columns)
      return LibraryTimelineGeometry(dates: Array(repeating: nil, count: count), mode: .all,
        width: width, target: 135, inset: dense ? 0 : 2, gap: dense ? 0 : 2,
        headerHeight: 44, columns: columns)
    }
    let pitch: (Int) -> CGFloat = { columns in
      geometry(columns).items[0].width + (MacLibraryDensity.isDense(columns) ? 0 : 2)
    }
    let first = geometry(columns).items[0]
    let stage = MacGridZoomStage(count: count, anchor: 0, fraction: .zero, columns: columns,
      pitch: pitch(columns), focus: first.origin)
    stage.frame = CGRect(x: 0, y: 0, width: width, height: 900)
    stage.referenceSide = { geometry($0).items[0].width }
    let pipeline = sourceMarks.map { _ in ThumbnailPipeline() }
    stage.makeTile = { index, side in
      if let sourceMarks, let pipeline {
        if sourceMarks {
          let tile = MacSourceZoomTile(frame: CGRect(x: 0, y: 0, width: side, height: side))
          tile.cell.configure(CatalogLibraryAsset(1), pipeline: pipeline, pixels: side * 2, originalAspect: fitted)
          tile.cell.setGroup(count: nil, state: "sending")
          return tile
        }
        let tile = MacZoomMediaTile(frame: CGRect(x: 0, y: 0, width: side, height: side))
        tile.configure(CatalogLibraryAsset(1), side: side, pixels: side * 2, pipeline: pipeline,
          originalAspect: fitted, selected: false, scale: 2)
        return tile
      }
      let tile = NSView(); tile.identifier = NSUserInterfaceItemIdentifier("photo-\(index)")
      return tile
    }
    stage.releaseTile = {
      ($0 as? MacZoomMediaTile)?.cancel()
      ($0 as? MacSourceZoomTile)?.cancel()
    }
    stage.denseFact = { .init(key: "clip-\($0)", date: Date(timeIntervalSince1970: 1_700_000_000)) }
    stage.ensureFace(columns, opacity: 1)
    let label = NSTextField(labelWithString: "\(count) items")
    label.frame = CGRect(x: 0, y: 0, width: width, height: 20)
    stage.attachFooter(label, columns: [3, 4, 6, 9, 20, 40]) {
      (geometry($0).items[0].origin, geometry($0).height + 14, 0)
    }
    return Fixture(stage: stage, label: label, geometry: geometry, pitch: pitch)
  }

  private func release(_ f: Fixture, to columns: Int, velocity: CGFloat,
    startEvent: Bool = true) -> CFTimeInterval {
    f.stage.ensureFace(columns, opacity: 0)
    f.stage.show(columns, animated: true)
    f.stage.hurryBlend(within: GridZoom.releaseFadeDuration)
    let requested = CACurrentMediaTime(), started = requested + 0.2
    let reference = f.stage.contentFocus(columns: columns)!
    f.stage.settle(with: GridZoom.Settle(start: requested, pitch: f.stage.pitch, focus: f.stage.focus,
      velocity: velocity, targetPitch: f.pitch(columns), targetFocus: reference)) {}
    if startEvent { f.stage.releaseAnimationStarted(at: started) }
    return started
  }

  private func faces(_ stage: MacGridZoomStage) -> [NSView] {
    stage.subviews.filter { !($0 is NSTextField) && !($0 is MacGridSectionHeader) }
  }
  private func attachedMarks(_ stage: MacGridZoomStage) -> Set<ObjectIdentifier> {
    Set(faces(stage).flatMap(macGridPhotoChildren).compactMap { $0 as? MacGridReadingTile }
      .flatMap(\.readingMarkLayers).map(ObjectIdentifier.init))
  }
  private func assertNativeFrame(_ actual: CGRect, _ expected: CGRect,
    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000001, file: file, line: line)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000001, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: 0.000001, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: 0.000001, file: file, line: line)
  }

  private func clip(_ face: NSView) -> CALayer? {
    if let canvas = macGridPhotoChildren(face).first as? MacDenseCanvas { return canvas.photoClippingLayer }
    return (face.subviews.first { $0 is MacGridPhotoPlane })?.layer?.mask
  }

  private func pillPoses(_ photoFaces: [NSView], sample: Int) -> [PillPose] {
    photoFaces.compactMap { macGridPhotoChildren($0).first as? MacDenseCanvas }.flatMap { canvas in
      (canvas.periodReadingLayer.sublayers ?? []).map { pill in
        let movement = pill.animation(forKey: "zoom.pill") as? CAKeyframeAnimation
        let visibility = pill.animation(forKey: "zoom.visibility") as? CAKeyframeAnimation
        let position = (movement?.values?[sample] as? NSValue)?.pointValue ?? pill.position
        let opacity = (visibility?.values?[sample] as? NSNumber)?.floatValue ?? pill.opacity
        return PillPose(layer: pill, parent: pill.superlayer, position: position, bounds: pill.bounds, opacity: opacity)
      }
    }
  }

  private func assertPillPoses(_ poses: [PillPose], file: StaticString = #filePath, line: UInt = #line) {
    for pose in poses {
      XCTAssertTrue(pose.layer.superlayer === pose.parent, "A reading pill was replaced or reparented", file: file, line: line)
      XCTAssertEqual(pose.layer.position.x, pose.position.x, accuracy: 0.001, file: file, line: line)
      XCTAssertEqual(pose.layer.position.y, pose.position.y, accuracy: 0.001, file: file, line: line)
      XCTAssertEqual(pose.layer.bounds, pose.bounds, file: file, line: line)
      XCTAssertEqual(pose.layer.opacity, pose.opacity, accuracy: 0.001, file: file, line: line)
    }
  }

  private func springValue(_ layer: CALayer, key: String, elapsed: CFTimeInterval) -> CGFloat {
    let current = CGFloat((layer.value(forKeyPath: key) as? NSNumber)?.doubleValue ?? 0)
    func sample(_ a: CASpringAnimation) -> CGFloat {
      let from = CGFloat((a.fromValue as! NSNumber).doubleValue)
      let to = CGFloat((a.toValue as! NSNumber).doubleValue)
      let rate = CGFloat(sqrt(a.stiffness / a.mass)), time = CGFloat(elapsed)
      let speed = CGFloat(a.initialVelocity) * (to - from)
      return to + (from - to + (speed + rate * (from - to)) * time) * exp(-rate * time)
    }
    guard let a = layer.animation(forKey: "zoom." + key) as? CASpringAnimation else { return current }
    if a.isAdditive {
      let second = layer.animation(forKey: "zoom.velocity." + key) as! CASpringAnimation
      return current + sample(a) + sample(second)
    }
    return sample(a)
  }

  private func rectangles(_ face: NSView, elapsed: CFTimeInterval) -> [CGRect] {
    if let canvas = macGridPhotoChildren(face).first as? MacDenseCanvas {
      let photos = canvas.photoContentLayer
      let origin = CGPoint(x: springValue(photos, key: "position.x", elapsed: elapsed),
        y: springValue(photos, key: "position.y", elapsed: elapsed))
      let scale = CGPoint(x: springValue(photos, key: "transform.scale.x", elapsed: elapsed),
        y: springValue(photos, key: "transform.scale.y", elapsed: elapsed))
      return (photos.sublayers ?? []).map { tile in
        let w = tile.bounds.width * springValue(tile, key: "transform.scale.x", elapsed: elapsed)
        let h = tile.bounds.height * springValue(tile, key: "transform.scale.y", elapsed: elapsed)
        return CGRect(x: origin.x + (springValue(tile, key: "position.x", elapsed: elapsed) - w * tile.anchorPoint.x) * scale.x,
          y: origin.y + (springValue(tile, key: "position.y", elapsed: elapsed) - h * tile.anchorPoint.y) * scale.y,
          width: w * scale.x, height: h * scale.y)
      }
    }
    return macGridPhotoChildren(face).compactMap { tile in
      guard let layer = tile.layer else { return nil }
      let w = springValue(layer, key: "bounds.size.width", elapsed: elapsed)
      let h = springValue(layer, key: "bounds.size.height", elapsed: elapsed)
      return CGRect(x: springValue(layer, key: "position.x", elapsed: elapsed) - w * layer.anchorPoint.x,
        y: springValue(layer, key: "position.y", elapsed: elapsed) - h * layer.anchorPoint.y, width: w, height: h)
    }
  }

  private func readingValue(_ layer: CALayer, key: String, step: Int, elapsed: CFTimeInterval) -> CGFloat {
    let animationKey = key == "opacity" ? "zoom.readingOpacity" : "zoom." + key
    if let track = layer.animation(forKey: animationKey) as? CAKeyframeAnimation {
      return CGFloat((track.values![step] as! NSNumber).doubleValue)
    }
    return springValue(layer, key: key, elapsed: elapsed)
  }
  private func linearValue(_ track: CAKeyframeAnimation, sample: Double) -> CGFloat {
    let values = track.values as! [NSNumber]
    let lower = max(0, min(values.count - 1, Int(floor(sample))))
    let upper = min(values.count - 1, lower + 1), t = CGFloat(sample - Double(lower))
    return CGFloat(truncating: values[lower]) * (1 - t) + CGFloat(truncating: values[upper]) * t
  }
  private func scalar(_ layer: CALayer, key: String, sample: Double, prefix: String = "zoom.") -> CGFloat {
    if let track = layer.animation(forKey: prefix + key) as? CAKeyframeAnimation {
      return linearValue(track, sample: sample)
    }
    return CGFloat((layer.value(forKeyPath: key) as? NSNumber)?.doubleValue ?? 0)
  }
  private func glyphRect(_ mark: CALayer, sample: Double, height: CGFloat) -> CGRect {
    let width = scalar(mark, key: "bounds.size.width", sample: sample), h = mark.bounds.height
    let x = scalar(mark, key: "position.x", sample: sample) - mark.anchorPoint.x * width
    let y = scalar(mark, key: "position.y", sample: sample) - mark.anchorPoint.y * h
    let plate = CGRect(x: x, y: height - y - h, width: width, height: h)
    if let text = mark as? MacTextBadgeLayer {
      let glyph = text.readingGlyphLayer, bitmap = glyph.contents as! CGImage
      let size = CGSize(width: CGFloat(bitmap.width) / glyph.contentsScale, height: CGFloat(bitmap.height) / glyph.contentsScale)
      let cx = scalar(glyph, key: "position.x", sample: sample, prefix: "zoom.readingGlyph.")
      return CGRect(x: plate.minX + cx - size.width / 2, y: plate.maxY - glyph.position.y - size.height / 2,
        width: size.width, height: size.height)
    }
    if mark is MacBadgeLayer, let glyph = mark.sublayers?.first {
      return CGRect(x: plate.minX + glyph.frame.minX, y: plate.maxY - glyph.frame.maxY,
        width: glyph.frame.width, height: glyph.frame.height)
    }
    return plate
  }

  /// Measure actual queued layer geometry, including the pre-existing X/size
  /// springs, rather than repeating the reading-layout helper's calculation.
  private func assertWholeReadingMarks(_ f: Fixture) -> (clamped: Bool, faded: Bool) {
    let footer = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
    var clamped = false, faded = false, durationCount = 0
    for face in faces(f.stage) {
      let boundary = clip(face)!.animation(forKey: "zoom.footerClip") as! CAKeyframeAnimation
      for tile in macGridPhotoChildren(face) {
        guard let reading = tile as? MacGridReadingTile, let root = tile.layer else { continue }
        for mark in reading.readingMarkLayers {
          let readingPlane = face.subviews.first { !($0 is MacGridPhotoPlane) && !($0 is MacDenseCanvas) }!
          XCTAssertTrue(mark.superlayer === readingPlane.layer)
          XCTAssertTrue(readingPlane.superview === face)
          XCTAssertFalse(readingPlane.isFlipped)
          XCTAssertNil(readingPlane.layer?.mask)
          let y = mark.animation(forKey: "zoom.position.y") as! CAKeyframeAnimation
          let opacity = mark.animation(forKey: "zoom.readingOpacity") as! CAKeyframeAnimation
          XCTAssertEqual(y.values!.count, 73); XCTAssertEqual(opacity.values!.count, 73)
          XCTAssertEqual(y.duration, footer.duration); XCTAssertEqual(opacity.duration, footer.duration)
          XCTAssertEqual(y.beginTime, footer.beginTime); XCTAssertEqual(opacity.beginTime, footer.beginTime)
          XCTAssertEqual(y.fillMode, .backwards); XCTAssertEqual(opacity.fillMode, .backwards)
          XCTAssertTrue(CATransform3DIsIdentity(mark.transform))
          if let text = mark as? MacTextBadgeLayer, text.text == "1:23" { durationCount += 1 }
          for step in 0...72 where !mark.isHidden {
            let elapsed = footer.duration * Double(step) / 72
            let alpha = readingValue(mark, key: "opacity", step: step, elapsed: elapsed)
            if alpha <= 0 { faded = true; continue }
            let tileWidth = springValue(root, key: "bounds.size.width", elapsed: elapsed)
            let tileHeight = springValue(root, key: "bounds.size.height", elapsed: elapsed)
            let photo = CGRect(x: springValue(root, key: "position.x", elapsed: elapsed) - root.anchorPoint.x * tileWidth,
              y: springValue(root, key: "position.y", elapsed: elapsed) - root.anchorPoint.y * tileHeight,
              width: tileWidth, height: tileHeight)
            let width = readingValue(mark, key: "bounds.size.width", step: step, elapsed: elapsed)
            let height = springValue(mark, key: "bounds.size.height", elapsed: elapsed)
            let x = readingValue(mark, key: "position.x", step: step, elapsed: elapsed) - mark.anchorPoint.x * width
            let y = readingValue(mark, key: "position.y", step: step, elapsed: elapsed) - mark.anchorPoint.y * height
            let displayed = CGRect(x: x, y: f.stage.bounds.height - y - height, width: width, height: height)
            let bottom = CGFloat((boundary.values![step] as! NSNumber).doubleValue)
            XCTAssertGreaterThanOrEqual(displayed.minX, max(0, photo.minX) - 0.5)
            XCTAssertLessThanOrEqual(displayed.maxX, min(f.stage.bounds.width, photo.maxX) + 0.5)
            XCTAssertGreaterThanOrEqual(displayed.minY, photo.minY - 0.5)
            XCTAssertLessThanOrEqual(displayed.maxY, min(bottom, photo.maxY) + 0.5,
              "A visible mark is cut by the photo/footer boundary at sample \(step)")
            XCTAssertEqual(height, mark.bounds.height, accuracy: 0.001, "Reading type must retain its native size")
            if let text = mark as? MacTextBadgeLayer {
              let glyph = text.readingGlyphLayer
              let center = (glyph.animation(forKey: "zoom.readingGlyph.position.x") as! CAKeyframeAnimation).values![step] as! NSNumber
              let glyphLeft = displayed.minX + CGFloat(center.doubleValue) - text.textWidth / 2
              XCTAssertGreaterThanOrEqual(glyphLeft, max(0, photo.minX) - 0.5)
              XCTAssertLessThanOrEqual(glyphLeft + text.textWidth, min(f.stage.bounds.width, photo.maxX) + 0.5)
            }
            if displayed.maxY < photo.maxY - 9 { clamped = true }
          }
          // Every interval, including one ending at zero opacity, must keep
          // the real bitmap glyph whole. Photo-only clipping and the reading
          // plane intentionally have different lower boundaries.
          for tick in 0...(72 * 8) where !mark.isHidden {
            let sample = Double(tick) / 8
            let alpha = linearValue(opacity, sample: sample)
            if alpha <= 0 { continue }
            let rect = glyphRect(mark, sample: sample, height: f.stage.bounds.height)
            let footerY = linearValue(footer, sample: sample) - f.label.layer!.position.y + f.label.frame.minY
            XCTAssertGreaterThanOrEqual(rect.minX, -0.001)
            XCTAssertLessThanOrEqual(rect.maxX, f.stage.bounds.width + 0.001)
            XCTAssertGreaterThanOrEqual(rect.minY, -0.001)
            XCTAssertLessThanOrEqual(rect.maxY, min(f.stage.bounds.height, footerY - DuckSpacing.xSmall) + 0.001,
              "A bitmap glyph is cut or enters the totals between keyframes at \(sample)")
          }
        }
      }
    }
    XCTAssertGreaterThan(durationCount, 0, "This regression needs actual configured video duration glyphs")
    return (clamped, faded)
  }

  /// Inspect installed CA tracks and actual masking relationships, including
  /// both faces' overflowing tails, rather than checking only model endpoints.
  @discardableResult private func assertReadingClearance(_ f: Fixture,
    file: StaticString = #filePath, line: UInt = #line) -> Bool {
    let label = f.label, move = label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
    let positions = move.values as! [NSNumber]
    XCTAssertEqual(positions.count, 73, file: file, line: line)
    XCTAssertEqual(faces(f.stage).count, 2, file: file, line: line)
    var croppedTail = false
    for face in faces(f.stage) {
      guard let boundary = clip(face) else { XCTFail("Missing photo content clipping", file: file, line: line); continue }
      XCTAssertTrue(CATransform3DIsIdentity(boundary.transform), file: file, line: line)
      XCTAssertEqual(boundary.anchorPoint, .zero, file: file, line: line)
      XCTAssertEqual(boundary.position, .zero, file: file, line: line)
      XCTAssertEqual(face.frame, f.stage.bounds, "Clipping must not relayout the photo face", file: file, line: line)
      if let canvas = macGridPhotoChildren(face).first as? MacDenseCanvas {
        XCTAssertTrue(canvas.photoContentLayer.superlayer === boundary, file: file, line: line)
        XCTAssertTrue(boundary.superlayer === canvas.layer, file: file, line: line)
        XCTAssertTrue(boundary.masksToBounds, file: file, line: line)
        XCTAssertNil(face.layer?.mask, "A dense face mask would also clip its reading pills", file: file, line: line)
        XCTAssertTrue(canvas.periodReadingLayer.superlayer === canvas.layer, file: file, line: line)
        XCTAssertTrue(CATransform3DIsIdentity(canvas.periodReadingLayer.transform), file: file, line: line)
        let pills = (canvas.periodReadingLayer.sublayers ?? [])
        XCTAssertFalse(pills.isEmpty, "The fixture must contain real period pills", file: file, line: line)
        for pill in pills {
          XCTAssertNotNil(pill.contents, file: file, line: line)
          XCTAssertTrue(pill.superlayer === canvas.periodReadingLayer, file: file, line: line)
          XCTAssertTrue(CATransform3DIsIdentity(pill.transform), file: file, line: line)
          XCTAssertGreaterThan(pill.bounds.height, 10, file: file, line: line)
        }
      } else {
        XCTAssertTrue((face.subviews.first { $0 is MacGridPhotoPlane })?.layer?.mask === boundary, file: file, line: line)
        XCTAssertNil(face.layer?.mask, file: file, line: line)
        XCTAssertEqual(boundary.backgroundColor?.alpha, 1, file: file, line: line)
      }
      guard let clipMove = boundary.animation(forKey: "zoom.footerClip") as? CAKeyframeAnimation else {
        XCTFail("Missing synchronized photo boundary track", file: file, line: line); continue
      }
      let heights = clipMove.values as! [NSNumber]
      XCTAssertEqual(heights.count, positions.count, file: file, line: line)
      XCTAssertEqual(clipMove.duration, move.duration, file: file, line: line)
      XCTAssertEqual(clipMove.beginTime, 0, file: file, line: line)
      XCTAssertEqual(clipMove.fillMode, .backwards, file: file, line: line)
      for step in positions.indices {
        let footerY = CGFloat(positions[step].doubleValue) - label.layer!.position.y + label.frame.minY
        let height = CGFloat(heights[step].doubleValue)
        XCTAssertEqual(height, min(f.stage.bounds.height, max(0, footerY - 30)), accuracy: 0.001, file: file, line: line)
        let elapsed = move.duration * Double(step) / Double(positions.count - 1)
        let photoRects = rectangles(face, elapsed: elapsed)
        XCTAssertFalse(photoRects.isEmpty, file: file, line: line)
        let clipRect = CGRect(x: 0, y: 0, width: boundary.bounds.width, height: height)
        for rect in photoRects {
          let inViewport = rect.intersection(f.stage.bounds)
          if !inViewport.isEmpty, inViewport.maxY > height + 0.5 { croppedTail = true }
          let visible = inViewport.intersection(clipRect)
          if !visible.isEmpty {
            XCTAssertGreaterThanOrEqual(footerY - visible.maxY, 29.5,
              "A visible photo intersects the reading area at sample \(step)", file: file, line: line)
          }
        }
      }
    }
    return croppedTail
  }

  private struct ReadingFamilyLayer {
    let family: String
    let layer: CALayer
  }

  private func readingFamilies(_ stage: MacGridZoomStage) -> [ReadingFamilyLayer] {
    faces(stage).compactMap { face in
      if let canvas = macGridPhotoChildren(face).first as? MacDenseCanvas {
        XCTAssertFalse((canvas.periodReadingLayer.sublayers ?? []).isEmpty)
        XCTAssertTrue(canvas.periodReadingLayer.superlayer === canvas.layer)
        return ReadingFamilyLayer(family: "dense-\(ObjectIdentifier(canvas))", layer: canvas.periodReadingLayer)
      }
      guard let mark = macGridPhotoChildren(face).compactMap({ $0 as? MacGridReadingTile })
        .flatMap(\.readingMarkLayers).first, let plane = mark.superlayer else {
        XCTFail("The ordinary reading family must contain real native media marks"); return nil
      }
      return ReadingFamilyLayer(family: "ordinary", layer: plane)
    }
  }

  private func familyValue(_ item: ReadingFamilyLayer, phase: CGFloat) -> CGFloat {
    guard let animation = item.layer.animation(forKey: "zoom.readingFamily") as? CAKeyframeAnimation else {
      return CGFloat(item.layer.opacity)
    }
    return MacGridReadingMarks.value(animation, at: phase)!
  }

  private func assertDisjointReadingFamilies(_ stage: MacGridZoomStage, ordinaryOnly: Bool = false,
    everyFamilyVisible: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
    let reading = readingFamilies(stage)
    XCTAssertGreaterThan(reading.count, 1, file: file, line: line)
    for item in reading {
      guard let gate = item.layer.animation(forKey: "zoom.readingFamily") as? CAKeyframeAnimation else {
        XCTFail("Every participating reading plane needs its own native CA gate", file: file, line: line); continue
      }
      XCTAssertEqual(gate.beginTime, 0, file: file, line: line)
      XCTAssertEqual(gate.fillMode, .backwards, file: file, line: line)
      XCTAssertEqual(gate.calculationMode, .linear, file: file, line: line)
      XCTAssertNotNil(gate.keyTimes, file: file, line: line)
      if everyFamilyVisible {
        XCTAssertTrue((gate.values as! [NSNumber]).contains { $0.floatValue > 0 }, file: file, line: line)
      }
    }
    XCTAssertTrue(reading.contains { item in
      ((item.layer.animation(forKey: "zoom.readingFamily") as? CAKeyframeAnimation)?.values as? [NSNumber])?.contains { $0.floatValue > 0 } == true
    }, file: file, line: line)
    // Sample actual installed layer tracks between keyTimes, including both
    // sides of every inserted crossing rather than only their endpoints.
    var times = (0...1000).map { CGFloat($0) / 1000 }
    for item in reading {
      let gate = item.layer.animation(forKey: "zoom.readingFamily") as! CAKeyframeAnimation
      for time in gate.keyTimes ?? [] {
        let t = CGFloat(time.doubleValue)
        times += [max(0, t - 0.00000001), t, min(1, t + 0.00000001)]
      }
    }
    for time in times {
      let visible = Set(reading.filter { familyValue($0, phase: time) > 0.000001 }.map(\.family))
      XCTAssertLessThanOrEqual(visible.count, 1, "Distinct text families overlap at phase \(time)", file: file, line: line)
      if ordinaryOnly {
        for item in reading { XCTAssertEqual(familyValue(item, phase: time), 1, accuracy: 0.000001, file: file, line: line) }
      }
    }
  }

  func testReadingFamilyHandoffKeepsOrdinaryMarksAndOverviewPeriodsDisjointBetweenCAKeyframes() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    for (from, to) in [(3, 20), (20, 3), (20, 40), (40, 20), (3, 4)] {
      let f = fixture(count: 12, width: 420, columns: from, sourceMarks: false)
      _ = release(f, to: to, velocity: -250)
      assertDisjointReadingFamilies(f.stage, ordinaryOnly: from == 3 && to == 4, everyFamilyVisible: true)
      f.stage.stop()
    }
  }

  func testReadingFamilyReversalAndThirdFamilyRetargetPreserveTheCurrentReadingGate() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    for target in [3, 40] {
      for phase: CGFloat in [0, 0.31375, 0.71375] {
        let f = fixture(count: 12, width: 420, columns: 3, sourceMarks: false)
        let start = release(f, to: 20, velocity: -250, startEvent: phase != 0)
        let before = readingFamilies(f.stage)
        let fade = before[0].layer.animation(forKey: "zoom.readingFamily") as! CAKeyframeAnimation
        let held = Dictionary(uniqueKeysWithValues: before.map { (ObjectIdentifier($0.layer), familyValue($0, phase: phase)) })
        let now = phase == 0 ? start + 10 : start + fade.duration * Double(phase)
        f.stage.freeze(at: now)
        for item in readingFamilies(f.stage) {
          XCTAssertEqual(familyValue(item, phase: 0), held[ObjectIdentifier(item.layer)]!, accuracy: 0.000001,
            "Input takeover must preserve the reading-family gate even before native start")
        }
        f.stage.ensureFace(target, opacity: 0)
        f.stage.show(target, animated: true, at: now)
        f.stage.hurryBlend(within: GridZoom.releaseFadeDuration, at: now)
        f.stage.settle(with: GridZoom.Settle(start: now, pitch: f.stage.pitch, focus: f.stage.focus,
          velocity: f.stage.frozenPitchVelocity, targetPitch: f.pitch(target),
          targetFocus: f.stage.contentFocus(columns: target)!)) {}
        for item in readingFamilies(f.stage) {
          if let expected = held[ObjectIdentifier(item.layer)] {
            XCTAssertEqual(familyValue(item, phase: 0), expected, accuracy: 0.000001,
              "Retarget must begin with the interrupted family gate")
          }
        }
        assertDisjointReadingFamilies(f.stage)
        f.stage.stop()
      }
    }
  }

  func testSparsePhotoTailsStayOutsideTheReadingAreaAcrossRowChanges() {
    var didCrop = false
    for count in [5, 6, 12] {
      for (from, to) in [(3, 4), (4, 6), (6, 4), (4, 3)] {
        for velocity: CGFloat in [-350, 0, 250] {
          let f = fixture(count: count, width: count == 12 ? 420 : 804, columns: from)
          _ = release(f, to: to, velocity: velocity)
          didCrop = assertReadingClearance(f) || didCrop
          f.stage.stop()
        }
      }
    }
    XCTAssertTrue(didCrop, "The regression must exercise a photo tail that would otherwise reach the label")
  }

  func testDensePhotoTailsAreClippedInViewportCoordinatesWhileRealPillsStayOutside() {
    var didCrop = false
    for (from, to) in [(20, 40), (40, 20)] {
      for velocity: CGFloat in [-250, 0, 250] {
        let f = fixture(count: 90, width: 804, columns: from)
        _ = release(f, to: to, velocity: velocity)
        didCrop = assertReadingClearance(f) || didCrop
        f.stage.stop()
      }
    }
    XCTAssertTrue(didCrop)
  }

  func testRealVideoAndSourceMarksKeepWholeGlyphsAtTheMovingPhotoBoundary() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    for source in [false, true] {
      var clamped = false, faded = false
      for (from, to) in [(3, 4), (4, 6), (6, 9), (9, 20)] {
        for velocity: CGFloat in [-250, 250] {
          let f = fixture(count: 12, width: 420, columns: from, sourceMarks: source)
          _ = release(f, to: to, velocity: velocity)
          let result = assertWholeReadingMarks(f)
          clamped = clamped || result.clamped; faded = faded || result.faded
          f.stage.stop()
        }
      }
      XCTAssertTrue(clamped, "Visible marks must follow a cropped photo's lower edge")
      XCTAssertTrue(faded, "Insufficient space must fade a whole mark instead of cutting its glyph")
    }
  }

  func testRealReadingMarksFreezeRetargetAndRestoreTheirNativeEndpointGeometry() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    for source in [false, true] {
      let f = fixture(count: 12, width: 420, columns: 3, sourceMarks: source)
      let start = release(f, to: 4, velocity: -250)
      let move = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      let sample = 17.375
      let marks = faces(f.stage).flatMap(macGridPhotoChildren).compactMap { $0 as? MacGridReadingTile }.flatMap(\.readingMarkLayers)
      let poses = marks.filter { !$0.isHidden }.map { mark -> (CALayer, CGRect, Float) in
        let y = mark.animation(forKey: "zoom.position.y") as! CAKeyframeAnimation
        let alpha = mark.animation(forKey: "zoom.readingOpacity") as! CAKeyframeAnimation
        let width = scalar(mark, key: "bounds.size.width", sample: sample)
        let frame = CGRect(x: scalar(mark, key: "position.x", sample: sample) - width * mark.anchorPoint.x,
          y: linearValue(y, sample: sample) - mark.bounds.height * mark.anchorPoint.y, width: width, height: mark.bounds.height)
        return (mark, frame, Float(linearValue(alpha, sample: sample)))
      }
      XCTAssertFalse(poses.isEmpty)
      let expectedFooter = linearValue(move, sample: sample) - f.label.layer!.position.y + f.label.frame.minY
      f.stage.freeze(at: start + move.duration * sample / 72)
      XCTAssertEqual(f.label.frame.minY, expectedFooter, accuracy: 0.001)
      let frozenAttached = attachedMarks(f.stage)
      for (mark, _, opacity) in poses where !frozenAttached.contains(ObjectIdentifier(mark)) {
        XCTAssertEqual(opacity, 0, "Freeze may discard a fully invisible coverage tile, but never a visible reading mark")
      }
      let frozen = poses.filter { frozenAttached.contains(ObjectIdentifier($0.0)) }
      XCTAssertFalse(frozen.isEmpty, "Freeze continuity must cover actual surviving stage marks")
      for (mark, frame, opacity) in frozen {
        XCTAssertEqual(mark.frame.minX, frame.minX, accuracy: 0.001)
        XCTAssertEqual(mark.frame.minY, frame.minY, accuracy: 0.001)
        XCTAssertEqual(mark.bounds.width, frame.width, accuracy: 0.001)
        XCTAssertEqual(mark.opacity, opacity, accuracy: 0.001)
        XCTAssertNil(mark.animation(forKey: "zoom.readingOpacity"))
        if let text = mark as? MacTextBadgeLayer {
          XCTAssertEqual(text.readingGlyphLayer.position.x, frame.width / 2, accuracy: 0.001)
          XCTAssertEqual(text.readingGlyphLayer.bounds.width, frame.width, accuracy: 0.001)
        }
      }
      f.stage.reanchor(to: CGPoint(x: 210, y: min(400, f.label.frame.minY - 40)))
      let reanchoredAttached = attachedMarks(f.stage)
      for (mark, _, opacity) in frozen where !reanchoredAttached.contains(ObjectIdentifier(mark)) {
        XCTAssertEqual(opacity, 0, "Reanchor must retain every visible reading mark")
      }
      let reanchored = frozen.filter { reanchoredAttached.contains(ObjectIdentifier($0.0)) }
      XCTAssertFalse(reanchored.isEmpty)
      for (mark, frame, opacity) in reanchored {
        XCTAssertEqual(mark.frame.minX, frame.minX, accuracy: 0.001)
        XCTAssertEqual(mark.frame.minY, frame.minY, accuracy: 0.001)
        XCTAssertEqual(mark.bounds.width, frame.width, accuracy: 0.001)
        XCTAssertEqual(mark.opacity, opacity, accuracy: 0.001)
      }
      _ = release(f, to: 3, velocity: f.stage.frozenPitchVelocity)
      let attached = attachedMarks(f.stage)
      for (mark, _, opacity) in reanchored where !attached.contains(ObjectIdentifier(mark)) {
        XCTAssertEqual(opacity, 0, "Retarget must not discard a visible reading mark")
      }
      let surviving = reanchored.filter { attached.contains(ObjectIdentifier($0.0)) }
      XCTAssertFalse(surviving.isEmpty, "Continuity must cover surviving stage marks after retarget")
      for (mark, frame, opacity) in surviving {
        guard let track = mark.animation(forKey: "zoom.position.y") as? CAKeyframeAnimation,
          let alpha = mark.animation(forKey: "zoom.readingOpacity") as? CAKeyframeAnimation else {
          XCTFail("A surviving reading mark is missing its retargeted trajectory"); continue
        }
        XCTAssertEqual((track.values!.first as! NSNumber).doubleValue, Double(frame.midY), accuracy: 0.001)
        XCTAssertEqual(scalar(mark, key: "position.x", sample: 0), frame.midX, accuracy: 0.001)
        XCTAssertEqual(scalar(mark, key: "bounds.size.width", sample: 0), frame.width, accuracy: 0.001)
        XCTAssertEqual((alpha.values!.first as! NSNumber).floatValue, opacity, accuracy: 0.001)
      }
      f.stage.detachFooter()
      for mark in marks {
        XCTAssertNil(mark.animation(forKey: "zoom.readingOpacity"))
        XCTAssertEqual(mark.opacity, 1)
      }
      f.stage.stop()

      // Stage adoption must preserve each density's real native plate geometry,
      // including the narrow 9-column case; a forced 42 pt plate would pulse.
      for (columns, fitted) in [3, 4, 6, 9].flatMap({ c in [false, true].map { (c, $0) } }) {
        let ended = fixture(count: 12, width: 420, columns: 6, sourceMarks: source, fitted: fitted)
        _ = release(ended, to: columns, velocity: 0)
        ended.stage.advance(to: CACurrentMediaTime() + 3)
        let tile = faces(ended.stage).flatMap(macGridPhotoChildren).first {
          $0 is MacGridReadingTile && $0.frame.minX >= 0 && $0.frame.maxX <= 420
        }!
        let duration = (tile as! MacGridReadingTile).readingMarkLayers.compactMap { $0 as? MacTextBadgeLayer }
          .first { $0.text == "1:23" }!
        let native: NSView
        let pipeline = ThumbnailPipeline()
        if source {
          let cell = MacSourceZoomTile(frame: CGRect(origin: .zero, size: tile.frame.size))
          cell.cell.configure(CatalogLibraryAsset(1), pipeline: pipeline, pixels: tile.frame.width * 2, originalAspect: fitted)
          cell.cell.setGroup(count: nil, state: "sending")
          cell.needsLayout = true; cell.layoutSubtreeIfNeeded(); cell.cell.viewDidLayout()
          native = cell
        } else {
          let media = MacZoomMediaTile(frame: CGRect(origin: .zero, size: tile.frame.size))
          media.configure(CatalogLibraryAsset(1), side: tile.frame.width, pixels: tile.frame.width * 2,
            pipeline: pipeline, originalAspect: fitted, selected: false, scale: 2)
          media.layout(); native = media
        }
        let nativeDuration = (native as! MacGridReadingTile).readingMarkLayers.compactMap { $0 as? MacTextBadgeLayer }
          .first { $0.text == "1:23" }!
        XCTAssertEqual(duration.bounds, nativeDuration.bounds)
        assertNativeFrame(duration.frame.offsetBy(dx: -tile.frame.minX, dy: tile.frame.maxY - ended.stage.bounds.height), nativeDuration.frame)
        XCTAssertEqual(duration.opacity, 1)
        XCTAssertEqual(duration.textWidth, nativeDuration.textWidth)
        let body = glyphRect(duration, sample: 0, height: ended.stage.bounds.height)
        XCTAssertGreaterThanOrEqual(body.minX, tile.frame.minX - 0.001)
        XCTAssertLessThanOrEqual(body.maxX, tile.frame.maxX + 0.001)
        XCTAssertGreaterThanOrEqual(body.minY, tile.frame.minY - 0.001)
        XCTAssertLessThanOrEqual(body.maxY, tile.frame.maxY + 0.001)
        let hosted = (tile as! MacGridReadingTile).readingMarkLayers
        let local = (native as! MacGridReadingTile).readingMarkLayers
        XCTAssertEqual(hosted.count, local.count)
        for (actual, expected) in zip(hosted, local) where !actual.isHidden {
          XCTAssertEqual(actual.bounds, expected.bounds)
          XCTAssertEqual(actual.opacity, expected.opacity, "Uncropped native status/media marks must not pulse at adoption")
          assertNativeFrame(actual.frame.offsetBy(dx: -tile.frame.minX, dy: tile.frame.maxY - ended.stage.bounds.height), expected.frame)
          if let text = actual as? MacTextBadgeLayer, let control = expected as? MacTextBadgeLayer {
            text.layoutIfNeeded(); control.layoutIfNeeded()
            XCTAssertEqual(text.readingGlyphLayer.frame, control.readingGlyphLayer.frame)
            XCTAssertEqual(text.readingGlyphLayer.contentsScale, control.readingGlyphLayer.contentsScale)
          } else {
            actual.layoutIfNeeded(); expected.layoutIfNeeded()
            XCTAssertEqual(actual.sublayers?.map(\.frame), expected.sublayers?.map(\.frame))
          }
        }
        ended.stage.detachFooter()
        XCTAssertEqual(duration.frame, nativeDuration.frame)
        if let cell = native as? MacSourceZoomTile { cell.cancel() }
        if let media = native as? MacZoomMediaTile { media.cancel() }
        ended.stage.stop()
      }
    }
  }

  func testRealReadingMarksUseTheViewportMaskWhenTheFooterIsBelowTheWindow() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    for source in [false, true] {
      let f = fixture(count: 60, width: 420, columns: 4, sourceMarks: source)
      f.stage.focus.y += 83
      f.stage.render()
      XCTAssertGreaterThan(f.label.frame.minY - 30, f.stage.bounds.height)
      let tile = faces(f.stage).flatMap(macGridPhotoChildren).first {
        $0 is MacGridReadingTile && $0.frame.minX >= 0 && $0.frame.maxX <= 420
          && $0.frame.minY < 900 && $0.frame.maxY > 900
      }!
      let duration = (tile as! MacGridReadingTile).readingMarkLayers.compactMap { $0 as? MacTextBadgeLayer }
        .first { $0.text == "1:23" }!
      XCTAssertGreaterThan(tile.frame.maxY - 7, f.stage.bounds.height,
        "The native bottom placement must actually cross the viewport in this fixture")
      XCTAssertGreaterThan(duration.opacity, 0)
      XCTAssertLessThanOrEqual(f.stage.bounds.height - duration.frame.minY, f.stage.bounds.height + 0.001)
      XCTAssertGreaterThanOrEqual(f.stage.bounds.height - duration.frame.maxY, tile.frame.minY - 0.001)
      let start = release(f, to: 6, velocity: -250)
      assertWholeReadingMarks(f)
      let move = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      f.stage.freeze(at: start + move.duration * 20 / 72)
      for face in faces(f.stage) {
        let edge = clip(face)!.bounds.height
        for view in macGridPhotoChildren(face) {
          guard let reading = view as? MacGridReadingTile else { continue }
          for mark in reading.readingMarkLayers where !mark.isHidden && mark.opacity > 0 {
            XCTAssertLessThanOrEqual(f.stage.bounds.height - mark.frame.minY, edge + 0.5)
          }
        }
      }
      f.stage.stop()
    }
  }

  func testRealGlyphsRemainWholeBetweenVisibleAndHiddenSamplesInTheQuietReadingSpace() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    for source in [false, true] {
      for (from, to): (CGFloat, CGFloat) in [(26, 16), (50, 0)] {
        let f = fixture(count: 12, width: 420, columns: 4, sourceMarks: source)
        let tile = faces(f.stage).flatMap(macGridPhotoChildren).first!
        let reading = tile as! MacGridReadingTile
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        host.wantsLayer = true; host.layer?.masksToBounds = true
        reading.setReadingHost(host)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let samples = [from, to].map { edge -> [MacGridReadingMarks.Pose] in
          let area = CGRect(x: 0, y: 0, width: 100, height: edge)
          return MacGridReadingMarks.hosted(reading.readingMarkPoses(in: frame, visible: area),
            tile: frame, visible: area, height: 100)
        }
        MacGridReadingMarks.apply(samples.last!)
        for mark in reading.readingMarkLayers { mark.layoutIfNeeded() }
        let batch = MacGridAnimationBatch()
        MacGridReadingMarks.animate(samples, start: CACurrentMediaTime(), duration: 1, batch: batch)
        batch.install()
        var visible = 0
        for mark in reading.readingMarkLayers where !mark.isHidden {
          let opacity = mark.animation(forKey: "zoom.readingOpacity") as! CAKeyframeAnimation
          for tick in 0...1000 {
            let sample = Double(tick) / 1000
            if linearValue(opacity, sample: sample) <= 0 { continue }
            let rect = glyphRect(mark, sample: sample, height: 100)
            let readingBottom = from * CGFloat(1 - sample) + to * CGFloat(sample) + 30 - DuckSpacing.xSmall
            XCTAssertGreaterThan(rect.height, 10, "This test must contain a real bitmap glyph")
            XCTAssertGreaterThanOrEqual(rect.minY, -0.001)
            XCTAssertLessThanOrEqual(rect.maxY, readingBottom + 0.001,
              "A fading glyph crosses the safe reading edge between two keyframes")
            XCTAssertGreaterThanOrEqual(rect.minX, -0.001); XCTAssertLessThanOrEqual(rect.maxX, 100.001)
            visible += 1
          }
        }
        XCTAssertGreaterThan(visible, 0)
        reading.setReadingHost(nil); reading.setReadingRect(nil)
        f.stage.stop()
      }
    }
  }

  func testPendingStartFreezeAndReverseRetargetKeepTheFooterAndPhotoBoundaryAtTheirOrigin() {
    for dense in [false, true] {
      let from = dense ? 20 : 4, to = dense ? 40 : 6
      let f = fixture(count: dense ? 90 : 12, width: dense ? 804 : 420, columns: from)
      let initialPitch = f.stage.pitch, initialFocus = f.stage.focus, reading = f.label.frame
      _ = release(f, to: to, velocity: -250, startEvent: false)
      let footer = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      XCTAssertEqual(footer.beginTime, 0)
      XCTAssertEqual(footer.fillMode, .backwards)
      let releaseY = CGFloat((footer.values!.first as! NSNumber).doubleValue)
        - f.label.layer!.position.y + f.label.frame.minY
      XCTAssertEqual(releaseY, reading.minY, accuracy: 0.001)
      for face in faces(f.stage) {
        let boundary = clip(face)!, movement = boundary.animation(forKey: "zoom.footerClip") as! CAKeyframeAnimation
        XCTAssertEqual(movement.beginTime, 0)
        XCTAssertEqual(movement.fillMode, .backwards)
        XCTAssertEqual(CGFloat((movement.values!.first as! NSNumber).doubleValue), reading.minY - 30, accuracy: 0.001)
      }
      // No native start event has been delivered: wall time alone must not
      // consume the footer, photo geometry or clipping release.
      f.stage.freeze(at: CACurrentMediaTime() + 10)
      XCTAssertEqual(f.stage.pitch, initialPitch, accuracy: 0.000001)
      XCTAssertEqual(f.stage.focus, initialFocus)
      XCTAssertEqual(f.label.frame, reading)
      for face in faces(f.stage) {
        XCTAssertEqual(clip(face)!.bounds.height, reading.minY - 30, accuracy: 0.001)
        XCTAssertNil(clip(face)!.animation(forKey: "zoom.footerClip"))
      }
      XCTAssertNil(f.label.layer!.animation(forKey: "zoom.footer"))

      // Reversing before commitment returns to the same native geometry.
      // The retargeted label and boundary must retain that same origin too.
      let reversedStart = release(f, to: from, velocity: f.stage.frozenPitchVelocity, startEvent: false)
      let reversed = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      for position in reversed.values as! [NSNumber] {
        XCTAssertEqual(CGFloat(position.doubleValue) - f.label.layer!.position.y + f.label.frame.minY,
          reading.minY, accuracy: 0.001)
      }
      for face in faces(f.stage) {
        let movement = clip(face)!.animation(forKey: "zoom.footerClip") as! CAKeyframeAnimation
        XCTAssertEqual(movement.beginTime, 0)
        XCTAssertEqual(movement.fillMode, .backwards)
        for height in movement.values as! [NSNumber] {
          XCTAssertEqual(CGFloat(height.doubleValue), reading.minY - 30, accuracy: 0.001)
        }
      }
      f.stage.freeze(at: reversedStart + 10)
      XCTAssertEqual(f.stage.pitch, initialPitch, accuracy: 0.000001)
      XCTAssertEqual(f.label.frame, reading)
      for face in faces(f.stage) {
        XCTAssertEqual(clip(face)!.bounds.height, reading.minY - 30, accuracy: 0.001)
      }
      f.stage.stop()
    }
  }

  func testFreezeReanchorAndRetargetPreserveTheReadingBoundaryAndIgnoreHiddenPhotos() {
    for dense in [false, true] {
      let from = dense ? 40 : 6, to = dense ? 20 : 3
      let f = fixture(count: dense ? 90 : 12, width: dense ? 804 : 420, columns: from)
      let start = release(f, to: to, velocity: 250)
      let move = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      let values = move.values as! [NSNumber], step = 5
      let expectedY = CGFloat(values[step].doubleValue) - f.label.layer!.position.y + f.label.frame.minY
      let readingPills = pillPoses(faces(f.stage), sample: step)
      if dense { XCTAssertFalse(readingPills.isEmpty) }
      f.stage.freeze(at: start + move.duration * Double(step) / Double(values.count - 1))
      XCTAssertEqual(f.label.frame.minY, expectedY, accuracy: 0.001)
      assertPillPoses(readingPills)
      let allFaces = faces(f.stage)
      let reading = f.label.frame
      let photos = allFaces.flatMap(macGridPhotoChildren)
      let before = Dictionary(uniqueKeysWithValues: photos.map { (ObjectIdentifier($0), $0.frame) })
      let densePixels = allFaces.compactMap { macGridPhotoChildren($0).first as? MacDenseCanvas }
        .flatMap { $0.photoContentLayer.sublayers ?? [] }
      let beforePixels = Dictionary(uniqueKeysWithValues: densePixels.map { (ObjectIdentifier($0), $0.frame) })
      for face in allFaces {
        XCTAssertEqual(clip(face)!.bounds.height, expectedY - 30, accuracy: 0.001)
        XCTAssertNil(clip(face)!.animation(forKey: "zoom.footerClip"))
      }
      let shownFace = allFaces.last!
      guard let hidden = rectangles(shownFace, elapsed: 0).first(where: {
        $0.minY >= expectedY - 30 && $0.intersects(f.stage.bounds)
      }) else {
        XCTFail("The takeover fixture must contain a fully clipped photo"); f.stage.stop(); continue
      }
      let point = CGPoint(x: hidden.midX, y: hidden.midY)
      let visibleRects = rectangles(shownFace, elapsed: 0).filter { $0.minY < expectedY - 30 && $0.intersects(f.stage.bounds) }
      XCTAssertFalse(visibleRects.isEmpty)
      f.stage.reanchor(to: point)
      XCTAssertEqual(f.label.frame, reading)
      assertPillPoses(readingPills)
      for photo in photos {
        XCTAssertEqual(photo.frame, before[ObjectIdentifier(photo)]!, "Input takeover must not move any existing photo or canvas")
      }
      for pixel in densePixels {
        XCTAssertEqual(pixel.frame, beforePixels[ObjectIdentifier(pixel)]!, "Input takeover must preserve every dense photo rectangle")
      }
      let reference = f.stage.contentFocus(columns: to)!
      // The adopted point can lie beyond a partially clipped photo, but its
      // identity must belong to a row that still has visible pixels.
      if dense {
        let row = (f.stage.anchor / to)
        let visibleLastRow = Int(floor((expectedY - 30 - 4) / f.stage.pitch))
        XCTAssertLessThanOrEqual(row, visibleLastRow)
        XCTAssertGreaterThanOrEqual(reference.y, f.geometry(to).items[0].minY)
      } else {
        let visibleIDs = Set(macGridPhotoChildren(shownFace).filter { $0.frame.minY < expectedY - 30 && $0.frame.intersects(f.stage.bounds) }
          .compactMap { $0.identifier?.rawValue })
        XCTAssertTrue(visibleIDs.contains("photo-\(f.stage.anchor)"))
      }
      let interruptedY = f.label.frame.minY
      _ = release(f, to: from, velocity: f.stage.frozenPitchVelocity)
      let resumed = f.label.layer!.animation(forKey: "zoom.footer") as! CAKeyframeAnimation
      XCTAssertEqual(CGFloat((resumed.values!.first as! NSNumber).doubleValue)
        - f.label.layer!.position.y + f.label.frame.minY, interruptedY, accuracy: 0.001)
      assertReadingClearance(f)
      f.stage.detachFooter()
      for face in faces(f.stage) {
        XCTAssertNil(face.layer?.mask)
        if let canvas = macGridPhotoChildren(face).first as? MacDenseCanvas {
          XCTAssertFalse(canvas.photoClippingLayer.masksToBounds)
          XCTAssertEqual(canvas.photoClippingLayer.bounds.size, canvas.bounds.size)
          XCTAssertNil(canvas.photoClippingLayer.animation(forKey: "zoom.footerClip"))
          canvas.reset()
          XCTAssertFalse(canvas.photoClippingLayer.masksToBounds)
        }
      }
      f.stage.stop()
    }
  }
}

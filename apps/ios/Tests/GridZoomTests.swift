import XCTest

@testable import BackupDuck

final class GridZoomTests: XCTestCase {
  // 402 pt wide phone grid: 1, 3, 5, 15 and 31 columns, gap 2 (0 when dense).
  private let stops = GridZoom.Stops(pitches: [402, 134, 80.4, 26.8, 13])

  func testStopPositionInterpolatesInLogSizeAndExtrapolatesBeyondEnds() {
    XCTAssertEqual(stops.position(pitch: 402), 0, accuracy: 1e-9)
    XCTAssertEqual(stops.position(pitch: 134), 1, accuracy: 1e-9)
    XCTAssertEqual(stops.position(pitch: 13), 4, accuracy: 1e-9)
    let halfway = stops.position(pitch: sqrt(134 * 80.4))
    XCTAssertEqual(halfway, 1.5, accuracy: 1e-9)
    XCTAssertLessThan(stops.position(pitch: 600), 0)
    XCTAssertGreaterThan(stops.position(pitch: 9), 4)
  }

  func testRubberBandResistsBeyondOutermostStopsAndIsIdentityInside() {
    XCTAssertEqual(stops.rubber(100), 100, accuracy: 1e-9)
    let high = stops.rubber(402 * 4)
    XCTAssertGreaterThan(high, 402)
    XCTAssertLessThan(high, 402 * exp(0.2) + 1e-6, "The large band is bounded")
    let low = stops.rubber(1)
    XCTAssertLessThan(low, 13)
    XCTAssertGreaterThan(low, 13 * exp(-0.05) - 1e-6, "The small band is bounded")
  }

  func testDeadZoneScalesWithDistanceAndHasFloor() {
    XCTAssertEqual(GridZoom.deadZone(startDistance: 50), 20)
    XCTAssertEqual(GridZoom.deadZone(startDistance: 400), 52, accuracy: 1e-9)
  }

  func testPinchIgnoresDeadZoneThenTracksContinuouslyFromItsEdge() {
    var pinch = GridZoom.Pinch(startDistance: 100, startPitch: 134)
    XCTAssertEqual(pinch.pitch(distance: 110), 134, "Inside the dead zone nothing moves")
    XCTAssertFalse(pinch.recognized)
    // Dead zone is 20; recognition happens at +20 and scale starts from 1 there.
    XCTAssertEqual(pinch.pitch(distance: 120), 134, accuracy: 1e-9)
    XCTAssertTrue(pinch.recognized)
    XCTAssertEqual(pinch.pitch(distance: 150), 134 * 150 / 120, accuracy: 1e-9)
    XCTAssertEqual(pinch.pitch(distance: 120), 134, accuracy: 1e-9, "Reversal retraces the same path")
  }

  func testPinchWithoutDeadZoneTracksMagnificationLinearly() {
    var pinch = GridZoom.Pinch(startDistance: 1, startPitch: 100, deadZone: 0)
    XCTAssertEqual(pinch.pitch(distance: 1.25), 125, accuracy: 1e-9)
    XCTAssertEqual(pinch.pitch(distance: 0.8), 80, accuracy: 1e-9)
  }

  func testDirectionNeedsDeliberateTravelBeforeSteppingToAdjacentStop() {
    var direction = GridZoom.Direction(startIndex: 1, startPitch: 134)
    XCTAssertEqual(direction.update(pitch: 130, shown: 1, stops: stops), 1)
    // Zooming out past the hysteresis previews the next stop.
    let pitch = 134 * exp(-0.12 * log(134 / 80.4) - 0.01)
    XCTAssertEqual(direction.update(pitch: pitch, shown: 1, stops: stops), 2)
  }

  func testDirectionReversalWithinAPairNeedsOnlySmallTravel() {
    var direction = GridZoom.Direction(startIndex: 1, startPitch: 134)
    var shown = direction.update(pitch: 110, shown: 1, stops: stops)
    XCTAssertEqual(shown, 2)
    shown = direction.update(pitch: 100, shown: shown, stops: stops)
    XCTAssertEqual(shown, 2)
    // A 1.5% reversal from the extreme flips back without crossing a stop.
    shown = direction.update(pitch: 100 * exp(GridZoom.reversalTravel + 0.001), shown: shown, stops: stops)
    XCTAssertEqual(shown, 1)
  }

  func testDirectionNeverLeavesStopRange() {
    var direction = GridZoom.Direction(startIndex: 4, startPitch: 13)
    XCTAssertEqual(direction.update(pitch: 2, shown: 4, stops: stops), 4)
    var up = GridZoom.Direction(startIndex: 0, startPitch: 402)
    XCTAssertEqual(up.update(pitch: 5000, shown: 0, stops: stops), 0)
  }

  func testReleaseKeepsPreviewStopAndStepsOnceForShortDeliberatePinch() {
    XCTAssertEqual(GridZoom.releaseIndex(shown: 2, start: 1, recognized: true, intent: -40, cancelled: false, count: 5), 2)
    XCTAssertEqual(GridZoom.releaseIndex(shown: 1, start: 1, recognized: false, intent: -9, cancelled: false, count: 5), 2)
    XCTAssertEqual(GridZoom.releaseIndex(shown: 1, start: 1, recognized: false, intent: 9, cancelled: false, count: 5), 0)
    XCTAssertEqual(GridZoom.releaseIndex(shown: 3, start: 1, recognized: true, intent: -90, cancelled: true, count: 5), 1)
    XCTAssertEqual(GridZoom.releaseIndex(shown: 1, start: 1, recognized: false, intent: 0, cancelled: false, forced: 9, count: 5), 4)
  }

  func testSettleIsCriticallyDampedWithoutOvershootAndEndsOnTarget() {
    let settle = GridZoom.Settle(
      start: 10, pitch: 100, focus: CGPoint(x: 50, y: 400), velocity: 0,
      targetPitch: 134, targetFocus: CGPoint(x: 70, y: 380))
    var previous: CGFloat = 100
    for step in 1...60 {
      let state = settle.state(at: 10 + Double(step) / 60)
      XCTAssertGreaterThanOrEqual(state.pitch, previous - 1e-9)
      XCTAssertLessThanOrEqual(state.pitch, 134 + 1e-9, "No overshoot")
      previous = state.pitch
    }
    XCTAssertFalse(settle.isDone(at: 10.05))
    XCTAssertTrue(settle.isDone(at: 11.5))
    XCTAssertEqual(settle.state(at: 10).pitch, 100, accuracy: 1e-9)
  }

  func testSettleLimitsCarriedVelocityAndMeasuresRecentSamples() {
    let fast = GridZoom.Settle(
      start: 0, pitch: 100, focus: .zero, velocity: 10_000, targetPitch: 110, targetFocus: .zero)
    XCTAssertEqual(fast.velocity, 10 * GridZoom.settleOmega, accuracy: 1e-9)
    XCTAssertEqual(GridZoom.Settle.velocity(of: [(0, 100), (0.05, 105)]), 100, accuracy: 1e-9)
    XCTAssertEqual(GridZoom.Settle.velocity(of: [(0, 100)]), 0)
  }

  func testBoundaryKeepsContentBottomAtViewportWhenShrinkingIntoLastRow() {
    // 1000 pt of content at pitch 100; focus 200 pt above the bottom, held at y=500.
    let boundary = GridZoom.Boundary(
      startFocusY: 500, contentHeight: 1000, focusInContent: 800, pitch: 100)
    XCTAssertEqual(boundary.distance, 2, accuracy: 1e-9)
    XCTAssertEqual(boundary.focusY(pitch: 100, viewportBottom: 700), 500, accuracy: 1e-9)
    XCTAssertEqual(boundary.focusY(pitch: 150, viewportBottom: 700), 500, accuracy: 1e-9, "Growing leaves the focus")
    // Shrinking to 60: rendered bottom would be 620, so the pivot moves down by 80.
    XCTAssertEqual(boundary.focusY(pitch: 60, viewportBottom: 700), 580, accuracy: 1e-9)
  }

  func testBoundaryPinsShortContentUnderTopInsetInsteadOfSinkingToBottom() {
    // 300 pt of content at pitch 100 in an 800 pt viewport, focus 100 pt below
    // the content top, held at y=160 with a 60 pt top inset.
    let boundary = GridZoom.Boundary(
      startFocusY: 160, contentHeight: 300, focusInContent: 100, pitch: 100)
    XCTAssertEqual(boundary.topDistance, 1, accuracy: 1e-9)
    XCTAssertEqual(boundary.focusY(pitch: 100, viewportBottom: 800, viewportTop: 60), 160, accuracy: 1e-9)
    // Bottom alone would push the focus down by 340 when shrinking to 40...
    XCTAssertEqual(boundary.focusY(pitch: 40, viewportBottom: 800), 160 + (800 - (160 + 2 * 40)), accuracy: 1e-9)
    // ...but with the top inset the content top stays at 60: focus = 60 + 1 * 40.
    XCTAssertEqual(boundary.focusY(pitch: 40, viewportBottom: 800, viewportTop: 60), 100, accuracy: 1e-9)
  }

  func testBoundaryTopRuleLeavesTallContentAlone() {
    let boundary = GridZoom.Boundary(
      startFocusY: 400, contentHeight: 5000, focusInContent: 2500, pitch: 100)
    XCTAssertEqual(boundary.focusY(pitch: 60, viewportBottom: 800, viewportTop: 60), 400 + 0, accuracy: 1e-9)
  }

  func testReanchorMovesFaceFocusWithoutMovingRenderedPixels() {
    let faceFocus = CGPoint(x: 300, y: 900)
    let stageFocus = CGPoint(x: 100, y: 200)
    let scale: CGFloat = 0.5
    let moved = GridZoom.reanchored(
      faceFocus: faceFocus, stageFocus: stageFocus, to: CGPoint(x: 160, y: 260), scale: scale)
    // A layout point renders at stageFocus + (p - faceFocus) * scale.
    func screen(_ p: CGPoint, focus: CGPoint, stage: CGPoint) -> CGPoint {
      CGPoint(x: stage.x + (p.x - focus.x) * scale, y: stage.y + (p.y - focus.y) * scale)
    }
    let probe = CGPoint(x: 340, y: 950)
    let before = screen(probe, focus: faceFocus, stage: stageFocus)
    let after = screen(probe, focus: moved, stage: CGPoint(x: 160, y: 260))
    XCTAssertEqual(before.x, after.x, accuracy: 1e-9)
    XCTAssertEqual(before.y, after.y, accuracy: 1e-9)
  }

  func testOffsetClampsToContentAndInsets() {
    XCTAssertEqual(
      GridZoom.offset(focusInContent: 2000, screenFocus: 300, contentHeight: 2100, viewportHeight: 800), 1300)
    XCTAssertEqual(
      GridZoom.offset(focusInContent: 100, screenFocus: 300, contentHeight: 2100, viewportHeight: 800), 0)
    XCTAssertEqual(
      GridZoom.offset(
        focusInContent: 100, screenFocus: 300, contentHeight: 2100, viewportHeight: 800, topInset: 60), -60 + 0)
  }
}

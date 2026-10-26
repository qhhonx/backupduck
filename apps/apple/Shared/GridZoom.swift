import CoreGraphics
import Foundation

/// Platform-neutral pinch/zoom mathematics for the media grid.
///
/// The iPhone calendar grid validated these rules against real gestures: a dead
/// zone before the pinch tracks, log-space density stops with a rubber band,
/// direction hysteresis, a critically damped release and a content-boundary pivot.
/// Hosts own views and layers; they must not re-derive these numbers.
enum GridZoom {
  /// Critically damped release rate, fitted to Photos release recordings.
  static let settleOmega: CGFloat = 12.5
  /// A new adjacent stop needs deliberate travel (in stop-index units).
  static let previewHysteresis: CGFloat = 0.12
  /// An established pair reverses after this much log-size travel from its extreme.
  static let reversalTravel: CGFloat = 0.015

  /// About 13% of the touch-down finger distance, at least 20 points.
  static func deadZone(startDistance: CGFloat) -> CGFloat { max(20, startDistance * 0.13) }

  /// Density stops, largest pitch (fewest columns) first.
  struct Stops: Equatable {
    let pitches: [CGFloat]
    /// Log-size band widths beyond the largest and smallest stop.
    var largeBand: CGFloat = 0.2
    var smallBand: CGFloat = 0.05
    init(pitches: [CGFloat], largeBand: CGFloat = 0.2, smallBand: CGFloat = 0.05) {
      precondition(!pitches.isEmpty, "At least one density stop is required")
      self.pitches = pitches
      self.largeBand = largeBand
      self.smallBand = smallBand
    }
    var count: Int { pitches.count }
    /// Continuous position in stop-index space, interpolated in log size.
    func position(pitch: CGFloat) -> CGFloat {
      let q = pitches
      guard q.count > 1, pitch > 0 else { return 0 }
      if pitch >= q[0] { return -log(pitch / q[0]) / log(q[0] / q[1]) }
      for i in 0..<(q.count - 1) where pitch >= q[i + 1] {
        return CGFloat(i) + log(q[i] / pitch) / log(q[i] / q[i + 1])
      }
      let n = q.count - 1
      return CGFloat(n) + log(q[n] / pitch) / log(q[n - 1] / q[n])
    }
    /// Beyond the outermost stops the size resists instead of tracking freely.
    func rubber(_ raw: CGFloat) -> CGFloat {
      guard let high = pitches.first, let low = pitches.last, raw > 0 else { return raw }
      func band(_ excess: CGFloat, _ limit: CGFloat) -> CGFloat { limit * (1 - exp(-excess / limit)) }
      if raw > high { return high * exp(band(log(raw / high), largeBand)) }
      if raw < low { return low * exp(-band(log(low / raw), smallBand)) }
      return raw
    }
    /// Nearest stop in log size.
    func nearest(pitch: CGFloat) -> Int {
      let z = position(pitch: pitch)
      return min(count - 1, max(0, Int(z.rounded())))
    }
  }

  /// Finger-distance (or magnification) tracking with a recognition dead zone.
  struct Pinch: Equatable {
    let startDistance: CGFloat
    let startPitch: CGFloat
    let deadZone: CGFloat
    private(set) var recognizedDistance: CGFloat?
    private(set) var intent: CGFloat = 0
    init(startDistance: CGFloat, startPitch: CGFloat, deadZone: CGFloat? = nil) {
      self.startDistance = startDistance
      self.startPitch = startPitch
      self.deadZone = deadZone ?? GridZoom.deadZone(startDistance: startDistance)
    }
    var recognized: Bool { recognizedDistance != nil }
    /// Raw, unbanded pitch for the current distance. Scale is measured from the
    /// dead-zone edge so it starts continuously.
    mutating func pitch(distance: CGFloat) -> CGFloat {
      intent = distance - startDistance
      if recognizedDistance == nil, abs(intent) >= deadZone {
        recognizedDistance = startDistance + (intent < 0 ? -deadZone : deadZone)
      }
      guard let recognizedDistance else { return startPitch }
      return startPitch * distance / max(0.0001, recognizedDistance)
    }
  }

  /// Chooses the previewed density stop during a held gesture.
  struct Direction: Equatable {
    let startIndex: Int
    let startPitch: CGFloat
    private(set) var direction = 0
    private(set) var extremePitch: CGFloat
    init(startIndex: Int, startPitch: CGFloat) {
      self.startIndex = startIndex
      self.startPitch = startPitch
      extremePitch = startPitch
    }
    /// Returns the stop to show for `pitch`, given the stop currently shown.
    mutating func update(pitch: CGFloat, shown: Int, stops: Stops) -> Int {
      let z = stops.position(pitch: pitch)
      var current = shown
      if direction == 0 {
        let travel = z - stops.position(pitch: startPitch)
        guard abs(travel) >= GridZoom.previewHysteresis else { return current }
        direction = travel > 0 ? 1 : -1
        current += direction
        extremePitch = pitch
      } else {
        let travel = log(extremePitch / pitch) * CGFloat(direction)
        if travel >= 0 {
          extremePitch = pitch
        } else if -travel >= GridZoom.reversalTravel {
          direction = -direction
          current += direction
          extremePitch = pitch
        }
      }
      // Continuing beyond a natural stop can reach another pair in the same
      // gesture. Reversing within a pair never needs to cross that stop again.
      let h = GridZoom.previewHysteresis
      let next = direction > 0 ? Int(ceil(z - h)) : Int(floor(z + h))
      current = direction > 0 ? max(current, next) : min(current, next)
      return min(stops.count - 1, max(0, current))
    }
  }

  /// Release keeps the preview intent. A short, unrecognized deliberate pinch
  /// still steps once; a cancelled gesture returns to the start stop.
  static func releaseIndex(
    shown: Int, start: Int, recognized: Bool, intent: CGFloat, cancelled: Bool,
    forced: Int? = nil, count: Int
  ) -> Int {
    var target = shown
    if !recognized, abs(intent) > 6 { target = start + (intent < 0 ? 1 : -1) }
    if cancelled { target = start }
    if let forced { target = forced }
    return min(count - 1, max(0, target))
  }

  /// Critically damped release of pitch and focus.
  struct Settle: Equatable {
    let start: TimeInterval
    let pitch: CGFloat
    let focus: CGPoint
    let velocity: CGFloat
    let targetPitch: CGFloat
    let targetFocus: CGPoint
    init(
      start: TimeInterval, pitch: CGFloat, focus: CGPoint, velocity: CGFloat,
      targetPitch: CGFloat, targetFocus: CGPoint
    ) {
      self.start = start
      self.pitch = pitch
      self.focus = focus
      // A fast release cannot overshoot visibly.
      let limit = abs(targetPitch - pitch) * GridZoom.settleOmega
      self.velocity = max(-limit, min(limit, velocity))
      self.targetPitch = targetPitch
      self.targetFocus = targetFocus
    }
    private static func spring(_ x0: CGFloat, _ target: CGFloat, _ v0: CGFloat, _ t: CGFloat) -> CGFloat {
      let w = GridZoom.settleOmega
      return target + (x0 - target + (v0 + w * (x0 - target)) * t) * exp(-w * t)
    }
    func state(at now: TimeInterval) -> (pitch: CGFloat, focus: CGPoint) {
      let t = CGFloat(max(0, now - start))
      return (
        Self.spring(pitch, targetPitch, velocity, t),
        CGPoint(
          x: Self.spring(focus.x, targetFocus.x, 0, t),
          y: Self.spring(focus.y, targetFocus.y, 0, t)))
    }
    func isDone(at now: TimeInterval) -> Bool {
      let t = now - start
      let s = state(at: now)
      return t > 0.1 && abs(s.pitch - targetPitch) < 0.05
        && hypot(s.focus.x - targetFocus.x, s.focus.y - targetFocus.y) < 0.25
    }
    /// Pitch change per second over the recent samples.
    static func velocity(of samples: [(TimeInterval, CGFloat)]) -> CGFloat {
      guard let first = samples.first, let last = samples.last, last.0 - first.0 > 0.01 else { return 0 }
      return (last.1 - first.1) / CGFloat(last.0 - first.0)
    }
  }

  /// Content boundaries: shrinking toward the final row moves the effective
  /// pivot to that edge before a gap can open below the content, and content
  /// shorter than the viewport stays pinned under the top inset instead of
  /// sinking to the bottom edge and jumping back on release.
  struct Boundary: Equatable {
    let startFocusY: CGFloat
    /// Distance from the focus to the content bottom, in pitch units.
    let distance: CGFloat
    /// Distance from the focus to the content top, in pitch units.
    let topDistance: CGFloat
    init(startFocusY: CGFloat, distance: CGFloat, topDistance: CGFloat = 0) {
      self.startFocusY = startFocusY
      self.distance = distance
      self.topDistance = topDistance
    }
    /// - Parameters:
    ///   - contentHeight: Content height in the layout the gesture started from.
    ///   - focusInContent: Focus y in that layout's content coordinates.
    ///   - pitch: Pitch of that layout.
    init(startFocusY: CGFloat, contentHeight: CGFloat, focusInContent: CGFloat, pitch: CGFloat) {
      let unit = max(0.0001, pitch)
      self.init(
        startFocusY: startFocusY, distance: (contentHeight - focusInContent) / unit,
        topDistance: focusInContent / unit)
    }
    /// Focus y to render for `pitch`. `viewportTop` is the top inset the content
    /// is pinned under; pass nil to leave the top edge free.
    func focusY(pitch: CGFloat, viewportBottom: CGFloat, viewportTop: CGFloat? = nil) -> CGFloat {
      let renderedBottom = startFocusY + distance * pitch
      var shift = max(0, viewportBottom - renderedBottom)
      if let viewportTop {
        let renderedTop = startFocusY - topDistance * pitch
        if renderedTop + shift > viewportTop { shift = viewportTop - renderedTop }
      }
      return startFocusY + shift
    }
  }

  /// Moves a face's focus when the shared screen focus moves, without moving
  /// any pixel. `scale` is stage pitch over the face's natural pitch.
  static func reanchored(
    faceFocus: CGPoint, stageFocus: CGPoint, to point: CGPoint, scale: CGFloat
  ) -> CGPoint {
    CGPoint(
      x: faceFocus.x + (point.x - stageFocus.x) / scale,
      y: faceFocus.y + (point.y - stageFocus.y) / scale)
  }

  /// Content offset that places `focusInContent` under `screenFocus`, clamped.
  static func offset(
    focusInContent: CGFloat, screenFocus: CGFloat, contentHeight: CGFloat,
    viewportHeight: CGFloat, topInset: CGFloat = 0, bottomInset: CGFloat = 0
  ) -> CGFloat {
    let low = -topInset
    let high = max(low, contentHeight - viewportHeight + bottomInset)
    return min(high, max(low, focusInContent - screenFocus))
  }
}

/// Shared native dock geometry. The period capsule is centred on the screen
/// between the compact native icon and its mirror position, 48 pt tall. It only
/// appears once the icon has reached this destination frame.
enum LibraryDockGeometry {
  static func capsule(width: CGFloat, icon: CGRect, gap: CGFloat = 12) -> CGRect {
    let reserve = min(icon.maxX, width - icon.minX) + gap
    let side = max(0, width - 2 * reserve)
    return CGRect(x: (width - side) / 2, y: icon.midY - 24, width: side, height: 48)
  }
}

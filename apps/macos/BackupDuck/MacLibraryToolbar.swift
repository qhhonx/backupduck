import AppKit
import Combine
import Photos
import SwiftUI

/// Calendar navigation is independent of the All Photos thumbnail scale.
enum MacLibraryLevel: String, CaseIterable, Identifiable {
  case years, months, all
  var id: String { rawValue }
  var title: String { self == .all ? "mac_library_all_photos" : "calendar_" + rawValue }
}

@MainActor final class MacVisibleRange: ObservableObject {
  @Published var title = ""
}

/// Sets the window subtitle from AppKit. As a SwiftUI `navigationSubtitle`, each
/// change of the visible range re-evaluated and re-laid out the whole toolbar
/// (about 40 ms, resolving every toolbar symbol again): a dropped frame each
/// time a fast scroll crossed a month.
struct MacLibrarySubtitle: NSViewRepresentable {
  let range: MacVisibleRange
  /// A subtitle that replaces the range (a selection count, or empty while the
  /// viewer or another page is showing).
  let fixed: String?
  func makeNSView(context: Context) -> MacSubtitleProbe { MacSubtitleProbe(range: range) }
  func updateNSView(_ view: MacSubtitleProbe, context: Context) {
    view.fixed = fixed
    // SwiftUI clears the subtitle when it changes the window title in the same
    // pass, so the subtitle is applied again after the pass.
    DispatchQueue.main.async { [weak view] in view?.apply() }
  }
}

@MainActor final class MacSubtitleProbe: NSView {
  var fixed: String? { didSet { if fixed != oldValue { apply() } } }
  private var title = ""
  private var sink: AnyCancellable?
  init(range: MacVisibleRange) {
    super.init(frame: .zero)
    title = range.title
    sink = range.$title.sink { [weak self] value in
      MainActor.assumeIsolated { self?.title = value; self?.apply() }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
  func apply() {
    let value = fixed ?? title
    if let window, window.subtitle != value { window.subtitle = value }
  }
}

/// This is a browsing index, not a backup queue. Only bounded cover samples are
/// retained per period; the complete membership remains in PhotoKit.
@MainActor final class MacLibraryNavigation: ObservableObject {
  @Published var level: MacLibraryLevel = .all
  @Published var originalAspect = false
  @Published var focusToken: String?
  @Published var focusRevision = 0
  /// The capture range on screen. It changes on almost every frame of a fast
  /// scroll, so it is published apart from this object: publishing it here
  /// re-evaluated the whole window, sidebar and grid included, on each change.
  let visibleRange = MacVisibleRange()
  var visibleDate: String {
    get { visibleRange.title }
    set { if visibleRange.title != newValue { visibleRange.title = newValue } }
  }
  /// The viewer lives in the window toolbar, as in Photos: title and subtitle
  /// describe the current photo, and the controls drive the open viewer.
  /// True from the moment the viewer opens until it starts to close, so the
  /// toolbar returns to the library as soon as the closing flight begins.
  @Published var viewerOpen = false
  @Published var viewerTitle = ""
  @Published var viewerSubtitle = ""
  @Published var viewerInfo = false
  @Published var viewerImmersive = false
  @Published var viewerHasLive = false
  @Published var viewerLiveRequest = 0
  var viewerCurrent: (() -> PHAsset?)?
  /// The viewer's media area in window coordinates.
  var viewerArea: (() -> CGRect?)?
  /// Bumped to ask All Photos to return to the newest photo.
  @Published var newestRevision = 0
  func scrollToNewest() { newestRevision &+= 1 }
  /// Frame of a visible cell in the grid's top-left coordinate space.
  var cellFrame: ((String) -> CGRect?)?
  /// Per level: the on-screen rectangle and pixels a photo occupies, in the grid's
  /// top-left space, so a level change can fly the matched photo between them.
  var coverFlight: [MacLibraryLevel: (String) -> MacCoverFlightSource?] = [:]
  /// Per level: where the focus lands — the cell showing the asset itself, or
  /// the cover of the period that contains the focus token.
  var coverLanding: [MacLibraryLevel: (_ token: String, _ assetID: String) -> MacCoverFlightSource?] = [:]
  /// Per level: the photo a level change keeps — the selected cover or cell,
  /// otherwise the one nearest the centre of the visible area.
  var focusCandidate: [MacLibraryLevel: () -> String?] = [:]
  /// Per level: show the focus photo on its period's cover when that cover can
  /// show it (a year card rotates through month photos), before a flight lands.
  var presentFocus: [MacLibraryLevel: (_ assetID: String, _ image: NSImage?) -> Void] = [:]
  @Published private(set) var years: [LibraryCalendarPeriod] = []
  @Published private(set) var months: [LibraryCalendarPeriod] = []
  @Published private(set) var indexing = false
  private var work: Task<Void, Never>?
  private var fetch: PHFetchResult<PHAsset>?
  private var epoch = 0
  func rebuild(_ next: PHFetchResult<PHAsset>?) {
    guard fetch !== next else { return }
    fetch = next; epoch += 1; work?.cancel()
    guard let next else { years = []; months = []; indexing = false; return }
    let expected = epoch
    indexing = true
    work = Task {
      let job = Task.detached(priority: .userInitiated) { Self.periods(next) }
      let result = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
      guard !Task.isCancelled, expected == self.epoch else { return }
      self.years = result.0; self.months = result.1; self.indexing = false; self.work = nil
    }
  }
  nonisolated static func periods(_ fetch: PHFetchResult<PHAsset>) -> ([LibraryCalendarPeriod], [LibraryCalendarPeriod]) {
    var index = LibraryCalendarIndex()
    fetch.enumerateObjects { asset, rawIndex, stop in
      if Task.isCancelled { stop.pointee = true; return }
      index.append(id: asset.localIdentifier, burst: asset.burstIdentifier,
        date: asset.creationDate, rawIndex: rawIndex)
    }
    return (index.years, index.months)
  }
  func focus(_ token: String) { focusToken = token; focusRevision &+= 1 }
}

/// Photos zooms through discrete column counts. Pinch and the buttons use the
/// same stops, and a window resize keeps the chosen count.
enum MacLibraryDensity {
  /// Four grid densities, then two gapless overview mosaics (month- and
  /// year-like) whose column counts follow the window width, as in Photos.
  static let grid = [3, 4, 6, 9]
  static let standard = 4
  static let denseThreshold = 12
  nonisolated(unsafe) static var overview = [20, 40]
  static var columns: [Int] { grid + overview }
  static func overview(forWidth width: CGFloat) -> [Int] {
    [max(denseThreshold + 2, Int(width / 44)), max(denseThreshold + 14, Int(width / 22))]
  }
  static func isDense(_ columns: Int) -> Bool { columns >= denseThreshold }
  static func step(_ columns: Int, by delta: Int) -> Int {
    let all = self.columns
    let index = all.firstIndex(of: columns)
      ?? all.indices.min { abs(all[$0] - columns) < abs(all[$1] - columns) } ?? 0
    return all[min(all.count - 1, max(0, index + delta))]
  }
}

struct MacLibraryScale: View {
  @Binding var columns: Int
  var body: some View {
    ControlGroup {
      Button { columns = MacLibraryDensity.step(columns, by: 1) } label: { Image(systemName: "minus") }
        .disabled(columns >= (MacLibraryDensity.columns.last ?? columns))
        .help("mac_library_zoom_out").accessibilityLabel(Text("mac_library_zoom_out")).accessibilityIdentifier("library.zoom_out")
      Button { columns = MacLibraryDensity.step(columns, by: -1) } label: { Image(systemName: "plus") }
        .disabled(columns <= (MacLibraryDensity.columns.first ?? columns))
        .help("mac_library_zoom_in").accessibilityLabel(Text("mac_library_zoom_in")).accessibilityIdentifier("library.zoom_in")
    }.accessibilityIdentifier("library.thumbnail_size")
  }
}

/// A photo as shown on one level: its rectangle in window coordinates, the
/// pixels it shows and the asset those pixels belong to.
struct MacCoverFlightSource {
  var rect: CGRect
  var image: NSImage?
  var radius: CGFloat
  var assetID: String
  /// The visible content area in window coordinates. Pixels outside it sit
  /// under the toolbar or the sidebar, and the flight is clipped to it.
  var clip: CGRect
  weak var window: NSWindow?
  /// The visible part of a scroll view below the toolbar, in window coordinates.
  @MainActor static func clip(of scroll: NSScrollView) -> CGRect {
    let rect = scroll.convert(scroll.bounds, to: nil)
    guard let window = scroll.window else { return rect }
    return rect.intersection(window.contentLayoutRect)
  }
}

/// The matched photo flies between levels on a Core Animation layer above the
/// window content. It never touches SwiftUI state, so the flight cannot cause
/// a view update in the middle of the level transition.
@MainActor enum MacCoverFlight {
  private static var current: MacFlightDriver?
  /// Flies the focus from its rectangle on the old level to its rectangle on
  /// the new one, clipped to the content area so it never passes over the
  /// toolbar. The destination is re-read on every frame: the level being
  /// revealed may still settle its scroll position, and a flight aimed at a
  /// stale rectangle lands beside the photo and then jumps.
  static func fly(from source: MacCoverFlightSource, to target: @escaping () -> MacCoverFlightSource?,
    duration: CFTimeInterval = 0.3) {
    guard let window = source.window, let frame = window.contentView?.superview, let first = target() else { return }
    current?.finish()
    current = MacFlightDriver(source: source, target: target, first: first, frame: frame, window: window, duration: duration)
  }
  fileprivate static func ended(_ driver: MacFlightDriver) { if current === driver { current = nil } }
}

@MainActor private final class MacFlightDriver: NSObject {
  private let host: MacFlightHost
  private let front = CALayer(), back = CALayer()
  private let source: MacCoverFlightSource
  private let target: () -> MacCoverFlightSource?
  private var last: MacCoverFlightSource
  private let start = CACurrentMediaTime()
  private let duration: CFTimeInterval
  private let crossfade: Bool
  private var link: CADisplayLink?
  init(source: MacCoverFlightSource, target: @escaping () -> MacCoverFlightSource?, first: MacCoverFlightSource,
    frame: NSView, window: NSWindow, duration: CFTimeInterval) {
    self.source = source; self.target = target; last = first; self.duration = duration
    crossfade = first.assetID != source.assetID && first.image != nil
    host = MacFlightHost(frame: frame.convert(first.clip, from: nil))
    super.init()
    host.wantsLayer = true
    host.layer?.masksToBounds = true
    frame.addSubview(host, positioned: .above, relativeTo: nil)
    for (layer, image) in [(back, crossfade ? first.image : nil), (front, source.image ?? first.image)] {
      layer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
      layer.contentsGravity = .resizeAspectFill; layer.masksToBounds = true
      layer.contentsScale = window.backingScaleFactor
      layer.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(), "opacity": NSNull(), "frame": NSNull()]
      host.layer?.addSublayer(layer)
    }
    back.opacity = 0
    step(0)
    let link = host.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }
  @objc private func tick(_ link: CADisplayLink) {
    let t = (CACurrentMediaTime() - start) / duration
    if let next = target() { last = next }
    if t >= 1.35 { finish(); return }
    step(t)
  }
  private func step(_ t: Double) {
    let x = min(1, max(0, t))
    let p = CGFloat(1 - pow(1 - x, 4))
    let a = host.convert(source.rect, from: nil), b = host.convert(last.rect, from: nil)
    let rect = CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
      width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
    let radius = source.radius + (last.radius - source.radius) * p
    // After landing the destination shows the same pixels underneath; the
    // flight hands over in the last few frames.
    let handover = Float(max(0, min(1, (t - 1) / 0.3)))
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for layer in [front, back] { layer.frame = rect; layer.cornerRadius = radius }
    if crossfade {
      front.opacity = Float(1 - min(1, x / 0.8)); back.opacity = (1 - handover) * Float(min(1, x / 0.5))
    } else {
      front.opacity = 1 - handover
    }
    CATransaction.commit()
  }
  func finish() {
    link?.invalidate(); link = nil
    host.removeFromSuperview()
    MacCoverFlight.ended(self)
  }
}

private final class MacFlightHost: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


/// Reports a SwiftUI region's rectangle in window coordinates to AppKit code.
struct MacAreaProbe: NSViewRepresentable {
  let report: (@escaping () -> CGRect?) -> Void
  func makeNSView(context: Context) -> NSView {
    let view = MacProbeView()
    report { [weak view] in view.flatMap { $0.window == nil ? nil : $0.convert($0.bounds, to: nil) } }
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}
private final class MacProbeView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

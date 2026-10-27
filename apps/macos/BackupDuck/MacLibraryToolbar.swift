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
  @Published var viewerState = "photo_viewer_loading"
  @Published var viewerProgress: Double?
  var viewerShare: (() -> Void)?
  var viewerBack: (() -> Void)?
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
  /// Like Photos and the iPhone, a relaunch opens at the grid last browsed;
  /// after an overview it opens at the densest grid stop.
  static let launchKey = "macLibraryLaunchColumns"
  static var remembered: Int {
    let stored = UserDefaults.standard.integer(forKey: launchKey)
    return grid.contains(stored) ? stored : standard
  }
  static func remember(_ columns: Int) {
    let value = grid.contains(columns) ? columns : (isDense(columns) ? grid.last ?? standard : standard)
    if UserDefaults.standard.integer(forKey: launchKey) != value { UserDefaults.standard.set(value, forKey: launchKey) }
  }
  static let denseThreshold = 12
  nonisolated(unsafe) static var overview = [20, 40]
  static var columns: [Int] { grid + overview }
  static func overview(forWidth width: CGFloat) -> [Int] {
    [max(denseThreshold + 2, Int(width / 44)), max(denseThreshold + 14, Int(width / 22))]
  }
  static func isDense(_ columns: Int) -> Bool { columns >= denseThreshold }
  static func canChangeAspect(level: MacLibraryLevel, columns: Int, hasPhotos: Bool) -> Bool {
    level == .all && !isDense(columns) && hasPhotos
  }
  static func step(_ columns: Int, by delta: Int) -> Int {
    let all = self.columns
    let index = all.firstIndex(of: columns)
      ?? all.indices.min { abs(all[$0] - columns) < abs(all[$1] - columns) } ?? 0
    return all[min(all.count - 1, max(0, index + delta))]
  }
}

/// A toolbar group, rather than a nested ControlGroup: AppKit owns one shared capsule.
struct MacLibraryScale: ToolbarContent {
  @Binding var columns: Int
  var enabled = true
  var stops: [Int] = MacLibraryDensity.columns
  private func step(_ delta: Int) -> Int {
    let index = stops.firstIndex(of: columns)
      ?? stops.indices.min { abs(stops[$0] - columns) < abs(stops[$1] - columns) } ?? 0
    return stops[min(stops.count - 1, max(0, index + delta))]
  }
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button { columns = step(1) } label: { Image(systemName: "minus") }
        .disabled(!enabled || columns >= (stops.last ?? columns))
        .help("mac_library_zoom_out").accessibilityLabel(Text("mac_library_zoom_out")).accessibilityIdentifier("library.zoom_out")
      Button { columns = step(-1) } label: { Image(systemName: "plus") }
        .disabled(!enabled || columns <= (stops.first ?? columns))
        .help("mac_library_zoom_in").accessibilityLabel(Text("mac_library_zoom_in")).accessibilityIdentifier("library.zoom_in")
    }
  }
}

/// Native toolbar sizing, independent of content spacing tokens.
enum MacBrowsingToolbarMetrics {
  static let compactWidth: CGFloat = 1100
  static let periodWidth: CGFloat = 230
}

/// Native fixed toolbar spacing separates semantic groups without drawing chrome.
struct MacBrowsingToolbarGap: ToolbarContent {
  var body: some ToolbarContent {
    if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
  }
}

/// Measure the whole window, including its sidebar, for browsing-toolbar adaptation.
struct MacToolbarWidth: NSViewRepresentable {
  @Binding var width: CGFloat
  func makeNSView(context: Context) -> Probe { Probe() }
  func updateNSView(_ view: Probe, context: Context) {
    view.report = { value in if width != value { width = value } }
    view.schedule()
  }
  final class Probe: NSView {
    var report: ((CGFloat) -> Void)?
    private var observer: NSObjectProtocol?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = window.map { window in
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.schedule() }
        }
      }
      schedule()
    }
    func schedule() {
      DispatchQueue.main.async { [weak self] in
        guard let self, let window = self.window else { return }
        self.report?(window.frame.width)
      }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
/// a view update in the middle of the level transition. The render server runs
/// the whole flight; app code only describes it.
@MainActor enum MacCoverFlight {
  private static var current: MacFlightDriver?
  /// Flies the focus from its rectangle on the old level to its rectangle on
  /// the new one, clipped to the content area so it never passes over the
  /// toolbar. The level being revealed may still settle its scroll position
  /// after the first layout pass, so the destination is read again after that
  /// pass and halfway through; a moved destination is absorbed by an additive
  /// animation instead of a jump at landing.
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
  private let target: () -> MacCoverFlightSource?
  private var landing: CGRect
  private let begin: CFTimeInterval
  private let duration: CFTimeInterval
  private var finished = false
  /// Quartic ease-out: fast departure, long soft arrival.
  private static let curve = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
  /// After landing the destination shows the same pixels underneath; the
  /// flight hands over during this share of the duration.
  private static let handover = 0.3
  init(source: MacCoverFlightSource, target: @escaping () -> MacCoverFlightSource?, first: MacCoverFlightSource,
    frame: NSView, window: NSWindow, duration: CFTimeInterval) {
    self.target = target; self.duration = duration
    let crossfade = first.assetID != source.assetID && first.image != nil
    host = MacFlightHost(frame: frame.convert(first.clip, from: nil))
    landing = .zero
    begin = CACurrentMediaTime()
    super.init()
    host.wantsLayer = true
    host.layer?.masksToBounds = true
    frame.addSubview(host, positioned: .above, relativeTo: nil)
    let start = host.convert(source.rect, from: nil), end = host.convert(first.rect, from: nil)
    landing = end
    for (layer, image) in [(back, crossfade ? first.image : nil), (front, source.image ?? first.image)] {
      layer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
      layer.contentsGravity = .resizeAspectFill; layer.masksToBounds = true
      layer.contentsScale = window.backingScaleFactor
      host.layer?.addSublayer(layer)
    }
    let total = duration * (1 + Self.handover), landed = NSNumber(value: 1 / (1 + Self.handover))
    CATransaction.begin(); CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in self?.finish() }
    for layer in [front, back] {
      // Model values are the destination; the animations run from the source.
      layer.bounds = CGRect(origin: .zero, size: end.size)
      layer.position = CGPoint(x: end.midX, y: end.midY)
      layer.cornerRadius = first.radius
      layer.opacity = 0
      let motion = CAAnimationGroup()
      motion.animations = [
        Self.basic("bounds.size", from: NSValue(size: start.size), to: NSValue(size: end.size)),
        Self.basic("position", from: NSValue(point: CGPoint(x: start.midX, y: start.midY)),
          to: NSValue(point: CGPoint(x: end.midX, y: end.midY))),
        Self.basic("cornerRadius", from: NSNumber(value: Double(source.radius)), to: NSNumber(value: Double(first.radius))),
      ]
      motion.duration = duration
      motion.timingFunction = Self.curve
      layer.add(motion, forKey: "flight")
      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.duration = total
      fade.calculationMode = .linear
      if layer === front {
        // The departing pixels give way to the destination's own pixels.
        fade.values = crossfade ? [1, 0, 0] : [1, 1, 0]
        fade.keyTimes = crossfade ? [0, NSNumber(value: 0.8 / (1 + Self.handover)), 1] : [0, landed, 1]
      } else {
        fade.values = crossfade ? [0, 1, 1, 0] : [0, 0]
        fade.keyTimes = crossfade ? [0, NSNumber(value: 0.5 / (1 + Self.handover)), landed, 1] : [0, 1]
      }
      layer.add(fade, forKey: "fade")
    }
    CATransaction.commit()
    DispatchQueue.main.async { [weak self] in self?.retarget() }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.5) { [weak self] in self?.retarget() }
  }
  private static func basic(_ key: String, from: Any, to: Any) -> CABasicAnimation {
    let animation = CABasicAnimation(keyPath: key)
    animation.fromValue = from; animation.toValue = to
    return animation
  }
  /// Moves the landing to the destination's current rectangle. The running
  /// flight still ends at the old rectangle, so an additive animation grows
  /// the old-to-new offset from zero over the remaining flight: the photo bends
  /// towards the new rectangle and lands on the new model values, without a jump.
  private func retarget() {
    guard !finished, let next = target() else { return }
    let end = host.convert(next.rect, from: nil)
    let dx = end.midX - landing.midX, dy = end.midY - landing.midY
    let dw = end.width - landing.width, dh = end.height - landing.height
    guard abs(dx) > 0.25 || abs(dy) > 0.25 || abs(dw) > 0.25 || abs(dh) > 0.25 else { return }
    landing = end
    let remaining = duration - (CACurrentMediaTime() - begin)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for layer in [front, back] {
      layer.bounds = CGRect(origin: .zero, size: end.size)
      layer.position = CGPoint(x: end.midX, y: end.midY)
      guard remaining > 0.016 else { continue }
      let correction = CAAnimationGroup()
      correction.animations = [
        Self.basic("bounds.size", from: NSValue(size: .zero), to: NSValue(size: CGSize(width: dw, height: dh))),
        Self.basic("position", from: NSValue(point: .zero), to: NSValue(point: CGPoint(x: dx, y: dy))),
      ]
      correction.animations?.forEach { ($0 as? CAPropertyAnimation)?.isAdditive = true }
      correction.duration = remaining
      correction.timingFunction = Self.curve
      layer.add(correction, forKey: "retarget-\(CACurrentMediaTime())")
    }
    CATransaction.commit()
  }
  func finish() {
    guard !finished else { return }
    finished = true
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

struct MacHistoryZoomActions {
  var smaller: () -> Void
  var larger: () -> Void
  var canShrink: Bool
  var canGrow: Bool
}
private struct MacHistoryZoomKey: FocusedValueKey { typealias Value = MacHistoryZoomActions }
extension FocusedValues {
  var historyZoom: MacHistoryZoomActions? {
    get { self[MacHistoryZoomKey.self] }
    set { self[MacHistoryZoomKey.self] = newValue }
  }
}

/// The same two-section filter menu for every media source.
struct MacGridFilterMenu: View {
  var shows: [(id: String, title: String, symbol: String)]
  var selected: String
  var choose: (String) -> Void
  @Binding var type: LibraryFilter
  var identifier: String
  private var active: Bool { selected != "all" || type != .all }
  var body: some View {
    Menu {
      // An inline picker's label is its section title; wrapping it in a
      // Section as well drew a second divider under each title.
      Picker("grid_filter_show", selection: Binding(get: { selected }, set: choose)) {
        ForEach(shows, id: \.id) { item in Label(LocalizedStringKey(item.title), systemImage: item.symbol).tag(item.id) }
      }.pickerStyle(.inline)
      Picker("grid_filter_type", selection: $type) {
        ForEach(LibraryFilter.allCases) { filter in
          Label(LocalizedStringKey(filter == .all ? "grid_filter_all_types" : filter == .burst ? "grid_filter_bursts" : filter.title), systemImage: filter.symbol).tag(filter)
        }
      }.pickerStyle(.inline)
    } label: {
      Label("library_filter", systemImage: "line.3.horizontal.decrease")
        .foregroundStyle(active ? AnyShapeStyle(DuckRole.accent) : AnyShapeStyle(.primary))
    }.menuIndicator(.hidden).help("library_filter").accessibilityIdentifier(identifier)
  }
  static var backupViews: [(id: String, title: String, symbol: String)] {
    LibraryBackupView.allCases.map { ($0.rawValue, $0.title, $0.symbol) }
  }
}

/// An explicit system toolbar item keeps search collapsed on first presentation.
/// Escape dismisses only an empty query, so existing input is never discarded.
struct MacGridSearch: View {
  @Binding var text: String
  @Binding var presented: Bool
  var prompt: LocalizedStringKey = "folders_search"
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Group {
      if presented {
        TextField(prompt, text: $text).textFieldStyle(.roundedBorder)
          .frame(minWidth: 120, idealWidth: 180, maxWidth: 220).focused($focused)
          .onAppear { focused = true }
          .onExitCommand { if text.isEmpty { show(false) } }
          .accessibilityIdentifier("grid.search_field")
          .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
      } else {
        Button { show(true) } label: { Label(prompt, systemImage: "magnifyingglass") }
          .labelStyle(.iconOnly).help(Text(prompt)).accessibilityIdentifier("grid.search")
          .transition(.opacity)
      }
    }
    .onChange(of: presented) { _, value in focused = value }
    // An empty field folds back once it loses focus, as the system search does.
    .onChange(of: focused) { _, value in if !value, text.isEmpty, presented { show(false) } }
  }
  private func show(_ value: Bool) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { presented = value }
  }
}
struct MacGridSearchAction { var open: () -> Void }
private struct MacGridSearchKey: FocusedValueKey { typealias Value = MacGridSearchAction }
extension FocusedValues {
  var gridSearch: MacGridSearchAction? {
    get { self[MacGridSearchKey.self] }
    set { self[MacGridSearchKey.self] = newValue }
  }
}

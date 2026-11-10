import AppKit
import Combine
import Photos
import SwiftUI

private struct MacWorkspaceActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
  var macWorkspaceActive: Bool {
    get { self[MacWorkspaceActiveKey.self] }
    set { self[MacWorkspaceActiveKey.self] = newValue }
  }
}

/// Calendar navigation is independent of the All Photos thumbnail scale.
enum MacLibraryLevel: String, CaseIterable, Identifiable {
  case years, months, all
  var id: String { rawValue }
  var title: String { self == .all ? "mac_library_all_photos" : "calendar_" + rawValue }
  var compactTitle: String { self == .all ? "mac_library_all_photos" : "mac_library_period_" + rawValue }
}

/// AppKit sends an action even when the selected segment is clicked again.
struct MacBrowserLevelControl: NSViewRepresentable {
  let labels: [String]
  let selection: Int
  let identifier: String
  let choose: (Int) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }
  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(labels: labels.map { NSLocalizedString($0, comment: "") },
      trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
    return control
  }
  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.choose = choose
    if control.segmentCount != labels.count { control.segmentCount = labels.count }
    for (index, label) in labels.enumerated() {
      let localized = NSLocalizedString(label, comment: "")
      if control.label(forSegment: index) != localized { control.setLabel(localized, forSegment: index) }
    }
    control.setAccessibilityIdentifier(identifier)
    control.selectedSegment = selection
  }
  final class Coordinator: NSObject {
    var choose: (Int) -> Void
    init(choose: @escaping (Int) -> Void) { self.choose = choose }
    @objc func changed(_ sender: NSSegmentedControl) {
      guard sender.selectedSegment >= 0 else { return }
      choose(sender.selectedSegment)
    }
  }
}

/// The toolbar owns the menu's chrome and sizes it to its readable period label.
struct MacBrowserLevelMenu: View {
  let selection: Int
  let choose: (Int) -> Void
  private var selectedLevel: MacLibraryLevel {
    MacLibraryLevel.allCases.indices.contains(selection) ? MacLibraryLevel.allCases[selection] : .all
  }
  var body: some View {
    Menu {
      ForEach(Array(MacLibraryLevel.allCases.enumerated()), id: \.element) { index, level in
        Button { choose(index) } label: {
          if index == selection {
            Label(LocalizedStringKey(level.compactTitle), systemImage: "checkmark")
          } else {
            Text(LocalizedStringKey(level.compactTitle))
          }
        }
      }
    } label: {
      Text(LocalizedStringKey(selectedLevel.compactTitle)).fixedSize()
    }
    .accessibilityIdentifier("library.view_mode")
  }
}

@MainActor final class MacVisibleRange: ObservableObject {
  @Published var title = ""
}

/// One navigation owner supplies both parts of the window chrome. Observing
/// the range here keeps scrolling updates out of the workspace body.
struct MacLibraryWindowChrome: ViewModifier {
  let title: String
  @ObservedObject var range: MacVisibleRange
  let fixed: String?
  var dateFormat: String?
  var ownsWindow = true

  private var subtitle: String {
    if let fixed { return fixed }
    // A browsing title has a date slot even before native membership has laid
    // out. A nonbreaking blank reserves native subtitle geometry without
    // inventing a date or changing to the larger single-line title style.
    let date = range.title.isEmpty ? "\u{00a0}" : dateFormat.map {
      String(format: NSLocalizedString($0, comment: ""), range.title)
    } ?? range.title
    return date
  }
  func body(content: Content) -> some View {
    content.navigationTitle(title).navigationSubtitle(subtitle)
      .background(MacWindowTitleOwner(title: ownsWindow ? title : nil, subtitle: subtitle))
  }
}

/// Retained pages may publish navigation preferences during the same update.
/// One native owner keeps the active title/subtitle pair coherent before display.
struct MacWindowTitleOwner: NSViewRepresentable {
  let title: String?
  let subtitle: String
  func makeNSView(context: Context) -> Probe { Probe() }
  func updateNSView(_ view: Probe, context: Context) {
    view.title = title; view.subtitle = subtitle; view.apply()
  }
  final class Probe: NSView {
    var title: String?
    var subtitle = ""
    private var observations: [NSKeyValueObservation] = []
    private var applying = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      observations.removeAll()
      if let window {
        observations = [window.observe(\.title, options: [.new]) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.apply() }
        }, window.observe(\.subtitle, options: [.new]) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.apply() }
        }]
      }
      apply()
    }
    func apply() {
      guard !applying, let window, let title else { return }
      applying = true
      if window.title != title { window.title = title }
      if window.subtitle != subtitle { window.subtitle = subtitle }
      applying = false
    }
  }
}

/// This is a browsing index, not a backup queue. Only bounded cover samples are
/// retained per period; the complete membership remains in PhotoKit.
@MainActor final class MacLibraryNavigation: ObservableObject {
  @Published var level: MacLibraryLevel = .all
  @Published var originalAspect = false
  @Published var focusToken: String?
  @Published var focusRevision = 0
  @Published private(set) var focusLevel: MacLibraryLevel = .all
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
  /// A read-only mirror drives toolbar appearance. Presentation belongs to the
  /// native window's Info store, shared by every grid and viewer navigation.
  @Published private(set) var informationPresented = false
  private weak var informationStore: MacPhotoInfoStore?
  private var informationObservation: AnyCancellable?
  private var initialInformationRequest: Bool?
  func bindInformation(_ store: MacPhotoInfoStore) {
    guard informationStore !== store else { return }
    informationStore = store
    informationObservation = store.$isPresented.sink { [weak self] value in
      if self?.informationPresented != value { self?.informationPresented = value }
    }
    if let initialInformationRequest {
      self.initialInformationRequest = nil; store.isPresented = initialInformationRequest
    }
  }
  func setInformationPresented(_ value: Bool) {
    if let informationStore { informationStore.isPresented = value }
    else { initialInformationRequest = value }
  }
  func toggleInformation() {
    setInformationPresented(!(informationStore?.isPresented ?? initialInformationRequest ?? false))
  }
  @Published var viewerState = "photo_viewer_loading"
  @Published var viewerProgress: Double?
  var viewerShare: (() -> Void)?
  var viewerBack: (() -> Void)?
  @Published var viewerHasLive = false
  @Published var viewerLiveRequest = 0
  var viewerCurrent: (() -> PHAsset?)?
  /// The viewer's media area in window coordinates.
  var viewerArea: (() -> CGRect?)?
  let viewerFlight = MacViewerFlight()
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
  func focus(_ token: String, at target: MacLibraryLevel = .all) {
    focusLevel = target; focusToken = token; focusRevision &+= 1
  }
  func selectLevel(_ next: MacLibraryLevel) {
    focusToken = nil
    if level == next { scrollToNewest() }
    else { level = next }
  }
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
  /// A readable search input that leaves the remaining toolbar controls usable.
  static let searchWidth: CGFloat = 240
}

/// Native fixed toolbar spacing separates semantic groups without drawing chrome.
struct MacBrowsingToolbarGap: ToolbarContent {
  var body: some ToolbarContent {
    if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
  }
}

/// The window owns toolbar composition; retained grids only publish the active
/// inspection target. Inactive grids cannot replace or withdraw another target.
@MainActor final class MacGridToolbarState: ObservableObject {
  @Published private(set) var canInspect = false
  @Published private(set) var hasSource = false
  private var owner: UUID?
  private weak var navigation: MacLibraryNavigation?
  func update(owner: UUID, navigation: MacLibraryNavigation, hasItems: Bool) {
    self.owner = owner; self.navigation = navigation
    if !hasSource { hasSource = true }
    if canInspect != hasItems { canInspect = hasItems }
  }
  func withdraw(owner: UUID) {
    guard self.owner == owner else { return }
    self.owner = nil; navigation = nil
    if hasSource { hasSource = false }
    if canInspect { canInspect = false }
  }
  func showInformation() { if canInspect { navigation?.toggleInformation() } }
}

private struct MacGridToolbarStateKey: EnvironmentKey {
  static let defaultValue: MacGridToolbarState? = nil
}
extension EnvironmentValues {
  var macGridToolbarState: MacGridToolbarState? {
    get { self[MacGridToolbarStateKey.self] }
    set { self[MacGridToolbarStateKey.self] = newValue }
  }
}

struct MacGridInfoButton: View {
  @ObservedObject var state: MacGridToolbarState
  var body: some View {
    Button { state.showInformation() } label: { Label("photo_viewer_info", systemImage: "info.circle") }
      .disabled(!state.canInspect).help(Text("folders_show_info"))
      .accessibilityIdentifier("library.grid.info")
  }
}

/// A permanent native selection action shares the symbol group with Info.
/// Selection and registration update its state without changing toolbar geometry.
struct MacSelectionBackupControl: View {
  @ObservedObject var action: SelectionBackupAction
  let count: Int
  let identifier: String
  let submit: () -> Void
  private var title: String {
    if !action.title.isEmpty { return action.title }
    return count > 0 ? String(format: NSLocalizedString("selection_backup_count", comment: ""), count)
      : NSLocalizedString("folders_back_up_selected", comment: "")
  }
  var body: some View {
    Button(action: submit) {
      Label(title, systemImage: "arrow.up")
    }
    .disabled(count == 0 || action.busy || action.added)
    .help(Text(title))
    .accessibilityLabel(Text(title))
    .accessibilityIdentifier(identifier)
    .onChange(of: action.added) { _, added in
      guard added else { return }
      NSAccessibility.post(element: NSApp!, notification: .announcementRequested,
        userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
  }
}

/// Native tracking also covers the AppKit list hosted inside the sidebar.
struct MacSidebarHover: NSViewRepresentable {
  var changed: (Bool) -> Void
  func makeNSView(context: Context) -> Probe { Probe() }
  func updateNSView(_ view: Probe, context: Context) {
    view.changed = changed
    view.scheduleRefresh()
  }
  final class Probe: NSView {
    var changed: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var refreshScheduled = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateTrackingAreas()
      scheduleRefresh()
    }
    override func updateTrackingAreas() {
      if let tracking { removeTrackingArea(tracking) }
      super.updateTrackingAreas()
      let next = NSTrackingArea(rect: .zero,
        options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited], owner: self)
      addTrackingArea(next)
      tracking = next
    }
    override func layout() { super.layout(); scheduleRefresh() }
    override func mouseEntered(with event: NSEvent) { scheduleRefresh() }
    override func mouseExited(with event: NSEvent) { scheduleRefresh() }
    func scheduleRefresh() {
      guard !refreshScheduled else { return }
      refreshScheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.refreshScheduled = false
        let next = self.window.map { window in
          window.isVisible && self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } ?? false
        guard next != self.hovered else { return }
        self.hovered = next
        self.changed?(next)
      }
    }
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
  /// The source collection stays at its captured offset while a viewer owns it.
  weak var sourceViewport: LibraryScrollView? = nil
  /// Full composition, independent of a cached centre-cropped rendition.
  var fullAspectRatio: CGFloat? = nil
  /// The rendition occupies its real centred region of the full composition.
  /// A square cover must reveal the full photo without stretching its pixels.
  static func renditionSize(_ image: NSImage?, fullAspect: CGFloat?, in viewport: CGSize) -> CGSize {
    guard let image, image.size.width > 0, image.size.height > 0,
      viewport.width > 0, viewport.height > 0 else { return viewport }
    let imageAspect = image.size.width / image.size.height
    let aspect = max(0.001, fullAspect ?? imageAspect)
    let fullWidth = max(viewport.width, viewport.height * aspect)
    let fullHeight = fullWidth / aspect
    let width = min(fullWidth, fullHeight * imageAspect)
    return CGSize(width: width, height: width / imageAspect)
  }
  @MainActor static func install(_ bitmap: CGImage?, on layer: CALayer) {
    layer.contents = bitmap
    if #available(macOS 26, *) { layer.preferredDynamicRange = .high }
    else {
      layer.wantsExtendedDynamicRangeContent = bitmap.map {
        $0.contentHeadroom > 1 || $0.colorSpace?.isHDR() == true
          || ($0.colorSpace.map { CGColorSpaceUsesExtendedRange($0) } ?? false)
      } ?? false
    }
  }
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
  /// toolbar. Native layout events retarget a moved destination with an
  /// additive animation instead of a timer or a jump at landing.
  static func fly(from source: MacCoverFlightSource, to target: @escaping () -> MacCoverFlightSource?,
    duration: CFTimeInterval = 0.3, owner: AnyObject? = nil, completion: (() -> Void)? = nil) {
    guard let window = source.window, let frame = window.contentView?.superview, let first = target(),
      source.image != nil || first.image != nil else { completion?(); return }
    current?.finish()
    current = MacFlightDriver(source: source, target: target, first: first, frame: frame, window: window, duration: duration, owner: owner, completion: completion)
  }
  static func cancel(owner: AnyObject) { if current?.owner === owner { current?.finish() } }
  static func destinationDidLayout() { current?.retarget() }
  fileprivate static func ended(_ driver: MacFlightDriver) { if current === driver { current = nil } }
}

@MainActor final class MacFlightDriver: NSObject {
  weak var owner: AnyObject?
  private let host: MacFlightHost
  private let front = CALayer(), back = CALayer()
  private let frontImage = CALayer(), backImage = CALayer()
  private let sourceImage: NSImage?
  private let destinationImage: NSImage?
  private let fullAspect: CGFloat?
  private let target: () -> MacCoverFlightSource?
  private var landing: CGRect
  private let begin: CFTimeInterval
  private let duration: CFTimeInterval
  private var finished = false
  private var completion: (() -> Void)?
  var presentationLayer: CALayer? { host.layer?.presentation() }
  /// Quartic ease-out: fast departure, long soft arrival.
  private static let curve = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
  /// After landing the destination shows the same pixels underneath; the
  /// flight hands over during this share of the duration.
  private static let handover = 0.3
  init(source: MacCoverFlightSource, target: @escaping () -> MacCoverFlightSource?, first: MacCoverFlightSource,
    frame: NSView, window: NSWindow, duration: CFTimeInterval, owner: AnyObject?, completion: (() -> Void)?) {
    self.owner = owner
    self.target = target; self.duration = duration; self.completion = completion
    let crossfade = first.image != nil
    sourceImage = source.image ?? first.image; destinationImage = first.image
    fullAspect = first.fullAspectRatio ?? source.fullAspectRatio
    host = MacFlightHost(frame: frame.convert(first.clip, from: nil))
    landing = .zero
    begin = CACurrentMediaTime()
    super.init()
    host.wantsLayer = true
    host.layer?.masksToBounds = true
    frame.addSubview(host, positioned: .above, relativeTo: nil)
    let start = host.convert(source.rect, from: nil), end = host.convert(first.rect, from: nil)
    landing = end
    for (layer, pixels, image) in [(back, backImage, crossfade ? first.image : nil), (front, frontImage, source.image ?? first.image)] {
      MacCoverFlightSource.install(image?.cgImage(forProposedRect: nil, context: nil, hints: nil), on: pixels)
      pixels.contentsGravity = .resize; layer.masksToBounds = true
      layer.contentsScale = window.backingScaleFactor
      pixels.contentsScale = window.backingScaleFactor
      layer.addSublayer(pixels)
      host.layer?.addSublayer(layer)
      let fromSize = MacCoverFlightSource.renditionSize(image, fullAspect: fullAspect, in: start.size)
      let toSize = MacCoverFlightSource.renditionSize(image, fullAspect: fullAspect, in: end.size)
      pixels.bounds = CGRect(origin: .zero, size: toSize)
      pixels.position = CGPoint(x: end.width / 2, y: end.height / 2)
      let composition = CAAnimationGroup()
      composition.animations = [
        Self.basic("bounds.size", from: NSValue(size: fromSize), to: NSValue(size: toSize)),
        Self.basic("position", from: NSValue(point: CGPoint(x: start.width / 2, y: start.height / 2)),
          to: NSValue(point: CGPoint(x: end.width / 2, y: end.height / 2))),
      ]
      composition.duration = duration; composition.fillMode = .backwards; composition.timingFunction = Self.curve
      pixels.add(composition, forKey: "composition")
    }
    let handover = completion == nil ? Self.handover : 0
    let total = duration * (1 + handover), landed = NSNumber(value: 1 / (1 + handover))
    CATransaction.begin(); CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in self?.finish() }
    for layer in [front, back] {
      // Model values are the destination; the animations run from the source.
      layer.bounds = CGRect(origin: .zero, size: end.size)
      layer.position = CGPoint(x: end.midX, y: end.midY)
      layer.cornerRadius = first.radius
      layer.opacity = completion == nil ? 0 : (layer === back && crossfade || layer === front && !crossfade ? 1 : 0)
      let motion = CAAnimationGroup()
      motion.animations = [
        Self.basic("bounds.size", from: NSValue(size: start.size), to: NSValue(size: end.size)),
        Self.basic("position", from: NSValue(point: CGPoint(x: start.midX, y: start.midY)),
          to: NSValue(point: CGPoint(x: end.midX, y: end.midY))),
        Self.basic("cornerRadius", from: NSNumber(value: Double(source.radius)), to: NSNumber(value: Double(first.radius))),
      ]
      motion.fillMode = .backwards
      motion.duration = duration
      motion.timingFunction = Self.curve
      layer.add(motion, forKey: "flight")
      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.duration = total
      fade.calculationMode = .linear
      fade.fillMode = .backwards
      if completion != nil {
        // A square source rendition and a fitted destination are different
        // pixels even when they identify the same asset. Land on the pixels
        // the native media view actually has, then transfer ownership.
        // Source-over composition is not an additive mix: fading both layers
        // leaks the window through the photo. Keep the landing fully opaque
        // under the departing rendition until native pixels take ownership.
        fade.values = layer === front ? (crossfade ? [1, 0, 0] : [1, 1, 1])
          : (crossfade ? [1, 1, 1] : [0, 0, 0])
        fade.keyTimes = [0, 0.8, 1]
      } else if layer === front {
        // The departing pixels give way to the destination's own pixels.
        fade.values = crossfade ? [1, 0, 0] : [1, 1, 0]
        fade.keyTimes = crossfade ? [0, NSNumber(value: 0.8 / (1 + Self.handover)), 1] : [0, landed, 1]
      } else {
        fade.values = crossfade ? [1, 1, 0] : [0, 0]
        fade.keyTimes = crossfade ? [0, landed, 1] : [0, 1]
      }
      layer.add(fade, forKey: "fade")
    }
    CATransaction.commit()
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
  func retarget() {
    guard !finished, let next = target() else { return }
    let end = host.convert(next.rect, from: nil)
    let dx = end.midX - landing.midX, dy = end.midY - landing.midY
    let dw = end.width - landing.width, dh = end.height - landing.height
    guard abs(dx) > 0.25 || abs(dy) > 0.25 || abs(dw) > 0.25 || abs(dh) > 0.25 else { return }
    landing = end
    let remaining = duration - (CACurrentMediaTime() - begin)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (pixels, image) in [(frontImage, sourceImage), (backImage, destinationImage)] {
      let oldSize = pixels.bounds.size
      let newSize = MacCoverFlightSource.renditionSize(image, fullAspect: fullAspect, in: end.size)
      pixels.bounds = CGRect(origin: .zero, size: newSize)
      pixels.position = CGPoint(x: end.width / 2, y: end.height / 2)
      if remaining > 0.016 {
        let correction = CAAnimationGroup()
        correction.animations = [
          Self.basic("bounds.size", from: NSValue(size: .zero),
            to: NSValue(size: CGSize(width: newSize.width - oldSize.width, height: newSize.height - oldSize.height))),
          Self.basic("position", from: NSValue(point: .zero), to: NSValue(point: CGPoint(x: dw / 2, y: dh / 2))),
        ]
        correction.animations?.forEach { ($0 as? CAPropertyAnimation)?.isAdditive = true }
        correction.duration = remaining; correction.timingFunction = Self.curve
        pixels.add(correction, forKey: "composition-retarget-\(CACurrentMediaTime())")
      }
    }
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
    let completed = completion; completion = nil
    CATransaction.begin(); CATransaction.setDisableActions(true)
    completed?()
    host.removeFromSuperview()
    CATransaction.commit()
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

/// Hosts the system search item without replacing the browsing content.
/// AppKit owns search rendering, editing and cancellation.
struct MacToolbarSearch: View {
  @Environment(\.macWorkspaceActive) private var active
  @Binding var text: String
  @Binding var presented: Bool
  var prompt: LocalizedStringKey = "folders_search"
  @FocusState private var focused: Bool
  @State private var draft: String
  @State private var preservesQueryOnBlur = false

  init(text: Binding<String>, presented: Binding<Bool>, prompt: LocalizedStringKey = "folders_search") {
    _text = text
    _presented = presented
    self.prompt = prompt
    _draft = State(initialValue: presented.wrappedValue ? text.wrappedValue : "")
  }

  var body: some View {
    if active { searchContent }
  }
  private var searchContent: some View {
    Color.clear.frame(width: 0, height: 0)
      .searchable(text: $draft, isPresented: $presented, placement: .toolbar, prompt: Text(prompt))
      .searchFocused($focused)
      .background(MacSearchPresentation(endEditing: {
        preservesQueryOnBlur = true
        focused = false; presented = false
        draft = ""
      }))
      .onChange(of: focused) { _, value in
        if value {
          preservesQueryOnBlur = false
          draft = text
        } else {
          presented = false
          draft = ""
        }
      }
      .onChange(of: draft) { _, value in
        // Compact AppKit search requires an empty field. Keep a dismissed
        // editor's draft separate from the query that still filters content.
        if !preservesQueryOnBlur || !value.isEmpty { text = value }
      }
      .onChange(of: text) { _, value in
        if presented || focused { draft = value }
      }
      .focusedSceneValue(\.gridSearch, MacGridSearchAction(open: { presented = true; focused = true }))
  }
}
/// The system search item stays mounted. A low-priority width preference yields
/// to AppKit's focused width, leaving its entire search transition system-owned.
private struct MacSearchPresentation: NSViewRepresentable {
  let endEditing: () -> Void
  func makeNSView(context: Context) -> MacToolbarSearchView { MacToolbarSearchView() }
  func updateNSView(_ view: MacToolbarSearchView, context: Context) {
    view.endEditing = endEditing
    view.updatePresentation()
  }
  static func dismantleNSView(_ view: MacToolbarSearchView, coordinator: ()) { view.stop() }
}

final class MacToolbarSearchView: NSView {
  private var clickObserver: MacSearchContentClick?
  private var notifications: [NSObjectProtocol] = []
  private weak var field: NSSearchField?
  private var compactWidth: NSLayoutConstraint?
  private var maximumWidth: NSLayoutConstraint?
  var endEditing: (() -> Void)?
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stop()
    guard let content = window?.contentView else { return }
    let click = MacSearchContentClick(target: nil, action: nil)
    click.endEditing = { [weak self] in self?.endEditing?() }
    content.addGestureRecognizer(click)
    clickObserver = click
    let center = NotificationCenter.default
    notifications.append(center.addObserver(forName: NSToolbar.willAddItemNotification, object: nil, queue: .main) { [weak self] note in
      MainActor.assumeIsolated {
        guard let self, let toolbar = note.object as? NSToolbar, toolbar === self.window?.toolbar,
          let item = note.userInfo?.values.compactMap({ $0 as? NSSearchToolbarItem }).first else { return }
        // The item is not in toolbar.items yet. Configure the notified item
        // before AppKit performs its first toolbar layout.
        self.updatePresentation(item)
      }
    })
    notifications.append(center.addObserver(forName: NSControl.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] note in
      MainActor.assumeIsolated {
        guard let self, let field = self.field, note.object as AnyObject? === field else { return }
        if !field.stringValue.isEmpty {
          self.endEditing?()
          field.stringValue = ""
          self.window?.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem })
            .first(where: { $0.searchField === field })?.endSearchInteraction()
        }
        self.updatePresentation()
      }
    })
    updatePresentation()
  }
  func updatePresentation() {
    guard let item = window?.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first else { return }
    updatePresentation(item)
  }
  private func updatePresentation(_ item: NSSearchToolbarItem) {
    let isNewField = field !== item.searchField
    if isNewField {
      compactWidth?.isActive = false
      maximumWidth?.isActive = false
      field = item.searchField
      // A search field's system height leaves room for its own search symbol.
      // AppKit renders the compact toolbar button at its native dimensions.
      let width = max(1, item.searchField.fittingSize.height)
      compactWidth = item.searchField.widthAnchor.constraint(lessThanOrEqualToConstant: width)
      compactWidth?.identifier = "BackupDuck.search.compact"
      // A required compact width prevents AppKit's own search expansion.
      // The focused-width constraint must win without replacing constraints
      // during the native begin/end interaction.
      compactWidth?.priority = .defaultLow
      compactWidth?.isActive = true
      maximumWidth = item.searchField.widthAnchor.constraint(lessThanOrEqualToConstant: MacBrowsingToolbarMetrics.searchWidth)
      maximumWidth?.identifier = "BackupDuck.search.maximum"
      maximumWidth?.isActive = true
      item.resignsFirstResponderWithCancel = true
    }
    if item.preferredWidthForSearchField != MacBrowsingToolbarMetrics.searchWidth {
      item.preferredWidthForSearchField = MacBrowsingToolbarMetrics.searchWidth
    }
  }
  func stop() {
    if let clickObserver { clickObserver.view?.removeGestureRecognizer(clickObserver); self.clickObserver = nil }
    notifications.forEach(NotificationCenter.default.removeObserver)
    notifications = []
    compactWidth?.isActive = false
    compactWidth = nil
    maximumWidth?.isActive = false
    maximumWidth = nil
    field = nil
  }
}

private final class MacSearchContentClick: NSGestureRecognizer {
  var endEditing: (() -> Void)?
  override func mouseDown(with event: NSEvent) {
    if let window = view?.window, window.contentLayoutRect.contains(event.locationInWindow),
      let search = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem })
        .first(where: { $0.searchField.currentEditor() != nil }) {
      endEditing?()
      // AppKit chooses the compact representation while ending interaction.
      // Clear the native editor before that decision; SwiftUI retains the
      // content query and adopts the empty draft on its next update.
      search.searchField.currentEditor()?.string = ""
      search.searchField.stringValue = ""
      search.endSearchInteraction()
      window.makeFirstResponder(nil)
    }
    state = .failed
  }
  override func canPrevent(_ other: NSGestureRecognizer) -> Bool { false }
  override func canBePrevented(by other: NSGestureRecognizer) -> Bool { false }
}

struct MacGridSearchAction { var open: () -> Void }
private struct MacGridSearchKey: FocusedValueKey { typealias Value = MacGridSearchAction }
extension FocusedValues {
  var gridSearch: MacGridSearchAction? {
    get { self[MacGridSearchKey.self] }
    set { self[MacGridSearchKey.self] = newValue }
  }
}

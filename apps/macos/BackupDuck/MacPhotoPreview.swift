import AppKit
import AVKit
import Combine
import CryptoKit
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MacPhotoPreview: View {
  @Environment(\.macWorkspaceActive) private var active
  @StateObject private var session: MediaPreviewSession
  @ObservedObject private var library: PhotoLibraryModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var navigation: MacLibraryNavigation
  @State private var playRequest = 0
  @State private var pageAnimated = false
  private var information: Bool { navigation.informationPresented }
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @StateObject private var facts = MacViewerFacts()
  @State private var shareFailure = false
  private var recorded: HistoryPhoto?
  private var collectionPaging: MacCollectionPaging?
  private let collectionCount: Int?
  private let close: (PHAsset) -> Void
  init(asset: PHAsset, library: PhotoLibraryModel, navigation: MacLibraryNavigation, reviewAssets: [PHAsset]? = nil, recorded: HistoryPhoto? = nil, collectionPaging: MacCollectionPaging? = nil,
    close: @escaping (PHAsset) -> Void) {
    self.library = library; self.navigation = navigation; self.close = close; self.recorded = recorded; self.collectionPaging = collectionPaging; self.collectionCount = reviewAssets?.count
    _session = StateObject(wrappedValue: MediaPreviewSession(asset: asset, library: library,
      poster: navigation.viewerFlight.poster(for: asset.localIdentifier) ?? library.previewPoster?(asset.localIdentifier), reviewAssets: reviewAssets))
  }
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Group {
          if collectionPaging?.native == true {
            MacPreviewPage(preview: session.current, session: session, flight: navigation.viewerFlight,
              playRequest: playRequest, onSwipe: { move(MacCollectionPaging.step(forHorizontalMotion: $0), animated: true) }, onPull: pull)
          } else {
            MacMediaPager(session: session, flight: navigation.viewerFlight, playRequest: playRequest,
              reversesSessionOrder: collectionCount == nil, animated: pageAnimated,
              onSwipe: { move(MacCollectionPaging.step(forHorizontalMotion: $0), animated: true) }, onPull: pull)
          }
        }
          // The media stays inside the visible area: under the toolbar or the
          // sidebar it would be covered, and the opening flight lands on it.
          .background(MacAreaProbe { area in navigation.viewerArea = area })
          .background(MacDetailViewportProbe { session.setMacDisplayTarget($0) })

        VStack(spacing: 0) {
          Spacer(minLength: 0)
          BurstPreviewControls(preview: session.current, select: session.activate)
        }
      }
      .modifier(MacViewerNavigationControls(previousEnabled: (collectionPaging?.hasPrevious ?? (adjacent(step: -1) != nil)) && !session.paging && !session.zoomed,
        nextEnabled: (collectionPaging?.hasNext ?? (adjacent(step: 1) != nil)) && !session.paging && !session.zoomed,
        previous: { move(-1) }, next: { move(1) }))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .tint(DuckRole.accent)
    }
    .modifier(MacViewerInspector(navigation: navigation,
      target: .library(session.current.asset, library, recorded?.job)))
    .background(MacMediaKeyHandler { event in
      if event.keyCode == 53 || event.charactersIgnoringModifiers == " " {
        close(session.current.asset); return true
      }
      if event.modifierFlags.intersection([.command,.option,.control]).isEmpty,
        event.keyCode == 123 || event.keyCode == 124 {
        guard !session.zoomed else { return false }
        move(event.keyCode == 123 ? -1 : 1); return true
      }
      return false
    })
    .onAppear {
      if active { session.start(); describe(); installCommands() }
      else { session.current.load(promptForCloud: false) }
    }
    .onDisappear {
      session.stop()
      // A recyclable collection leaf may disappear after its successor has
      // installed window commands. The owning collection clears them on exit.
      if active, collectionPaging == nil {
        navigation.viewerCurrent = nil; navigation.viewerShare = nil; navigation.viewerBack = nil
      }
    }
    .onChange(of: active) { _, visible in
      if visible { session.current.activate(); describe(); updateMark(); installCommands() }
      else { session.current.deactivate() }
    }
    .onChange(of: session.current.asset.localIdentifier) { _, _ in playRequest = 0; describe() }
    .onChange(of: session.current.livePhoto != nil) { _, _ in describe() }
    .onChange(of: navigation.viewerLiveRequest) { _, _ in if active { playRequest += 1 } }
    .task(id: "\(session.current.asset.localIdentifier)|\(model.pairing?.receiverID ?? "")|\(model.queueRevision)|\(model.pendingImports)|\(model.summary.received)|\(model.summary.published)") {
      await loadFacts()
      updateMark()
    }
    .onChange(of: facts.stateKey) { _, _ in updateMark() }
    .onChange(of: facts.job) { _, _ in updateMark() }
    .onChange(of: facts.job.flatMap { model.transferProgress[$0.id] }) { _, _ in updateMark() }
    .alert("library_context_share", isPresented: $shareFailure) { Button("settings_done") {} } message: { Text("library_preview_icloud_failed") }
  }
  private func loadFacts() async {
    let asset = session.current.asset
    let original = recorded?.source == asset.localIdentifier ? recorded?.job : nil
    await facts.load(source: asset.localIdentifier, revision: original == nil ? PhotoLibraryModel.revision(asset) : nil,
      model: model, library: original == nil ? library : nil, recorded: original)
  }
  private func installCommands() {
    navigation.viewerCurrent = { [weak session] in session?.current.asset }
    if collectionPaging == nil { navigation.viewerBack = { close(session.current.asset) } }
    navigation.viewerShare = { MacViewerSharing.show(asset: session.current.asset) { shareFailure = true } }
  }
  private func updateMark() {
    guard active else { return }
    navigation.viewerState = facts.stateKey(model: model); navigation.viewerProgress = facts.progress(model: model)
  }
  /// Title, subtitle and controls of the window toolbar follow the current photo.
  private func describe() {
    guard active else { return }
    let asset = session.current.asset
    navigation.viewerTitle = MacViewerTitle.date(asset.creationDate)
    let total = session.count
    let index = session.index(of: asset).map { collectionCount == nil ? total - $0 : $0 + 1 }
    navigation.viewerSubtitle = MacViewerTitle.subtitle(asset.creationDate,
      index: collectionPaging.map { $0.index + 1 } ?? index, total: collectionPaging?.count ?? total)
    navigation.viewerHasLive = session.current.livePhoto != nil
  }
  private func setInformation(_ value: Bool) {
    withAnimation(reduceMotion ? nil : .timingCurve(0.2,0.8,0.2,1,duration: 0.26)) { navigation.setInformationPresented(value) }
  }
  /// Dragging up reveals information; dragging down hides it, then leaves.
  private func pull(_ direction: Int) {
    if direction == -2 { if information { setInformation(false) }; return }
    if direction > 0 { setInformation(true) }
    else if information { setInformation(false) }
    else { close(session.current.asset) }
  }
  /// Keys and arrow buttons change the photo at once, as Photos does; only a
  /// swipe slides the strip.
  private func adjacent(step: Int) -> PHAsset? {
    session.adjacent(to: session.current.asset, direction: collectionCount == nil ? -step : step)
  }
  private func move(_ step: Int, animated: Bool = false) {
    guard !session.paging, !session.zoomed else { return }
    if let collectionPaging {
      if animated, let swipe = collectionPaging.swipe { swipe(step) }
      else { collectionPaging.move(step) }
      return
    }
    guard let asset = adjacent(step: step) else { return }
    pageAnimated = animated
    session.activate(asset)
  }
  private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }.buttonStyle(.borderless).accessibilityLabel(Text(LocalizedStringKey(label)))
      .help(Text(LocalizedStringKey(label))).accessibilityIdentifier(id)
  }
}

/// Tracks the actual host window's backing scale and profile as it moves or resizes.
struct MacDetailViewportProbe: NSViewRepresentable {
  let update: (MacDetailPosterTarget) -> Void
  func makeNSView(context: Context) -> MacDetailViewportView {
    let view = MacDetailViewportView(); view.update = update; return view
  }
  func updateNSView(_ view: MacDetailViewportView, context: Context) { view.update = update; view.report() }
}
final class MacDetailViewportView: NSView {
  var update: ((MacDetailPosterTarget) -> Void)?
  private var screenObservation: NSObjectProtocol?
  private var pendingTarget: MacDetailPosterTarget?
  private var deliveredTarget: MacDetailPosterTarget?
  private var reportScheduled = false
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
    screenObservation = nil
    pendingTarget = nil; deliveredTarget = nil
    guard let window else { return }
    screenObservation = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
      object: window, queue: .main) { [weak self] _ in self?.report() }
    report()
  }
  override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); report() }
  override func layout() { super.layout(); report() }
  func report() {
    guard let screen = window?.screen, bounds.width > 0, bounds.height > 0 else { return }
    let pixels = convertToBacking(bounds).size
    let profile = screen.colorSpace?.cgColorSpace?.copyICCData().map {
      SHA256.hash(data: $0 as Data).map { String(format: "%02x", $0) }.joined()
    } ?? "unknown"
    let target = MacDetailPosterTarget(pixels: CGSize(width: ceil(pixels.width), height: ceil(pixels.height)), profile: profile)
    guard target != pendingTarget, target != deliveredTarget || pendingTarget != nil else { return }
    pendingTarget = target
    guard !reportScheduled else { return }
    reportScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.reportScheduled = false
      guard self.window != nil, let target = self.pendingTarget else { return }
      self.pendingTarget = nil
      guard target != self.deliveredTarget else { return }
      self.deliveredTarget = target; self.update?(target)
    }
  }
  deinit { if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) } }
}

/// Both source adapters use the same edge-revealed navigation controls.
struct MacViewerNavigationControls: ViewModifier {
  let previousEnabled: Bool
  let nextEnabled: Bool
  var previous: () -> Void
  var next: () -> Void
  @State private var edge = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func body(content: Content) -> some View {
    GeometryReader { proxy in
      ZStack {
        content
        HStack {
        arrow("chevron.left", label: "preview_previous", id: "library.preview.previous", action: previous)
          .keyboardShortcut(.leftArrow, modifiers: []).disabled(!previousEnabled).opacity(edge < 0 ? 1 : 0)
        Spacer()
        arrow("chevron.right", label: "preview_next", id: "library.preview.next", action: next)
          .keyboardShortcut(.rightArrow, modifiers: []).disabled(!nextEnabled).opacity(edge > 0 ? 1 : 0)
      }.padding(.horizontal, 14).frame(maxHeight: .infinity)
        .allowsHitTesting(edge != 0)
      }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: edge)
        .onContinuousHover { phase in
          guard case .active(let point) = phase else { edge = 0; return }
          edge = point.x < 90 ? -1 : point.x > proxy.size.width - 90 ? 1 : 0
        }
    }
  }
  private func arrow(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }.buttonStyle(.borderless)
      .accessibilityLabel(Text(LocalizedStringKey(label))).help(Text(LocalizedStringKey(label)))
      .accessibilityIdentifier(id)
  }
}

/// AppKit owns horizontal live tracking and page-controller reuse. Lightweight
/// positions remain stable across swipes; only neighbouring media are loaded.
struct MacMediaPager: NSViewControllerRepresentable {
  @Environment(\.self) private var environment
  @ObservedObject var session: MediaPreviewSession
  let flight: MacViewerFlight
  let playRequest: Int
  var reversesSessionOrder = false
  var animated = false
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  var onTap: () -> Void = {}
  /// Native indices follow the actual grid, independently of PhotoKit's fetch order.
  func asset(at index: Int) -> PHAsset? {
    session.asset(at: reversesSessionOrder ? session.count - 1 - index : index)
  }
  func index(of asset: PHAsset) -> Int? {
    session.index(of: asset).map { reversesSessionOrder ? session.count - 1 - $0 : $0 }
  }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSViewController(context: Context) -> NSPageController {
    let controller = MediaPageController()
    controller.view = NSView(frame: CGRect(x: 0,y: 0,width: 800,height: 550))
    controller.view.autoresizingMask = [.width,.height]; controller.view.wantsLayer = true
    controller.view.layer?.backgroundColor = NSColor.clear.cgColor
    controller.transitionStyle = .horizontalStrip; controller.delegate = context.coordinator
    context.coordinator.install(controller)
    return controller
  }
  func updateNSViewController(_ controller: NSPageController, context: Context) {
    let c = context.coordinator; c.parent = self
    if c.active == session.current.asset.localIdentifier, !session.paging, let view = controller.selectedViewController as? NSHostingController<AnyView> {
      view.rootView = AnyView(MacPreviewPage(preview: session.current, session: session, flight: flight, playRequest: playRequest, onSwipe: onSwipe, onPull: onPull, onTap: onTap).environment(\.self, environment))
    }
    guard !session.paging else { return }
    let index = index(of: session.current.asset)
    if let index, controller.arrangedObjects.count == session.count, index != controller.selectedIndex,
      !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      // Keys and buttons switch in place: the page controller animates even
      // a zero-length animator change, so the index is set directly.
      controller.selectedIndex = index; controller.completeTransition(); c.install(controller)
    } else if let index, controller.arrangedObjects.count == session.count, index != controller.selectedIndex {
      session.paging = true
      NSAnimationContext.runAnimationGroup { context in
        context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !animated ? 0 : 0.2
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2,0.8,0.2,1)
        controller.animator().selectedIndex = index
      } completionHandler: {
        Task { @MainActor in
          controller.completeTransition(); self.session.paging = false; c.install(controller)
        }
      }
    } else if controller.arrangedObjects.count != session.count || c.active != session.current.asset.localIdentifier {
      c.install(controller)
    }
  }
  static func dismantleNSViewController(_ controller: NSPageController, coordinator: Coordinator) { controller.delegate = nil }
  @MainActor final class Coordinator: NSObject, NSPageControllerDelegate {
    var parent: MacMediaPager
    var active = ""
    init(_ parent: MacMediaPager) { self.parent = parent }
    func install(_ controller: NSPageController) {
      (controller as? MediaPageController)?.wheelPage = { [weak self, weak controller] direction in
        guard let self, let controller else { return }
        let index = controller.selectedIndex + MacCollectionPaging.step(forHorizontalMotion: direction)
        guard let asset = self.parent.asset(at: index) else { return }
        controller.completeTransition()
        controller.selectedIndex = index; controller.completeTransition()
        self.parent.session.paging = false
        if self.parent.session.current.asset.localIdentifier != asset.localIdentifier {
          self.parent.session.activate(asset)
        }
        self.active = asset.localIdentifier
      }
      let asset = parent.session.current.asset
      active = asset.localIdentifier
      if controller.arrangedObjects.count != parent.session.count {
        controller.arrangedObjects = Array(0..<parent.session.count)
      }
      if let index = parent.index(of: asset), controller.selectedIndex != index {
        controller.selectedIndex = index
      }
    }
    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier { "media" }
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
      let view = NSHostingController(rootView: AnyView(Color.clear)); view.view.wantsLayer = true
      view.view.autoresizingMask = [.width,.height]
      return view
    }
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
      guard let host = viewController as? NSHostingController<AnyView>, let index = object as? Int,
        let asset = parent.asset(at: index) else { return }
      host.rootView = AnyView(MacPreviewPage(preview: parent.session.model(for: asset), session: parent.session, flight: parent.flight, playRequest: asset.localIdentifier == parent.session.current.asset.localIdentifier ? parent.playRequest : 0, onSwipe: parent.onSwipe, onPull: parent.onPull, onTap: parent.onTap).environment(\.self, parent.environment))
    }
    func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect { pageController.view.bounds }
    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) { parent.session.paging = true; parent.session.current.deactivate() }
    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
      if let index = object as? Int, let asset = parent.asset(at: index) { parent.session.activate(asset) }
    }
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
      pageController.completeTransition(); parent.session.paging = false
      install(pageController)
    }
  }
}
final class MediaPageController: NSPageController {
  func pauseSelectedMedia() {
    func pause(_ view: NSView) {
      (view as? MacVideoSurface)?.pausePlayback()
      (view as? MacMediaScroll)?.live.stopPlayback()
      view.subviews.forEach(pause)
    }
    if let view = selectedViewController?.view { pause(view) }
  }

  var wheelPage: ((Int) -> Void)?
  override func scrollWheel(with event: NSEvent) {
    if event.phase.isEmpty, event.momentumPhase.isEmpty,
      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
      wheelPage?(event.scrollingDeltaX > 0 ? 1 : -1)
      return
    }
    super.scrollWheel(with: event)
  }
  override func viewDidLayout() {
    super.viewDidLayout()
    selectedViewController?.view.frame = view.bounds
  }
}
private struct MacPreviewPage: View {
  @Environment(\.macWorkspaceActive) private var active
  static func fitted(_ asset: PHAsset, in size: CGSize) -> CGRect {
    guard asset.pixelWidth > 0, asset.pixelHeight > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
    let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    var fit = CGSize(width: size.width, height: size.width / aspect)
    if fit.height > size.height { fit = CGSize(width: size.height * aspect, height: size.height) }
    return CGRect(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2, width: fit.width, height: fit.height)
  }
  @ObservedObject var preview: MediaPreviewModel
  @ObservedObject var session: MediaPreviewSession
  let flight: MacViewerFlight
  let playRequest: Int
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  var onTap: () -> Void = {}
  private var currentFlight: MacViewerFlight? {
    active && preview.asset.localIdentifier == session.current.asset.localIdentifier ? flight : nil
  }
  private var showsLoadingIndicator: Bool {
    switch preview.indicatorState {
    case .indeterminate, .progress: return true
    default: return false
    }
  }
  var body: some View {
    ZStack {
      if let player = preview.player { MacVideoWithPoster(player: player, image: preview.image, flight: currentFlight, assetID: preview.asset.localIdentifier, entryReady: preview.macEntryPosterReady, onSwipe: onSwipe, onPull: onPull).accessibilityIdentifier("library.preview.video") }
      else if let image = preview.image { MacMediaZoom(image: image, livePhoto: preview.livePhoto, playRequest: playRequest, fitRevision: session.fitRevision, zoomed: { session.zoomed = $0 }, flight: currentFlight, assetID: preview.asset.localIdentifier, entryReady: preview.macEntryPosterReady, onSwipe: onSwipe, onPull: onPull, onTap: onTap).id(preview.asset.localIdentifier).accessibilityIdentifier("library.preview.photo") }
      if showsLoadingIndicator {
        // A small badge on the photo's own bottom-right corner, mirroring the
        // Live badge at its bottom-left, instead of a large one in the window.
        GeometryReader { proxy in
          let fit = Self.fitted(preview.asset, in: proxy.size)
          Group {
            switch preview.indicatorState {
            case .progress(let value): ProgressView(value: value).progressViewStyle(.circular)
            case .indeterminate: ProgressView()
            default: EmptyView()
            }
          }
          .controlSize(.mini).frame(width: 14, height: 14).padding(5)
          .background(.ultraThinMaterial, in: Circle())
          .position(x: fit.maxX - 20, y: fit.maxY - 20)
        }.allowsHitTesting(false).accessibilityLabel(Text("preview_loading"))
      }
      if preview.cloudNeeded || preview.failure {
        MediaPreviewFailure { preview.load() }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.primary)
  }
}
struct MacMediaZoom: NSViewRepresentable {
  let image: NSImage
  let livePhoto: PHLivePhoto?
  let playRequest: Int
  let fitRevision: Int
  var zoomed: (Bool) -> Void
  var flight: MacViewerFlight? = nil
  var assetID: String = ""
  var entryReady = true
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  var onTap: () -> Void = {}
  func makeNSView(context: Context) -> MacMediaScroll { MacMediaScroll() }
  func updateNSView(_ scroll: MacMediaScroll, context: Context) {
    scroll.zoomed = zoomed
    scroll.flight = flight; scroll.flightAssetID = assetID; scroll.flightEntryReady = entryReady
    flight?.register(scroll)
    scroll.onSwipe = onSwipe; scroll.onPull = onPull; scroll.onTap = onTap
    if scroll.fitRevision != fitRevision {
      scroll.fitRevision = fitRevision; scroll.setMagnification(1, centeredAt: scroll.contentView.bounds.origin)
    }
    scroll.photo.setImage(image, holding: flight?.holdsImage(for: assetID) == true)
    scroll.live.livePhoto = livePhoto; scroll.live.isHidden = livePhoto == nil
    if scroll.playRequest != playRequest { scroll.playRequest = playRequest; scroll.live.startPlayback(with: .full) }
    scroll.needsLayout = true
  }
  static func dismantleNSView(_ scroll: MacMediaScroll, coordinator: ()) { scroll.live.stopPlayback(); scroll.live.livePhoto = nil }
}
/// Grid, flight and settled detail hand over the same CGImage representation.
/// AppKit owns view layout; Core Animation owns rendition crossfades.
@MainActor class MacMediaImageView: NSImageView {
  private var pendingImage: NSImage?
  private var displayedBitmap: CGImage?
  override var wantsUpdateLayer: Bool { true }
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.contentsGravity = .resizeAspect
    layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func setImage(_ value: NSImage?, holding: Bool) {
    if holding { pendingImage = value; return }
    pendingImage = nil
    guard image !== value else { return }
    let old = displayedBitmap
    image = value
    displayedBitmap = value?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    if let layer { MacCoverFlightSource.install(displayedBitmap, on: layer) }
    if old != nil, displayedBitmap != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let fade = CATransition(); fade.type = .fade; fade.duration = 0.2
      layer?.add(fade, forKey: "rendition")
    }
    CATransaction.commit()
  }
  override func updateLayer() { if let layer { MacCoverFlightSource.install(displayedBitmap, on: layer) } }
  func releaseFlight() {
    guard let pendingImage else { return }
    self.pendingImage = nil; setImage(pendingImage, holding: false)
  }
}
@MainActor final class MacMediaScroll: NSScrollView {
  let photo = MacMediaImageView(), live = PHLivePhotoView()
  var playRequest = 0
  var fitRevision = 0
  weak var flight: MacViewerFlight?
  var flightAssetID = ""
  var flightEntryReady = true
  private var flightReportScheduled = false
  var zoomed: ((Bool) -> Void)?
  var onSwipe: ((Int) -> Void)?
  var onPull: ((Int) -> Void)?
  var onTap: (() -> Void)?
  private var tapWork: DispatchWorkItem?
  private let media = NSView()
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    drawsBackground = false; allowsMagnification = true; minMagnification = 1; maxMagnification = 5
    // Automatic toolbar insets fitted the photo smaller than the area the
    // opening flight aimed at, so it shrank a little after landing.
    automaticallyAdjustsContentInsets = false; contentInsets = NSEdgeInsetsZero
    horizontalScrollElasticity = .none; verticalScrollElasticity = .none
    documentView = media; media.addSubview(photo); media.addSubview(live)
    photo.imageScaling = .scaleProportionallyUpOrDown; live.contentMode = .aspectFit
    let double = NSClickGestureRecognizer(target: self, action: #selector(doubleClick(_:))); double.numberOfClicksRequired = 2; addGestureRecognizer(double)
    // A single click has no chrome action; keep double-click zoom ownership.
    let single = NSClickGestureRecognizer(target: self, action: #selector(singleClick(_:))); single.numberOfClicksRequired = 1; addGestureRecognizer(single)
    // A mouse drag pages sideways and pulls up for information or down to leave.
    let drag = NSPanGestureRecognizer(target: self, action: #selector(drag(_:))); drag.buttonMask = 1; addGestureRecognizer(drag)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() {
    super.layout()
    if magnification <= 1.01 {
      media.frame = CGRect(origin: .zero, size: contentView.bounds.size); photo.frame = media.bounds; live.frame = media.bounds
    }
    scheduleFlightReport()
  }
  private func scheduleFlightReport() {
    guard flight != nil, !flightReportScheduled else { return }
    flightReportScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.flightReportScheduled = false
      if self.flightEntryReady { self.flight?.ready(image: self.photo.image, in: self.photo, id: self.flightAssetID) }
    }
  }
  private var wheelX: CGFloat = 0, wheelY: CGFloat = 0, wheelHandled = false, lastNotch = Date.distantPast
  /// Trackpad and wheel gestures at fit size: sideways pages, upwards reveals
  /// information and downwards hides it or leaves, as a mouse drag does.
  override func scrollWheel(with event: NSEvent) {
    guard magnification <= 1.01 else { super.scrollWheel(with: event); return }
    if event.phase == [] && event.momentumPhase == [] {
      if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
        if !MacPagerForwarding.forward(event, from: self) { onSwipe?(event.scrollingDeltaX > 0 ? 1 : -1) }
      } else if abs(event.scrollingDeltaY) > 2 {
        guard Date().timeIntervalSince(lastNotch) > 0.5 else { return }
        lastNotch = Date(); onPull?(event.scrollingDeltaY < 0 ? 1 : -2)
      }
      return
    }
    if event.phase == .began { wheelX = 0; wheelY = 0; wheelHandled = false }
    if event.phase.contains(.mayBegin) || (event.phase == .began && event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0) {
      _ = MacPagerForwarding.forward(event, from: self); return
    }
    if !event.momentumPhase.isEmpty {
      if abs(wheelX) > abs(wheelY) { _ = MacPagerForwarding.forward(event, from: self) }
      return
    }
    wheelX += event.scrollingDeltaX; wheelY += event.scrollingDeltaY
    if abs(wheelX) > abs(wheelY) {
      // Sideways belongs to the page controller's own live swipe.
      if !MacPagerForwarding.forward(event, from: self), event.phase == .ended, !wheelHandled {
        wheelHandled = true; onSwipe?(wheelX > 0 ? 1 : -1)
      }
      return
    }
    guard !wheelHandled, abs(wheelY) > 60 else { return }
    wheelHandled = true
    // Fingers moving up read as negative deltas under natural scrolling.
    let fingersUp = event.isDirectionInvertedFromDevice ? wheelY < 0 : wheelY > 0
    // Scrolling back only hides information; leaving stays a deliberate act.
    onPull?(fingersUp ? 1 : -2)
  }
  override func magnify(with event: NSEvent) {
    super.magnify(with: event); zoomed?(magnification > 1.01)
  }
  func releaseFlight() {
    let previous = photo.image
    photo.releaseFlight()
    if photo.image !== previous, flightEntryReady { flight?.ready(image: photo.image, in: photo, id: flightAssetID) }
  }
  @objc private func drag(_ gesture: NSPanGestureRecognizer) {
    guard gesture.state == .ended, magnification <= 1.01 else { return }
    let move = gesture.translation(in: self)
    let speed = gesture.velocity(in: self)
    // A short, quick flick pages as readily as a long drag.
    if (abs(move.x) > 40 || abs(speed.x) > 400), abs(move.x) > 1.2 * abs(move.y) { onSwipe?(move.x < 0 ? -1 : 1) }
    else if abs(move.y) > 90, abs(move.y) > 1.5 * abs(move.x) {
      // Gesture translation follows the view's own coordinates: up is positive
      // unless the view is flipped.
      let up = isFlipped ? move.y < 0 : move.y > 0
      onPull?(up ? 1 : -1)
    }
  }
  @objc private func singleClick(_ gesture: NSClickGestureRecognizer) {
    tapWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.onTap?() }
    tapWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
  }
  @objc private func doubleClick(_ gesture: NSClickGestureRecognizer) {
    tapWork?.cancel()
    setMagnification(magnification > 1.01 ? 1 : 2.5, centeredAt: gesture.location(in: media))
    zoomed?(magnification > 1.01)
  }
}

/// AVKit prepares below the retained poster. A ready player item alone is not
/// proof that its first frame has reached the window.
struct MacVideoWithPoster: NSViewRepresentable {
  @Environment(\.macWorkspaceActive) private var active
  let player: AVPlayer
  let image: NSImage?
  var flight: MacViewerFlight? = nil
  var assetID: String = ""
  var entryReady = true
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  func makeNSView(context: Context) -> MacVideoSurface { MacVideoSurface() }
  func updateNSView(_ view: MacVideoSurface, context: Context) {
    view.onSwipe = onSwipe; view.onPull = onPull
    view.wheelEnabled = active
    view.flight = flight; view.flightAssetID = assetID; view.flightEntryReady = entryReady
    flight?.register(view)
    view.update(player: player, image: image)
  }
  static func dismantleNSView(_ view: MacVideoSurface, coordinator: ()) { view.stop() }
}
/// A video keeps paging: sideways trackpad scrolls go to the page controller
/// instead of scrubbing, and a mouse drag outside the control bar swipes.
/// AVPlayerView's own subviews receive scroll events and scrub with them
/// before any ancestor sees them, so sideways gestures over a video are taken
/// from the window's event stream instead and handed to the page controller.
@MainActor private final class MacPagingPlayerView: AVPlayerView {
  var wheelEnabled = true
  private var monitor: Any?
  private var sideways = false
  private var wheelX: CGFloat = 0, wheelY: CGFloat = 0
  var onSwipe: ((Int) -> Void)?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, self.wheelEnabled, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
        self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
      // The direction is decided when a gesture begins and kept through its
      // momentum, so a sideways swipe never turns into scrubbing halfway.
      if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
        self.sideways = false; self.wheelX = 0; self.wheelY = 0
      }
      self.wheelX += event.scrollingDeltaX; self.wheelY += event.scrollingDeltaY
      if !self.sideways { self.sideways = abs(self.wheelX) > abs(self.wheelY) }
      guard self.sideways else { return event }
      if MacPagerForwarding.forward(event, from: self) { return nil }
      if event.phase == .ended { self.onSwipe?(self.wheelX > 0 ? 1 : -1) }
      return nil
    }
  }
}
/// Hands a scroll event to the enclosing page controller, which owns the
/// interactive swipe. The hosting views between them do not pass it on.
@MainActor enum MacPagerForwarding {
  static func forward(_ event: NSEvent, from view: NSView) -> Bool {
    var current: NSView? = view.superview
    while let candidate = current {
      if let pager = candidate.nextResponder as? NSPageController {
        // A leaf media adapter may be nested in a wider collection. Continue
        // to that collection's native strip instead of consuming the gesture.
        if pager.arrangedObjects.count < 2 { current = candidate.superview; continue }
        pager.scrollWheel(with: event); return true
      }
      current = candidate.superview
    }
    return false
  }
}
@MainActor final class MacVideoSurface: NSView {
  var wheelEnabled = true { didSet { video.wheelEnabled = wheelEnabled } }
  private let video = MacPagingPlayerView()
  weak var flight: MacViewerFlight?
  var flightAssetID = ""
  var flightEntryReady = true
  private var flightReportScheduled = false
  var onSwipe: ((Int) -> Void)?
  var onPull: ((Int) -> Void)?
  @objc private func drag(_ gesture: NSPanGestureRecognizer) {
    guard gesture.state == .ended else { return }
    // The bottom strip belongs to the playback controls and their scrubber.
    let start = gesture.location(in: self).y - gesture.translation(in: self).y
    guard start > 70 else { return }
    let move = gesture.translation(in: self), speed = gesture.velocity(in: self)
    if (abs(move.x) > 40 || abs(speed.x) > 400), abs(move.x) > 1.2 * abs(move.y) { onSwipe?(move.x < 0 ? -1 : 1) }
    else if abs(move.y) > 60, abs(move.y) > 1.5 * abs(move.x) { onPull?(move.y > 0 ? 1 : -1) }
  }
  private let poster = MacVideoPoster()
  private var observation: NSKeyValueObservation?
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    video.controlsStyle = .floating; video.videoGravity = .resizeAspect
    video.showsFullScreenToggleButton = true
    poster.imageScaling = .scaleProportionallyUpOrDown
    addSubview(video); addSubview(poster)
    let drag = NSPanGestureRecognizer(target: self, action: #selector(drag(_:)))
    drag.buttonMask = 1; drag.delaysPrimaryMouseButtonEvents = false
    addGestureRecognizer(drag)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func pausePlayback() { video.player?.pause() }
  func update(player: AVPlayer, image: NSImage?) {
    video.onSwipe = onSwipe
    poster.setImage(image, holding: flight?.holdsImage(for: flightAssetID) == true)
    if video.player !== player {
      observation = nil; video.player = player; poster.isHidden = false
      observation = video.observe(\.isReadyForDisplay, options: [.initial,.new]) { [weak self] _,_ in
        Task { @MainActor in
          guard let self else { return }; self.releaseFlight()
        }
      }
    }
    releaseFlight(); needsLayout = true
  }
  func releaseFlight() {
    if flight?.holdsImage(for: flightAssetID) != true { poster.releaseFlight() }
    poster.isHidden = video.isReadyForDisplay && (flight?.mediaVisible ?? true)
  }
  override func layout() {
    super.layout(); video.frame = bounds; poster.frame = bounds
    guard flight != nil, !flightReportScheduled else { return }
    flightReportScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.flightReportScheduled = false
      if self.flightEntryReady { self.flight?.ready(image: self.poster.image, in: self.poster, id: self.flightAssetID) }
    }
  }
  func stop() { observation = nil; video.player?.pause(); video.player = nil }
}
@MainActor private final class MacVideoPoster: MacMediaImageView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The hidden grid must not retain ownership of Escape/Space while the viewer
/// is active. Install once per viewer and remove on every dismissal path.
struct MacMediaKeyHandler: NSViewRepresentable {
  @Environment(\.macWorkspaceActive) private var active
  var handle: (NSEvent) -> Bool
  func makeNSView(context: Context) -> MacMediaKeyView { MacMediaKeyView() }
  func updateNSView(_ view: MacMediaKeyView, context: Context) { view.handle = active ? handle : nil }
  static func dismantleNSView(_ view: MacMediaKeyView, coordinator: ()) { view.stop() }
}
@MainActor final class MacMediaKeyView: NSView {
  var handle: ((NSEvent) -> Bool)?
  private var monitor: Any?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow(); stop()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window?.isKeyWindow == true, !self.isHiddenOrHasHiddenAncestor else { return event }
      return self.handle?(event) == true ? nil : event
    }
  }
  func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

/// Fallback for an entry point without a workspace environment; it still hosts the same sidebar and chrome.
@MainActor enum MacPhotoViewerWindow {
  private static var controller: NSWindowController?
  static func open(asset: PHAsset, library: PhotoLibraryModel, collection: [PHAsset]? = nil) {
    show(.photo(asset, collection ?? [asset], nil), library: library)
  }
  static func openUnavailable(_ photo: HistoryPhoto, model: BackupModel) {
    show(.photo(nil, [], photo), library: PhotoLibraryModel())
  }
  static func openFolder(_ photo: FolderPhoto, context: [FolderPhoto], folders: FolderSources) {
    show(.folder(photo, context, folders, nil), library: PhotoLibraryModel())
  }
  private static func show(_ request: MacViewerRequest, library: PhotoLibraryModel) {
    controller?.close()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.identifier = NSUserInterfaceItemIdentifier("photo.viewer")
    let host = NSHostingController(rootView: MacWorkspace(model: BackupEnvironment.activeModel(), library: library,
      initialDestination: .transfers, initialViewer: request))
    host.sizingOptions = []; window.contentViewController = host
    window.setContentSize(NSSize(width: 1180, height: 800)); window.contentMinSize = NSSize(width: 900, height: 620)
    window.isReleasedWhenClosed = false; window.center()
    let made = NSWindowController(window: window); controller = made; made.showWindow(nil)
  }
}

/// One native directory owns mixed-source paging. Leaf adapters render media and
/// contribute facts; they never replace the directory after a swipe settles.
struct MacCollectionPager: NSViewControllerRepresentable {
  @Environment(\.self) private var environment
  @Environment(\.macWorkspaceActive) private var active
  var count: Int
  var selectedIndex: Int
  var animated = false
  var selected: (Int) -> Void
  var page: (Int, Bool) -> AnyView
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSViewController(context: Context) -> MediaPageController {
    let controller = MediaPageController()
    controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 550))
    controller.view.autoresizingMask = [.width, .height]
    controller.transitionStyle = .horizontalStrip
    controller.delegate = context.coordinator
    context.coordinator.install(controller)
    return controller
  }
  func updateNSViewController(_ controller: MediaPageController, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    guard !coordinator.transitioning else { return }
    coordinator.install(controller)
  }
  static func dismantleNSViewController(_ controller: MediaPageController, coordinator: Coordinator) {
    controller.delegate = nil; controller.wheelPage = nil
  }
  @MainActor final class Coordinator: NSObject, NSPageControllerDelegate {
    var parent: MacCollectionPager
    var transitioning = false
    private var hosts: [ObjectIdentifier: (NSHostingController<AnyView>, Int)] = [:]
    init(_ parent: MacCollectionPager) { self.parent = parent }
    func install(_ controller: MediaPageController) {
      controller.wheelPage = { [weak self, weak controller] direction in
        guard let self, let controller, !self.transitioning else { return }
        let index = controller.selectedIndex + MacCollectionPaging.step(forHorizontalMotion: direction)
        guard (0..<self.parent.count).contains(index) else { return }
        controller.selectedIndex = index; controller.completeTransition()
        self.parent.selected(index); self.refresh(selected: index)
      }
      if controller.arrangedObjects.count != parent.count {
        controller.arrangedObjects = Array(0..<parent.count)
      }
      guard (0..<parent.count).contains(parent.selectedIndex) else { return }
      let index = parent.selectedIndex
      if controller.selectedIndex != index, parent.animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        transitioning = true
        NSAnimationContext.runAnimationGroup { context in
          context.duration = DuckMotion.enter
          controller.animator().selectedIndex = index
        } completionHandler: { [weak self, weak controller] in
          MainActor.assumeIsolated {
            guard let self, let controller else { return }
            controller.completeTransition(); self.transitioning = false
            self.refresh(selected: controller.selectedIndex)
          }
        }
      } else {
        if controller.selectedIndex != index { controller.selectedIndex = index; controller.completeTransition() }
        refresh(selected: index)
      }
    }
    private func page(_ index: Int, selected: Bool) -> AnyView {
      AnyView(parent.page(index, selected)
        .environment(\.self, parent.environment)
        .environment(\.macWorkspaceActive, parent.active && selected))
    }
    private func refresh(selected: Int) {
      for (_, (host, index)) in hosts where (0..<parent.count).contains(index) {
        host.rootView = page(index, selected: index == selected)
      }
    }
    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier { "media" }
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
      NSHostingController(rootView: AnyView(Color.clear))
    }
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
      guard let index = object as? Int, (0..<parent.count).contains(index), let host = viewController as? NSHostingController<AnyView> else { return }
      hosts[ObjectIdentifier(host)] = (host, index)
      host.rootView = page(index, selected: index == pageController.selectedIndex)
    }
    func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect { pageController.view.bounds }
    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
      transitioning = true
      (pageController as? MediaPageController)?.pauseSelectedMedia()
    }
    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
      guard let index = object as? Int else { return }
      parent.selected(index)
    }
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
      pageController.completeTransition(); transitioning = false
      refresh(selected: pageController.selectedIndex)
    }
  }
}

/// An information target describes source identity, never the surface that opened it.
/// Grid selection and viewer paging therefore use exactly the same facts and actions.
enum MacPhotoInformationTarget {
  case library(PHAsset, PhotoLibraryModel?, BackupJob?)
  case folder(FolderPhoto, FolderSources, BackupJob?)
  case recorded(HistoryPhoto)
  case selection(Int)
  var identity: String {
    switch self {
    case let .library(asset, _, _): return "asset:" + asset.localIdentifier + "|" + PhotoLibraryModel.revision(asset)
    case let .folder(photo, _, _): return "file:" + photo.source_id + "|" + photo.revision
    case let .recorded(photo): return "record:" + photo.source
    case let .selection(count): return "selection:\(count)"
    }
  }
}

/// The native workspace window owns the only presentation choice. Contributors
/// change the target; only an explicit Info action or window close changes visibility.
@MainActor final class MacPhotoInfoStore: ObservableObject {
  @Published var isPresented = false
  @Published private(set) var target: MacPhotoInformationTarget = .selection(0)
  private(set) var currentOwner: UUID?
  var openHistory: ((HistoryPhoto) -> Void)?
  func publish(_ target: MacPhotoInformationTarget, owner: UUID, history: ((HistoryPhoto) -> Void)?) {
    currentOwner = owner; openHistory = history; self.target = target
  }
  func withdraw(owner: UUID) {
    guard currentOwner == owner else { return }
    currentOwner = nil; openHistory = nil; target = .selection(0)
  }
}

struct MacPhotoInformationRoot: View {
  @ObservedObject var store: MacPhotoInfoStore
  var body: some View {
    Group {
      if store.isPresented {
        ScrollView {
          MacPhotoInformationContent(target: store.target)
            .id(store.target.identity).padding(DuckSpacing.large)
        }
      }
    }
    .environment(\.macViewerHistory, store.openHistory)
  }
}

struct MacPhotoInformationContent: View {
  let target: MacPhotoInformationTarget
  @ViewBuilder var body: some View {
    switch target {
    case let .library(asset, library, recorded):
      MacPhotoInformation(asset: asset, library: library, recorded: recorded)
    case let .folder(photo, folders, recorded):
      MacFolderInformation(photo: photo, folders: folders, recorded: recorded)
    case let .recorded(photo): MacRecordedInformation(photo: photo)
    case let .selection(count):
      VStack(alignment: .leading, spacing: DuckSpacing.small) {
        if count > 1 {
          Text(String(format: NSLocalizedString("grid_selected_count", comment: ""), count)).font(.headline)
          Text("grid_info_multiple_note").foregroundStyle(.secondary)
        } else {
          Text("grid_info_no_selection").font(.headline)
          Text("grid_info_select_photo").foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Paging owns media lifetimes; Info belongs to the native workspace window.
struct MacViewerLayout<Content: View>: View {
  let navigation: MacLibraryNavigation
  @ViewBuilder var content: () -> Content
  var body: some View { content() }
}
struct MacViewerInspector: ViewModifier {
  @Environment(\.macWorkspaceActive) private var active
  @Environment(\.macViewerHistory) private var history
  let navigation: MacLibraryNavigation
  let target: MacPhotoInformationTarget
  func body(content: Content) -> some View {
    content.background(MacViewerInspectorContribution(target: target, navigation: navigation,
      active: active, history: history))
  }
}
struct MacInfoWindowAnchor: NSViewRepresentable {
  let navigation: MacLibraryNavigation
  func makeNSView(context: Context) -> MacViewerInspectorAnchor { MacViewerInspectorAnchor() }
  func updateNSView(_ view: MacViewerInspectorAnchor, context: Context) {
    view.update(target: .selection(0), navigation: navigation, active: false, history: nil)
  }
}
private struct MacViewerInspectorContribution: NSViewRepresentable {
  let target: MacPhotoInformationTarget
  let navigation: MacLibraryNavigation
  let active: Bool
  var history: ((HistoryPhoto) -> Void)?
  func makeNSView(context: Context) -> MacViewerInspectorAnchor { MacViewerInspectorAnchor() }
  func updateNSView(_ view: MacViewerInspectorAnchor, context: Context) {
    view.update(target: target, navigation: navigation, active: active, history: history)
  }
  static func dismantleNSView(_ view: MacViewerInspectorAnchor, coordinator: ()) { view.withdraw() }
}

/// Native presentation crosses the representable update boundary. A retiring
/// contribution cannot clear a successor that has already adopted the same photo.
@MainActor final class MacViewerInspectorAnchor: NSView {
  private let ownerToken = UUID()
  private var target: MacPhotoInformationTarget = .selection(0)
  private var history: ((HistoryPhoto) -> Void)?
  private weak var navigation: MacLibraryNavigation?
  private weak var owner: NSWindow?
  private var active = false, scheduled = false
  private var generation = 0
  func update(target: MacPhotoInformationTarget, navigation: MacLibraryNavigation, active: Bool,
    history: ((HistoryPhoto) -> Void)?) {
    self.target = target; self.navigation = navigation; self.active = active; self.history = history
    schedule()
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if owner !== window { withdraw(); owner = window }
    schedule()
  }
  private func schedule() {
    guard !scheduled else { return }
    scheduled = true
    let expected = generation
    DispatchQueue.main.async { [weak self] in
      guard let self, self.generation == expected else { return }
      self.scheduled = false
      guard let window = self.window, let navigation = self.navigation else { return }
      self.owner = window
      let info = MacViewerInfoPanel.forWindow(window)
      navigation.bindInformation(info.store)
      if self.active { info.store.publish(self.target, owner: self.ownerToken, history: self.history) }
      else { self.withdrawTarget(from: info.store) }
    }
  }
  private func withdrawTarget(from store: MacPhotoInfoStore) {
    let token = ownerToken
    DispatchQueue.main.async { store.withdraw(owner: token) }
  }
  func withdraw() {
    generation &+= 1; scheduled = false
    if let owner, let info = MacViewerInfoPanel.existing(for: owner) { withdrawTarget(from: info.store) }
  }
}

@MainActor final class MacPhotoInfoUtilityPanel: NSPanel {
  weak var workspaceWindow: NSWindow?
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
      event.charactersIgnoringModifiers?.lowercased() == "i" {
      performClose(nil); return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

@MainActor final class MacViewerInfoPanel: NSObject, NSWindowDelegate {
  private static let panels = NSMapTable<NSWindow, MacViewerInfoPanel>.weakToStrongObjects()
  private static func workspaceWindow(_ window: NSWindow) -> NSWindow {
    if let parent = window.sheetParent { return workspaceWindow(parent) }
    if let owner = (window as? MacPhotoInfoUtilityPanel)?.workspaceWindow { return workspaceWindow(owner) }
    return window
  }
  static func existing(for window: NSWindow) -> MacViewerInfoPanel? { panels.object(forKey: workspaceWindow(window)) }
  static func forWindow(_ window: NSWindow) -> MacViewerInfoPanel {
    let window = workspaceWindow(window)
    if let existing = existing(for: window) { return existing }
    let made = MacViewerInfoPanel(owner: window); panels.setObject(made, forKey: window); return made
  }
  let panel: NSPanel
  let store: MacPhotoInfoStore
  let controller: NSHostingController<MacPhotoInformationRoot>
  private weak var owner: NSWindow?
  private var observation: AnyCancellable?
  private var ownerClose: NSObjectProtocol?
  private init(owner: NSWindow) {
    self.owner = owner
    let store = MacPhotoInfoStore(); self.store = store
    controller = NSHostingController(rootView: MacPhotoInformationRoot(store: store))
    panel = MacPhotoInfoUtilityPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
      styleMask: [.titled, .closable, .utilityWindow, .resizable], backing: .buffered, defer: false)
    super.init()
    (panel as? MacPhotoInfoUtilityPanel)?.workspaceWindow = owner
    panel.title = NSLocalizedString("photo_viewer_info", comment: "")
    panel.identifier = NSUserInterfaceItemIdentifier("photo.info")
    panel.appearance = owner.appearance
    panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
    panel.hidesOnDeactivate = true; panel.becomesKeyOnlyIfNeeded = true
    panel.delegate = self
    // AppKit owns utility-window geometry. An empty SwiftUI root must not
    // supply the panel's initial fitting size or resize it as selection changes.
    let contentSize = panel.contentLayoutRect.size
    let container = NSViewController()
    container.view = NSView(frame: NSRect(origin: .zero, size: contentSize))
    container.view.autoresizingMask = [.width, .height]
    controller.sizingOptions = []
    container.addChild(controller)
    controller.view.frame = container.view.bounds
    controller.view.autoresizingMask = [.width, .height]
    container.view.addSubview(controller.view)
    panel.contentViewController = container
    panel.setContentSize(contentSize)
    panel.contentMinSize = NSSize(width: 280, height: 280)
    panel.setFrameTopLeftPoint(NSPoint(x: owner.frame.maxX - panel.frame.width - DuckSpacing.large,
      y: owner.frame.maxY - DuckSpacing.large))
    observation = store.$isPresented.dropFirst().sink { [weak self] visible in self?.setVisible(visible) }
    ownerClose = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
      object: owner, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.store.isPresented = false }
      }
  }
  deinit { if let ownerClose { NotificationCenter.default.removeObserver(ownerClose) } }
  private func setVisible(_ visible: Bool) {
    panel.appearance = owner?.appearance
    if visible, owner?.isVisible == true { panel.orderFront(nil) }
    else if !visible { panel.orderOut(nil) }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    store.isPresented = false
    return true
  }
}

/// Grids contribute to the same window panel without sharing a viewer session.
private struct MacGridInformationEnabledKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
  var macGridInformationEnabled: Bool {
    get { self[MacGridInformationEnabledKey.self] }
    set { self[MacGridInformationEnabledKey.self] = newValue }
  }
}
struct MacGridInfoCommands { var toggle: () -> Void }
private struct MacGridInfoCommandsKey: FocusedValueKey { typealias Value = MacGridInfoCommands }
private struct MacWindowInfoCommandsKey: FocusedValueKey { typealias Value = MacGridInfoCommands }
extension FocusedValues {
  var windowInfoCommands: MacGridInfoCommands? {
    get { self[MacWindowInfoCommandsKey.self] }
    set { self[MacWindowInfoCommandsKey.self] = newValue }
  }
  var gridInfoCommands: MacGridInfoCommands? {
    get { self[MacGridInfoCommandsKey.self] }
    set { self[MacGridInfoCommandsKey.self] = newValue }
  }
}

struct MacGridInspector: ViewModifier {
  @Environment(\.macWorkspaceActive) private var workspaceActive
  @Environment(\.macGridInformationEnabled) private var enabled
  @Environment(\.macGridToolbarState) private var toolbarState
  @Environment(\.macViewerHistory) private var history
  @ObservedObject var navigation: MacLibraryNavigation
  let source: any MacGridSource
  var active = true
  // Retained sources pass their observed selection as a value dependency.
  var selection: Set<String>? = nil
  @State private var toolbarOwner = UUID()
  private var ownsInfo: Bool { active && workspaceActive && enabled && !navigation.viewerOpen && navigation.level == .all }
  func body(content: Content) -> some View {
    let ids = source.membershipReady ? (selection ?? source.selection).intersection(Set(source.identifiers)).sorted() : []
    content
      .background(MacViewerInspectorContribution(target: ids.count == 1 ? source.informationTarget(ids[0]) : .selection(ids.count),
        navigation: navigation, active: ownsInfo, history: history))
      .focusedSceneValue(\.gridInfoCommands, ownsInfo && !source.identifiers.isEmpty ? MacGridInfoCommands(toggle: { navigation.toggleInformation() }) : nil)
      .onChange(of: ids, initial: true) { _, ids in updateToolbar(ids) }
      .onChange(of: source.identifiers.isEmpty) { _, _ in updateToolbar(ids) }
      .onChange(of: ownsInfo, initial: true) { _, _ in updateToolbar(ids) }
      .onDisappear { toolbarState?.withdraw(owner: toolbarOwner) }
      .toolbar {
        if toolbarState == nil, ownsInfo, !source.identifiers.isEmpty {
          ToolbarItem(id: "browser.info", placement: .primaryAction) {
            Button { navigation.toggleInformation() } label: { Label("photo_viewer_info", systemImage: "info.circle") }
              .help(Text("folders_show_info"))
              .accessibilityIdentifier("library.grid.info")
          }
        }
      }
  }
  private func updateToolbar(_ ids: [String]) {
    if ownsInfo { toolbarState?.update(owner: toolbarOwner, navigation: navigation, hasItems: !source.identifiers.isEmpty) }
    else { toolbarState?.withdraw(owner: toolbarOwner) }
  }
}

/// Shared information action policy, independent of grid or viewer presentation.
enum MacPhotoInformationAction: Equatable {
  case none, backup, retry
  var title: String? {
    switch self { case .none: nil; case .backup: "library_context_backup"; case .retry: "retry_task" }
  }
  static func resolve(loaded: Bool, unavailable: Bool, state: String, paired: Bool,
    canBackUp: Bool, hasJob: Bool) -> Self {
    guard loaded, !unavailable else { return .none }
    if state == "photo_viewer_failed", hasJob || (paired && canBackUp) { return .retry }
    guard paired, canBackUp else { return .none }
    return state == "photo_viewer_not_backed_up" ? .backup : .none
  }
}

struct MacInformationHistory: ViewModifier {
  @Binding var presented: Bool
  let job: BackupJob?
  @ObservedObject var model: BackupModel
  func body(content: Content) -> some View {
    content.sheet(isPresented: $presented) {
      NavigationStack {
        BackupHistoryView(model: model, initialFocus: job.map(HistoryPhoto.init)).navigationTitle("records_title")
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("records_done") { presented = false } } }
      }.frame(minWidth: 640, minHeight: 480).environment(\.macViewerPresentation, nil)
    }
  }
}
struct MacInformationConfirmation: ViewModifier {
  @ObservedObject var action: SelectionBackupAction
  let confirm: () async -> Void
  func body(content: Content) -> some View {
    content.confirmationDialog("selection_backup_repeat_title", isPresented: $action.confirmingRepeat, titleVisibility: .visible) {
      Button("selection_backup_repeat_action") { Task { await confirm() } }
      Button("cancel", role: .cancel) { action.cancel() }
    } message: { Text("selection_backup_repeat_note") }
  }
}

/// Both the grid and viewer render this exact component and register the same
/// durable request. Metadata loading never starts a second media session.
struct MacPhotoInformation: View {
  @StateObject private var preview: MediaPreviewModel
  @StateObject private var facts = MacViewerFacts()
  @StateObject private var action = SelectionBackupAction()
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @Environment(\.macViewerHistory) private var openHistory
  @State private var history = false
  let library: PhotoLibraryModel
  let recorded: BackupJob?
  init(asset: PHAsset, library: PhotoLibraryModel? = nil, recorded: BackupJob? = nil) {
    self.library = library ?? PhotoLibraryModel()
    self.recorded = recorded?.asset.source_id == asset.localIdentifier ? recorded : nil
    _preview = StateObject(wrappedValue: MediaPreviewModel(asset: asset, isCurrent: false))
  }
  private var informationAction: MacPhotoInformationAction {
    .resolve(loaded: facts.loaded, unavailable: facts.unavailable, state: facts.stateKey,
      paired: model.pairing != nil, canBackUp: true, hasJob: facts.job != nil)
  }
  var body: some View {
    PhotoMetadataPanel(preview: preview, revision: facts.informationRevision, backupInfo: { fields in
      AnyView(facts.information(takenAt: preview.asset.creationDate, filename: preview.filename,
        fields: fields, model: model, action: informationAction.title,
        busy: action.busy || facts.working, perform: requestBackup, history: showHistory))
    })
    .task(id: "\(preview.asset.localIdentifier)|\(model.pairing?.receiverID ?? "")|\(model.queueRevision)|\(model.pendingImports)|\(model.summary.received)|\(model.summary.published)") { await loadFacts() }
    .modifier(MacInformationConfirmation(action: action) {
      await action.confirm(library: library, model: model); facts.error = action.error; await loadFacts()
    })
    .modifier(MacInformationHistory(presented: $history, job: facts.job, model: model))
  }
  private func loadFacts() async {
    await facts.load(source: preview.asset.localIdentifier,
      revision: recorded == nil ? PhotoLibraryModel.revision(preview.asset) : nil,
      model: model, library: recorded == nil ? library : nil, recorded: recorded)
  }
  private func showHistory() {
    guard let job = facts.job else { return }
    if let openHistory { openHistory(HistoryPhoto(job: job)) } else { history = true }
  }
  private func requestBackup() {
    guard !facts.working, !action.busy else { return }
    let requestedAction = informationAction
    Task {
      facts.working = true
      if requestedAction == .retry, let job = facts.job {
        facts.error = await model.retry(job.id) ? nil : model.message
      } else {
        await action.request(library: library, model: model, sources: [preview.asset.localIdentifier])
        facts.error = action.error
      }
      facts.working = false; await loadFacts()
    }
  }
}

struct MacRecordedInformation: View {
  let photo: HistoryPhoto
  @StateObject private var facts = MacViewerFacts()
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @Environment(\.macViewerHistory) private var openHistory
  @State private var history = false
  private var informationAction: MacPhotoInformationAction {
    .resolve(loaded: facts.loaded, unavailable: facts.unavailable, state: facts.stateKey,
      paired: model.pairing != nil, canBackUp: false, hasJob: facts.job != nil)
  }
  var body: some View {
    facts.information(takenAt: photo.takenAt, filename: photo.job?.asset.resources.first?.filename ?? "",
      fields: PhotoInformationLayout.fileFields(for: photo.job), model: model,
      action: informationAction.title, busy: facts.working, perform: retry, history: {
        guard let job = facts.job else { return }
        if let openHistory { openHistory(HistoryPhoto(job: job)) } else { history = true }
      })
    .task(id: "\(photo.source)|\(model.queueRevision)|\(model.summary.received)|\(model.summary.published)") { await loadFacts() }
    .modifier(MacInformationHistory(presented: $history, job: facts.job, model: model))
  }
  private func loadFacts() async { await facts.load(source: photo.source, revision: nil, model: model, recorded: photo.job) }
  private func retry() {
    guard !facts.working, let job = facts.job else { return }
    Task {
      facts.working = true; facts.error = await model.retry(job.id) ? nil : model.message
      facts.working = false; await loadFacts()
    }
  }
}

struct MacFolderInformation: View {
  let photo: FolderPhoto
  @ObservedObject var folders: FolderSources
  var recorded: BackupJob?
  @StateObject private var facts = MacViewerFacts()
  @StateObject private var action = SelectionBackupAction()
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @Environment(\.macViewerHistory) private var openHistory
  @State private var history = false
  @State private var resolution: String?
  private var informationAction: MacPhotoInformationAction {
    .resolve(loaded: facts.loaded, unavailable: facts.unavailable, state: facts.stateKey,
      paired: model.pairing != nil, canBackUp: photo.canBackUp, hasJob: facts.job != nil)
  }
  var body: some View {
    PhotoInformationLayout(takenAt: photo.date, job: facts.job,
      receiverName: facts.job.flatMap { model.receiverDeviceName(for: $0) } ?? model.peerDevice?.name ?? "Pixel",
      needsYou: photo.backup == "needs_you", filename: (photo.relative as NSString).lastPathComponent,
      fields: fields, model: model, loaded: facts.loaded, unavailable: facts.unavailable,
      unpaired: model.pairing == nil && facts.job == nil && photo.backup != "saved",
      preparing: facts.working || photo.backup == "sending", allowsRetry: false,
      showHistory: facts.job == nil ? nil : {
        if let job = facts.job, let openHistory { openHistory(HistoryPhoto(job: job)) } else { history = true }
      }, actionKey: informationAction.title, actionBusy: facts.working || action.busy,
      performAction: requestBackup, actionFailure: facts.error,
      backupFacts: facts.job == nil && photo.backup == "saved" ? AnyView(savedFact) : nil)
    .task(id: "\(photo.id)|\(photo.revision)|\(model.pairing?.receiverID ?? "")|\(model.queueRevision)|\(model.summary.received)|\(model.summary.published)|\(folders.revision)") { await loadFacts() }
    .task(id: "\(photo.id)|\(photo.revision)|\(folders.facts[photo.folder_id]?.available == true)") { await loadResolution() }
    .modifier(MacInformationConfirmation(action: action) { await action.confirm(); facts.error = action.error; await loadFacts() })
    .modifier(MacInformationHistory(presented: $history, job: facts.job, model: model))
  }
  private func loadFacts() async {
    await facts.load(source: photo.source_id, revision: photo.revision, model: model, recorded: recorded, fallback: photo.backup)
  }
  private func requestBackup() {
    guard !facts.working, !action.busy else { return }
    let receiver = model.pairing?.receiverID
    Task {
      if informationAction == .retry, let job = facts.job {
        facts.working = true; facts.error = await model.retry(job.id) ? nil : model.message; facts.working = false
      } else {
        var repeats = Set<String>()
        await action.request(prepare: {
          guard let receiver, model.pairing?.receiverID == receiver else { throw Bridge.Failure(code: "conflict") }
          repeats = try await folders.selectedBackupRepeatSources([photo], receiver: receiver)
          return !repeats.isEmpty
        }, submit: {
          guard let receiver, model.pairing?.receiverID == receiver else { return false }
          return await folders.backUp([photo], receiver: receiver, repeatSources: repeats)
        }, failure: { folders.error })
        facts.error = action.error
      }
      await loadFacts()
    }
  }
  private var fields: [(String, String)] {
    let format = UTType(mimeType: photo.media_type)?.localizedDescription ?? photo.media_type
    var fields = [("preview_file_size", ByteCountFormatter.string(fromByteCount: Int64(clamping: photo.size), countStyle: .file)),
      ("preview_format", format)]
    if let resolution { fields.append(("preview_resolution", resolution)) }
    if photo.date_source == "file_modified" { fields.append(("design_capture_time", NSLocalizedString("folders_date_fallback", comment: ""))) }
    return fields
  }
  private func loadResolution() async {
    resolution = nil
    guard let source = folders.sources.first(where: { $0.id == photo.folder_id }),
      let root = folders.sourceURL(source), !photo.relative.hasPrefix("/"),
      !photo.relative.split(separator: "/").contains("..") else { return }
    let file = root.appendingPathComponent(photo.relative).standardizedFileURL
    guard file.path.hasPrefix(root.standardizedFileURL.path + "/") else { return }
    let video = photo.media_type.hasPrefix("video/")
    let result = await Task.detached(priority: .userInitiated) { () async -> String? in
      _ = root.startAccessingSecurityScopedResource()
      defer { root.stopAccessingSecurityScopedResource() }
      guard file.resolvingSymlinksInPath().path == file.path else { return nil }
      if video {
        let asset = AVURLAsset(url: file)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
          let size = try? await track.load(.naturalSize),
          let transform = try? await track.load(.preferredTransform) else { return nil }
        let transformed = size.applying(transform)
        let width = abs(transformed.width), height = abs(transformed.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return "\(Int(width.rounded())) × \(Int(height.rounded()))"
      }
      guard let image = CGImageSourceCreateWithURL(file as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
      let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
      return (5...8).contains(orientation) ? "\(height) × \(width)" : "\(width) × \(height)"
    }.value
    if !Task.isCancelled { resolution = result }
  }
  private var savedFact: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.small) {
      Label("records_fact_saved", systemImage: "checkmark.circle.fill").foregroundStyle(DuckRole.primaryText)
      if let time = photo.saved_at_ms {
        Text(Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .abbreviated, time: .shortened))
          .font(.callout).foregroundStyle(.secondary)
      }
    }
  }
}

/// Missing originals retain their recorded facts, using the same inspector and toolbar state.
struct MacRecordedPhotoPreview: View {
  @Environment(\.macWorkspaceActive) private var active
  let photo: HistoryPhoto
  @ObservedObject var model: BackupModel
  @ObservedObject var navigation: MacLibraryNavigation
  var close: () -> Void
  var collectionPaging: MacCollectionPaging? = nil
  @StateObject private var facts = MacViewerFacts()
  @StateObject private var router = BackupPhotoRouter()
  @Environment(\.macViewerPresentation) private var present
  var body: some View {
    GeometryReader { proxy in
      let side = max(1, min(proxy.size.width, proxy.size.height))
      if photo.job?.asset.metadata?["source_type"] == "folder" {
        MacFolderPreviewUnavailable {
          router.macPresent = present
          router.open(photo, collection: [photo], frame: .zero)
        }.frame(width: proxy.size.width, height: proxy.size.height)
      } else {
        AssetThumbnail(sourceID: photo.source, size: side, cornerRadius: 0)
          .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }.background(DuckRole.background)
      .modifier(MacViewerNavigationControls(previousEnabled: collectionPaging?.hasPrevious ?? false,
        nextEnabled: collectionPaging?.hasNext ?? false,
        previous: { collectionPaging?.move(-1) }, next: { collectionPaging?.move(1) }))
      .modifier(MacViewerInspector(navigation: navigation, target: .recorded(photo)))
      .background(MacMediaKeyHandler { event in
        if event.keyCode == 53 { close(); return true }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
          if event.keyCode == 123 { collectionPaging?.move(-1); return true }
          if event.keyCode == 124 { collectionPaging?.move(1); return true }
        }
        return false
      })
      .task(id: "\(model.queueRevision)|\(model.summary.received)|\(model.summary.published)|\(active)") {
        guard active else { return }
        navigation.viewerTitle = MacViewerTitle.date(photo.takenAt)
        navigation.viewerSubtitle = MacViewerTitle.subtitle(photo.takenAt, index: (collectionPaging?.index ?? 0) + 1, total: collectionPaging?.count ?? 1)
        navigation.viewerCurrent = nil; navigation.viewerShare = nil; navigation.viewerHasLive = false
        if collectionPaging == nil { navigation.viewerBack = close }
        await facts.load(source: photo.source, revision: nil, model: model, recorded: photo.job)
        updateMark()
      }
      .onDisappear { if active, collectionPaging == nil { navigation.viewerBack = nil } }
      .onChange(of: facts.stateKey) { _, _ in updateMark() }
      .onChange(of: facts.job) { _, _ in updateMark() }
    .onChange(of: facts.job.flatMap { model.transferProgress[$0.id] }) { _, _ in updateMark() }
  }
  private func updateMark() { guard active else { return }; navigation.viewerState = facts.stateKey(model: model); navigation.viewerProgress = facts.progress(model: model) }
}

/// The same window-scoped presentation is inherited by history and file grids.
struct MacCollectionPaging {
  var index: Int
  var count: Int
  var move: (Int) -> Void
  var native = false
  var swipe: ((Int) -> Void)? = nil
  var hasPrevious: Bool { index > 0 }
  var hasNext: Bool { index + 1 < count }
  /// Media motion is opposite to the next-page command: dragging left reveals
  /// the next item on the right. Collection positions increase in reading order.
  static func step(forHorizontalMotion direction: Int) -> Int { -direction }
  func moveForHorizontalMotion(_ direction: Int) {
    (swipe ?? move)(Self.step(forHorizontalMotion: direction))
  }
}

enum MacViewerRequest {
  case history(HistoryPhoto, [HistoryPhoto], MacHistoryGridState, (String) -> Void)
  case photo(PHAsset?, [PHAsset], HistoryPhoto?)
  case folder(FolderPhoto, [FolderPhoto], FolderSources, ((FolderPhoto) -> Void)?, navigation: MacLibraryNavigation? = nil)
}
private struct MacViewerPresentationKey: EnvironmentKey {
  static let defaultValue: ((MacViewerRequest) -> Void)? = nil
}
extension EnvironmentValues {
  var macViewerPresentation: ((MacViewerRequest) -> Void)? {
    get { self[MacViewerPresentationKey.self] }
    set { self[MacViewerPresentationKey.self] = newValue }
  }
}
private struct MacViewerHistoryKey: EnvironmentKey {
  static let defaultValue: ((HistoryPhoto) -> Void)? = nil
}
extension EnvironmentValues {
  var macViewerHistory: ((HistoryPhoto) -> Void)? {
    get { self[MacViewerHistoryKey.self] }
    set { self[MacViewerHistoryKey.self] = newValue }
  }
}
struct MacViewerCommands {
  var back: () -> Void
  var info: () -> Void
  var share: () -> Void
}
private struct MacViewerCommandsKey: FocusedValueKey { typealias Value = MacViewerCommands }
extension FocusedValues {
  var photoViewerCommands: MacViewerCommands? {
    get { self[MacViewerCommandsKey.self] }
    set { self[MacViewerCommandsKey.self] = newValue }
  }
}

enum MacViewerTitle {
  private static func placeName(_ place: String?) -> String? {
    guard let value = place?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
  }
  static func date(_ date: Date?, place: String? = nil) -> String {
    if let place = placeName(place) { return place }
    return fullDate(date)
  }
  static func fullDate(_ date: Date?, locale: Locale = .current, calendar: Calendar = .current,
    timeZone: TimeZone = .current) -> String {
    guard let date else { return NSLocalizedString("design_capture_unknown", comment: "") }
    let formatter = DateFormatter()
    formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = timeZone
    if locale.language.languageCode?.identifier == "zh" {
      formatter.dateFormat = "y年M月d日HH:mm:ss"
    } else {
      formatter.setLocalizedDateFormatFromTemplate("yMdHms")
    }
    return formatter.string(from: date)
  }
  static func subtitle(_ date: Date?, index: Int?, total: Int, place: String? = nil) -> String {
    var parts: [String] = []
    if placeName(place) != nil, date != nil { parts.append(fullDate(date)) }
    if let index, total > 0 { parts.append("\(index.formatted())/\(total.formatted())") }
    return parts.joined(separator: "  ·  ")
  }
}

/// Native toolbar items are shared by library, recorded and file-backed media.
struct MacViewerToolbar: ToolbarContent {
  @ObservedObject var navigation: MacLibraryNavigation
  var back: () -> Void
  var body: some ToolbarContent {
    ToolbarItem(id: "viewer.back", placement: .navigation) {
      Button(action: back) { Label("mac_library_back", systemImage: "chevron.backward") }
        .keyboardShortcut(.cancelAction).help(Text("mac_library_back"))
        .accessibilityIdentifier("library.preview.close")
    }
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      ToolbarItem(id: "viewer.title", placement: .principal) { title }.sharedBackgroundVisibility(.hidden)
    } else { ToolbarItem(id: "viewer.title", placement: .principal) { title } }
    #else
    ToolbarItem(id: "viewer.title", placement: .principal) { title }
    #endif
    ToolbarItemGroup(placement: .primaryAction) {
      Button { navigation.viewerShare?() } label: { Label("library_context_share", systemImage: "square.and.arrow.up") }
        .disabled(navigation.viewerShare == nil).help(Text("library_context_share"))
        .accessibilityIdentifier("library.preview.share")
      MacViewerInfoButton(navigation: navigation)
    }
  }
  private var title: some View {
    VStack(spacing: 1) {
      Text(navigation.viewerTitle).font(.headline).lineLimit(1)
      Text(navigation.viewerSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }.accessibilityElement(children: .combine).accessibilityIdentifier("library.preview.title")
  }
}

struct MacViewerInfoButton: View {
  @ObservedObject var navigation: MacLibraryNavigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var marked: Bool {
    navigation.viewerProgress == nil && ["photo_viewer_failed", "records_load_failed", "photo_viewer_not_backed_up"].contains(navigation.viewerState)
  }
  private var label: String {
    let info = NSLocalizedString("photo_viewer_info", comment: "")
    guard navigation.viewerState != "photo_viewer_saved" else { return info }
    let state = NSLocalizedString(navigation.viewerState, comment: "")
      + (navigation.viewerProgress.map { " " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    return String(format: NSLocalizedString("photo_viewer_info_state", comment: ""), state)
  }
  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: DuckMotion.enter)) { navigation.toggleInformation() }
    } label: {
      Image(systemName: navigation.informationPresented ? "info.circle.fill" : "info.circle")
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        .overlay(alignment: .topTrailing) {
          Image(systemName: "circle.fill")
            .resizable().frame(width: 6, height: 6)
            .foregroundStyle(navigation.viewerState == "photo_viewer_failed" || navigation.viewerState == "records_load_failed" ? DuckRole.attentionGlyph : DuckRole.accent)
            .offset(x: 4, y: -3)
            .symbolEffect(.disappear, options: .nonRepeating, isActive: !marked && !reduceMotion)
            .opacity(reduceMotion ? (marked ? 1 : 0) : 1)
        }
        .overlay {
          if let progress = navigation.viewerProgress {
            Circle().trim(from: 0, to: progress).stroke(DuckRole.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
              .rotationEffect(.degrees(-90)).frame(width: 26, height: 26)
              .animation(reduceMotion ? nil : .linear(duration: DuckMotion.progress), value: progress)
              .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: DuckMotion.enter), value: navigation.viewerProgress == nil)
        .animation(.easeInOut(duration: DuckMotion.enter), value: marked)
        .animation(.easeInOut(duration: DuckMotion.enter), value: navigation.informationPresented)
    }
    .accessibilityLabel(label).accessibilityValue(Text(navigation.informationPresented ? "preview_hide_info" : "folders_show_info"))
    .help(Text(navigation.informationPresented ? "preview_hide_info" : "folders_show_info"))
    .accessibilityIdentifier("library.preview.info")
  }
}

@MainActor enum MacViewerSharing {
  private static var picker: NSSharingServicePicker?
  private static var editingInput: PHContentEditingInput?
  static func show(asset: PHAsset, failure: @escaping () -> Void) {
    if let sample = asset as? any PreviewSample { show(sample.previewImage); return }
    guard BackupEnvironment.usesPhotoLibrary else { failure(); return }
    let options = PHContentEditingInputRequestOptions(); options.isNetworkAccessAllowed = true
    asset.requestContentEditingInput(with: options) { input, _ in
      Task { @MainActor in
        guard let input else { failure(); return }
        editingInput = input
        if let url = input.fullSizeImageURL ?? (input.audiovisualAsset as? AVURLAsset)?.url { show(url) }
        else { failure() }
      }
    }
  }
  static func show(_ item: Any?) {
    guard let item, let view = NSApp.keyWindow?.contentView else { return }
    picker = NSSharingServicePicker(items: [item])
    picker?.show(relativeTo: NSRect(x: view.bounds.maxX - 60, y: view.bounds.maxY, width: 1, height: 1), of: view, preferredEdge: .minY)
  }
}

/// A read-only projection of core facts; requests still use the existing durable endpoints.
@MainActor final class MacViewerFacts: ObservableObject {
  @Published private(set) var job: BackupJob?
  @Published private(set) var tile: String?
  @Published private(set) var loaded = false
  @Published private(set) var unavailable = false
  @Published var working = false
  @Published var error: String?
  private var identity = ""
  private var generation = UUID()
  var stateKey: String {
    if working { return "photo_viewer_backing_up" }
    if !loaded { return "photo_viewer_loading" }
    if unavailable { return "records_load_failed" }
    if error != nil || tile == "needs_you" || job?.state == "failed" || job?.processing == "failed" { return "photo_viewer_failed" }
    if tile == "sending" { return "photo_viewer_backing_up" }
    if tile == "saved" { return "photo_viewer_saved" }
    if job?.state == "received" {
      switch job?.processing {
      case "complete": return "photo_viewer_saved"
      case "pending": return "records_fact_saving"
      default: return "photo_viewer_confirming_photos"
      }
    }
    if tile == "saving" { return "records_fact_saving" }
    return job == nil ? "photo_viewer_not_backed_up" : "photo_viewer_backing_up"
  }
  func stateKey(model: BackupModel) -> String {
    guard stateKey == "photo_viewer_backing_up", !working, let job else { return stateKey }
    let live = model.transferProgress[job.id]
    if ["queued", "running"].contains(job.state) {
      let confirmed = job.totalBytes > 0 && job.confirmedBytes >= job.totalBytes
      let finishing = live.map { progress in
        guard !progress.waitingForNetwork else { return false }
        if progress.phase == "commit" { return true }
        return ["bundle", "upload"].contains(progress.phase) && progress.expected > 0
          && progress.sent >= progress.expected && job.totalBytes > 0
          && progress.displayedBytes(confirmed: job.confirmedBytes, total: job.totalBytes) == job.totalBytes
      } ?? false
      if confirmed || finishing { return "photo_viewer_confirming_receipt" }
    }
    switch job.state {
    case "queued": return "state_queued"
    case "waiting": return "state_waiting"
    case "paused": return "state_paused"
    default: return "photo_viewer_backing_up"
    }
  }
  func progress(model: BackupModel) -> Double? {
    guard stateKey(model: model) == "photo_viewer_backing_up", let job, job.state == "running", job.totalBytes > 0 else { return nil }
    if let live = model.transferProgress[job.id]?.activeFraction(confirmed: job.confirmedBytes, total: job.totalBytes) { return live }
    guard job.confirmedBytes > 0, job.confirmedBytes < job.totalBytes else { return nil }
    return Double(job.confirmedBytes) / Double(job.totalBytes)
  }
  func load(source: String, revision: String?, model: BackupModel, library: PhotoLibraryModel? = nil,
    recorded: BackupJob? = nil, fallback: String? = nil) async {
    let expected = UUID(); generation = expected
    let key = source + "|" + (model.pairing?.receiverID ?? "")
    if identity != key { identity = key; job = recorded; tile = fallback; loaded = false; unavailable = false; working = false; error = nil }
    guard let receiver = recorded?.receiverID ?? model.pairing?.receiverID else { loaded = true; return }
    do {
      let data = try await Bridge.call(["op": "source_job", "receiver_id": receiver, "source_id": source])
      let current = try JSONDecoder().decode(BackupJob?.self, from: data)
      var state = fallback
      if let library, let revision {
        let group = LibraryGroup(sources: [LibrarySource(id: source, revision: revision)], complete: true)
        guard let states = await librarySourceStates([source: group], receiver: receiver, cache: library.tileStates,
          revision: "\(model.queueRevision)|\(model.pendingImports)|\(model.summary.received)|\(model.summary.published)") else { throw Bridge.Failure(code: "internal") }
        state = states[source]
      }
      guard !Task.isCancelled, identity == key, generation == expected else { return }
      job = current.flatMap { $0.asset.source_id == source && (revision == nil || $0.asset.revision == revision) ? $0 : nil } ?? recorded
      tile = state
      if tile == "sending", job?.state == "received" { job = nil }
      loaded = true; unavailable = false
    } catch {
      guard !Task.isCancelled, identity == key, generation == expected else { return }
      loaded = true; unavailable = recorded == nil && fallback == nil
    }
  }
  var informationRevision: Int {
    var hash = Hasher()
    hash.combine(loaded); hash.combine(unavailable); hash.combine(tile); hash.combine(working); hash.combine(error)
    hash.combine(job?.id); hash.combine(job?.state); hash.combine(job?.processing); hash.combine(job?.confirmedBytes)
    return hash.finalize()
  }
  func information(takenAt: Date?, filename: String, fields: [(String, String)], model: BackupModel,
    action: String?, busy: Bool, perform: @escaping () -> Void, history: @escaping () -> Void) -> some View {
    PhotoInformationLayout(takenAt: takenAt, job: job,
      receiverName: job.flatMap { model.receiverDeviceName(for: $0) } ?? model.peerDevice?.name ?? "Pixel",
      needsYou: tile == "needs_you", filename: filename, fields: fields, model: model,
      loaded: loaded, unavailable: unavailable, unpaired: model.pairing == nil && job == nil,
      preparing: working || tile == "sending", allowsRetry: false, showHistory: job == nil ? nil : history,
      actionKey: action, actionBusy: busy, performAction: perform, actionFailure: error)
  }
}


/// Shared entry and return ownership for every Mac media source. Layout events,
/// rather than a guessed queue turn, establish the viewer's native endpoint.
@MainActor final class MacViewerFlight: ObservableObject {
  private(set) var mediaVisible = true
  @Published private(set) var backgroundVisible = true
  private let mediaViews = NSHashTable<NSView>.weakObjects()
  private var pending: MacCoverFlightSource?
  private var openingPoster: MacCoverFlightSource?
  private var endpoint: MacCoverFlightSource?
  private var generation = 0
  private var sourceViewportHold: MacGridViewportHold?
  func holdsImage(for id: String) -> Bool { !mediaVisible && openingPoster != nil && endpoint?.assetID == id }
  func poster(for id: String) -> NSImage? {
    if openingPoster?.assetID == id { return openingPoster?.image }
    return endpoint?.assetID == id ? endpoint?.image : nil
  }
  func register(_ view: NSView) {
    mediaViews.add(view)
    view.alphaValue = mediaVisible ? 1 : 0
  }
  private func setMediaVisible(_ visible: Bool) {
    mediaVisible = visible
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for view in mediaViews.allObjects {
      view.alphaValue = visible ? 1 : 0
      if visible {
        (view as? MacMediaScroll)?.releaseFlight()
        (view as? MacVideoSurface)?.releaseFlight()
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
      }
    }
    CATransaction.commit()
  }
  func releaseSourceViewport() {
    sourceViewportHold?.release(); sourceViewportHold = nil
  }
  /// Sidebar navigation suspends ownership without dismissing this session.
  /// Returning needs no new entry flight; close resolves the live landing.
  func suspendPresentation() {
    generation &+= 1; pending = nil; openingPoster = nil
    MacCoverFlight.cancel(owner: self)
    setMediaVisible(true); backgroundVisible = true
    releaseSourceViewport()
  }
  func begin(_ source: MacCoverFlightSource?) {
    releaseSourceViewport()
    sourceViewportHold = source?.sourceViewport?.retainViewport()
    generation &+= 1; pending = nil; openingPoster = nil; endpoint = nil
    setMediaVisible(true); mediaViews.removeAllObjects()
    endpoint = nil
    pending = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : source
    if pending?.image == nil { pending = nil }
    openingPoster = pending
    mediaVisible = pending == nil; backgroundVisible = pending == nil
  }
  /// The native image view has installed these pixels and laid out its fitted
  /// rectangle. Neither asset metadata nor an outer SwiftUI frame is the endpoint.
  func ready(image: NSImage?, in view: NSImageView, id: String) {
    guard let image, let window = view.window,
      image.size.width > 0, image.size.height > 0,
      view.bounds.width > 0, view.bounds.height > 0 else { return }
    let scale = min(view.bounds.width / image.size.width, view.bounds.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let rect = CGRect(x: view.bounds.midX - size.width / 2, y: view.bounds.midY - size.height / 2,
      width: size.width, height: size.height)
    let area = view.convert(view.bounds, to: nil).intersection(window.contentLayoutRect)
    ready(MacCoverFlightSource(rect: view.convert(rect, to: nil), image: image,
      radius: 0, assetID: id, clip: area, window: window,
      fullAspectRatio: openingPoster?.assetID == id ? openingPoster?.fullAspectRatio : nil))
  }
  func ready(_ destination: MacCoverFlightSource) {
    if let openingPoster, openingPoster.assetID != destination.assetID { return }
    endpoint = destination
    guard let source = pending else { MacCoverFlight.destinationDidLayout(); return }
    pending = nil
    let expected = generation
    backgroundVisible = true
    MacCoverFlight.fly(from: source, to: { [weak self] in self?.endpoint }, owner: self) { [weak self] in
      guard let self, self.generation == expected else { return }
      // Native pixels become visible in the same transaction that removes the
      // flight. Publishing SwiftUI opacity here would leave a blank commit.
      self.setMediaVisible(true); self.openingPoster = nil
    }
  }
  func close(to destination: @escaping () -> MacCoverFlightSource?, completion: @escaping () -> Void) {
    // Return focus may need to reveal the current asset after paging. Release
    // the source before resolving that live landing, never after the flight.
    releaseSourceViewport()
    generation &+= 1; pending = nil; openingPoster = nil
    let expected = generation
    setMediaVisible(false); backgroundVisible = false
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      var source = endpoint, let target = destination(), source.image != nil else { completion(); return }
    source.clip = target.clip
    MacCoverFlight.fly(from: source, to: destination, owner: self) { [weak self] in
      guard self?.generation == expected else { return }
      completion()
    }
  }
}

struct MacViewerFlightSurface<Content: View>: View {
  @ObservedObject var flight: MacViewerFlight
  @ViewBuilder var content: () -> Content
  var body: some View {
    ZStack {
      DuckRole.background.opacity(flight.backgroundVisible ? 1 : 0)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil
          : .easeOut(duration: 0.28), value: flight.backgroundVisible)
      content()
    }
    .onDisappear { flight.releaseSourceViewport() }
  }
}

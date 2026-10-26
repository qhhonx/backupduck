import AppKit
import AVKit
import Photos
import PhotosUI
import SwiftUI

struct MacPhotoPreview: View {
  @StateObject private var session: MediaPreviewSession
  @ObservedObject private var library: PhotoLibraryModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var navigation: MacLibraryNavigation
  @State private var playRequest = 0
  @State private var pageAnimated = false
  private var information: Bool { navigation.viewerInfo }
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @StateObject private var facts = MacViewerFacts()
  @StateObject private var backupAction = SelectionBackupAction()
  @State private var history = false
  @State private var shareFailure = false
  @Environment(\.macViewerHistory) private var openHistory
  private var recorded: HistoryPhoto?
  private var collectionPaging: MacCollectionPaging?
  private let collectionCount: Int?
  private let close: (PHAsset) -> Void
  init(asset: PHAsset, library: PhotoLibraryModel, navigation: MacLibraryNavigation, reviewAssets: [PHAsset]? = nil, recorded: HistoryPhoto? = nil, collectionPaging: MacCollectionPaging? = nil,
    close: @escaping (PHAsset) -> Void) {
    self.library = library; self.navigation = navigation; self.close = close; self.recorded = recorded; self.collectionPaging = collectionPaging; self.collectionCount = reviewAssets?.count
    _session = StateObject(wrappedValue: MediaPreviewSession(asset: asset, library: library,
      poster: library.previewPoster?(asset.localIdentifier), reviewAssets: reviewAssets))
  }
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        MacMediaPager(session: session, playRequest: playRequest, animated: pageAnimated, onSwipe: { move($0, animated: true) }, onPull: pull)
          // The media stays inside the visible area: under the toolbar or the
          // sidebar it would be covered, and the opening flight lands on it.
          .background(MacAreaProbe { area in navigation.viewerArea = area })

        VStack(spacing: 0) {
          Spacer(minLength: 0)
          BurstPreviewControls(preview: session.current, select: session.activate)
        }
      }
      .modifier(MacViewerNavigationControls(previousEnabled: (collectionPaging?.hasPrevious ?? (session.adjacent(to: session.current.asset, direction: 1) != nil)) && !session.paging && !session.zoomed,
        nextEnabled: (collectionPaging?.hasNext ?? (session.adjacent(to: session.current.asset, direction: -1) != nil)) && !session.paging && !session.zoomed,
        previous: { move(1) }, next: { move(-1) }))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DuckRole.background).tint(DuckRole.accent)
    }
    .inspector(isPresented: Binding(get: { navigation.viewerInfo }, set: { navigation.viewerInfo = $0 })) {
      ScrollView {
        PhotoMetadataPanel(preview: session.current, backupInfo: { fields in
          AnyView(facts.information(takenAt: session.current.asset.creationDate, filename: session.current.filename,
            fields: fields, model: model, action: actionKey, busy: backupAction.busy || facts.working,
            perform: requestBackup, history: showHistory))
        }).padding(DuckSpacing.large)
      }
        .inspectorColumnWidth(min: 240, ideal: 290, max: 380)
    }
    .background(MacMediaKeyHandler { event in
      if event.keyCode == 53 || event.charactersIgnoringModifiers == " " {
        close(session.current.asset); return true
      }
      if event.modifierFlags.intersection([.command,.option,.control]).isEmpty,
        event.keyCode == 123 || event.keyCode == 124 {
        guard !session.zoomed else { return false }
        move(event.keyCode == 123 ? 1 : -1); return true
      }
      return false
    })
    .onAppear {
      session.start(); describe()
      navigation.viewerCurrent = { [weak session] in session?.current.asset }
      navigation.viewerBack = { close(session.current.asset) }
      navigation.viewerShare = { MacViewerSharing.show(asset: session.current.asset) { shareFailure = true } }
    }
    .onDisappear {
      session.stop(); navigation.viewerCurrent = nil; navigation.viewerShare = nil; navigation.viewerBack = nil
    }
    .onChange(of: session.current.asset.localIdentifier) { _, _ in playRequest = 0; describe() }
    .onChange(of: session.current.livePhoto != nil) { _, _ in describe() }
    .onChange(of: navigation.viewerLiveRequest) { _, _ in playRequest += 1 }
    .task(id: "\(session.current.asset.localIdentifier)|\(model.pairing?.receiverID ?? "")|\(model.queueRevision)|\(model.pendingImports)") {
      await loadFacts()
      updateMark()
    }
    .onChange(of: facts.stateKey) { _, _ in updateMark() }
    .onChange(of: facts.job) { _, _ in updateMark() }
    .confirmationDialog("selection_backup_repeat_title", isPresented: $backupAction.confirmingRepeat, titleVisibility: .visible) {
      Button("selection_backup_repeat_action") { Task { await backupAction.confirm(library: library, model: model) } }
      Button("cancel", role: .cancel) { backupAction.cancel() }
    } message: { Text("selection_backup_repeat_note") }
    .alert("library_context_share", isPresented: $shareFailure) { Button("settings_done") {} } message: { Text("library_preview_icloud_failed") }
    .sheet(isPresented: $history) {
      NavigationStack {
        BackupHistoryView(model: model, initialFocus: facts.job.map(HistoryPhoto.init)).navigationTitle("records_title")
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("records_done") { history = false } } }
      }.frame(minWidth: 640, minHeight: 480).environment(\.macViewerPresentation, nil)
    }
  }
  private var actionKey: String? {
    guard facts.loaded, !facts.unavailable, model.pairing != nil else { return nil }
    if facts.stateKey == "photo_viewer_failed" { return "retry_task" }
    return facts.stateKey == "photo_viewer_not_backed_up" ? "library_context_backup" : nil
  }
  private func showHistory() {
    guard let job = facts.job else { return }
    if let openHistory { openHistory(HistoryPhoto(job: job)) } else { history = true }
  }
  private func loadFacts() async {
    let asset = session.current.asset
    let original = recorded?.source == asset.localIdentifier ? recorded?.job : nil
    await facts.load(source: asset.localIdentifier, revision: original == nil ? PhotoLibraryModel.revision(asset) : nil,
      model: model, library: original == nil ? library : nil, recorded: original)
  }
  private func requestBackup() {
    guard !facts.working, !backupAction.busy else { return }
    let source = session.current.asset.localIdentifier, receiver = model.pairing?.receiverID, job = facts.job
    Task {
      facts.working = true
      let failure: String?
      if let job, job.state == "failed" || job.processing == "failed" {
        failure = await model.retry(job.id) ? nil : model.message
      } else {
        await backupAction.request(library: library, model: model, sources: [source])
        failure = backupAction.error
      }
      guard session.current.asset.localIdentifier == source, model.pairing?.receiverID == receiver else { return }
      facts.working = false; facts.error = failure
      await loadFacts(); updateMark()
    }
  }
  private func updateMark() {
    navigation.viewerState = facts.stateKey; navigation.viewerProgress = facts.progress
  }
  /// Title, subtitle and controls of the window toolbar follow the current photo.
  private func describe() {
    let asset = session.current.asset
    navigation.viewerTitle = MacViewerTitle.date(asset.creationDate)
    let total = collectionCount ?? library.fetch?.count ?? session.count
    let index: Int?
    if collectionCount == nil, let fetch = library.fetch {
      let raw = fetch.index(of: asset); index = raw == NSNotFound ? nil : total - raw
    } else { index = session.index(of: asset).map { total - $0 } }
    navigation.viewerSubtitle = MacViewerTitle.subtitle(asset.creationDate, index: collectionPaging.map { $0.index + 1 } ?? index, total: collectionPaging?.count ?? total)
    navigation.viewerHasLive = session.current.livePhoto != nil
  }
  private func setInformation(_ value: Bool) {
    withAnimation(reduceMotion ? nil : .timingCurve(0.2,0.8,0.2,1,duration: 0.26)) { navigation.viewerInfo = value }
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
  private func move(_ direction: Int, animated: Bool = false) {
    guard !session.paging, !session.zoomed else { return }
    if let collectionPaging { collectionPaging.move(-direction); return }
    guard let asset = session.adjacent(to: session.current.asset, direction: direction) else { return }
    pageAnimated = animated
    session.activate(asset)
  }
  private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }.buttonStyle(.borderless).accessibilityLabel(Text(LocalizedStringKey(label)))
      .help(Text(LocalizedStringKey(label))).accessibilityIdentifier(id)
  }
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

/// AppKit owns horizontal live tracking and page-controller reuse. The arranged
/// objects contain only the current asset and its immediate neighbours.
private struct MacMediaPager: NSViewControllerRepresentable {
  @ObservedObject var session: MediaPreviewSession
  let playRequest: Int
  var animated = false
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  var onTap: () -> Void = {}
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
      view.rootView = AnyView(MacPreviewPage(preview: session.current, session: session, playRequest: playRequest, onSwipe: onSwipe, onPull: onPull, onTap: onTap))
    }
    guard !session.paging else { return }
    let objects = controller.arrangedObjects.compactMap { $0 as? PHAsset }
    if let index = objects.firstIndex(where: { $0.localIdentifier == session.current.asset.localIdentifier }), index != controller.selectedIndex,
      !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      // Keys and buttons switch in place: the page controller animates even
      // a zero-length animator change, so the index is set directly.
      controller.selectedIndex = index; controller.completeTransition(); c.install(controller)
    } else if let index = objects.firstIndex(where: { $0.localIdentifier == session.current.asset.localIdentifier }), index != controller.selectedIndex {
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
    } else if !objects.contains(where: { $0.localIdentifier == session.current.asset.localIdentifier }) || c.active != session.current.asset.localIdentifier {
      c.install(controller)
    }
  }
  static func dismantleNSViewController(_ controller: NSPageController, coordinator: Coordinator) { controller.delegate = nil }
  @MainActor final class Coordinator: NSObject, NSPageControllerDelegate {
    var parent: MacMediaPager
    var active = ""
    init(_ parent: MacMediaPager) { self.parent = parent }
    func install(_ controller: NSPageController) {
      let asset = parent.session.current.asset
      let assets = [parent.session.adjacent(to: asset, direction: -1), asset, parent.session.adjacent(to: asset, direction: 1)].compactMap { $0 }
      active = asset.localIdentifier; controller.arrangedObjects = assets
      controller.selectedIndex = assets.firstIndex { $0.localIdentifier == asset.localIdentifier } ?? 0
    }
    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier { "media" }
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
      let view = NSHostingController(rootView: AnyView(Color.clear)); view.view.wantsLayer = true
      view.view.autoresizingMask = [.width,.height]
      return view
    }
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
      guard let host = viewController as? NSHostingController<AnyView>, let asset = object as? PHAsset else { return }
      host.rootView = AnyView(MacPreviewPage(preview: parent.session.model(for: asset), session: parent.session, playRequest: asset.localIdentifier == parent.session.current.asset.localIdentifier ? parent.playRequest : 0, onSwipe: parent.onSwipe, onPull: parent.onPull, onTap: parent.onTap))
    }
    func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect { pageController.view.bounds }
    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) { parent.session.paging = true; parent.session.current.deactivate() }
    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
      if let asset = object as? PHAsset { parent.session.activate(asset) }
    }
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
      pageController.completeTransition(); parent.session.paging = false
      install(pageController)
    }
  }
}
private final class MediaPageController: NSPageController {
  override func viewDidLayout() {
    super.viewDidLayout()
    selectedViewController?.view.frame = view.bounds
  }
}
private struct MacPreviewPage: View {
  static func fitted(_ asset: PHAsset, in size: CGSize) -> CGRect {
    guard asset.pixelWidth > 0, asset.pixelHeight > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
    let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    var fit = CGSize(width: size.width, height: size.width / aspect)
    if fit.height > size.height { fit = CGSize(width: size.height * aspect, height: size.height) }
    return CGRect(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2, width: fit.width, height: fit.height)
  }
  @ObservedObject var preview: MediaPreviewModel
  @ObservedObject var session: MediaPreviewSession
  let playRequest: Int
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  var onTap: () -> Void = {}
  var body: some View {
    ZStack {
      if let player = preview.player { MacVideoWithPoster(player: player, image: preview.image, onSwipe: onSwipe, onPull: onPull).accessibilityIdentifier("library.preview.video") }
      else if let image = preview.image { MacMediaZoom(image: image, livePhoto: preview.livePhoto, playRequest: playRequest, fitRevision: session.fitRevision, zoomed: { session.zoomed = $0 }, onSwipe: onSwipe, onPull: onPull, onTap: onTap).id(preview.asset.localIdentifier).accessibilityIdentifier("library.preview.photo") }
      if preview.loading {
        // A small badge on the photo's own bottom-right corner, mirroring the
        // Live badge at its bottom-left, instead of a large one in the window.
        GeometryReader { proxy in
          let fit = Self.fitted(preview.asset, in: proxy.size)
          Group {
            if preview.progress > 0 { ProgressView(value: preview.progress).progressViewStyle(.circular) }
            else { ProgressView() }
          }
          .controlSize(.mini).frame(width: 14, height: 14).padding(5)
          .background(.ultraThinMaterial, in: Circle())
          .position(x: fit.maxX - 20, y: fit.maxY - 20)
        }.allowsHitTesting(false).accessibilityLabel(Text("library_loading"))
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
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  var onTap: () -> Void = {}
  func makeNSView(context: Context) -> MacMediaScroll { MacMediaScroll() }
  func updateNSView(_ scroll: MacMediaScroll, context: Context) {
    scroll.zoomed = zoomed
    scroll.onSwipe = onSwipe; scroll.onPull = onPull; scroll.onTap = onTap
    if scroll.fitRevision != fitRevision {
      scroll.fitRevision = fitRevision; scroll.setMagnification(1, centeredAt: scroll.contentView.bounds.origin)
    }
    scroll.photo.image = image; scroll.live.livePhoto = livePhoto; scroll.live.isHidden = livePhoto == nil
    if scroll.playRequest != playRequest { scroll.playRequest = playRequest; scroll.live.startPlayback(with: .full) }
    scroll.needsLayout = true
  }
  static func dismantleNSView(_ scroll: MacMediaScroll, coordinator: ()) { scroll.live.stopPlayback(); scroll.live.livePhoto = nil }
}
@MainActor final class MacMediaScroll: NSScrollView {
  let photo = NSImageView(), live = PHLivePhotoView()
  var playRequest = 0
  var fitRevision = 0
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
  }
  private var wheelX: CGFloat = 0, wheelY: CGFloat = 0, wheelHandled = false, lastNotch = Date.distantPast
  /// Trackpad and wheel gestures at fit size: sideways pages, upwards reveals
  /// information and downwards hides it or leaves, as a mouse drag does.
  override func scrollWheel(with event: NSEvent) {
    guard magnification <= 1.01 else { super.scrollWheel(with: event); return }
    if event.phase == [] && event.momentumPhase == [] {
      // A wheel without phases: one notch is one step.
      guard Date().timeIntervalSince(lastNotch) > 0.5 else { return }
      if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 2 {
        lastNotch = Date(); onSwipe?(event.scrollingDeltaX > 0 ? 1 : -1)
      } else if abs(event.scrollingDeltaY) > 2 {
        lastNotch = Date(); onPull?(event.scrollingDeltaY < 0 ? 1 : -2)
      }
      return
    }
    if event.phase == .began { wheelX = 0; wheelY = 0; wheelHandled = false }
    if !event.momentumPhase.isEmpty {
      if abs(wheelX) > abs(wheelY) { _ = MacPagerForwarding.forward(event, from: self) }
      return
    }
    wheelX += event.scrollingDeltaX; wheelY += event.scrollingDeltaY
    if abs(wheelX) > abs(wheelY) {
      // Sideways belongs to the page controller's own live swipe.
      if !MacPagerForwarding.forward(event, from: self) { nextResponder?.scrollWheel(with: event) }
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
  let player: AVPlayer
  let image: NSImage?
  var onSwipe: (Int) -> Void = { _ in }
  var onPull: (Int) -> Void = { _ in }
  func makeNSView(context: Context) -> MacVideoSurface { MacVideoSurface() }
  func updateNSView(_ view: MacVideoSurface, context: Context) {
    view.onSwipe = onSwipe; view.onPull = onPull
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
  private var monitor: Any?
  private var sideways = false
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
        self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
      // The direction is decided when a gesture begins and kept through its
      // momentum, so a sideways swipe never turns into scrubbing halfway.
      if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
        self.sideways = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
      }
      guard self.sideways else { return event }
      return MacPagerForwarding.forward(event, from: self) ? nil : event
    }
  }
}
/// Hands a scroll event to the enclosing page controller, which owns the
/// interactive swipe. The hosting views between them do not pass it on.
@MainActor enum MacPagerForwarding {
  static func forward(_ event: NSEvent, from view: NSView) -> Bool {
    var current: NSView? = view.superview
    while let candidate = current {
      if let pager = candidate.nextResponder as? NSPageController { pager.scrollWheel(with: event); return true }
      current = candidate.superview
    }
    return false
  }
}
@MainActor final class MacVideoSurface: NSView {
  private let video = MacPagingPlayerView()
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
  func update(player: AVPlayer, image: NSImage?) {
    poster.image = image
    if video.player !== player {
      observation = nil; video.player = player; poster.isHidden = false
      observation = video.observe(\.isReadyForDisplay, options: [.initial,.new]) { [weak self] _,_ in
        Task { @MainActor in
          guard let self else { return }; self.poster.isHidden = self.video.isReadyForDisplay
        }
      }
    }
  }
  override func layout() { super.layout(); video.frame = bounds; poster.frame = bounds }
  func stop() { observation = nil; video.player?.pause(); video.player = nil }
}
@MainActor private final class MacVideoPoster: NSImageView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The hidden grid must not retain ownership of Escape/Space while the viewer
/// is active. Install once per viewer and remove on every dismissal path.
struct MacMediaKeyHandler: NSViewRepresentable {
  var handle: (NSEvent) -> Bool
  func makeNSView(context: Context) -> MacMediaKeyView { MacMediaKeyView() }
  func updateNSView(_ view: MacMediaKeyView, context: Context) { view.handle = handle }
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

/// Missing originals retain their recorded facts, using the same inspector and toolbar state.
struct MacRecordedPhotoPreview: View {
  let photo: HistoryPhoto
  @ObservedObject var model: BackupModel
  @ObservedObject var navigation: MacLibraryNavigation
  var close: () -> Void
  var collectionPaging: MacCollectionPaging? = nil
  @StateObject private var facts = MacViewerFacts()
  @StateObject private var router = BackupPhotoRouter()
  @Environment(\.macViewerPresentation) private var present
  @Environment(\.macViewerHistory) private var openHistory
  @State private var history = false
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
      .inspector(isPresented: $navigation.viewerInfo) {
        ScrollView {
          facts.information(takenAt: photo.takenAt, filename: photo.job?.asset.resources.first?.filename ?? "",
            fields: PhotoInformationLayout.fileFields(for: photo.job), model: model,
            action: facts.stateKey == "photo_viewer_failed" && facts.job != nil ? "retry_task" : nil,
            busy: facts.working, perform: retry, history: {
              if let job = facts.job, let openHistory { openHistory(HistoryPhoto(job: job)) } else { history = true }
            }).padding(DuckSpacing.large)
        }.inspectorColumnWidth(min: 240, ideal: 290, max: 380)
      }
      .background(MacMediaKeyHandler { event in if event.keyCode == 53 { close(); return true }; return false })
      .task(id: model.queueRevision) {
        navigation.viewerTitle = MacViewerTitle.date(photo.takenAt)
        navigation.viewerSubtitle = MacViewerTitle.subtitle(photo.takenAt, index: (collectionPaging?.index ?? 0) + 1, total: collectionPaging?.count ?? 1)
        navigation.viewerShare = nil; navigation.viewerBack = close
        await facts.load(source: photo.source, revision: nil, model: model, recorded: photo.job)
        updateMark()
      }
      .onDisappear { navigation.viewerBack = nil }
      .onChange(of: facts.stateKey) { _, _ in updateMark() }
      .onChange(of: facts.job) { _, _ in updateMark() }
      .sheet(isPresented: $history) {
        NavigationStack {
          BackupHistoryView(model: model, initialFocus: facts.job.map(HistoryPhoto.init)).navigationTitle("records_title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("records_done") { history = false } } }
        }.frame(minWidth: 640, minHeight: 480)
      }
  }
  private func updateMark() { navigation.viewerState = facts.stateKey; navigation.viewerProgress = facts.progress }
  private func retry() {
    guard let job = facts.job else { return }
    Task { facts.working = true; facts.error = await model.retry(job.id) ? nil : model.message; facts.working = false
      await facts.load(source: photo.source, revision: nil, model: model, recorded: photo.job); updateMark() }
  }
}

/// The same window-scoped presentation is inherited by history and file grids.
struct MacCollectionPaging {
  var index: Int
  var count: Int
  var move: (Int) -> Void
  var hasPrevious: Bool { index > 0 }
  var hasNext: Bool { index + 1 < count }
}

enum MacViewerRequest {
  case history(HistoryPhoto, [HistoryPhoto], MacHistoryGridState, (String) -> Void)
  case photo(PHAsset?, [PHAsset], HistoryPhoto?)
  case folder(FolderPhoto, [FolderPhoto], FolderSources, ((FolderPhoto) -> Void)?)
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
  static func date(_ date: Date?) -> String {
    guard let date else { return NSLocalizedString("design_capture_unknown", comment: "") }
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 8
    if (0..<7).contains(days) {
      let formatter = DateFormatter(); formatter.doesRelativeDateFormatting = true
      formatter.dateStyle = .full; formatter.timeStyle = .none
      if days < 2 { return formatter.string(from: date) }
      return date.formatted(.dateTime.weekday(.wide))
    }
    return date.formatted(date: .long, time: .omitted)
  }
  static func subtitle(_ date: Date?, index: Int?, total: Int) -> String {
    var parts = date.map { [$0.formatted(date: .omitted, time: .shortened)] } ?? []
    if let index, total > 0 { parts.append(String(format: NSLocalizedString("mac_viewer_position", comment: ""), index, total)) }
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
  private var marked: Bool { navigation.viewerState != "photo_viewer_saved" && navigation.viewerProgress == nil }
  private var label: String {
    let info = NSLocalizedString("photo_viewer_info", comment: "")
    guard navigation.viewerState != "photo_viewer_saved" else { return info }
    let state = NSLocalizedString(navigation.viewerState, comment: "")
      + (navigation.viewerProgress.map { " " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    return String(format: NSLocalizedString("photo_viewer_info_state", comment: ""), state)
  }
  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: DuckMotion.enter)) { navigation.viewerInfo.toggle() }
    } label: {
      Image(systemName: navigation.viewerInfo ? "info.circle.fill" : "info.circle")
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
        .animation(.easeInOut(duration: DuckMotion.enter), value: navigation.viewerInfo)
    }
    .accessibilityLabel(label).accessibilityValue(Text(navigation.viewerInfo ? "preview_hide_info" : "folders_show_info"))
    .help(Text(navigation.viewerInfo ? "preview_hide_info" : "folders_show_info"))
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
    if job?.state == "received" { return job?.processing == "complete" ? "photo_viewer_saved" : "photo_viewer_received" }
    if tile == "saving" { return "photo_viewer_received" }
    return job == nil ? "photo_viewer_not_backed_up" : "photo_viewer_backing_up"
  }
  var progress: Double? {
    guard stateKey == "photo_viewer_backing_up", let job, job.state == "running",
      job.confirmedBytes > 0, job.confirmedBytes < job.totalBytes else { return nil }
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
          revision: "\(model.queueRevision)|\(model.pendingImports)") else { throw Bridge.Failure(code: "internal") }
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

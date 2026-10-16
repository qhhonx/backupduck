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
  @State private var edge = 0
  @State private var windowProbe: NSView?
  @State private var pageAnimated = false
  private var information: Bool { navigation.viewerInfo }
  /// A click on the photo hides every control and turns the background black.
  private var immersive: Bool { navigation.viewerImmersive }
  private let reviewing: Bool
  private let close: (PHAsset) -> Void
  init(asset: PHAsset, library: PhotoLibraryModel, navigation: MacLibraryNavigation, reviewAssets: [PHAsset]? = nil,
    close: @escaping (PHAsset) -> Void) {
    self.library = library; self.navigation = navigation; self.close = close; reviewing = reviewAssets != nil
    _session = StateObject(wrappedValue: MediaPreviewSession(asset: asset, library: library,
      poster: library.previewPoster?(asset.localIdentifier), reviewAssets: reviewAssets))
  }
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        MacMediaPager(session: session, playRequest: playRequest, animated: pageAnimated, onSwipe: { move($0, animated: true) }, onPull: pull, onTap: toggleImmersive)
          // The media stays inside the visible area: under the toolbar or the
          // sidebar it would be covered, and the opening flight lands on it.
          .background(MacAreaProbe { area in navigation.viewerArea = area })
          .background(MacWindowProbe { windowProbe = $0 })
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          BurstPreviewControls(preview: session.current, select: session.activate)
        }
        .opacity(immersive ? 0 : 1).allowsHitTesting(!immersive)
        // Arrows stay out of the way until the pointer nears an edge.
        HStack {
          arrow("chevron.left", label: "preview_previous", id: "library.preview.previous", direction: 1)
            .keyboardShortcut(.leftArrow, modifiers: []).opacity(edge < 0 && !immersive ? 1 : 0)
          Spacer()
          arrow("chevron.right", label: "preview_next", id: "library.preview.next", direction: -1)
            .keyboardShortcut(.rightArrow, modifiers: []).opacity(edge > 0 && !immersive ? 1 : 0)
        }.padding(.horizontal, 14).allowsHitTesting(edge != 0 && !immersive)
        if information {
          infoSheet(height: proxy.size.height)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: immersive)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: edge)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Black reaches up under the faded title bar but never behind the sidebar,
      // whose material would turn dark.
      .background((immersive ? Color.black : Color(nsColor: .windowBackgroundColor)).ignoresSafeArea(edges: .top)).tint(DuckColors.action)
      .onContinuousHover { phase in
        guard case .active(let point) = phase else { edge = 0; return }
        edge = point.x < 90 ? -1 : point.x > proxy.size.width - 90 ? 1 : 0
      }
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
    }
    .onDisappear {
      session.stop(); navigation.viewerCurrent = nil
      navigation.viewerInfo = false; navigation.viewerImmersive = false
    }
    .onChange(of: session.current.asset.localIdentifier) { _, _ in playRequest = 0; describe() }
    .onChange(of: session.current.livePhoto != nil) { _, _ in describe() }
    .onChange(of: navigation.viewerLiveRequest) { _, _ in playRequest += 1 }
    .onChange(of: navigation.viewerImmersive) { _, value in
      // Immersive viewing fades the title bar away instead of removing the
      // toolbar: removing it changed the safe area and the photo jumped.
      MacTitlebarFade.set(hidden: value, in: windowProbe?.window)
    }
    .onDisappear { MacTitlebarFade.set(hidden: false, in: windowProbe?.window) }
  }
  private func toggleImmersive() {
    if information { setInformation(false); return }
    // The background cross-fades with the title bar instead of cutting.
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { navigation.viewerImmersive.toggle() }
  }
  /// Title, subtitle and controls of the window toolbar follow the current photo.
  private func describe() {
    let asset = session.current.asset
    navigation.viewerTitle = asset.creationDate?.formatted(date: .long, time: .omitted)
      ?? NSLocalizedString("library_preview", comment: "")
    var parts: [String] = []
    if let date = asset.creationDate { parts.append(date.formatted(date: .omitted, time: .standard)) }
    if let index = library.previewIndex(of: asset), let total = library.fetch?.count, total > 0 {
      parts.append("\((total - index).formatted())/\(total.formatted())")
    }
    navigation.viewerSubtitle = parts.joined(separator: "  ·  ")
    navigation.viewerHasLive = session.current.livePhoto != nil
  }
  /// Information rises from the bottom as a sheet with its own close button.
  private func infoSheet(height: CGFloat) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      VStack(spacing: 0) {
        HStack {
          Text("apple_photo_detail").font(.headline)
          Spacer()
          Button { setInformation(false) } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
          }.buttonStyle(.plain).accessibilityLabel(Text("mac_library_back")).accessibilityIdentifier("library.preview.info.close")
        }.padding(.horizontal, 20).padding(.vertical, 14)
        Divider()
        ScrollView { PhotoMetadataPanel(preview: session.current).padding(20) }
      }
      .frame(maxWidth: 560).frame(height: min(440, height * 0.6))
      .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
      .shadow(color: .black.opacity(0.18), radius: 16, y: -2)
      .gesture(DragGesture(minimumDistance: 24).onEnded { if $0.translation.height > 60 { setInformation(false) } })
    }
    .frame(maxWidth: .infinity)
  }
  private func arrow(_ symbol: String, label: String, id: String, direction: Int) -> some View {
    icon(symbol, label: label, id: id) { move(direction) }
      .disabled(session.adjacent(to: session.current.asset, direction: direction) == nil || session.paging || session.zoomed)
  }
  private func setInformation(_ value: Bool) {
    withAnimation(reduceMotion ? nil : .timingCurve(0.2,0.8,0.2,1,duration: 0.26)) { navigation.viewerInfo = value }
  }
  /// Dragging up reveals information; dragging down hides it, then leaves.
  private func pull(_ direction: Int) {
    if direction == -2 { if information { setInformation(false) }; return }
    if direction > 0 { if !reviewing { setInformation(true) } }
    else if information { setInformation(false) }
    else { close(session.current.asset) }
  }
  /// Keys and arrow buttons change the photo at once, as Photos does; only a
  /// swipe slides the strip.
  private func move(_ direction: Int, animated: Bool = false) {
    guard !session.paging, !session.zoomed, let asset = session.adjacent(to: session.current.asset, direction: direction) else { return }
    pageAnimated = animated
    session.activate(asset)
  }
  private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 17)).frame(width: 32, height: 32)
        .background(.quaternary, in: Circle())
    }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(label)))
      .help(Text(LocalizedStringKey(label))).accessibilityIdentifier(id)
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
        VStack(spacing: 12) {
          Image(systemName: preview.cloudNeeded ? "icloud.and.arrow.down" : "exclamationmark.circle").font(.largeTitle)
          Text(preview.cloudNeeded ? "preview_cloud_title" : "library_preview_unavailable").font(.callout)
          Button("retry_task") { preview.load() }.duckSecondaryAction()
        }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.primary)
  }
}
private struct MacMediaZoom: NSViewRepresentable {
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
@MainActor private final class MacMediaScroll: NSScrollView {
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
    // One click toggles the immersive (black, controls hidden) state; it waits
    // briefly so a double click can zoom instead.
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
    if !event.momentumPhase.isEmpty { return }
    wheelX += event.scrollingDeltaX; wheelY += event.scrollingDeltaY
    if abs(wheelX) > abs(wheelY) {
      // Sideways belongs to the page controller's own live swipe.
      nextResponder?.scrollWheel(with: event); return
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
private struct MacVideoWithPoster: NSViewRepresentable {
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
@MainActor private final class MacPagingPlayerView: AVPlayerView {
  override func scrollWheel(with event: NSEvent) {
    if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || !event.momentumPhase.isEmpty {
      superview?.nextResponder?.scrollWheel(with: event)
    } else { super.scrollWheel(with: event) }
  }
}
@MainActor private final class MacVideoSurface: NSView {
  let video = MacPagingPlayerView()
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
private struct MacMediaKeyHandler: NSViewRepresentable {
  var handle: (NSEvent) -> Bool
  func makeNSView(context: Context) -> MacMediaKeyView { MacMediaKeyView() }
  func updateNSView(_ view: MacMediaKeyView, context: Context) { view.handle = handle }
  static func dismantleNSView(_ view: MacMediaKeyView, coordinator: ()) { view.stop() }
}
@MainActor private final class MacMediaKeyView: NSView {
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

/// Gives SwiftUI a view whose window AppKit code can reach.
private struct MacWindowProbe: NSViewRepresentable {
  let found: (NSView) -> Void
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { found(view) }
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

/// Fades the window's title bar (traffic lights and toolbar) without changing
/// the content layout.
@MainActor enum MacTitlebarFade {
  static func set(hidden: Bool, in window: NSWindow?) {
    guard let bar = window?.standardWindowButton(.closeButton)?.superview?.superview else { return }
    if !hidden { bar.isHidden = false }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
      bar.animator().alphaValue = hidden ? 0 : 1
    } completionHandler: {
      Task { @MainActor in if hidden, bar.alphaValue < 0.01 { bar.isHidden = true } }
    }
  }
}

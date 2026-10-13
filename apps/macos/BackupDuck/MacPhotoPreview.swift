import AppKit
import AVKit
import Photos
import PhotosUI
import SwiftUI

struct MacPhotoPreview: View {
  @StateObject private var session: MediaPreviewSession
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var information = false
  @State private var playRequest = 0
  init(asset: PHAsset, library: PhotoLibraryModel) {
    _session = StateObject(wrappedValue: MediaPreviewSession(asset: asset, library: library))
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        if session.current.livePhoto != nil {
          Button { playRequest += 1 } label: { Image(systemName: "livephoto").font(.title3) }
            .buttonStyle(.plain).accessibilityLabel(Text("mac_library_play_live"))
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(session.current.asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? NSLocalizedString("library_preview", comment: "")).font(.headline)
          if let date = session.current.asset.creationDate { Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.white.opacity(0.65)) }
        }
        Spacer()
        icon("info.circle", label: "apple_photo_detail", id: "library.preview.info") {
          withAnimation(reduceMotion ? nil : .timingCurve(0.2,0.8,0.2,1,duration: 0.26)) { information.toggle() }
        }
        icon("xmark", label: "settings_done", id: "library.preview.close") { dismiss() }.keyboardShortcut(.cancelAction)
      }.padding(.horizontal, 20).frame(height: 64).foregroundStyle(.white)
      HStack(spacing: 0) {
        ZStack {
          MacMediaPager(session: session, playRequest: playRequest)
          HStack {
            icon("chevron.left", label: "preview_previous", id: "library.preview.previous") { move(-1) }
              .keyboardShortcut(.leftArrow, modifiers: [])
              .disabled(session.adjacent(to: session.current.asset, direction: -1) == nil || session.paging)
            Spacer()
            icon("chevron.right", label: "preview_next", id: "library.preview.next") { move(1) }
              .keyboardShortcut(.rightArrow, modifiers: [])
              .disabled(session.adjacent(to: session.current.asset, direction: 1) == nil || session.paging)
          }.padding(.horizontal, 12).foregroundStyle(.white)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        if information {
          ScrollView { PhotoMetadataPanel(preview: session.current).padding(20) }
            .frame(width: 310).background(DuckColors.surface).transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      BurstPreviewControls(preview: session.current, select: session.activate).foregroundStyle(.white)
    }.frame(minWidth: 640, idealWidth: 1000, minHeight: 520, idealHeight: 700)
      .preferredColorScheme(.dark).background(Color.black).tint(DuckColors.action)
      .onAppear { session.start() }.onDisappear { session.stop() }
      .onChange(of: policy.choice) { _, _ in session.reloadForPolicy() }
      .previewCloudConsent()
  }
  private func move(_ direction: Int) {
    guard !session.paging, let asset = session.adjacent(to: session.current.asset, direction: direction) else { return }
    session.activate(asset)
  }
  private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 18)).frame(width: 36, height: 36).background(.white.opacity(0.1), in: Circle()) }
      .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(label))).accessibilityIdentifier(id)
  }
}

/// AppKit owns horizontal live tracking and page-controller reuse. The arranged
/// objects contain only the current asset and its immediate neighbours.
private struct MacMediaPager: NSViewControllerRepresentable {
  @ObservedObject var session: MediaPreviewSession
  let playRequest: Int
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSViewController(context: Context) -> NSPageController {
    let controller = MediaPageController()
    controller.view = NSView(frame: CGRect(x: 0,y: 0,width: 800,height: 550))
    controller.view.autoresizingMask = [.width,.height]; controller.view.wantsLayer = true
    controller.view.layer?.backgroundColor = NSColor.black.cgColor
    controller.transitionStyle = .horizontalStrip; controller.delegate = context.coordinator
    context.coordinator.install(controller)
    return controller
  }
  func updateNSViewController(_ controller: NSPageController, context: Context) {
    let c = context.coordinator; c.parent = self
    if c.active == session.current.asset.localIdentifier, !session.paging, let view = controller.selectedViewController as? NSHostingController<AnyView> {
      view.rootView = AnyView(MacPreviewPage(preview: session.current, playRequest: playRequest))
    }
    guard !session.paging else { return }
    let objects = controller.arrangedObjects.compactMap { $0 as? PHAsset }
    if let index = objects.firstIndex(where: { $0.localIdentifier == session.current.asset.localIdentifier }), index != controller.selectedIndex {
      session.paging = true
      NSAnimationContext.runAnimationGroup { context in
        context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.26
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2,0.8,0.2,1)
        controller.animator().selectedIndex = index
      } completionHandler: {
        controller.completeTransition(); self.session.paging = false; c.install(controller)
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
      let view = NSHostingController(rootView: AnyView(Color.black)); view.view.wantsLayer = true
      view.view.autoresizingMask = [.width,.height]
      return view
    }
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
      guard let host = viewController as? NSHostingController<AnyView>, let asset = object as? PHAsset else { return }
      host.rootView = AnyView(MacPreviewPage(preview: parent.session.model(for: asset), playRequest: asset.localIdentifier == parent.session.current.asset.localIdentifier ? parent.playRequest : 0))
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
  @ObservedObject var preview: MediaPreviewModel
  let playRequest: Int
  var body: some View {
    ZStack {
      if let player = preview.player { NativeMacVideo(player: player).accessibilityIdentifier("library.preview.video") }
      else if let image = preview.image { MacMediaZoom(image: image, livePhoto: preview.livePhoto, playRequest: playRequest).id(preview.asset.localIdentifier).accessibilityIdentifier("library.preview.photo") }
      if preview.loading && preview.image == nil { ProgressView().tint(.white).padding(20) }
      if preview.cloudNeeded || preview.failure {
        VStack(spacing: 12) {
          Image(systemName: preview.cloudNeeded ? "icloud.and.arrow.down" : "exclamationmark.circle").font(.largeTitle)
          Text(preview.cloudNeeded ? "preview_cloud_title" : "library_preview_unavailable").font(.callout)
          Button(PreviewNetworkPolicy.shared.allowed ? "retry_task" : "preview_cloud_allow") {
            if PreviewNetworkPolicy.shared.allowed { preview.load() }
            else { PreviewNetworkPolicy.shared.asking = true }
          }.duckSecondaryAction()
        }.padding(20).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black).foregroundStyle(.white)
  }
}
private struct MacMediaZoom: NSViewRepresentable {
  let image: NSImage
  let livePhoto: PHLivePhoto?
  let playRequest: Int
  func makeNSView(context: Context) -> MacMediaScroll { MacMediaScroll() }
  func updateNSView(_ scroll: MacMediaScroll, context: Context) {
    scroll.photo.image = image; scroll.live.livePhoto = livePhoto; scroll.live.isHidden = livePhoto == nil
    if scroll.playRequest != playRequest { scroll.playRequest = playRequest; scroll.live.startPlayback(with: .full) }
    scroll.needsLayout = true
  }
  static func dismantleNSView(_ scroll: MacMediaScroll, coordinator: ()) { scroll.live.stopPlayback(); scroll.live.livePhoto = nil }
}
@MainActor private final class MacMediaScroll: NSScrollView {
  let photo = NSImageView(), live = PHLivePhotoView()
  var playRequest = 0
  private let media = NSView()
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    drawsBackground = true; backgroundColor = .black; allowsMagnification = true; minMagnification = 1; maxMagnification = 5
    horizontalScrollElasticity = .none; verticalScrollElasticity = .none
    documentView = media; media.addSubview(photo); media.addSubview(live)
    photo.imageScaling = .scaleProportionallyUpOrDown; live.contentMode = .aspectFit
    let double = NSClickGestureRecognizer(target: self, action: #selector(doubleClick(_:))); double.numberOfClicksRequired = 2; addGestureRecognizer(double)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() {
    super.layout()
    if magnification <= 1.01 {
      media.frame = CGRect(origin: .zero, size: contentView.bounds.size); photo.frame = media.bounds; live.frame = media.bounds
    }
  }
  @objc private func doubleClick(_ gesture: NSClickGestureRecognizer) {
    setMagnification(magnification > 1.01 ? 1 : 2.5, centeredAt: gesture.location(in: media))
  }
}

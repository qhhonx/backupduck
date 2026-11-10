import Combine
import Photos
import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct IOSLibraryPage: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  var body: some View {
    IOSCalendarLibraryPage(library: library, model: model)
  }
}

private struct IOSCalendarLibraryPage: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @StateObject private var backupAction = SelectionBackupAction()
  @State private var selecting = false
  var body: some View {
    Group {
      if let placeholder = library.placeholder, !isLoadingPlaceholder && !isFilterEmpty {
        NavigationStack {
          LibraryPlaceholder(kind:placeholder,requestingAccess:library.requestingPermission,
            requestAccess:{Task { await library.open(requestPermission:true) }},
            clearFilter:{Task { await library.resetFilters() }})
            .navigationTitle("nav_library")
        }
      } else {
        // interaction.md I2: the active backup view is a soft pill that clears
        // with one tap, as Photos shows an active filter.
        calendar.safeAreaInset(edge: .bottom) {
          if library.backupView != .all && !selecting {
          Button { Task { await library.changeBackupView(.all) } } label: {
            HStack(spacing: 8) {
              Text(String(format: NSLocalizedString("library_view_pill", comment: ""),
                NSLocalizedString(library.backupView.title, comment: ""), library.total.formatted()))
              Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
          }
          .buttonStyle(.plain).padding(.bottom, 8)
          .accessibilityHint(Text("library_view_clear"))
          }
        }
      }
    }.background(Color(uiColor: .systemBackground)).tint(DuckRole.accent)
      .task { await library.open() }
      .onAppear { library.refreshVisiblePreviews() }
      .onDisappear { library.thumbnails.clear() }
  }
  private var isFilterEmpty: Bool {
    if case .filterEmpty? = library.placeholder { return true }
    return false
  }
  private var isLoadingPlaceholder: Bool {
    if case .loading? = library.placeholder { return true }
    return false
  }
  private var calendar: some View {
    IOSCalendarLibrary(library:library,model:model, backupAction: backupAction, selectionChanged: { selecting = $0 }).ignoresSafeArea(.container)
      .toolbarColorScheme(library.placeholder == nil && library.loaded > 0 ? .dark : nil, for: .navigationBar)
  }

}
struct IOSPreviewItem: Identifiable {
  let asset: PHAsset
  let frame: CGRect
  let poster: UIImage?
  var background: UIColor = .systemBackground
  var id: String { asset.localIdentifier }
}

/// The review owns its return geometry; the main library's scroll and frame
/// provider remain untouched while this batch is being inspected.
@MainActor func presentSelectedMediaReview(from review: CalendarSelectedController, assets: [PHAsset], library: PhotoLibraryModel) {
  func key(_ asset: PHAsset) -> String { asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier }
  guard let asset = assets.first(where: { key($0) == review.focusedID })
    ?? assets.first(where: { review.selected.contains(key($0)) }),
    let frame = review.previewFrame(key(asset)), review.presentedViewController == nil else { return }
  let selectedIndex = review.assets.firstIndex(where: { $0.id == key(asset) })
  let poster = selectedIndex.flatMap { (review.grid.cellForItem(at: IndexPath(item: $0,section: 0)) as? CalendarGridCell)?.image.image }
  let item = IOSPreviewItem(asset: asset,frame: frame,poster: poster ?? library.thumbnails.poster(for: asset))
  let session = MediaPreviewSession(asset: asset, library: library, poster: item.poster, reviewAssets: assets)
  presentMediaViewer(NativeMediaViewer(item: item, session: session, review: review) {}, from: review, poster: item.poster)
}

struct IOSPreviewPresentation: UIViewControllerRepresentable {
  let item: IOSPreviewItem?
  let library: PhotoLibraryModel
  var collection: [PHAsset]? = nil
  let close: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
  func updateUIViewController(_ host: UIViewController, context: Context) {
    guard let item, context.coordinator.active == nil else { return }
    let coordinator = context.coordinator
    DispatchQueue.main.async {
      guard host.view.window != nil, host.presentedViewController == nil, coordinator.active == nil else { return }
      coordinator.active = item.id
      let session = MediaPreviewSession(asset: item.asset, library: library, poster: item.poster, reviewAssets: collection)
      presentMediaViewer(NativeMediaViewer(item: item, session: session) { coordinator.active = nil; close() },
        from: host, poster: item.poster)
    }
  }
  final class Coordinator { var active: String? }
}
struct IOSRecordedPhotoViewer: UIViewControllerRepresentable {
  let photo: HistoryPhoto
  let model: BackupModel
  let close: () -> Void
  func makeUIViewController(context: Context) -> UINavigationController { makeViewer() }
  /// The recorded viewer for the shared transition, flying from and back to
  /// its history tile.
  func makeNativeViewer(frame: @escaping (String) -> CGRect?, background: UIColor = .systemBackground) -> NativeMediaViewer {
    let asset = RecordedPhotoAsset(photo: photo)
    let library = PhotoLibraryModel()
    library.previewFrame = frame
    let session = MediaPreviewSession(asset: asset, library: library, reviewAssets: [asset])
    let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: asset, frame: frame(photo.source) ?? .zero, poster: nil, background: background),
      session: session, close: close)
    viewer.backupModel = model
    viewer.recordedPhoto = photo
    return viewer
  }
  func makeViewer() -> UINavigationController {
    let asset = RecordedPhotoAsset(photo: photo)
    let session = MediaPreviewSession(asset: asset, library: PhotoLibraryModel(), reviewAssets: [asset])
    let viewer = NativeMediaViewer(item: IOSPreviewItem(asset: asset, frame: .zero, poster: nil), session: session, close: close)
    viewer.backupModel = model
    viewer.recordedPhoto = photo
    viewer.flying = false
    let nav = MediaViewerNavigationController(rootViewController: viewer)
    viewer.loadViewIfNeeded(); session.start(); viewer.stage.alpha = 1; viewer.backdrop.alpha = 1
    viewer.layoutMedia()
    return nav
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
  static func dismantleUIViewController(_ controller: UINavigationController, coordinator: ()) {
    (controller.viewControllers.first as? NativeMediaViewer)?.releasePreviewSource()
  }
}

/// Present the native navigation owner directly so status-bar appearance follows
/// the media canvas, including unavailable-source immersion.
struct IOSRecordedPhotoPresentation: UIViewControllerRepresentable {
  let photo: HistoryPhoto?
  let model: BackupModel
  /// The tile frame of a source, for the flight out and back.
  var frame: (String) -> CGRect? = { _ in nil }
  var background: UIColor = .systemBackground
  let close: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
  func updateUIViewController(_ host: UIViewController, context: Context) {
    guard let photo, !context.coordinator.active else { return }
    let coordinator = context.coordinator
    DispatchQueue.main.async {
      guard host.view.window != nil, host.presentedViewController == nil, !coordinator.active else { return }
      coordinator.active = true
      let viewer = IOSRecordedPhotoViewer(photo: photo, model: model) {
        coordinator.active = false; close()
      }.makeNativeViewer(frame: frame, background: background)
      presentMediaViewer(viewer, from: host, poster: nil)
    }
  }
  final class Coordinator { var active = false }
}

/// Retains recorded identity and metadata without asking PhotoKit for a missing source.
private final class RecordedPhotoAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let photo: HistoryPhoto
  init(photo: HistoryPhoto) { self.photo = photo; super.init() }
  override var localIdentifier: String { photo.source }
  override var creationDate: Date? { photo.takenAt }
  override var modificationDate: Date? { nil }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var location: CLLocation? { nil }
  override var duration: TimeInterval { 0 }
  override var pixelWidth: Int { 1 }
  override var pixelHeight: Int { 1 }
  var previewImage: LibraryImage? { nil }
  var previewFilename: String { photo.job?.asset.resources.first?.filename ?? "" }
  var previewMetadata: [(String, String)] { PhotoInformationLayout.fileFields(for: photo.job) }
}

/// Presents the library viewer from the controller that owns the tapped tile,
/// with `MediaViewerTransition`. No SwiftUI state sits between the tap and
/// the presentation.
@MainActor func presentLibraryViewer(_ asset: PHAsset, frame: CGRect, poster: UIImage?,
  library: PhotoLibraryModel, from presenter: UIViewController) {
  guard presenter.presentedViewController == nil else { return }
  let item = IOSPreviewItem(asset: asset, frame: frame, poster: poster)
  let session = MediaPreviewSession(asset: asset, library: library, poster: poster)
  presentMediaViewer(NativeMediaViewer(item: item, session: session) {}, from: presenter, poster: poster)
}

/// Snapshots and the live viewer must share the source sheet's native clip.
@MainActor private func applyMediaViewerSheetClipping(to target: UIView, from source: UIView) {
  // The sheet may place its system clipping surface above the controller's
  // view. Read only matching native geometry; never identify private classes.
  let frame = source.convert(source.bounds, to: nil)
  var clipping = source, ancestor: UIView? = source
  while let candidate = ancestor, candidate !== source.window {
    if candidate.convert(candidate.bounds, to: nil).integral == frame.integral {
      if #available(iOS 26.0, *) {
        if candidate.effectiveRadius(corner: .allCorners) > 0 { clipping = candidate; break }
      } else if candidate.layer.cornerRadius > 0 { clipping = candidate; break }
    }
    ancestor = candidate.superview
  }
  if #available(iOS 26.0, *) {
    target.cornerConfiguration = .corners(
      topLeftRadius: .fixed(clipping.effectiveRadius(corner: .topLeft)),
      topRightRadius: .fixed(clipping.effectiveRadius(corner: .topRight)),
      bottomLeftRadius: .fixed(clipping.effectiveRadius(corner: .bottomLeft)),
      bottomRightRadius: .fixed(clipping.effectiveRadius(corner: .bottomRight)))
  } else {
    target.layer.cornerRadius = clipping.layer.cornerRadius
    target.layer.maskedCorners = clipping.layer.maskedCorners
  }
  target.layer.cornerCurve = clipping.layer.cornerCurve
  target.clipsToBounds = true
}

@MainActor private func mediaViewerNavigationBar(in view: UIView) -> UINavigationBar? {
  if let bar = view as? UINavigationBar, !bar.isHidden { return bar }
  return view.subviews.lazy.compactMap { mediaViewerNavigationBar(in: $0) }.first
}

/// A media presentation from a sheet keeps the sheet's native frame while
/// UIKit gives the viewer its own presentation container and input ownership.
@MainActor private final class MediaViewerSheetPresentation: UIPresentationController {
  weak var sourceSheet: UIPresentationController?
  override var frameOfPresentedViewInContainerView: CGRect {
    guard let containerView, let source = sourceSheet?.presentedView else { return super.frameOfPresentedViewInContainerView }
    return containerView.convert(source.bounds, from: source)
  }
  override func containerViewWillLayoutSubviews() {
    super.containerViewWillLayoutSubviews()
    layoutPresentedView()
  }
  func layoutPresentedView() {
    guard let presentedView, let source = sourceSheet?.presentedView else { return }
    presentedView.frame = frameOfPresentedViewInContainerView
    applyMediaViewerSheetClipping(to: presentedView, from: source)
    guard let navigation = presentedViewController as? UINavigationController,
      let sourceBar = mediaViewerNavigationBar(in: source) else { return }
    navigation.view.layoutIfNeeded()
    let sourceTop = sourceBar.convert(sourceBar.bounds, to: presentedView).minY
    // A custom presentation lacks the sheet's native navigation inset. Reserve
    // the source bar's actual top extent before UIKit lays out the first frame.
    let automaticTop = max(0, presentedView.safeAreaInsets.top - navigation.additionalSafeAreaInsets.top)
    let top = max(0, sourceTop - automaticTop)
    if navigation.additionalSafeAreaInsets.top != top {
      navigation.additionalSafeAreaInsets.top = top
      navigation.view.setNeedsLayout(); navigation.view.layoutIfNeeded()
    }
  }
}

@MainActor private func mediaViewerSheet(from presenter: UIViewController) -> UIPresentationController? {
  var owner = presenter
  while let parent = owner.parent { owner = parent }
  guard owner.presentingViewController != nil,
    let sheet = owner.presentationController as? UISheetPresentationController else { return nil }
  return sheet
}

@MainActor protocol MediaViewerNavigationOwning: AnyObject {}

/// Presentation can change safe areas before UIKit hands a source back.
/// A source retains its established viewport until that handoff is complete.
@MainActor protocol MediaViewerSourceGeometryOwning: AnyObject {
  func retainMediaViewerSourceGeometry()
  func releaseMediaViewerSourceGeometry()
}

@MainActor func presentMediaViewer(_ viewer: NativeMediaViewer, from presenter: UIViewController, poster: UIImage?) {
  guard presenter.presentedViewController == nil else { return }
  viewer.usesTransition = true
  viewer.flying = false
  viewer.openingTransition = true
  let navigation = MediaViewerNavigationController(rootViewController: viewer)
  viewer.transitionNavigation = navigation
  let sourceSheet = mediaViewerSheet(from: presenter)
  if let window = presenter.view.window {
    viewer.session.setDisplayViewport(sourceSheet?.presentedView?.bounds.size ?? window.bounds.size, screen: window.screen)
  }
  let transition = MediaViewerTransition()
  transition.sourceSheet = sourceSheet
  viewer.mediaTransition = transition
  navigation.modalPresentationStyle = sourceSheet == nil ? .overFullScreen : .custom
  navigation.modalPresentationCapturesStatusBarAppearance = sourceSheet == nil
  navigation.transitioningDelegate = transition
  navigation.mediaTransition = transition
  viewer.loadViewIfNeeded(); viewer.session.start()
  if sourceSheet != nil { navigation.view.accessibilityViewIsModal = true }
  viewer.stage.alpha = 1; viewer.backdrop.alpha = 1
  // Wait at most five frames for the full-aspect rendition (photo or video
  // poster), or a little longer while there is no picture at all, so the
  // flight never shows an empty frame; then fly whatever picture there is.
  func present(_ waited: Int) {
    viewer.view.frame = sourceSheet?.presentedView?.bounds ?? presenter.view.window?.bounds ?? viewer.view.frame
    viewer.view.layoutIfNeeded()
    if viewer.pages.count == 3 {
      let page = viewer.pages[1]
      if !page.scroll.showsFullAspect { page.refresh() }
      let pictured = page.scroll.photo.image != nil
      if !page.scroll.showsFullAspect, waited < 5 || (!pictured && waited < 20) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { present(waited + 1) }
        return
      }
      if !pictured, let poster { page.scroll.display(poster) }
    }
    guard presenter.presentedViewController == nil, presenter.view.window != nil else { return }
    transition.retainSourceGeometry(from: presenter)
    presenter.present(navigation, animated: true)
  }
  present(0)
}

/// The viewer's presentation, built from the UIKit transition API as the
/// shared media surface behaves: the grid stays below the viewer content,
/// and the photo flies within that content below the filmstrip and native bars.
/// The viewer backdrop and filmstrip join the photo's property animator;
/// the live media takes over at identical pixels.
@MainActor final class MediaViewerTransition: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning {
  private weak var sourceGeometryOwner: MediaViewerSourceGeometryOwning?
  private var sourceSheetState: (modal: Bool, expands: Bool)?
  func retainSourceGeometry(from presenter: UIViewController) {
    func owner(in controller: UIViewController) -> MediaViewerSourceGeometryOwning? {
      (controller as? MediaViewerSourceGeometryOwning) ?? controller.children.compactMap { owner(in: $0) }.first
    }
    sourceGeometryOwner = owner(in: presenter)
    sourceGeometryOwner?.retainMediaViewerSourceGeometry()
    if let sheet = sourceSheet as? UISheetPresentationController {
      sourceSheetState = (sheet.presentedViewController.isModalInPresentation, sheet.prefersScrollingExpandsWhenScrolledToEdge)
      sheet.presentedViewController.isModalInPresentation = true
      sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    }
  }
  private func releaseSourceGeometry() {
    sourceGeometryOwner?.releaseMediaViewerSourceGeometry()
    sourceGeometryOwner = nil
    if let state = sourceSheetState, let sheet = sourceSheet as? UISheetPresentationController {
      sheet.presentedViewController.isModalInPresentation = state.modal
      sheet.prefersScrollingExpandsWhenScrolledToEdge = state.expands
    }
    sourceSheetState = nil
  }
  weak var sourceSheet: UIPresentationController?
  func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
    guard let sourceSheet else { return nil }
    let controller = MediaViewerSheetPresentation(presentedViewController: presented, presenting: presenting)
    controller.sourceSheet = sourceSheet
    return controller
  }
  private var presenting = true
  /// Set by a drag-to-dismiss before it asks for the dismissal.
  private var drag: (origin: CGPoint, center: CGPoint)?
  private var interactiveReturnRequested = false
  private var interaction: (context: UIViewControllerContextTransitioning, viewer: NativeMediaViewer,
    surface: UIView?, flyer: UIView?, clip: UIView?, cover: UIView?, geometry: MediaFlightGeometry?)?
  private static let duration: TimeInterval = 0.36
  /// The whole screen as it was when the viewer opened. A grid in a sheet
  /// does not fill the screen, and what surrounds it does not change while
  /// the viewer is open.
  private var screen: UIView?
  private(set) weak var entrySourceCover: UIView?
  private(set) var entryFlightViews: [UIView] = []
  /// The grid as it is now, at its own place on screen, over the screen as it
  /// was when the viewer opened.
  private func gridCover(_ grid: UIView?, in container: UIView) -> UIView? {
    guard let grid, let cover = grid.snapshotView(afterScreenUpdates: true) else { return nil }
    cover.frame = container.convert(grid.bounds, from: grid)
    if let source = sourceSheet?.presentedView { applyMediaViewerSheetClipping(to: cover, from: source) }
    return sourceCover(cover, in: container)
  }
  private func sourceCover(_ cover: UIView, in container: UIView) -> UIView {
    guard screen != nil && cover.frame.integral != container.bounds.integral else { return cover }
    let stack = UIView(frame: container.bounds)
    if let screen { screen.frame = stack.bounds; stack.addSubview(screen) }
    stack.addSubview(cover)
    return stack
  }
  func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    self.presenting = true; return self
  }
  func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    presenting = false; return self
  }
  func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
    interactiveReturnRequested ? self : nil
  }
  nonisolated func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval { Self.duration }
  func beginInteractive(origin: CGPoint, center: CGPoint) {
    interactiveReturnRequested = true; drag = (origin, center)
  }
  nonisolated func startInteractiveTransition(_ context: UIViewControllerContextTransitioning) {
    MainActor.assumeIsolated { startDrag(context) }
  }
  private func startDrag(_ context: UIViewControllerContextTransitioning) {
    interactiveReturnRequested = false
    let container = context.containerView
    guard let navigation = context.viewController(forKey: .from), let viewer = viewer(navigation) else {
      context.completeTransition(true); return
    }
    // The finger already lifted before UIKit started the dismissal: nothing
    // would ever end it, and its cover would swallow every touch.
    guard drag != nil else {
      context.cancelInteractiveTransition()
      // Let the navigation controller finish installing its interactive stack
      // before completing a cancellation that arrived during that installation.
      DispatchQueue.main.async {
        context.completeTransition(false)
        viewer.transitionDidCancelClose()
      }
      return
    }
    let grid = context.viewController(forKey: .to)?.view
    grid?.layoutIfNeeded()
    let destination = viewer.returnFrame()
    viewer.setSourceHidden(true)
    grid?.layoutIfNeeded()
    viewer.activateReturnChrome()
    let cover = gridCover(grid, in: container)
    if let cover { container.insertSubview(cover, belowSubview: navigation.view) }
    if !viewer.session.library.previewOwnsVacancy {
      blank(destination, background: viewer.item.background, in: cover, container: container)
    }
    var flyer: UIView?, clip: UIView?, geometry: MediaFlightGeometry?
    let surface = viewer.mediaSurface()
    if let surface, let snapshot = surface.snapshotView(afterScreenUpdates: false) {
      let base = surface.convert(surface.bounds, to: viewer.view)
      snapshot.isUserInteractionEnabled = false
      snapshot.bounds = CGRect(origin: .zero, size: base.size); snapshot.center = CGPoint(x: base.midX, y: base.midY)
      let mask = UIView(frame: snapshot.bounds); mask.backgroundColor = DuckMedia.backgroundUIColor; snapshot.mask = mask
      viewer.view.insertSubview(snapshot, aboveSubview: viewer.stage)
      surface.alpha = 0
      if let destination, viewer.infoHeight == 0 {
        geometry = MediaFlightGeometry(bounds: snapshot.bounds, fitted: base, thumbnail: viewer.view.convert(destination, from: nil))
      }
      flyer = snapshot; clip = mask
    }
    interaction = (context, viewer, surface, flyer, clip, cover, geometry)
  }
  /// Follows the finger: the photo moves and shrinks with the drag, and the
  /// grid shows through in proportion to the distance.
  func updateInteractive(_ translation: CGPoint) {
    guard let interaction, let drag else { return }
    let progress = min(1, max(0, translation.y / 240))
    interaction.flyer?.transform = MediaFlightGeometry.drag(origin: drag.origin, center: drag.center, translation: translation)
    interaction.viewer.setTransitionContentVisibility(1 - progress)
    interaction.context.updateInteractiveTransition(progress)
  }
  /// Release carries the finger's velocity into one spring, to the tile or back.
  /// False when no dismissal was running, so the viewer restores itself.
  @discardableResult func endInteractive(commit: Bool, velocity: CGFloat) -> Bool {
    guard let interaction else { drag = nil; return false }
    self.interaction = nil; drag = nil; interactiveReturnRequested = false
    // Release UIKit's native bar transition on the same gesture event as
    // the content spring, instead of waiting until the photo has landed.
    if commit { interaction.context.finishInteractiveTransition() }
    else { interaction.context.cancelInteractiveTransition() }
    let animation = animator(velocity: velocity)
    animation.addAnimations {
      if commit {
        interaction.viewer.setTransitionContentVisibility(0)
        if let geometry = interaction.geometry {
          interaction.flyer?.transform = geometry.transform; interaction.clip?.frame = geometry.crop
        } else { interaction.flyer?.alpha = 0 }
      } else {
        interaction.viewer.setTransitionContentVisibility(1)
        interaction.flyer?.transform = .identity
      }
    }
    animation.addCompletion { _ in
      let context = interaction.context
      if commit {
        UIView.performWithoutAnimation {
          context.viewController(forKey: .from)?.view.removeFromSuperview()
          interaction.viewer.transitionDidClose()
          context.completeTransition(true)
          self.releaseSourceGeometry()
          interaction.flyer?.removeFromSuperview(); interaction.cover?.removeFromSuperview()
        }
      } else {
        interaction.surface?.alpha = 1
        interaction.flyer?.removeFromSuperview(); interaction.cover?.removeFromSuperview()
        context.completeTransition(false)
        interaction.viewer.transitionDidCancelClose()
      }
    }
    animation.startAnimation()
    return true
  }
  nonisolated func animateTransition(using context: UIViewControllerContextTransitioning) {
    MainActor.assumeIsolated { presenting ? open(context) : close(context) }
  }
  /// The grid snapshot can be taken before the hidden tile is committed; its
  /// slot is blanked so the flying photo is never shown twice.
  private func blank(_ frame: CGRect?, background: UIColor, in cover: UIView?, container: UIView) {
    guard let frame, let cover else { return }
    let slot = UIView(frame: cover.convert(container.convert(frame, from: nil), from: container))
    slot.backgroundColor = background
    cover.addSubview(slot)
  }
  private func viewer(_ controller: UIViewController?) -> NativeMediaViewer? {
    (controller as? NativeMediaViewer) ?? (controller as? UINavigationController)?.viewControllers.first as? NativeMediaViewer
  }
  private func animator(velocity: CGFloat = 0) -> UIViewPropertyAnimator {
    let timing = UISpringTimingParameters(dampingRatio: 0.94, initialVelocity: CGVector(dx: 0, dy: min(4, abs(velocity) / 800)))
    return UIViewPropertyAnimator(duration: Self.duration, timingParameters: timing)
  }
  /// The picture that flies in: the viewer's displayed rendition, or the
  /// grid's thumbnail. A snapshot of the not yet drawn viewer could come out
  /// empty and show as a white flash, so no snapshot is taken.
  private func flyer(for viewer: NativeMediaViewer) -> UIView? {
    let shown = viewer.pages.count == 3 ? viewer.pages[1].scroll.photo.image : nil
    guard let image = shown ?? viewer.item.poster else { return nil }
    let flyer = UIImageView(image: image)
    flyer.contentMode = .scaleAspectFill; flyer.clipsToBounds = true
    flyer.isUserInteractionEnabled = false
    viewer.view.insertSubview(flyer, aboveSubview: viewer.stage)
    return flyer
  }
  private func open(_ context: UIViewControllerContextTransitioning) {
    let container = context.containerView
    guard let navigation = context.viewController(forKey: .to), let viewer = viewer(navigation) else {
      context.completeTransition(true); return
    }
    // The grid as it is now, before anything changes. Its tapped tile stays
    // in place and fades with the grid while the copy flies, as in Photos;
    // only the way back leaves the landing slot empty until the photo arrives.
    let source = context.viewController(forKey: .from)?.view
    screen = source?.window?.snapshotView(afterScreenUpdates: false)
      ?? source?.window?.snapshotView(afterScreenUpdates: true)
    let cover = screen.map { screen -> UIView in
      let copy = UIView(frame: container.bounds)
      copy.isUserInteractionEnabled = false; copy.layer.allowsGroupOpacity = true
      screen.frame = copy.bounds; copy.addSubview(screen); return copy
    }
    entrySourceCover = cover
    UIView.performWithoutAnimation {
      // Install the source before any destination layout can commit pixels.
      if let cover { container.addSubview(cover) }
      navigation.view.frame = context.finalFrame(for: navigation)
      if let cover { container.insertSubview(navigation.view, belowSubview: cover) }
      else { container.addSubview(navigation.view) }
      (navigation.presentationController as? MediaViewerSheetPresentation)?.layoutPresentedView()
      navigation.view.layoutIfNeeded(); viewer.layoutMedia()
    }
    navigation.view.isUserInteractionEnabled = false
    if viewer.pages.count == 3 { viewer.pages[1].flightLocked = true }
    // Keep native glass live at its natural opacity. Dissolving the source
    // composition reveals it without freezing a transient material backdrop.
    viewer.setTransitionContentVisibility(1)
    let reduce = UIAccessibility.isReduceMotionEnabled
    let surface = viewer.mediaSurface()
    var flight: (view: UIView, clip: UIView)?
    var twin: (view: UIView, clip: UIView)?
    if !reduce, let surface, surface.bounds.width > 0, let snapshot = flyer(for: viewer) {
      let base = surface.convert(surface.bounds, to: viewer.view)
      let geometry = MediaFlightGeometry(bounds: surface.bounds, fitted: base, thumbnail: viewer.view.convert(viewer.item.frame, from: nil))
      snapshot.bounds = CGRect(origin: .zero, size: base.size); snapshot.center = CGPoint(x: base.midX, y: base.midY)
      let clip = UIView(frame: geometry.crop); clip.backgroundColor = DuckMedia.backgroundUIColor; snapshot.mask = clip
      snapshot.transform = geometry.transform
      flight = (snapshot, clip)
      entryFlightViews = [snapshot]
      if let cover, let image = (snapshot as? UIImageView)?.image {
        let viewport = UIView(frame: cover.convert(viewer.view.bounds, from: viewer.view))
        viewport.bounds = viewer.view.bounds; viewport.clipsToBounds = true
        viewport.isUserInteractionEnabled = false
        if let sheet = sourceSheet?.presentedView { applyMediaViewerSheetClipping(to: viewport, from: sheet) }
        let copy = UIImageView(image: image)
        copy.contentMode = .scaleAspectFill; copy.clipsToBounds = true
        copy.isUserInteractionEnabled = false
        copy.bounds = snapshot.bounds; copy.center = snapshot.center; copy.transform = snapshot.transform
        let mask = UIView(frame: geometry.crop); mask.backgroundColor = DuckMedia.backgroundUIColor; copy.mask = mask
        viewport.addSubview(copy); cover.addSubview(viewport)
        twin = (copy, mask); entryFlightViews.append(copy)
      }
      surface.alpha = 0
    }
    viewer.setSourceHidden(true)
    let animation = reduce ? UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) : animator()
    animation.addAnimations {
      cover?.alpha = 0
      if let flight { flight.view.transform = .identity; flight.clip.frame = flight.view.bounds }
      if let twin { twin.view.transform = .identity; twin.clip.frame = twin.view.bounds }
    }
    animation.addCompletion { _ in
      viewer.openingTransition = false
      if viewer.pages.count == 3 { viewer.pages[1].flightLocked = false }
      UIView.performWithoutAnimation {
        surface?.alpha = 1
        flight?.view.removeFromSuperview(); cover?.removeFromSuperview()
        self.entrySourceCover = nil; self.entryFlightViews.removeAll()
      }
      navigation.view.isUserInteractionEnabled = true
      context.completeTransition(true)
      viewer.transitionDidOpen()
    }
    animation.startAnimation()
  }
  private func close(_ context: UIViewControllerContextTransitioning) {
    let container = context.containerView
    guard let navigation = context.viewController(forKey: .from), let viewer = viewer(navigation) else {
      context.completeTransition(true); return
    }
    // The grid settles its return position before it is captured, hidden
    // behind the opaque viewer, so the photo lands on a definite slot.
    let grid = context.viewController(forKey: .to)?.view
    grid?.layoutIfNeeded()
    let destination = viewer.returnFrame()
    viewer.setSourceHidden(true)
    grid?.layoutIfNeeded()
    viewer.activateReturnChrome()
    let cover = gridCover(grid, in: container)
    if let cover { container.insertSubview(cover, belowSubview: navigation.view) }
    if !viewer.session.library.previewOwnsVacancy {
      blank(destination, background: viewer.item.background, in: cover, container: container)
    }
    let reduce = UIAccessibility.isReduceMotionEnabled
    var flight: (view: UIView, clip: UIView, geometry: MediaFlightGeometry)?
    if !reduce, let surface = viewer.mediaSurface(), let destination, viewer.infoHeight == 0,
      let snapshot = surface.snapshotView(afterScreenUpdates: false) {
      let held = surface.transform
      surface.transform = .identity
      let base = surface.convert(surface.bounds, to: viewer.view), size = surface.bounds.size
      surface.transform = held
      let geometry = MediaFlightGeometry(bounds: CGRect(origin: .zero, size: size), fitted: base,
        thumbnail: viewer.view.convert(destination, from: nil))
      snapshot.isUserInteractionEnabled = false
      snapshot.bounds = CGRect(origin: .zero, size: size); snapshot.center = CGPoint(x: base.midX, y: base.midY)
      snapshot.transform = held
      let clip = UIView(frame: snapshot.bounds); clip.backgroundColor = DuckMedia.backgroundUIColor; snapshot.mask = clip
      viewer.view.insertSubview(snapshot, aboveSubview: viewer.stage)
      surface.alpha = 0
      flight = (snapshot, clip, geometry)
    }
    let animation = reduce ? UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) : animator(velocity: viewer.closingVelocity)
    animation.addAnimations {
      viewer.setTransitionContentVisibility(0)
      if let flight { flight.view.transform = flight.geometry.transform; flight.clip.frame = flight.geometry.crop }
    }
    animation.addCompletion { _ in
      let cancelled = context.transitionWasCancelled
      // Native edge-back can cancel the same return animator.
      UIView.performWithoutAnimation {
        if cancelled {
          viewer.mediaSurface()?.alpha = 1
          viewer.setTransitionContentVisibility(1)
        } else {
          navigation.view.removeFromSuperview()
          viewer.transitionDidClose()
        }
        context.completeTransition(!cancelled)
        if !cancelled { self.releaseSourceGeometry() }
        flight?.view.removeFromSuperview(); cover?.removeFromSuperview()
      }
      if cancelled { viewer.transitionDidCancelClose() }
    }
    animation.startAnimation()
  }
}

@MainActor final class MediaViewerNavigationController: UINavigationController, MediaViewerNavigationOwning {
  /// Retained here: `transitioningDelegate` is weak.
  var mediaTransition: MediaViewerTransition?
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .clear
    interactivePopGestureRecognizer?.isEnabled = false
  }
}

/// Reserve the system title slot while the system button supplies its glass.
@MainActor private final class MediaViewerTitleView: UIView {
  override var intrinsicContentSize: CGSize { CGSize(width: 162,height: 44) }
  override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }
}

/// A system circular button; its quiet mark describes facts, never an action.
@MainActor private final class MediaViewerInfoButton: UIButton {
  private let dot = UIImageView(image: UIImage(systemName: "circle.fill"))
  private let ring = CAShapeLayer()
  private var open = false, marked = false
  private var fraction: Double?

  init() {
    super.init(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
    if #available(iOS 26.0, *) { configuration = .glass() }
    else { configuration = .plain() }
    configuration?.cornerStyle = .capsule
    configuration?.buttonSize = .large
    configuration?.contentInsets = .zero
    configuration?.image = UIImage(systemName: "info.circle")
    configuration?.preferredSymbolConfigurationForImage = .init(textStyle: .body)
    configuration?.baseForegroundColor = .label
    dot.contentMode = .scaleAspectFit
    dot.addSymbolEffect(.disappear, animated: false)
    dot.isUserInteractionEnabled = false; addSubview(dot)
    ring.fillColor = UIColor.clear.cgColor
    ring.lineWidth = 1.5; ring.lineCap = .round; ring.isHidden = true
    layer.addSublayer(ring)
    isAccessibilityElement = true
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (button: MediaViewerInfoButton, _: UITraitCollection) in
      button.ring.strokeColor = DuckRole.accentUIColor.resolvedColor(with: button.traitCollection).cgColor
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var intrinsicContentSize: CGSize { CGSize(width: 48, height: 48) }
  override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

  override func layoutSubviews() {
    super.layoutSubviews()
    dot.frame = CGRect(x: bounds.maxX-10, y: bounds.minY+4, width: 6, height: 6)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    ring.frame = bounds
    ring.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: 16,
      startAngle: -.pi/2, endAngle: 1.5 * .pi, clockwise: true).cgPath
    CATransaction.commit()
  }

  func setOpen(_ value: Bool) {
    guard value != open else { return }; open = value
    let image = UIImage(systemName: value ? "info.circle.fill" : "info.circle")!
    accessibilityHint = NSLocalizedString(value ? "preview_hide_info" : "photo_viewer_info_hint", comment: "")
    if UIAccessibility.isReduceMotionEnabled {
      UIView.transition(with: self, duration: DuckMotion.enter, options: [.transitionCrossDissolve, .beginFromCurrentState]) { self.configuration?.image = image }
    } else {
      let previous = imageView?.image
      configuration?.image = image
      imageView?.image = previous
      imageView?.setSymbolImage(image, contentTransition: .replace)
    }
  }

  func setState(_ state: String, progress: Double?) {
    let failed = state == "photo_viewer_failed" || state == "records_load_failed"
    // Normal preparation, queue scheduling and confirmation are described in
    // Info. They must not turn an unavailable byte fraction into a status dot.
    let showMark = (failed || state == "photo_viewer_not_backed_up") && progress == nil
    dot.tintColor = failed ? DuckRole.attentionGlyphUIColor : DuckRole.accentUIColor
    if showMark != marked {
      marked = showMark
      if UIAccessibility.isReduceMotionEnabled {
        dot.removeAllSymbolEffects(animated: false)
        UIView.transition(with: dot, duration: DuckMotion.enter, options: [.transitionCrossDissolve, .beginFromCurrentState]) { self.dot.alpha = showMark ? 1 : 0 }
      } else {
        dot.alpha = 1
        if showMark { dot.removeSymbolEffect(ofType: .disappear) }
        else { dot.addSymbolEffect(.disappear) }
      }
    }
    if fraction != progress {
      let previous = ring.presentation()?.strokeEnd ?? ring.strokeEnd
      let changes = {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        self.ring.isHidden = progress == nil
        self.ring.strokeColor = DuckRole.accentUIColor.resolvedColor(with: self.traitCollection).cgColor
        self.ring.strokeEnd = progress ?? 0
        CATransaction.commit()
      }
      ring.removeAnimation(forKey: "progress")
      if UIAccessibility.isReduceMotionEnabled {
        UIView.transition(with: self, duration: DuckMotion.enter, options: [.transitionCrossDissolve, .beginFromCurrentState], animations: changes)
      } else {
        changes()
        if let progress, fraction != nil {
          let animation = CABasicAnimation(keyPath: "strokeEnd")
          animation.fromValue = previous; animation.toValue = progress
          animation.duration = DuckMotion.progress
          ring.add(animation, forKey: "progress")
        }
      }
      fraction = progress
    }
    let key = progress == nil ? state : "photo_viewer_backing_up"
    let stateText = NSLocalizedString(key, comment: "").lowercased(with: .current) + (progress.map { " " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    accessibilityLabel = state == "photo_viewer_saved" ? NSLocalizedString("photo_viewer_info", comment: "")
      : String(format: NSLocalizedString("photo_viewer_info_state", comment: ""), stateText)
    accessibilityHint = NSLocalizedString(open ? "preview_hide_info" : "photo_viewer_info_hint", comment: "")
  }
}

/// One UIKit owner coordinates paging, scrubbing, information and image flight.
/// Gesture progress is direct; controllers are recycled only after a page settles.
@MainActor final class NativeMediaViewer: UIViewController, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
  private var finished = false
  /// Opened and closed by `MediaViewerTransition`: the presentation owns the
  /// flight and the crossfade with the grid; the viewer only shows its page.
  var usesTransition = false
  weak var transitionNavigation: UINavigationController?
  var closingVelocity: CGFloat = 0
  let item: IOSPreviewItem, session: MediaPreviewSession, closeViewer: () -> Void
  let backdrop = UIView(), stage = UIView(), pager = UIScrollView(), footer = UIView()
  // A native pop detaches navigation ownership before its interactive content
  // has finished. Missing chrome must never resolve to the media's root view.
  var header: UINavigationBar? { navigationController?.navigationBar }
  let backupAction = SelectionBackupAction()
  var backupModel = BackupEnvironment.activeModel()
  private let infoButton = MediaViewerInfoButton()
  private var backupActionKey: String?
  var shareItem: UIBarButtonItem!, infoItem: UIBarButtonItem!
  let titleButton = UIButton(type: .system)
  private let titleContainer = MediaViewerTitleView()
  // An undrawn hit target keeps title-toggle closing available after its chrome fades.
  private let titleToggleTarget = UIButton(type: .system)
  private var observedJob: BackupJob?
  private var observedTileState: String?
  private var backupFactsLoaded = false, backupFactsUnavailable = false
  private var backupFactsKey = ""
  private var backupFactsTask: Task<Void, Never>?
  private var retryingBackup = false
  private var retryError: String?
  private var retrySource: String?
  private var retryRegistered = false
  var recordedPhoto: HistoryPhoto?
  private var unavailableHost: UIHostingController<AnyView>?
  var backupSource = ""
  private var backupReceiver: String?, retryReceiver: String?
  private var currentBackupReceiver: String? { recordedPhoto?.job?.receiverID ?? backupModel.pairing?.receiverID }
  /// Catalogs substitute registration only; production keeps the durable selected endpoint.
  var backupRequest: (@MainActor () async -> Void)?
  var retryRequest: (@MainActor (BackupJob) async -> Bool)?
  var expandedToolbarHeight: CGFloat = 44
  private var expandedNavigationHeight: CGFloat = 0
  let loadingIndicator = MediaLoadingIndicator()
  private let previewFailure = UIHostingController(rootView: MediaPreviewFailure(retry: {}))
  let stripLayout = MediaFilmstripLayout()
  lazy var strip = UICollectionView(frame: .zero, collectionViewLayout: stripLayout)
  let information = UIView()
  private let stripFade = CAGradientLayer()
  var informationHost: UIHostingController<AnyView>?
  var pages: [NativeMediaPage] = []
  var pageCache: [String: NativeMediaPage] = [:]
  var pageAssets: [PHAsset] = []
  var cancellables = Set<AnyCancellable>(), mediaObservations = Set<AnyCancellable>()
  var animator: UIViewPropertyAnimator?, infoAnimator: UIViewPropertyAnimator?
  var suppress = false, closing = false, flying = true, chrome = true, infoHeight: CGFloat = 0
  var openingTransition = false
  var mediaTransition: MediaViewerTransition?
  private var transitionContentVisibility: CGFloat = 1
  private(set) var returnChromeViews: [UIView] = []
  private weak var returnChromeNavigation: UINavigationController?
  private var returnChromePrepared = false, returnChromeReady = false, returnChromeActive = false
  private var returnBarHidden = false, returnToolbarHidden = true
  private var returnToolbarItems: [(UIBarButtonItem, Bool)]?
  var index: Int = 0, verticalKind = 0, startInfo: CGFloat = 0
  private var lastLayoutBounds = CGRect.null, lastToolbarFrame = CGRect.null
  private var lastLayoutInsets = UIEdgeInsets.zero
  private var stripRevision = -1, stripCount = -1
  var pendingAsset: PHAsset?
  var mediaClipping: [(UIView,Bool)] = []
  weak var review: CalendarSelectedController?
  let selectionButton = UIButton(type: .system)
  /// One alpha for the review toggle and the selection marks on every page.
  var selectionAlpha: CGFloat = 0 {
    didSet { selectionButton.alpha = selectionAlpha; pages.forEach { $0.selectionMark.alpha = selectionAlpha } }
  }
  var completeReview = false
  var pageStride: CGFloat { stage.bounds.width + 40 }
  var dragOrigin = CGPoint.zero, dragCenter = CGPoint.zero
  init(item: IOSPreviewItem, session: MediaPreviewSession, review: CalendarSelectedController? = nil, close: @escaping () -> Void) {
    self.item = item; self.session = session; self.review = review; closeViewer = close; super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override var preferredStatusBarStyle: UIStatusBarStyle {
    !chrome || traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
  }
  override var prefersStatusBarHidden: Bool { !chrome || infoHeight > 0 }
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .clear
    edgesForExtendedLayout = .all; extendedLayoutIncludesOpaqueBars = true
    backdrop.backgroundColor = .systemBackground; backdrop.alpha = 0; view.addSubview(backdrop)
    stage.alpha = 0
    view.addSubview(stage); stage.addSubview(pager); view.addSubview(footer)
    pager.isPagingEnabled = true; pager.decelerationRate = .fast; pager.delegate = self
    pager.contentInsetAdjustmentBehavior = .never; pager.showsHorizontalScrollIndicator = false
    pager.accessibilityIdentifier = "library.preview.pager"
    let pan = UIPanGestureRecognizer(target: self, action: #selector(vertical(_:))); pan.delegate = self
    stage.addGestureRecognizer(pan); pager.panGestureRecognizer.require(toFail: pan)
    navigationItem.backAction = UIAction(title: "") { [weak self] _ in self?.dismissViewer() }
    navigationItem.largeTitleDisplayMode = .never
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    navigationItem.standardAppearance = appearance
    navigationItem.scrollEdgeAppearance = appearance
    navigationItem.compactAppearance = appearance
    navigationItem.compactScrollEdgeAppearance = appearance
    if review != nil {
      selectionButton.accessibilityIdentifier = "calendar.selected_preview_toggle"
      selectionButton.addAction(UIAction { [weak self] _ in
        guard let self, let review = self.review else { return }
        var ids = review.selected; let id = self.reviewID(self.session.current.asset)
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        review.setSelection(ids); self.updateReviewSelection()
      },for: .touchUpInside)
      view.addSubview(selectionButton)
    }
    if #available(iOS 26.0, *) { titleButton.configuration = .glass() }
    else { titleButton.configuration = .plain() }
    titleButton.configuration?.contentInsets = .zero
    titleButton.configuration?.titlePadding = 0
    titleButton.configuration?.titleAlignment = .center
    titleButton.configuration?.titleLineBreakMode = .byTruncatingTail
    titleButton.configuration?.subtitleLineBreakMode = .byTruncatingTail
    titleButton.titleLabel?.adjustsFontForContentSizeCategory = true
    titleButton.subtitleLabel?.adjustsFontForContentSizeCategory = true
    titleButton.accessibilityIdentifier = "library.preview.title"
    titleButton.accessibilityHint = NSLocalizedString("photo_viewer_info_hint", comment: "")
    titleButton.addAction(UIAction { [weak self] _ in
      guard let self else { return }; self.setInfo(self.infoHeight == 0)
    }, for: .touchUpInside)
    // The principal title must stay in the navigation title slot. Center item
    // groups can be collapsed by UIKit into its trailing overflow menu.
    titleContainer.frame = CGRect(x: 0,y: 0,width: 162,height: 44)
    titleButton.frame = titleContainer.bounds
    titleButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    titleContainer.addSubview(titleButton)
    navigationItem.titleView = titleContainer
    titleToggleTarget.accessibilityIdentifier = "library.preview.title_toggle"
    titleToggleTarget.accessibilityLabel = NSLocalizedString("preview_hide_info", comment: "")
    titleToggleTarget.addAction(UIAction { [weak self] _ in self?.setInfo(false) }, for: .touchUpInside)
    view.addSubview(titleToggleTarget)
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (viewer: NativeMediaViewer, _: UITraitCollection) in
      viewer.updateBackupControl()
    }
    configureToolbar()
    backupAction.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateBackupControl(); self?.refreshInformation() }.store(in: &cancellables)
    backupModel.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
      self?.refreshBackupObservation(); self?.updateBackupControl(); self?.refreshInformation()
    }.store(in: &cancellables)
    loadingIndicator.retry = { [weak self] in self?.session.current.load() }
    view.addSubview(loadingIndicator)
    previewFailure.rootView = MediaPreviewFailure(retry: { [weak self] in self?.session.current.load() })
    addChild(previewFailure); view.addSubview(previewFailure.view); previewFailure.didMove(toParent: self)
    previewFailure.view.backgroundColor = .clear
    previewFailure.view.isHidden = true
    strip.backgroundColor = .clear; strip.showsHorizontalScrollIndicator = false
    // The filmstrip reads oldest to newest while retaining the grid's IDs,
    // collection order, paging context and native scrub coordinates.
    strip.transform = .identity
    // This manually placed horizontal strip must not inherit navigation safe-area insets.
    strip.contentInsetAdjustmentBehavior = .never
    strip.alwaysBounceVertical = false
    if #available(iOS 26.0, *) {
      pager.topEdgeEffect.isHidden = true
      pager.bottomEdgeEffect.isHidden = true
      strip.topEdgeEffect.isHidden = true
      strip.bottomEdgeEffect.isHidden = true
    }
    strip.dataSource = self; strip.delegate = self; strip.accessibilityIdentifier = "library.preview.filmstrip"
    strip.register(PreviewStripCell.self, forCellWithReuseIdentifier: "preview.strip"); footer.addSubview(strip)
    stripFade.colors = [UIColor.clear.cgColor, UIColor.label.cgColor, UIColor.label.cgColor, UIColor.clear.cgColor]
    stripFade.locations = [0, 0.08, 0.92, 1]
    stripFade.startPoint = CGPoint(x: 0,y: 0.5); stripFade.endPoint = CGPoint(x: 1,y: 0.5)
    footer.layer.mask = stripFade
    // Resolve the panel surface in the same traits as its hosted semantic text.
    // Converting a SwiftUI color outside that environment can freeze its light value.
    information.backgroundColor = .systemBackground
    information.clipsToBounds = true
    information.accessibilityIdentifier = "preview.info.drawer"; view.addSubview(information)
    let panelPan = UIPanGestureRecognizer(target: self, action: #selector(dragInformation(_:))); panelPan.delegate = self
    information.addGestureRecognizer(panelPan)
    session.$current.receive(on: DispatchQueue.main).sink { [weak self] model in self?.currentChanged(model) }.store(in: &cancellables)
    session.$collectionRevision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
      guard let self else { return }; self.currentChanged(self.session.current)
    }.store(in: &cancellables)
    session.$paging.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in
      self?.updateStatus()
    }.store(in: &cancellables)
    session.$zoomed.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] zoomed in
      guard let self else { return }
      self.pager.isScrollEnabled = !zoomed && !self.closing && !self.flying
    }.store(in: &cancellables)
    PreviewNetworkPolicy.shared.$choice.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.session.reloadForPolicy() }.store(in: &cancellables)
    index = session.index(of: session.current.asset) ?? 0; installPages(); observeMedia()
    if recordedPhoto != nil {
      let host = UIHostingController(rootView: AnyView(ContentUnavailableView {
        Label("library_deleted_title", systemImage: "photo")
      } description: {
        if recordedPhoto?.job?.state == "received" && recordedPhoto?.job?.processing == "complete" {
          Text("library_deleted_saved_note")
        }
      }))
      // The explanation takes no touches, so a tap anywhere on the page
      // toggles the chrome as it does over a photo.
      host.view.isUserInteractionEnabled = false
      addChild(host); stage.addSubview(host.view); host.view.backgroundColor = .clear; host.didMove(toParent: self)
      unavailableHost = host
    }
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if flying { session.start(); enter() }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let toolbarFrame = navigationController.map { view.convert($0.toolbar.bounds, from: $0.toolbar) } ?? .zero
    guard lastLayoutBounds != view.bounds || lastLayoutInsets != view.safeAreaInsets || lastToolbarFrame != toolbarFrame else { return }
    lastLayoutBounds = view.bounds; lastLayoutInsets = view.safeAreaInsets; lastToolbarFrame = toolbarFrame
    layoutMedia(); centerStrip()
  }
  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    if isViewLoaded { layoutMedia() }
  }
  deinit { animator?.stopAnimation(true); infoAnimator?.stopAnimation(true); backupFactsTask?.cancel() }
  func layoutMedia() {
    let b = view.bounds, bottom = view.window?.safeAreaInsets.bottom ?? 0
    if let screen = view.window?.screen { session.setDisplayViewport(b.size, screen: screen) }
    backdrop.frame = b
    let footerHeight: CGFloat = 58
    // Floating toolbars have a full-screen host. The navigation controller's
    // safe-area reservation describes the controls, unlike the host's bounds.
    // Retain that reservation during immersion so the media viewport stays put.
    let toolbarReservation = view.safeAreaInsets.bottom - bottom
    if chrome, toolbarReservation > 0 { expandedToolbarHeight = toolbarReservation }
    let toolbarHeight = expandedToolbarHeight
    let toolbarTop = b.height-bottom-toolbarHeight
    footer.frame = CGRect(x: 0,y: toolbarTop-footerHeight,width: b.width,height: footerHeight)
    strip.frame = CGRect(x: 16,y: 10,width: b.width-32,height: 46)
    stripFade.frame = footer.bounds
    strip.contentInset = UIEdgeInsets(top: 0,left: strip.bounds.width/2,bottom: 0,right: strip.bounds.width/2)
    // Bars and filmstrip float over the full-screen browsing frame. Information
    // alone docks the media above its panel; immersion never changes the fit.
    let navigationBottom = (view.window?.safeAreaInsets.top ?? 0) + (header?.bounds.height ?? 0)
    if chrome, infoHeight == 0, navigationBottom > 0 { expandedNavigationHeight = navigationBottom }
    let infoFraction = min(1, max(0, infoHeight / max(1, informationOpenHeight)))
    stage.frame = CGRect(x: 0, y: 0, width: b.width, height: max(1, b.height - infoHeight))
    stage.clipsToBounds = true
    unavailableHost?.view.frame = stage.bounds
    suppress = true; pager.frame = CGRect(x: -20,y: 0,width: pageStride,height: stage.bounds.height)
    pager.contentSize = CGSize(width: pageStride*3,height: stage.bounds.height)
    pager.contentInset = UIEdgeInsets(top: 0,left: index == 0 ? -pageStride : 0,bottom: 0,
      right: index == session.count-1 ? -pageStride : 0)
    pager.alwaysBounceHorizontal = session.count > 1
    for (i,page) in pages.enumerated() {
      page.scroll.informationFraction = infoFraction
      page.view.frame = CGRect(x: CGFloat(i)*pageStride+20,y: 0,width: stage.bounds.width,height: stage.bounds.height)
      page.view.isHidden = (i == 0 && index == 0) || (i == 2 && index == session.count-1)
    }
    if !pager.isDragging && !pager.isDecelerating { pager.contentOffset.x = pager.bounds.width }
    suppress = false
    // The information surface continues directly below the photo, without sheet chrome.
    information.frame = CGRect(x: 0,y: b.height-infoHeight,width: b.width,height: infoHeight + bottom)
    informationHost?.view.frame = CGRect(x: 0,y: 0,width: b.width,height: max(0,infoHeight-bottom-toolbarHeight))
    pages.forEach { $0.view.layoutIfNeeded() }
    let media = imageRect()
    selectionButton.frame = CGRect(x: media.maxX-44,y: media.maxY-44,width: 44,height: 44)
    selectionAlpha = chrome && !flying && !openingTransition && !closing && infoHeight == 0 ? 1 : 0
    let infoFade = max(0,1-infoFraction*3)
    let chromeAlpha: CGFloat = chrome && !flying ? 1 : 0
    // Returning source controls belong to the navigation transition. A layout
    // callback from the departing viewer cannot hide or disable those controls.
    let ownsChrome = !closing && navigationController?.topViewController === self
    if ownsChrome {
      header?.alpha = chromeAlpha * infoFade
      navigationController?.toolbar.alpha = chromeAlpha
    }
    footer.alpha = chromeAlpha * infoFade * transitionContentVisibility
    footer.isUserInteractionEnabled = chromeAlpha * infoFade > 0
    infoButton.setOpen(infoHeight > 0)
    titleToggleTarget.frame = titleButton.convert(titleButton.bounds, to: view)
    titleToggleTarget.isHidden = infoFraction < 0.5 || !chrome || flying
    titleToggleTarget.accessibilityLabel = titleButton.accessibilityLabel
    titleToggleTarget.accessibilityHint = NSLocalizedString("preview_hide_info", comment: "")
    if ownsChrome {
      header?.isUserInteractionEnabled = chrome && !flying && infoFade > 0
      navigationController?.toolbar.isUserInteractionEnabled = chrome && !flying
    }
    // A reviewed selection keeps its mark in the photo's trailing corner, so
    // loading progress takes the leading corner instead of stacking above it.
    let loadingX: CGFloat = review == nil ? max(6,min(b.width-42,media.maxX-42)) : max(6,min(b.width-42,media.minX+6))
    let loadingY: CGFloat = max(view.safeAreaInsets.top+6,min(footer.frame.minY-42,media.maxY-42))
    loadingIndicator.frame = CGRect(x: loadingX,y: loadingY,width: 36,height: 36)
    let failureSize = previewFailure.sizeThatFits(in: CGSize(width: max(1, b.width - 2 * DuckSpacing.large), height: b.height))
    previewFailure.view.frame = CGRect(x: (b.width - failureSize.width) / 2,
      y: (b.height - failureSize.height) / 2, width: failureSize.width, height: failureSize.height)
    previewFailure.view.alpha = !flying && !closing ? infoFade : 0
    loadingIndicator.alpha = !flying && !openingTransition && !closing ? infoFade : 0
  }
  /// The flyer is a sibling above the media stage and below the footer. Return
  /// chrome follows the same direct gesture and property animator as the media;
  /// its navigation owner remains available while UIKit detaches the viewer.
  func setTransitionContentVisibility(_ visibility: CGFloat) {
    transitionContentVisibility = visibility
    backdrop.alpha = visibility
    stage.alpha = visibility
    information.alpha = visibility
    let infoFraction = min(1, max(0, infoHeight / max(1, informationOpenHeight)))
    footer.alpha = chrome && !flying ? max(0, 1 - infoFraction * 3) * visibility : 0
    if returnChromeActive {
      returnChromeViews.forEach { $0.alpha = visibility }
    } else if closing, let navigation = transitionNavigation ?? navigationController {
      navigation.navigationBar.alpha = chrome ? max(0, 1 - infoFraction * 3) * visibility : 0
      navigation.toolbar.alpha = chrome ? visibility : 0
    }
  }
  /// Floating system groups can render outside the bar view's alpha hierarchy.
  /// Capture their native pixels once, with transparent space around the groups.
  /// A temporary native shield keeps content removal invisible while taking the
  /// two bounded snapshots; all temporary state is restored synchronously.
  func prepareReturnChrome() {
    guard !returnChromePrepared, let navigation = transitionNavigation ?? navigationController else { return }
    returnChromePrepared = true; returnChromeNavigation = navigation
    returnBarHidden = navigation.isNavigationBarHidden; returnToolbarHidden = navigation.isToolbarHidden
    returnToolbarItems = toolbarItems?.map { ($0, $0.isHidden) }
    guard chrome else { returnChromeReady = true; return }
    let native = navigation.view!
    guard let window = native.window, let parent = native.superview,
      let shield = native.snapshotView(afterScreenUpdates: false) ?? native.snapshotView(afterScreenUpdates: true) else { return }
    let viewport = native.convert(view.bounds, from: view)
    let bar = native.convert(navigation.navigationBar.bounds, from: navigation.navigationBar)
    var regions: [CGRect] = []
    if !returnBarHidden, navigation.navigationBar.alpha > 0 {
      regions.append(CGRect(x: viewport.minX, y: max(viewport.minY, bar.minY - DuckSpacing.small),
        width: viewport.width, height: bar.height + 2 * DuckSpacing.small).intersection(viewport))
    }
    if !returnToolbarHidden {
      let top = max(viewport.minY, native.convert(CGPoint(x: 0, y: footer.frame.maxY), from: view).y - DuckSpacing.small)
      regions.append(CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.maxY - top)))
    }
    guard regions.allSatisfy({ !$0.isEmpty && !$0.isNull }) else { return }
    let wasHidden = view.isHidden, background = native.backgroundColor
    // Return preparation shields the current viewer while its native controls
    // are captured. Entry keeps the real controls and never uses this capture.
    shield.frame = window.convert(native.bounds, from: native)
    shield.isUserInteractionEnabled = false
    UIView.performWithoutAnimation {
      window.addSubview(shield)
      defer { shield.removeFromSuperview() }
      // The first snapshot may synchronously commit a previously undrawn view.
      // Install the current-view shield before asking UIKit for those pixels.
      guard let underlay = view.snapshotView(afterScreenUpdates: false) ?? view.snapshotView(afterScreenUpdates: true) else { return }
      // Preserve the glass's sampled background outside the captured container.
      underlay.frame = parent.convert(view.bounds, from: view); underlay.isUserInteractionEnabled = false
      parent.insertSubview(underlay, belowSubview: native)
      defer {
        view.isHidden = wasHidden; native.backgroundColor = background
        underlay.removeFromSuperview()
      }
      view.isHidden = true; native.backgroundColor = .clear
      for region in regions {
        // Floating groups can render outside the native bar's alpha hierarchy.
        // Keep their bounded pixels in the viewer's own fade plane while UIKit
        // retains the independently presented navigation controller.
        let image = UIGraphicsImageRenderer(size: region.size).image { context in
          context.cgContext.translateBy(x: -region.minX, y: -region.minY)
          native.drawHierarchy(in: native.bounds, afterScreenUpdates: true)
        }
        let snapshot = UIImageView(image: image)
        snapshot.frame = view.convert(region, from: native)
        snapshot.isUserInteractionEnabled = false
        returnChromeViews.append(snapshot)
      }
    }
    returnChromeReady = returnChromeViews.count == regions.count
    if !returnChromeReady { returnChromeViews.removeAll() }
  }
  /// Source geometry and its cover are fixed before changing native bar layout.
  func activateReturnChrome() {
    guard returnChromeReady, !returnChromeActive, let navigation = returnChromeNavigation else { return }
    returnChromeActive = true
    UIView.performWithoutAnimation {
      returnChromeViews.forEach { view.insertSubview($0, aboveSubview: footer) }
      navigationItem.setHidesBackButton(true, animated: false)
      navigationItem.rightBarButtonItem?.isHidden = true; titleContainer.isHidden = true
      returnToolbarItems?.forEach { $0.0.isHidden = true }
      setToolbarItems([], animated: false)
      navigation.setNavigationBarHidden(true, animated: false)
      navigation.setToolbarHidden(true, animated: false)
    }
  }
  func finishReturnChrome(cancelled: Bool) {
    UIView.performWithoutAnimation {
      if cancelled, returnChromeActive, let navigation = returnChromeNavigation {
        returnToolbarItems?.forEach { $0.0.isHidden = $0.1 }
        setToolbarItems(returnToolbarItems?.map(\.0), animated: false)
        navigationItem.setHidesBackButton(!chrome, animated: false)
        navigationItem.rightBarButtonItem?.isHidden = !chrome; titleContainer.isHidden = !chrome
        navigation.setNavigationBarHidden(returnBarHidden, animated: false)
        navigation.setToolbarHidden(returnToolbarHidden, animated: false)
        navigation.view.layoutIfNeeded(); layoutMedia()
      }
      returnChromeViews.forEach { $0.removeFromSuperview() }; returnChromeViews.removeAll()
      returnChromePrepared = false; returnChromeReady = false; returnChromeActive = false
      returnChromeNavigation = nil; returnToolbarItems = nil
    }
  }
  func makePage(_ asset: PHAsset, cache: Bool = true) -> NativeMediaPage {
    if cache, let cached = pageCache[asset.localIdentifier] { return cached }
    let controller = NativeMediaPage(model: session.model(for: asset),session: session)
    controller.zoomChanged = { [weak self] zoomed in
      guard let self, self.session.current.asset.localIdentifier == asset.localIdentifier else { return }
      if self.session.zoomed != zoomed { self.session.zoomed = zoomed }
    }
    controller.tapped = { [weak self] in self?.toggleChrome() }
    if review == nil { controller.information = { [weak self] in self?.setInfo(true) } }
    if cache { pageCache[asset.localIdentifier] = controller }
    return controller
  }
  func installPages() {
    suppress = true
    for page in pages { page.willMove(toParent: nil); page.view.removeFromSuperview(); page.removeFromParent() }
    let asset = session.current.asset
    pageAssets = [session.adjacent(to: asset,direction: -1) ?? asset,asset,session.adjacent(to: asset,direction: 1) ?? asset]
    pages = pageAssets.enumerated().map { slot,asset in makePage(asset,cache: slot == 1 || asset.localIdentifier != session.current.asset.localIdentifier) }
    for page in pages {
      addChild(page); pager.addSubview(page.view); page.didMove(toParent: self); page.selectionMark.alpha = selectionAlpha
      // A fit photo hands vertical movement to the viewer before its scroll
      // view can transfer that movement to the surrounding sheet. Zoom rejects
      // the viewer pan and disables paging, leaving the native scroll in charge.
      if let vertical = stage.gestureRecognizers?.first(where: { $0 is UIPanGestureRecognizer }) {
        page.scroll.panGestureRecognizer.require(toFail: vertical)
      }
      page.scroll.panGestureRecognizer.require(toFail: pager.panGestureRecognizer)
    }
    let keep = Set(pageAssets.map(\.localIdentifier))
    for id in Array(pageCache.keys) where !keep.contains(id) { pageCache.removeValue(forKey: id) }
    pager.isScrollEnabled = !session.zoomed && !flying && !closing; layoutMedia(); suppress = false
  }
  func currentChanged(_ model: MediaPreviewModel) {
    guard !closing, model === session.current else { return }
    if !catchingUp, pager.isDragging || pager.isDecelerating { pendingAsset = model.asset; return }
    if !openingTransition { setSourceHidden(true) }
    index = session.index(of: model.asset) ?? index
    if pageAssets.count != 3 || pageAssets[1].localIdentifier != model.asset.localIdentifier { installPages() }
    let changedVisibleIdentity = strip.indexPathsForVisibleItems.contains { path in
      (strip.cellForItem(at: path) as? PreviewStripCell)?.identity != session.asset(at: path.item)?.localIdentifier
    }
    if stripRevision != session.collectionRevision || stripCount != session.count || changedVisibleIdentity {
      stripRevision = session.collectionRevision; stripCount = session.count
      strip.reloadData()
    }
    for path in strip.indexPathsForVisibleItems {
      (strip.cellForItem(at: path) as? PreviewStripCell)?.setSelected(path.item == index)
    }
    stripLayout.current = index
    stripLayout.aspect = CGFloat(max(1,model.asset.pixelWidth))/CGFloat(max(1,model.asset.pixelHeight))
    stripLayout.neighborAspects = Dictionary(uniqueKeysWithValues:
      (max(0,index-1)...min(max(0,session.count-1),index+1)).compactMap { i in
        session.asset(at: i).map { (i,CGFloat(max(1,$0.pixelWidth))/CGFloat(max(1,$0.pixelHeight))) }
      })
    stripLayout.invalidateLayout(); strip.layoutIfNeeded()
    if !strip.isDragging && !strip.isDecelerating { centerStrip() }
    refreshBackupObservation(); observeMedia(); refreshInformation(); updateReviewSelection()
  }
  func reviewID(_ asset: PHAsset) -> String { asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier }
  func updateReviewSelection() {
    guard let review else { return }
    let selected = review.selected.contains(reviewID(session.current.asset))
    for (page,asset) in zip(pages,pageAssets) { page.reviewSelected = review.selected.contains(reviewID(asset)) }
    selectionButton.accessibilityLabel = NSLocalizedString(selected ? "library_deselect_item" : "library_select_item",comment: "")
    selectionButton.accessibilityTraits = selected ? [.button,.selected] : .button
  }
  func observeMedia() {
    mediaObservations.removeAll()
    session.current.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatus() }.store(in: &mediaObservations)
    updateStatus()
  }
  func updateStatus() {
    let model = session.current
    updateBackupControl()
    loadingIndicator.update(state: model.indicatorState, identity: model.asset.localIdentifier)
    previewFailure.view.isHidden = !model.failure || recordedPhoto != nil
    if model.failure || recordedPhoto != nil { loadingIndicator.isHidden = true }
    if !flying && !closing && verticalKind == 0 && infoAnimator?.isRunning != true { layoutMedia() }
  }
  func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { session.count }
  func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "preview.strip",for: path) as! PreviewStripCell
    cell.contentView.transform = .identity
    if let asset = session.asset(at: path.item) { cell.configure(asset, selected: path.item == index, pipeline: session.library.thumbnails) }
    return cell
  }
  func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) { (cell as? PreviewStripCell)?.cancel() }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
    guard !pager.isDragging && !pager.isDecelerating, let asset = session.asset(at: path.item) else { return }
    let step = path.item-index
    if abs(step) == 1 && !session.zoomed && !UIAccessibility.isReduceMotionEnabled {
      session.paging = true
      pager.setContentOffset(CGPoint(x: CGFloat(step+1)*pageStride,y: 0),animated: true)
    } else { session.activate(asset) }
  }
  func centerStrip() {
    guard !strip.isDragging && !strip.isDecelerating else { return }
    let offset = CGPoint(x: stripLayout.focusCenter-strip.bounds.width/2, y: 0)
    guard strip.contentOffset != offset else { return }
    suppress = true; strip.contentOffset = offset; suppress = false
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !suppress, !flying, !closing else { return }
    if scrollView === pager {
      session.paging = true
      if !strip.isDragging && !strip.isDecelerating {
        stripLayout.focus = CGFloat(index)+pager.contentOffset.x/max(1,pager.bounds.width)-1
        stripLayout.invalidateLayout(); strip.layoutIfNeeded(); centerStrip()
      }
    } else if scrollView === strip, strip.isDragging || strip.isDecelerating {
      let next = max(0,min(session.count-1,stripLayout.nearest(strip.contentOffset.x+strip.bounds.width/2)))
      if next != index, let asset = session.asset(at: next) {
        index = next; session.activate(asset)
      }
    }
  }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { settle(scrollView) } }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle(scrollView) }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { if scrollView === pager { settle(scrollView) } }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView === strip || scrollView === pager else { return }
    if scrollView === pager { catchDecelerating(); return }
    let oldCenter = stripLayout.center(index), oldOffset = strip.contentOffset.x
    stripLayout.focus = nil
    stripLayout.expansion = 0; stripLayout.invalidateLayout(); strip.layoutIfNeeded()
    suppress = true; strip.contentOffset.x = oldOffset+stripLayout.center(index)-oldCenter; suppress = false
  }
  /// A new swipe while the last one still glides adopts the page it was
  /// gliding to first, keeping the remaining offset, so swipes chain like
  /// the system viewer instead of hitting the edge of the three pages.
  private var catchingUp = false
  private func catchDecelerating() {
    guard pager.isDecelerating else { return }
    let width = max(1, pager.bounds.width)
    let shift = Int(round(pager.contentOffset.x / width)) - 1
    guard shift != 0, let asset = session.asset(at: index + shift) else { return }
    let residual = pager.contentOffset.x - CGFloat(1 + shift) * width
    UIView.performWithoutAnimation {
      session.activate(asset); pendingAsset = nil
      catchingUp = true; currentChanged(session.current); catchingUp = false
      suppress = true; pager.contentOffset.x = width + residual; suppress = false
    }
  }
  func settle(_ scrollView: UIScrollView) {
    stripLayout.focus = nil
    if scrollView === pager {
      let shift = Int(round(pager.contentOffset.x/max(1,pager.bounds.width)))-1
      // Adopt the settled neighbouring controller and offset in the same update.
      // Resetting the old centre before asynchronous model delivery flashes it.
      UIView.performWithoutAnimation {
        if shift != 0, let asset = session.asset(at: index+shift) {
          session.activate(asset); pendingAsset = nil; currentChanged(session.current)
        }
        suppress = true; pager.contentOffset.x = pager.bounds.width; suppress = false
      }
      session.paging = false
      if let pendingAsset { self.pendingAsset = nil; currentChanged(session.model(for: pendingAsset)) }
    }
    guard !strip.isTracking else { return }
    stripLayout.current = index
    let changes = {
      self.stripLayout.expansion = 1; self.stripLayout.invalidateLayout(); self.strip.layoutIfNeeded(); self.centerStrip()
    }
    if UIAccessibility.isReduceMotionEnabled { changes() }
    else { UIView.animate(withDuration: 0.25,delay: 0,options: [.beginFromCurrentState,.curveEaseOut],animations: changes) }
  }
  func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    guard !flying, !closing, !session.zoomed, !pager.isDragging, !pager.isDecelerating else { return false }
    if let pan = recognizer as? UIPanGestureRecognizer {
      let velocity = pan.velocity(in: view)
      if recognizer.view === information {
        guard velocity.y > 0 else { return false }
        let location = recognizer.location(in: information)
        var node = information.hitTest(location, with: nil)
        while let child = node, child !== information {
          if let scroll = child as? UIScrollView, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 1 { return false }
          node = child.superview
        }
      }
      return (review == nil || velocity.y > 0) && abs(velocity.y) > abs(velocity.x)*1.35
    }
    return true
  }
  func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var node = touch.view
    while let view = node { if view is UIControl { return false }; node = view.superview }
    return recognizer.view === information || touch.location(in: stage).y < stage.bounds.height*0.84
  }
  @objc func vertical(_ gesture: UIPanGestureRecognizer) {
    let point = gesture.translation(in: view), velocity = gesture.velocity(in: view)
    switch gesture.state {
    case .began:
      animator?.stopAnimation(true); interruptInformation()
      startInfo = infoHeight; verticalKind = infoHeight > 0 || velocity.y < 0 ? 2 : 1
      // A drag while a presentation is still settling cannot dismiss; it is
      // ignored rather than leaving the viewer waiting for a dismissal.
      if verticalKind == 1, usesTransition, navigationController?.transitionCoordinator != nil
        || presentingViewController?.transitionCoordinator != nil || presentedViewController != nil {
        verticalKind = 0; return
      }
      if verticalKind == 1, usesTransition, let transition = mediaTransition {
        // The drag drives the dismissal transition itself; the grid shows
        // through it in proportion to the drag.
        prepareReturnChrome()
        closing = true; pager.isScrollEnabled = false; selectionAlpha = 0
        let frame = imageRect()
        transition.beginInteractive(origin: gesture.location(in: view), center: CGPoint(x: frame.midX, y: frame.midY))
        closeThroughNavigationOwner()
        verticalKind = 3
      } else if verticalKind == 1 {
        _ = returnFrame()
        setSourceHidden(true)
        unclipMedia(); pages[1].flightLocked = true
        dragOrigin = gesture.location(in: view)
        let frame = imageRect(); dragCenter = CGPoint(x: frame.midX,y: frame.midY)
      }
    case .changed:
      if verticalKind == 3 {
        mediaTransition?.updateInteractive(point)
      } else if verticalKind == 1 {
        mediaSurface()?.transform = MediaFlightGeometry.drag(origin: dragOrigin,center: dragCenter,translation: point)
        let chromeAlpha = chrome ? max(0,1-point.y/100) : 0
        backdrop.alpha = max(0,1-max(0,point.y)/320); header?.alpha = chromeAlpha; footer.alpha = chromeAlpha; navigationController?.toolbar.alpha = chromeAlpha; selectionAlpha = chromeAlpha; loadingIndicator.alpha = chromeAlpha
      } else { if !chrome { setChrome(true, animated: false) }; ensureInformation(); infoHeight = max(0,min(view.bounds.height*0.7,startInfo-point.y)); layoutMedia() }
    case .ended, .cancelled, .failed:
      if verticalKind == 3 {
        let commit = gesture.state == .ended && (point.y > 12 && velocity.y > -120)
        let running = mediaTransition?.endInteractive(commit: commit, velocity: velocity.y) ?? false
        // The dismissal never started: the viewer stays open and interactive.
        if !running { transitionDidCancelClose() }
      } else if verticalKind == 1 {
        if gesture.state == .ended && (point.y > 12 && velocity.y > -120) { dismissViewer(velocity: velocity.y) }
        else { animate(changes: { self.mediaSurface()?.transform = .identity; self.backdrop.alpha = 1; self.layoutMedia() }) { self.pages[1].flightLocked = false; self.restoreMediaClipping() } }
      } else {
        setInfo(gesture.state == .ended ? infoHeight-velocity.y*0.12 > informationOpenHeight*0.35 : startInfo > 0)
      }
      verticalKind = 0
    default: break
    }
  }
  @objc func dragInformation(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began: interruptInformation(); startInfo = infoHeight
    case .changed: infoHeight = max(0,min(view.bounds.height*0.7,startInfo-gesture.translation(in: view).y)); layoutMedia()
    case .ended, .cancelled, .failed: setInfo(gesture.state == .ended ? infoHeight-gesture.velocity(in: view).y*0.12 > informationOpenHeight*0.35 : startInfo > 0)
    default: break
    }
  }
  var informationOpenHeight: CGFloat {
    // Keep a substantial upper image region even for wide photos. Filling this
    // region produces the information crop rather than shrinking the photo.
    view.bounds.height * 0.54
  }
  func ensureInformation() {
    guard review == nil, informationHost == nil else { return }
    let host = UIHostingController(rootView: informationContent)
    host.safeAreaRegions = []
    addChild(host); information.addSubview(host.view); host.view.backgroundColor = .clear; host.didMove(toParent: self); informationHost = host
  }
  private var informationRevision = 0
  func refreshInformation() {
    informationRevision &+= 1
    informationHost?.rootView = informationContent
  }
  private var informationContent: AnyView {
    if let photo = recordedPhoto {
      return AnyView(ScrollView {
        PhotoInformationLayout(takenAt: photo.takenAt, job: observedJob ?? photo.job,
          receiverName: photo.job.flatMap { backupModel.receiverDeviceName(for: $0) } ?? backupModel.peerDevice?.name ?? "Pixel",
          needsYou: photo.mark == .needsYou, filename: photo.job?.asset.resources.first?.filename ?? "",
          fields: PhotoInformationLayout.fileFields(for: photo.job), model: backupModel,
          awaitingReceipt: awaitingBackupReceipt, allowsRetry: false, showHistory: observedJob == nil ? nil : { [weak self] in self?.showBackupHistory() },
          actionKey: backupActionKey, actionBusy: retryingBackup || backupAction.busy,
          performAction: { [weak self] in self?.requestBackup() }, actionFailure: backupFeedbackError)
          .padding(.horizontal, DuckSpacing.medium).padding(.top, DuckSpacing.medium).padding(.bottom, DuckSpacing.large)
      })
    }
    return AnyView(ScrollView {
      PhotoMetadataPanel(preview: session.current, revision: informationRevision, backupInfo: { [weak self] fields in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(PhotoInformationLayout(takenAt: self.session.current.asset.creationDate, job: self.observedJob,
          receiverName: self.observedJob.flatMap { self.backupModel.receiverDeviceName(for: $0) } ?? self.backupModel.peerDevice?.name ?? "Pixel",
          needsYou: self.observedTileState == "needs_you", filename: self.session.current.filename,
          fields: fields, model: self.backupModel, loaded: self.backupFactsLoaded,
          unavailable: self.backupFactsUnavailable, unpaired: self.backupModel.pairing == nil,
          preparing: self.observedTileState == "sending" || (self.backupSource == self.session.current.asset.localIdentifier && self.backupReceiver == self.currentBackupReceiver && self.backupAction.added),
          awaitingReceipt: self.awaitingBackupReceipt, allowsRetry: false, showHistory: self.observedJob == nil ? nil : { [weak self] in self?.showBackupHistory() },
          actionKey: self.backupActionKey, actionBusy: self.retryingBackup || self.backupAction.busy,
          performAction: { [weak self] in self?.requestBackup() }, actionFailure: self.backupFeedbackError))
      }).padding(.horizontal, DuckSpacing.medium).padding(.top, DuckSpacing.medium).padding(.bottom, DuckSpacing.large)
    })
  }
  func setInfo(_ open: Bool) {
    guard review == nil, !flying && !closing else { return }
    interruptInformation()
    if open && !chrome { setChrome(true, animated: false) }
    session.fitMedia(); if open { ensureInformation() }
    let target: CGFloat = open ? informationOpenHeight : 0
    infoHeight = target
    let finish: () -> Void = { [weak self] in
      guard let self, self.infoHeight == 0 else { return }
      self.informationHost?.willMove(toParent: nil); self.informationHost?.view.removeFromSuperview()
      self.informationHost?.removeFromParent(); self.informationHost = nil
      if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .layoutChanged, argument: self.titleButton) }
    }
    if UIAccessibility.isReduceMotionEnabled { layoutMedia(); setNeedsStatusBarAppearanceUpdate(); finish() } else {
      // The reference travels for about half a second, with a longer return.
      let animation = UIViewPropertyAnimator(duration: open ? 0.52 : 0.6,dampingRatio: 1) { self.layoutMedia(); self.setNeedsStatusBarAppearanceUpdate() }
      animation.addCompletion { position in if position == .end { finish() } }
      infoAnimator = animation; animation.startAnimation()
    }
  }
  /// Freeze the visible geometry before reversing a drawer animation. The model
  /// height is already the destination while Core Animation is interpolating.
  func interruptInformation() {
    guard let infoAnimator else { return }
    let visibleHeight = information.layer.presentation().map { view.bounds.maxY - $0.frame.minY } ?? infoHeight
    infoAnimator.stopAnimation(true); self.infoAnimator = nil
    infoHeight = visibleHeight
    UIView.performWithoutAnimation { layoutMedia() }
  }
  func toggleChrome() {
    guard !flying && !closing else { return }
    // With the information open, a tap on the photo only closes it; the
    // immersive view is reached from the photo alone.
    if infoHeight > 0 { setInfo(false); return }
    setChrome(!chrome)
  }
  func setChrome(_ visible: Bool, animated: Bool = true) {
    chrome = visible
    // Floating UIKit toolbar groups are hosted outside the toolbar view.
    // Hide the system bar itself; alpha on its host leaves its glass visible.
    toolbarItems?.forEach { $0.isHidden = !visible }
    navigationItem.setHidesBackButton(!visible, animated: false)
    navigationItem.rightBarButtonItem?.isHidden = !visible
    titleContainer.isHidden = !visible
    navigationController?.setToolbarHidden(!visible, animated: false)
    let changes = {
      self.backdrop.backgroundColor = visible ? .systemBackground : .init(DuckViewerSurface.immersive)
      // The explanation stays legible on the immersive surface.
      self.unavailableHost?.overrideUserInterfaceStyle = visible ? .unspecified : .dark
      self.layoutMedia(); self.setNeedsStatusBarAppearanceUpdate()
    }
    guard animated else { changes(); return }
    if UIAccessibility.isReduceMotionEnabled {
      UIView.transition(with: navigationController?.view ?? view, duration: DuckMotion.enter, options: [.transitionCrossDissolve, .beginFromCurrentState], animations: changes)
    } else {
      // Fade the system bars in place; native hide/show slides and changes the
      // safe area, which would move the fitted photo during immersion.
      UIView.animate(withDuration: visible ? 0.2 : 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: changes)
    }
  }
  private func configureToolbar() {
    shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), primaryAction: UIAction { [weak self] _ in
      guard let self else { return }
      LibraryPhotoActions.shareAsset(self.session.current.asset, from: self, anchor: self.shareItem)
    })
    shareItem.accessibilityIdentifier = "library.preview.share"
    shareItem.accessibilityLabel = NSLocalizedString("library_context_share", comment: "")
    infoButton.accessibilityIdentifier = "library.preview.info"
    infoButton.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if self.backupFactsUnavailable { self.refreshBackupObservation(force: true) }
      self.setInfo(self.infoHeight == 0)
    }, for: .touchUpInside)
    infoButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([infoButton.widthAnchor.constraint(equalToConstant: 48), infoButton.heightAnchor.constraint(equalToConstant: 48)])
    infoItem = UIBarButtonItem(customView: infoButton)
    if #available(iOS 26.0, *) {
      // UIKit draws the Share group and the Info button's system glass.
      shareItem.sharesBackground = false; infoItem.hidesSharedBackground = true
    }
    if let review { toolbarItems = [.flexibleSpace(), review.makePreviewBackupItem(), .flexibleSpace()] }
    else { toolbarItems = [shareItem!, .flexibleSpace(), infoItem!] }
    navigationController?.setToolbarHidden(false, animated: false)
    let toolbarAppearance = UIToolbarAppearance()
    toolbarAppearance.configureWithTransparentBackground()
    navigationController?.toolbar.standardAppearance = toolbarAppearance
    navigationController?.toolbar.scrollEdgeAppearance = toolbarAppearance
    updateMoreMenu(actionKey: nil)
    refreshBackupObservation()
  }
  /// This is a presentation snapshot; all registration and retry stay in the core.
  private func refreshBackupObservation(force: Bool = false) {
    let asset = session.current.asset
    let receiver = currentBackupReceiver
    let revision = PhotoLibraryModel.revision(asset)
    // Receipt and saving into the Pixel's Photos are observations of their
    // own; either one changes this photo's facts without a queue change.
    let observed = "\(backupModel.queueRevision)|\(backupModel.pendingImports)|\(backupModel.summary.received)|\(backupModel.summary.published)"
    let stateRevision = observed
    let key = "\(asset.localIdentifier)|\(revision)|\(receiver ?? "")|\(observed)"
    guard force || key != backupFactsKey else { return }
    let sameSource = backupFactsKey.hasPrefix("\(asset.localIdentifier)|\(revision)|\(receiver ?? "")|")
    backupFactsKey = key; backupFactsTask?.cancel()
    if force { session.library.tileStates.observations = nil }
    if !sameSource {
      observedJob = recordedPhoto?.job
      observedTileState = recordedPhoto.flatMap { photo in
        guard photo.job == nil else { return nil }
        return photo.mark == .needsYou ? "needs_you" : "sending"
      }
      backupFactsLoaded = recordedPhoto != nil; backupFactsUnavailable = false
      retryRegistered = false
    }
    guard let receiver else { backupFactsLoaded = true; updateBackupControl(); return }
    backupFactsTask = Task { [weak self] in
      do {
        let data = try await Bridge.call(["op": "source_job", "receiver_id": receiver, "source_id": asset.localIdentifier])
        let job = try JSONDecoder().decode(BackupJob?.self, from: data)
        guard let self else { return }
        let group = LibraryGroup(sources: [LibrarySource(id: asset.localIdentifier, revision: revision)], complete: true)
        guard let states = await librarySourceStates([asset.localIdentifier: group], receiver: receiver,
          cache: self.session.library.tileStates, revision: stateRevision) else {
          throw Bridge.Failure(code: "internal")
        }
        guard !Task.isCancelled, self.backupFactsKey == key else { return }
        self.observedJob = job.flatMap { job in
          job.asset.source_id == asset.localIdentifier && (self.recordedPhoto != nil || job.asset.revision == revision) ? job : nil
        } ?? self.recordedPhoto?.job
        self.observedTileState = states[asset.localIdentifier] ?? (self.recordedPhoto?.job == nil ? self.observedTileState : nil)
        // A newly registered preparation can supersede an earlier received job.
        if self.observedTileState == "sending", self.observedJob?.state == "received" { self.observedJob = nil }
        self.backupFactsLoaded = true; self.backupFactsUnavailable = false
        self.retryRegistered = false
        self.updateBackupControl(); self.refreshInformation()
      } catch {
        guard !Task.isCancelled, let self, self.backupFactsKey == key else { return }
        self.backupFactsLoaded = true; self.backupFactsUnavailable = self.recordedPhoto == nil
        self.updateBackupControl(); self.refreshInformation()
      }
    }
  }
  private func showBackupHistory() {
    guard observedJob != nil else { return }
    let history = IOSHistoryNavigationController(model: backupModel, focus: observedJob.map(HistoryPhoto.init), sheet: true) { [weak self] in
      self?.dismiss(animated: true)
    }
    present(history, animated: true)
  }
  private var canRequestBackup: Bool {
    recordedPhoto == nil && backupModel.pairing != nil && backupFactsLoaded && !backupFactsUnavailable
  }
  private func requestBackup() {
    guard !backupAction.busy, !retryingBackup else { return }
    let source = session.current.asset.localIdentifier
    if let job = observedJob, job.state == "failed" || job.processing == "failed" {
      retryingBackup = true; retryError = nil; retrySource = source; retryReceiver = currentBackupReceiver; updateBackupControl()
      Task {
        let succeeded: Bool
        if let retryRequest { succeeded = await retryRequest(job) }
        else { succeeded = await backupModel.retry(job.id) }
        retryingBackup = false
        retryRegistered = succeeded
        if !succeeded { retryError = backupModel.message ?? NSLocalizedString("apple_selected_backup_failed", comment: "") }
        refreshBackupObservation(force: true); updateBackupControl()
      }
      return
    }
    if backupModel.pairing == nil, recordedPhoto == nil {
      present(UIHostingController(rootView: IOSConnectSheet(model: backupModel)), animated: true)
      return
    }
    guard canRequestBackup else { return }
    backupSource = source; backupReceiver = currentBackupReceiver; retryError = nil
    Task {
      if let backupRequest { await backupRequest() }
      else { await backupAction.request(library: session.library, model: backupModel, sources: [source]) }
      refreshBackupObservation(); updateBackupControl()
    }
  }
  private var backupFeedbackError: String? {
    let source = session.current.asset.localIdentifier
    return (backupSource == source && backupReceiver == currentBackupReceiver ? backupAction.error : nil)
      ?? (retrySource == source && retryReceiver == currentBackupReceiver ? retryError : nil)
  }
  private var awaitingBackupReceipt: Bool {
    observedJob.map { job in
      // Native request completion checkpoints acknowledged bytes and requeues
      // the job before its commit/receipt request is claimed. Queue scheduling
      // does not restart media transfer or erase this whole-job observation.
      guard ["queued", "running"].contains(job.state) else { return false }
      if job.totalBytes > 0, job.confirmedBytes >= job.totalBytes { return true }
      guard let live = backupModel.transferProgress[job.id], !live.waitingForNetwork else { return false }
      if live.phase == "commit" { return true }
      return ["bundle", "upload"].contains(live.phase) && live.expected > 0 && live.sent >= live.expected
        && job.totalBytes > 0 && live.displayedBytes(confirmed: job.confirmedBytes, total: job.totalBytes) == job.totalBytes
    } ?? false
  }
  private func updateBackupControl() {
    guard infoItem != nil else { return }
    let source = session.current.asset.localIdentifier
    let ownsFeedback = backupSource == source && backupReceiver == currentBackupReceiver
    let ownsRetry = retrySource == source && retryReceiver == currentBackupReceiver
    let submitted = (ownsFeedback && backupAction.added) || (ownsRetry && retryRegistered)
    let failed = observedJob?.state == "failed" || observedJob?.processing == "failed" || observedTileState == "needs_you"
    let liveProgress = observedJob.flatMap { backupModel.transferProgress[$0.id] }
    let awaitingReceipt = awaitingBackupReceipt
    let sendingState: String = {
      if awaitingReceipt { return "photo_viewer_confirming_receipt" }
      switch observedJob?.state {
      case "queued": return "state_queued"
      case "waiting": return "state_waiting"
      case "paused": return "state_paused"
      default: return "photo_viewer_backing_up"
      }
    }()
    let stateKey: String
    var actionKey: String?
    if (ownsFeedback && backupAction.busy) || (ownsRetry && (retryingBackup || retryRegistered)) || (submitted && observedJob == nil && observedTileState == nil) {
      stateKey = "photo_viewer_backing_up"
    } else if !backupFactsLoaded {
      stateKey = "photo_viewer_loading"
    } else if backupFactsUnavailable {
      stateKey = "records_load_failed"
    } else if failed || backupFeedbackError != nil {
      stateKey = "photo_viewer_failed"
      if failed && (observedJob != nil || canRequestBackup) || backupFeedbackError != nil { actionKey = "retry_task" }
    } else if observedTileState == "sending" {
      stateKey = sendingState
    } else if observedTileState == "saved" {
      stateKey = "photo_viewer_saved"
    } else if observedJob?.state == "received" {
      switch observedJob?.processing {
      case "complete": stateKey = "photo_viewer_saved"
      case "pending": stateKey = "records_fact_saving"
      default: stateKey = "photo_viewer_confirming_photos"
      }
    } else if observedTileState == "saving" {
      stateKey = "records_fact_saving"
    } else if observedJob != nil {
      stateKey = sendingState
    } else {
      stateKey = "photo_viewer_not_backed_up"
      if canRequestBackup { actionKey = "library_context_backup" }
    }
    updateTitle()
    updateMoreMenu(actionKey: actionKey)
    backupActionKey = actionKey
    // Progress follows the same live transfer bytes as the task list, falling
    // back to the bytes the core has acknowledged.
    let progress: Double? = observedJob.flatMap { job in
      guard stateKey == "photo_viewer_backing_up", job.state == "running", job.totalBytes > 0 else { return nil }
      if let live = liveProgress?.activeFraction(confirmed: job.confirmedBytes, total: job.totalBytes) {
        return live
      }
      guard job.confirmedBytes > 0, job.confirmedBytes < job.totalBytes else { return nil }
      return Double(job.confirmedBytes) / Double(job.totalBytes)
    }
    infoButton.setState(stateKey, progress: progress)
    shareItem.isEnabled = recordedPhoto == nil
    refreshInformation()
    feedback.text = backupFeedbackError
    feedback.isHidden = feedback.text == nil
    if feedback.superview == nil { feedback.font = .preferredFont(forTextStyle: .footnote); feedback.textColor = .secondaryLabel; feedback.numberOfLines = 0; feedback.textAlignment = .center; feedback.adjustsFontForContentSizeCategory = true; footer.addSubview(feedback) }
    let height = feedback.sizeThatFits(CGSize(width: max(1,view.bounds.width-32),height: .greatestFiniteMagnitude)).height
    feedback.frame = CGRect(x: 16,y: -height-8,width: view.bounds.width-32,height: height)
    if backupAction.confirmingRepeat, presentedViewController == nil {
      let alert = UIAlertController(title: NSLocalizedString("selection_backup_repeat_title", comment: ""), message: NSLocalizedString("selection_backup_repeat_note", comment: ""), preferredStyle: .actionSheet)
      alert.addAction(UIAlertAction(title: NSLocalizedString("selection_backup_repeat_action", comment: ""), style: .default) { [weak self] _ in
        guard let self else { return }; Task { await self.backupAction.confirm(library: self.session.library, model: self.backupModel) }
      })
      alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel) { [weak self] _ in self?.backupAction.cancel() })
      alert.popoverPresentationController?.barButtonItem = infoItem
      present(alert, animated: true)
    }
  }
  private func updateMoreMenu(actionKey: String?) {
    guard review == nil else { navigationItem.rightBarButtonItems = nil; return }
    var actions: [UIAction] = []
    if observedJob != nil {
      actions.append(UIAction(title: NSLocalizedString("library_context_history", comment: ""),
        image: UIImage(systemName: "clock.arrow.circlepath")) { [weak self] _ in self?.showBackupHistory() })
    }
    if let actionKey {
      actions.append(UIAction(title: NSLocalizedString(actionKey, comment: ""),
        image: UIImage(systemName: actionKey == "retry_task" ? "arrow.clockwise" : "arrow.up"),
        attributes: backupAction.busy || retryingBackup ? .disabled : []) { [weak self] _ in self?.requestBackup() })
    }
    moreActions = actions
    // The item and its menu are made once and build their actions when they
    // open; replacing a presented menu would dismiss it.
    if moreItem == nil {
      let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
        UIDeferredMenuElement.uncached { [weak self] done in done(self?.moreActions ?? []) }]))
      more.accessibilityLabel = NSLocalizedString("photo_viewer_more", comment: "")
      more.accessibilityIdentifier = "library.preview.more"
      if #available(iOS 26.0, *) { more.identifier = "library.preview.more" }
      moreItem = more
    }
    moreItem?.isHidden = !chrome
    if navigationItem.rightBarButtonItem !== moreItem { navigationItem.rightBarButtonItem = moreItem }
  }
  private var moreItem: UIBarButtonItem?
  private var moreActions: [UIMenuElement] = []
  private func viewerTitleFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }
  private func updateTitle() {
    let takenAt = recordedPhoto?.takenAt ?? session.current.asset.creationDate
    let dateText: String
    if let takenAt {
      let calendar = Calendar.current
      let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: takenAt),
        to: calendar.startOfDay(for: Date())).day ?? -1
      dateText = (0..<7).contains(days) ? takenAt.formatted(.dateTime.weekday(.wide))
        : takenAt.formatted(date: .long, time: .omitted)
    } else { dateText = NSLocalizedString("design_capture_unknown", comment: "") }
    let timeText = takenAt?.formatted(date: .omitted, time: .shortened) ?? "—"
    titleButton.configuration?.attributedTitle = AttributedString(dateText, attributes: AttributeContainer([
      .font: viewerTitleFont(.subheadline, weight: .semibold), .foregroundColor: UIColor.label]))
    titleButton.configuration?.attributedSubtitle = AttributedString(timeText, attributes: AttributeContainer([
      .font: viewerTitleFont(.caption2, weight: .medium), .foregroundColor: UIColor.label]))
    titleButton.titleLabel?.numberOfLines = 1; titleButton.subtitleLabel?.numberOfLines = 1
    titleButton.frame = titleContainer.bounds
    titleButton.accessibilityLabel = takenAt?.formatted(date: .long, time: .shortened) ?? dateText
    titleButton.isEnabled = review == nil
  }
  private let feedback = UILabel()
  func animate(duration: TimeInterval = 0.36, velocity: CGFloat = 0, changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
    animator?.stopAnimation(true)
    if UIAccessibility.isReduceMotionEnabled { changes(); completion?(); return }
    let timing = UISpringTimingParameters(dampingRatio: 0.94,initialVelocity: CGVector(dx: 0,dy: min(4,abs(velocity)/800)))
    let animation = UIViewPropertyAnimator(duration: duration,timingParameters: timing)
    animation.addAnimations(changes); animation.addCompletion { _ in completion?() }; animator = animation; animation.startAnimation()
  }
  func unclipMedia() {
    guard mediaClipping.isEmpty else { return }
    var node = mediaSurface()?.superview
    while let ancestor = node, ancestor !== view {
      mediaClipping.append((ancestor,ancestor.clipsToBounds)); ancestor.clipsToBounds = false; node = ancestor.superview
    }
  }
  func restoreMediaClipping() {
    for (node,clipped) in mediaClipping { node.clipsToBounds = clipped }
    mediaClipping.removeAll()
  }
  func mediaSurface() -> UIView? { pages.count == 3 ? pages[1].surface : nil }
  func imageRect() -> CGRect {
    pages.forEach { $0.view.layoutIfNeeded() }
    if let surface = mediaSurface(), surface.bounds.width > 0 { return surface.convert(surface.bounds,to: view) }
    let asset = session.current.asset; let size = CGSize(width: max(1,asset.pixelWidth),height: max(1,asset.pixelHeight))
    let scale = min(stage.bounds.width/size.width,stage.bounds.height/size.height)
    let frame = CGRect(x: stage.bounds.midX-size.width*scale/2,y: stage.bounds.midY-size.height*scale/2,width: size.width*scale,height: size.height*scale)
    return stage.convert(frame,to: view)
  }
  /// Waits at most five frames for the local full-aspect rendition, so the
  /// flight's widening crop does not reveal empty sides beside a centre-cropped
  /// grid thumbnail.
  func enter(waited: Int = 0) {
    if waited < 5, pages.count == 3, pages[1].isViewLoaded, !pages[1].scroll.showsFullAspect,
      session.current.asset.mediaType != .video
    {
      pages[1].refresh()
      if !pages[1].scroll.showsFullAspect {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
          guard let self, self.flying, !self.closing else { return }
          self.enter(waited: waited + 1)
        }
        return
      }
    }
    setSourceHidden(true)
    layoutMedia()
    guard let surface = mediaSurface(), surface.bounds.width > 0 else {
      flying = false; stage.alpha = 1; backdrop.alpha = 1; pager.isScrollEnabled = !session.zoomed; layoutMedia(); return
    }
    unclipMedia(); pages[1].flightLocked = true
    let base = surface.convert(surface.bounds,to: view)
    let flight = MediaFlightGeometry(bounds: surface.bounds, fitted: base, thumbnail: view.convert(item.frame,from: nil))
    let clip = UIView(frame: flight.crop); clip.backgroundColor = DuckMedia.backgroundUIColor; surface.mask = clip
    UIView.performWithoutAnimation { surface.transform = flight.transform; self.stage.alpha = 1 }
    // Commit the small pose before UIKit starts interpolating. Revealing a
    // newly attached page at its fitted pose for one frame creates a flash.
    CATransaction.flush()
    DispatchQueue.main.async { [weak self, weak surface, weak clip] in
      guard let self, let surface, let clip, self.flying, !self.closing else { return }
      self.animate(changes: {
        surface.transform = .identity; clip.frame = surface.bounds; self.backdrop.alpha = 1
      }) { [weak self] in
        guard let self else { return }
        surface.mask = nil; self.pages[1].flightLocked = false; self.restoreMediaClipping()
        self.flying = false; self.pager.isScrollEnabled = !self.session.zoomed; self.updateStatus()
      }
    }
  }
  func setSourceHidden(_ hidden: Bool) {
    if let review { review.setPreviewHidden(hidden ? reviewID(session.current.asset) : nil) }
    else { session.library.previewVisibility?(hidden ? session.current.asset.localIdentifier : nil) }
  }
  func releasePreviewSource() {
    setSourceHidden(false)
    session.stop(); backupFactsTask?.cancel()
  }
  func returnFrame() -> CGRect? {
    if let review { return review.previewFrame(reviewID(session.current.asset)) }
    return session.library.previewFrame?(session.current.asset.localIdentifier)
  }
  /// The presentation transition has landed the photo on its fitted frame.
  func transitionDidOpen() {
    pager.isScrollEnabled = !session.zoomed; updateStatus()
    // As in the system library, the grid behind the viewer scrolls the photo
    // fully into view now, so the way back always has a definite target.
    UIView.performWithoutAnimation { _ = returnFrame() }
  }
  /// A cancelled drag-to-dismiss returned the viewer to its open state.
  func transitionDidCancelClose() {
    closing = false; selectionAlpha = chrome && infoHeight == 0 ? 1 : 0
    pager.isScrollEnabled = !session.zoomed
    finishReturnChrome(cancelled: true)
    navigationController?.setToolbarHidden(!chrome, animated: false)
    layoutMedia()
  }
  /// The dismissal transition has returned the photo to its tile.
  func transitionDidClose() {
    guard !finished else { return }; finished = true
    finishReturnChrome(cancelled: false)
    releasePreviewSource()
    if completeReview, let review { review.done() } else { closeViewer() }
  }
  func finishClosing() {
    guard !finished else { return }; finished = true
    // Restore the tile and remove the flight in the same nonanimated commit.
    UIView.performWithoutAnimation {
      self.releasePreviewSource()
      self.stage.alpha = 0
      self.completeClosing()
    }
  }
  private func completeClosing() {
    if completeReview, let review {
      review.dismiss(animated: false) { [weak review] in review?.done() }
    } else { closeViewer() }
  }
  private func closeThroughNavigationOwner() {
    presentingViewController?.dismiss(animated: true)
  }
  func dismissViewer(velocity: CGFloat = 0) {
    guard !flying && !closing else { return }
    if usesTransition { prepareReturnChrome() }
    closing = true; pager.isScrollEnabled = false
    if usesTransition {
      selectionAlpha = 0; closingVelocity = velocity
      closeThroughNavigationOwner()
      // A dismissal UIKit declined (another transition was running) leaves
      // the viewer open and usable instead of waiting for it.
      if navigationController?.transitionCoordinator == nil, presentingViewController != nil { transitionDidCancelClose() }
      return
    }
    let destination = returnFrame()
    setSourceHidden(true)
    selectionAlpha = 0
    if let surface = mediaSurface(), let destination, infoHeight == 0 {
      unclipMedia(); pages[1].flightLocked = true
      let held = surface.transform
      surface.transform = .identity
      let base = surface.convert(surface.bounds,to: view), size = surface.bounds.size
      surface.transform = held
      let target = view.convert(destination,from: nil)
      let flight = MediaFlightGeometry(bounds: CGRect(origin: .zero,size: size),fitted: base,thumbnail: target)
      let clip = UIView(frame: surface.bounds); clip.backgroundColor = DuckMedia.backgroundUIColor; surface.mask = clip
      for page in pages where page !== pages[1] { page.view.alpha = 0 }
      // Preserve UIKit controller ownership and live playback. Only transform
      // and crop the existing media node; no player view changes parent.
      animate(velocity: velocity,changes: {
        surface.transform = flight.transform; clip.frame = flight.crop
        self.backdrop.alpha = 0; self.header?.alpha = 0; self.footer.alpha = 0; self.navigationController?.toolbar.alpha = 0; self.loadingIndicator.alpha = 0
      }) { self.finishClosing() }
    } else { animate(duration: 0.2,changes: { self.view.alpha = 0 }) { self.finishClosing() } }
  }
}
@MainActor private final class PreviewStripCell: UICollectionViewCell {
  let photo = UIImageView()
  weak var pipeline: ThumbnailPipeline?
  var request = PHInvalidImageRequestID, identity: String?
  override init(frame: CGRect) {
    super.init(frame: frame); photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.layer.cornerRadius = 5; contentView.addSubview(photo)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSubviews() { super.layoutSubviews(); photo.frame = contentView.bounds }
  func configure(_ asset: PHAsset, selected: Bool, pipeline: ThumbnailPipeline) {
    setSelected(selected)
    accessibilityLabel = asset.creationDate?.formatted(date: .abbreviated,time: .shortened); accessibilityTraits = selected ? [.button,.selected] : .button
    if identity != asset.localIdentifier {
      cancel(); identity = asset.localIdentifier
      photo.image = pipeline.poster(for: asset)
    }
    self.pipeline = pipeline
    guard request == PHInvalidImageRequestID else { return }
    request = pipeline.request(asset,pixels: 120) { [weak self] image,_ in guard let self, self.identity == asset.localIdentifier else { return }; if let image { self.photo.image = image } }
  }
  func setSelected(_ selected: Bool) { photo.layer.borderWidth = 0; accessibilityTraits = selected ? [.button,.selected] : .button }
  func cancel() { pipeline?.cancel(request); request = PHInvalidImageRequestID }
  override func prepareForReuse() { super.prepareForReuse(); cancel(); identity = nil; photo.image = nil }
}

/// Stable UIKit ownership keeps asynchronous posters, Live Photos and video
/// readiness from replacing the node that is currently flying to/from the grid.
@MainActor final class NativeMediaPage: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
  let model: MediaPreviewModel
  let session: MediaPreviewSession
  let scroll = MediaZoomScroll()
  lazy var video = AVPlayerViewController()
  var zoomChanged: (Bool) -> Void = { _ in }
  var tapped: () -> Void = {}
  var information: (() -> Void)?
  private var observations = Set<AnyCancellable>()
  private var readiness: NSKeyValueObservation?
  private var attachedPlayer: AVPlayer?
  private var allowVideo = false
  var videoReady = false
  var surface: UIView { scroll.media }
  /// A reviewed selection's mark belongs to its photo and pages with it; the
  /// viewer's toggle above the current page takes the taps.
  let selectionMark = UIImageView()
  var reviewSelected: Bool? { didSet { updateSelectionMark() } }
  var flightLocked = false {
    didSet {
      scroll.flightLocked = flightLocked
      if !flightLocked { refresh(); scroll.setNeedsLayout() }
      else { updateVideoVisibility() }
    }
  }
  init(model: MediaPreviewModel, session: MediaPreviewSession) {
    self.model = model; self.session = session; super.init(nibName: nil,bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func loadView() {
    view = UIView(); view.backgroundColor = .clear
    scroll.delegate = self; scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = model.asset.mediaType == .video ? 1 : 5
    scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.mediaSize = CGSize(width: max(1,model.asset.pixelWidth),height: max(1,model.asset.pixelHeight))
    scroll.photo.isAccessibilityElement = true
    scroll.photo.accessibilityIdentifier = "library.preview.photo"
    scroll.photo.accessibilityValue = model.asset.localIdentifier; scroll.photo.accessibilityTraits = .image
    view.addSubview(scroll)
    selectionMark.isUserInteractionEnabled = false; selectionMark.alpha = 0
    view.addSubview(selectionMark); updateSelectionMark()
    let double = UITapGestureRecognizer(target: self,action: #selector(doubleTap(_:))); double.numberOfTapsRequired = 2
    let single = UITapGestureRecognizer(target: self,action: #selector(singleTap(_:))); single.delegate = self
    if model.asset.mediaType != .video { single.require(toFail: double) }
    single.cancelsTouchesInView = false
    scroll.addGestureRecognizer(single)
    if model.asset.mediaType != .video { scroll.addGestureRecognizer(double) }
    if information != nil {
      scroll.photo.accessibilityCustomActions = [UIAccessibilityCustomAction(name: NSLocalizedString("apple_photo_detail",comment: ""),target: self,selector: #selector(showInformation))]
    }
    if model.asset.mediaType == .video {
      addChild(video); video.view.backgroundColor = .clear; video.videoGravity = .resizeAspect
      video.view.autoresizingMask = [.flexibleWidth,.flexibleHeight]
      scroll.media.insertSubview(video.view, belowSubview: scroll.photo); video.didMove(toParent: self)
      video.view.accessibilityIdentifier = "library.preview.video"
      readiness = video.observe(\.isReadyForDisplay,options: [.initial,.new]) { [weak self] _,_ in
        Task { @MainActor [weak self] in guard let self else { return }; self.videoReady = self.video.isReadyForDisplay; self.updateVideoVisibility() }
      }
    }
    model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &observations)
    session.$fitRevision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
      guard let self, self.session.current === self.model, !self.flightLocked else { return }
      self.scroll.setZoomScale(1,animated: false)
    }.store(in: &observations)
    refresh()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    scroll.frame = view.bounds; scroll.setNeedsLayout(); scroll.layoutIfNeeded()
    if model.asset.mediaType == .video { video.viewIfLoaded?.frame = scroll.media.bounds }
    placeSelectionMark()
  }
  private func placeSelectionMark() {
    let media = scroll.media.convert(scroll.media.bounds,to: view), side = DuckMediaSelection.size
    selectionMark.frame = CGRect(x: media.maxX-22-side/2,y: media.maxY-22-side/2,width: side,height: side)
  }
  private func updateSelectionMark() {
    selectionMark.isHidden = reviewSelected == nil
    if reviewSelected == true { DuckMediaSelection.configure(selectionMark); return }
    selectionMark.image = UIImage(systemName: "circle",withConfiguration: UIImage.SymbolConfiguration(pointSize: 23))
    selectionMark.tintColor = DuckMedia.onMediaUIColor
    selectionMark.backgroundColor = .clear; selectionMark.layer.cornerRadius = 0
    selectionMark.contentMode = .center
  }
  func refresh() {
    guard isViewLoaded else { return }
    if !flightLocked {
      if let image = model.image { scroll.display(image) }
      scroll.live.livePhoto = model.livePhoto; scroll.live.isHidden = model.livePhoto == nil
    }
    if attachedPlayer !== model.player {
      attachedPlayer = model.player; videoReady = false; video.player = model.player
    }
    updateVideoVisibility()
  }
  func updateVideoVisibility() {
    guard model.asset.mediaType == .video, isViewLoaded else { return }
    // Keep AVKit in the normal render tree while its first frame prepares.
    // The poster owns the visible pixels until both readiness and the flight
    // release, without changing opacity on the native player's own layers.
    // A return flight retains the already presented face, including playback.
    if !flightLocked { allowVideo = videoReady }
    scroll.photo.isHidden = allowVideo
    video.view.isUserInteractionEnabled = allowVideo
    video.view.accessibilityElementsHidden = !allowVideo
    scroll.photo.isAccessibilityElement = !allowVideo
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { scroll.media }
  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    let zoomed = scroll.zoomScale > 1.01
    scroll.centerMedia(); zoomChanged(zoomed); placeSelectionMark()
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var node = touch.view
    while let view = node { if view is UIControl { return false }; node = view.superview }
    return true
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    model.asset.mediaType == .video && other is UITapGestureRecognizer
  }
  @objc func showInformation() -> Bool { information?(); return information != nil }
  @objc func singleTap(_ gesture: UITapGestureRecognizer) { tapped() }
  @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
    guard !flightLocked else { return }
    if scroll.zoomScale > 1.01 { scroll.setZoomScale(1,animated: !UIAccessibility.isReduceMotionEnabled) }
    else {
      let point = gesture.location(in: scroll.media), w = scroll.bounds.width/2.5, h = scroll.bounds.height/2.5
      scroll.zoom(to: CGRect(x: point.x-w/2,y: point.y-h/2,width: w,height: h),animated: !UIAccessibility.isReduceMotionEnabled)
    }
  }
  deinit { readiness?.invalidate() }
}

/// One unobtrusive media-local loading owner; known progress is never invented.
@MainActor final class MediaLoadingIndicator: UIView {
  let track = CAShapeLayer(), arc = CAShapeLayer(), symbol = UIImageView()
  let appearance = UIView()
  private var loadingIdentity: String?
  private var revealed = false
  var retry: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    appearance.backgroundColor = DuckMedia.scrimBurstUIColor; appearance.layer.cornerRadius = 18
    appearance.alpha = 0; appearance.isUserInteractionEnabled = false; addSubview(appearance)
    for shape in [track,arc] { shape.fillColor = UIColor.clear.cgColor; shape.lineWidth = 2; shape.lineCap = .round; appearance.layer.addSublayer(shape) }
    track.strokeColor = DuckMedia.onMediaUIColor.withAlphaComponent(0.3).cgColor; arc.strokeColor = DuckMedia.onMediaCGColor
    symbol.tintColor = DuckMedia.onMediaUIColor; symbol.contentMode = .scaleAspectFit; appearance.addSubview(symbol)
    let tap = UITapGestureRecognizer(target: self,action: #selector(retryTapped)); addGestureRecognizer(tap)
    isAccessibilityElement = true; accessibilityIdentifier = "library.preview.loading"
    accessibilityElementsHidden = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSubviews() {
    super.layoutSubviews(); appearance.frame = bounds; appearance.layer.cornerRadius = bounds.width/2
    let path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX,y: bounds.midY),radius: max(1,bounds.width/2-7),startAngle: -.pi/2,endAngle: .pi*1.5,clockwise: true).cgPath
    track.frame = bounds; arc.frame = bounds; track.path = path; arc.path = path
    symbol.frame = bounds.insetBy(dx: 9,dy: 9)
  }
  func update(state: MediaPreviewIndicatorState, identity: String) {
    isHidden = false
    if loadingIdentity != identity {
      revealed = false
      appearance.layer.removeAllAnimations()
      UIView.performWithoutAnimation { appearance.alpha = 0 }
      accessibilityElementsHidden = true
    }
    loadingIdentity = identity
    let progress: Double? = if case .progress(let value) = state { value } else { nil }
    let indeterminate = state == .indeterminate
    let loading = indeterminate || progress != nil
    let cloud = state == .cloud, failure = state == .failed
    setRevealed(state != .hidden)
    accessibilityTraits = failure || cloud ? .button : .updatesFrequently
    accessibilityLabel = NSLocalizedString(failure ? "retry_task" : cloud ? "preview_cloud_setting" : "preview_loading",comment: "")
    isUserInteractionEnabled = cloud || failure
    accessibilityValue = progress.map { "\(Int($0 * 100))%" }
    // A finished load fades out what it showed; it never swaps in the cloud
    // symbol on its way out.
    if loading || cloud || failure {
      track.isHidden = !loading; arc.isHidden = !loading; symbol.isHidden = loading
      symbol.image = UIImage(systemName: failure ? "exclamationmark.arrow.circlepath" : "icloud.and.arrow.down")
    }
    CATransaction.begin(); CATransaction.setDisableActions(true); arc.strokeEnd = progress.map { CGFloat($0) } ?? 0.22; CATransaction.commit()
    if indeterminate && !UIAccessibility.isReduceMotionEnabled {
      if arc.animation(forKey: "loading.rotation") == nil {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.fromValue = 0; spin.toValue = 2*Double.pi; spin.duration = 1; spin.repeatCount = .infinity; arc.add(spin,forKey: "loading.rotation")
      }
    } else { arc.removeAnimation(forKey: "loading.rotation") }
  }
  private func setRevealed(_ visible: Bool) {
    guard revealed != visible else { return }; revealed = visible
    accessibilityElementsHidden = !visible
    UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
      self.appearance.alpha = visible ? 1 : 0
    }
  }
  @objc func retryTapped() { if revealed { retry?() } }
}
@MainActor final class MediaZoomScroll: UIScrollView {
  let media = UIView(), photo = UIImageView(), live = PHLivePhotoView()
  var mediaSize = CGSize.zero
  var flightLocked = false
  var active = false
  var fitRevision = -1
  private var lastBounds = CGSize.zero
  private var lastImage: CGSize = .zero
  var informationFraction: CGFloat = 0
  private var lastInformationFraction: CGFloat = 0
  override init(frame: CGRect) {
    super.init(frame: frame); addSubview(media); media.addSubview(photo); media.addSubview(live)
    media.tag = 902
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; live.contentMode = .scaleAspectFit
    photo.autoresizingMask = [.flexibleWidth,.flexibleHeight]; live.autoresizingMask = [.flexibleWidth,.flexibleHeight]
    backgroundColor = .clear
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  /// Grid thumbnails are centre crops (aspect fill). Shown in the photo's full
  /// frame they must keep their true place, the centred region of the photo
  /// (aspect fit), so a later full-aspect image only adds the sides. Filling the
  /// frame instead magnified the crop, and its replacement looked like the
  /// photo stretching sideways at the end of the opening flight.
  func display(_ image: UIImage) {
    photo.image = image
    photo.contentMode = MediaZoomScroll.matchesAspect(image.size, mediaSize) ? .scaleAspectFill : .scaleAspectFit
  }
  static func matchesAspect(_ image: CGSize, _ media: CGSize) -> Bool {
    guard image.width > 0, image.height > 0, media.width > 0, media.height > 0 else { return true }
    return abs(log((image.width / image.height) / (media.width / media.height))) < 0.02
  }
  var showsFullAspect: Bool {
    photo.image.map { MediaZoomScroll.matchesAspect($0.size, mediaSize) } ?? false
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard !flightLocked else { return }
    let size = mediaSize
    if bounds.size != lastBounds || size != lastImage || informationFraction != lastInformationFraction {
      let wasZoomed = zoomScale > 1.01
      if !wasZoomed { fit(size) }
      lastBounds = bounds.size; lastImage = size
      lastInformationFraction = informationFraction
    }
    centerMedia()
    if zoomScale <= 1.01 {
      contentOffset = CGPoint(x: max(0,(contentSize.width-bounds.width)/2)-contentInset.left,
        y: max(0,(contentSize.height-bounds.height)/2)-contentInset.top)
    }
  }
  private func fit(_ size: CGSize) {
    guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return }
    let fitted = min(bounds.width/size.width, bounds.height/size.height)
    let filled = max(bounds.width/size.width, bounds.height/size.height)
    let factor = fitted + (filled-fitted) * informationFraction
    let fit = CGSize(width: size.width*factor, height: size.height*factor)
    media.frame = CGRect(origin: .zero, size: fit); photo.frame = media.bounds; live.frame = media.bounds; contentSize = fit
  }
  func centerMedia() {
    guard !flightLocked else { return }
    contentInset = UIEdgeInsets(top: max(0,(bounds.height-contentSize.height)/2), left: max(0,(bounds.width-contentSize.width)/2), bottom: 0, right: 0)
  }
}

/// One uniform media scale and a matching local crop meet either grid endpoint.
struct MediaFlightGeometry {
    let transform: CGAffineTransform
    let crop: CGRect
    init(bounds: CGRect, fitted: CGRect, thumbnail: CGRect) {
        let scale = max(0.0001,max(thumbnail.width/max(1,bounds.width),thumbnail.height/max(1,bounds.height)))
        transform = CGAffineTransform(translationX: thumbnail.midX-fitted.midX,y: thumbnail.midY-fitted.midY)
            .scaledBy(x: scale,y: scale)
        crop = CGRect(x: bounds.midX-thumbnail.width/scale/2,y: bounds.midY-thumbnail.height/scale/2,
            width: thumbnail.width/scale,height: thumbnail.height/scale)
    }
    static func drag(origin: CGPoint, center: CGPoint, translation: CGPoint) -> CGAffineTransform {
        let scale = max(0.65,1-max(0,translation.y)/1000)
        return CGAffineTransform(translationX: translation.x+(1-scale)*(origin.x-center.x),
            y: translation.y+(1-scale)*(origin.y-center.y)).scaledBy(x: scale,y: scale)
    }
}

/// Geometry is evaluated for at most two emphasized items, even in a large library.
/// Paging supplies fractional focus; direct scrubbing owns a uniform compact strip.
@MainActor final class MediaFilmstripLayout: UICollectionViewLayout {
    let pitch: CGFloat = 23
    var current = 0, expansion: CGFloat = 1, aspect: CGFloat = 1
    var focus: CGFloat?
    var neighborAspects: [Int: CGFloat] = [:]
    var count: Int { collectionView?.numberOfItems(inSection: 0) ?? 0 }
    var position: CGFloat { max(0,min(CGFloat(max(0,count-1)),focus ?? CGFloat(current))) }
    private var emphasis: [(Int,CGFloat)] {
        let first = Int(floor(position)), fraction = position-CGFloat(first)
        return [(first,(1-fraction)*expansion),(first+1,fraction*expansion)]
    }
    private func expandedWidth(_ index: Int) -> CGFloat {
        min(30,max(24,30*(neighborAspects[index] ?? aspect)))
    }
    private func weight(_ index: Int) -> CGFloat {
        emphasis.first(where: { $0.0 == index })?.1 ?? 0
    }
    var selectedWidth: CGFloat { 20+(expandedWidth(current)-20)*weight(current) }
    var extra: CGFloat { emphasis.reduce(0) { $0+(expandedWidth($1.0)-20+16)*$1.1 } }
    func center(_ index: Int) -> CGFloat {
        var x = CGFloat(index)*pitch+10
        for (item,weight) in emphasis {
            let widthDelta = (expandedWidth(item)-20)*weight
            if index > item { x += widthDelta+16*weight }
            else if index == item { x += widthDelta/2+8*weight }
        }
        return x
    }
    var focusCenter: CGFloat {
        let first = Int(floor(position)), fraction = position-CGFloat(first)
        return center(first)+(center(min(max(0,count-1),first+1))-center(first))*fraction
    }
    func nearest(_ x: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        var low = 0, high = count-1
        while low < high {
            let middle = (low+high)/2
            if x > (center(middle)+center(middle+1))/2 { low = middle+1 }
            else { high = middle }
        }
        return low
    }
    override var collectionViewContentSize: CGSize {
        CGSize(width: max(0,CGFloat(count)*pitch-3+extra),height: collectionView?.bounds.height ?? 44)
    }
    override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView, path.item >= 0, path.item < count else { return nil }
        let width = 20+(expandedWidth(path.item)-20)*weight(path.item)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
        attributes.frame = CGRect(x: center(path.item)-width/2,y: (collectionView.bounds.height-30)/2,width: width,height: 30)
        return attributes
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard count > 0 else { return [] }
        let first = max(0,Int(floor((rect.minX-extra)/pitch))-2)
        let last = min(count-1,Int(ceil(rect.maxX/pitch))+2)
        guard first <= last else { return [] }
        return (first...last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0,section: 0)) }.filter { $0.frame.intersects(rect) }
    }
    override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool { bounds.size != collectionView?.bounds.size }
}

private extension UIView {
  var libraryViewController: UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return nil
  }
}

/// UIKit owns menu presentation. The image keeps its full aspect and sharpens
/// in place using the existing bounded, cancellable thumbnail pipeline.
@MainActor final class LibraryPhotoPreview: UIViewController {
  private let asset: PHAsset, pipeline: ThumbnailPipeline
  private let photo = UIImageView()
  private var request = PHInvalidImageRequestID
  init(asset: PHAsset, pipeline: ThumbnailPipeline, poster: UIImage?) {
    self.asset = asset; self.pipeline = pipeline
    super.init(nibName: nil, bundle: nil)
    let cached = pipeline.contextPreview(for: asset)
    photo.image = Self.preferred(poster, cached, aspect: aspect)
    let available = UIScreen.main.bounds.size
    let width = min(320, available.width - 48), height = min(480, available.height * 0.6)
    let fittedWidth = min(width, height * aspect)
    preferredContentSize = CGSize(width: fittedWidth, height: fittedWidth / aspect)
  }
  private static func preferred(_ current: UIImage?, _ incoming: UIImage?, aspect: CGFloat) -> UIImage? {
    if let incoming {
      let matches: (UIImage) -> Bool = { abs(log(($0.size.width / max(1,$0.size.height)) / aspect)) < 0.05 }
      if matches(incoming), current.map({ !matches($0) }) ?? true { return incoming }
    }
    return calendarPreferredImage(current, incoming, aspect: aspect)
  }
  private var aspect: CGFloat { CGFloat(max(1,asset.pixelWidth)) / CGFloat(max(1,asset.pixelHeight)) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func loadView() {
    // A cropped seed fills the full-aspect slot until uncropped pixels arrive.
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true
    view = photo
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    request = pipeline.request(asset, pixels: max(preferredContentSize.width, preferredContentSize.height) * traitCollection.displayScale,
      contentMode: .aspectFit) { [weak self] image, _ in
      guard let self, let image else { return }
      self.photo.image = Self.preferred(self.photo.image, image, aspect: self.aspect)
    }
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated); pipeline.cancel(request); request = PHInvalidImageRequestID
  }
  deinit {
    let pipeline = pipeline, request = request
    Task { @MainActor in pipeline.cancel(request) }
  }
}

/// Menu identity is the asset ID, never an index path that can be recycled.
@MainActor enum LibraryPhotoActions {
  static func menu(asset: PHAsset, library: PhotoLibraryModel, model: BackupModel,
    presenter: UIViewController) -> UIMenu {
    UIMenu(children: commands.map { command in
      UIAction(title: NSLocalizedString(command.key, comment: ""), image: UIImage(systemName: command.symbol)) { [weak presenter] _ in
        guard let presenter else { return }
        perform(command.key, asset: asset, library: library, model: model, presenter: presenter)
      }
    })
  }
  private static let commands = [
    (key: "library_context_backup", symbol: "arrow.up"),
    (key: "library_context_history", symbol: "clock.arrow.circlepath"),
    (key: "library_context_share", symbol: "square.and.arrow.up"),
  ]
  static func accessibilityActions(asset: PHAsset, library: PhotoLibraryModel, model: BackupModel,
    presenter: UIViewController) -> [UIAccessibilityCustomAction] {
    accessibilityActions { [weak presenter] key in
      guard let presenter else { return false }
      perform(key, asset: asset, library: library, model: model, presenter: presenter)
      return true
    }
  }
  /// Command labels do not require a materialized photo-library object.
  /// Hosts can resolve that object when the user invokes the action.
  static func accessibilityActions(perform: @escaping (String) -> Bool) -> [UIAccessibilityCustomAction] {
    commands.map { command in
      UIAccessibilityCustomAction(name: NSLocalizedString(command.key, comment: "")) { _ in perform(command.key) }
    }
  }
  static func perform(_ key: String, asset: PHAsset, library: PhotoLibraryModel,
    model: BackupModel, presenter: UIViewController) {
    switch key {
    case "library_context_backup":
      presenter.present(UIHostingController(rootView: LibraryContextBackup(asset: asset, library: library, model: model)), animated: true)
    case "library_context_history":
      presenter.present(UIHostingController(rootView: LibraryContextHistory(asset: asset)), animated: true)
    default: shareAsset(asset, from: presenter)
    }
  }
  static func shareAsset(_ asset: PHAsset, from presenter: UIViewController, anchor: UIBarButtonItem? = nil) {
    if let sample = asset as? any PreviewSample {
      guard let image = sample.previewImage else { return }
      let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
      sheet.popoverPresentationController?.barButtonItem = anchor
      presenter.present(sheet, animated: true)
      return
    }
    let resources = PHAssetResource.assetResources(for: asset)
    guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first else { return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("library-share-" + UUID().uuidString)
    let provider = NSItemProvider()
    let assetID = asset.localIdentifier, filename = resource.originalFilename
    let typeIdentifier = resource.uniformTypeIdentifier, resourceType = resource.type.rawValue
    provider.suggestedName = filename
    // The system loads the original on demand, off the UI thread. There is no
    // full-size context preview or additional thumbnail pipeline.
    provider.registerFileRepresentation(forTypeIdentifier: typeIdentifier,
      fileOptions: [], visibility: .all) { completion in
      let progress = Progress(totalUnitCount: 1)
      progress.isCancellable = false
      guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: photoLibraryFetchOptions()).firstObject,
        let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type.rawValue == resourceType }) else {
        completion(nil, false, CocoaError(.fileNoSuchFile)); return progress
      }
      let requestDirectory = directory.appendingPathComponent(UUID().uuidString)
      do { try FileManager.default.createDirectory(at: requestDirectory, withIntermediateDirectories: true) }
      catch { completion(nil, false, error); return progress }
      let url = requestDirectory.appendingPathComponent(filename)
      let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true
      PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
        progress.completedUnitCount = 1
        completion(error == nil ? url : nil, false, error)
      }
      return progress
    }
    let sheet = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [provider]))
    sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
    sheet.popoverPresentationController?.barButtonItem = anchor
    sheet.popoverPresentationController?.sourceView = presenter.view
    sheet.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY), size: .zero)
    presenter.present(sheet, animated: true)
  }
}

private struct LibraryContextBackup: View {
  let asset: PHAsset
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @StateObject private var action = SelectionBackupAction()
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    DuckSheetLayout(title: "library_context_backup", busy: action.busy, closeOnly: true) {
      DuckSelectionBackupControl(action: action, count: 1,
        request: { await action.request(library: library, model: model, sources: [asset.localIdentifier]) },
        confirm: { await action.confirm(library: library, model: model) })
    } actions: { EmptyView() }
    .task { await action.request(library: library, model: model, sources: [asset.localIdentifier]) }
    .onChange(of: action.added) { _, added in if added { dismiss() } }
  }
}

private struct LibraryContextHistory: View {
  let asset: PHAsset
  var body: some View {
    DuckSheetLayout(title: "library_context_history", closeOnly: true) {
      // Reuse the history's source observation and actionable missing-record
      // state; receipt and publication retain their independent timestamps.
      PhotoBackupInfo(sourceID: asset.localIdentifier, takenAt: asset.creationDate)
    } actions: { EmptyView() }
  }
}

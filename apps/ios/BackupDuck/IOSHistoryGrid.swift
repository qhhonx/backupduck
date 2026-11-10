import Photos
import SwiftUI
import UIKit

/// Supporting SwiftUI pages and native media destinations share a real UIKit
/// stack. UIKit owns Back, interactive cancellation and the visible bars.
struct IOSNativeNavigation<Content: View>: UIViewControllerRepresentable {
  let title: String
  var route: String? = nil
  var routeChanged: (String?) -> Void = { _ in }
  var destination: ((String) -> UIViewController)? = nil
  @ViewBuilder let content: () -> Content

  func makeUIViewController(context: Context) -> IOSNativeNavigationController {
    let navigation = IOSNativeNavigationController()
    navigation.hostingEnvironment = context.environment
    navigation.installRoot(title: title, content: AnyView(content()))
    return navigation
  }
  func updateUIViewController(_ navigation: IOSNativeNavigationController, context: Context) {
    navigation.hostingEnvironment = context.environment
    navigation.routeChanged = routeChanged
    navigation.updateRoot(AnyView(content()))
    navigation.updateRoute(route, destination: destination)
  }
}

/// Each pushed page has one stable native navigation item. Hosted SwiftUI
/// preferences and embedded media controls write to that page's item only.
@MainActor private final class IOSNativePageHostingController: UIHostingController<AnyView> {
  var pageNavigationItem: UINavigationItem?
  override var navigationItem: UINavigationItem { pageNavigationItem ?? super.navigationItem }
}

@MainActor private final class IOSNativePageController: UIViewController {
  let content: IOSNativePageHostingController
  var source: AnyView
  init(content: AnyView) {
    source = content
    self.content = IOSNativePageHostingController(rootView: content)
    super.init(nibName: nil, bundle: nil)
    self.content.pageNavigationItem = navigationItem
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(content); view.addSubview(content.view)
    content.view.frame = view.bounds
    content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    content.didMove(toParent: self)
  }
  override var childForStatusBarStyle: UIViewController? { content }
  override var childForStatusBarHidden: UIViewController? { content }
  override var childForHomeIndicatorAutoHidden: UIViewController? { content }
}

@MainActor private final class IOSNativeNavigationObserver: NSObject, UINavigationControllerDelegate {
  weak var owner: IOSNativeNavigationController?
  func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
    owner?.didShowPage()
  }
}

@MainActor final class IOSNativeNavigationController: UINavigationController, MediaViewerNavigationOwning {
  private var root: IOSNativePageController!
  private var routeController: UIViewController?
  private var route: String?
  private let observer = IOSNativeNavigationObserver()
  private var initialPage: DuckSettingsPage?
  private var pendingRouteUpdate: (() -> Void)?
  var routeChanged: (String?) -> Void = { _ in }
  private var supportingValues: IOSSupportingValues?
  var hostingEnvironment: EnvironmentValues? {
    didSet {
      let next = hostingEnvironment.map(IOSSupportingValues.init)
      guard next != supportingValues else { return }
      supportingValues = next
      for page in viewControllers.compactMap({ $0 as? IOSNativePageController }) {
        page.content.rootView = routed(page.source)
      }
    }
  }
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }

  init() {
    super.init(navigationBarClass: CalendarNavigationBar.self, toolbarClass: nil)
    observer.owner = self
    delegate = observer
    navigationBar.tintColor = DuckRole.accentUIColor
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  private func routed(_ content: AnyView) -> AnyView {
    let routed = AnyView(content.environment(\.duckSettingsNavigator, DuckSettingsNavigator(
      open: { [weak self] page in self?.pushPage(page) },
      back: { [weak self] in self?.popViewController(animated: true) }))
      .environment(\.duckNativeNavigation, true))
    return hostingEnvironment.map { AnyView(routed.iosSupportingEnvironment($0)) } ?? routed
  }
  func pushPage(_ page: DuckSettingsPage, animated: Bool = true) {
    guard transitionCoordinator == nil else { return }
    let controller = IOSNativePageController(content: AnyView(page.content.navigationTitle(page.title)))
    controller.content.rootView = routed(controller.source)
    controller.navigationItem.backButtonDisplayMode = .minimal
    controller.navigationItem.largeTitleDisplayMode = .never
    pushViewController(controller, animated: animated)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    let page = initialPage
    initialPage = nil
    MediaStatusBarRootController.install(in: view.window)
    if let page { pushPage(page, animated: false) }
  }
  func installRoot(title: String, content: AnyView, initialPage: DuckSettingsPage? = nil) {
    self.initialPage = initialPage
    root = IOSNativePageController(content: content)
    root.content.rootView = routed(root.source)
    root.navigationItem.title = title
    root.navigationItem.backButtonDisplayMode = .minimal
    navigationBar.prefersLargeTitles = true
    viewControllers = [root]
  }
  func updateRoot(_ content: AnyView) {
    root.source = content
    root.content.rootView = routed(content)
  }
  func updateRoute(_ value: String?, destination: ((String) -> UIViewController)?) {
    guard value != route else { pendingRouteUpdate = nil; return }
    if let transitionCoordinator {
      pendingRouteUpdate = { [weak self] in self?.updateRoute(value, destination: destination) }
      transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
        DispatchQueue.main.async {
          let pending = self?.pendingRouteUpdate
          self?.pendingRouteUpdate = nil
          pending?()
        }
      }
      return
    }
    route = value
    if let value, let destination {
      let controller = destination(value)
      controller.navigationItem.backButtonDisplayMode = .minimal
      controller.navigationItem.largeTitleDisplayMode = .never
      routeController = controller
      if viewControllers.count > 1 { setViewControllers([root, controller], animated: false) }
      else { pushViewController(controller, animated: view.window != nil) }
    } else if routeController != nil {
      popToRootViewController(animated: view.window != nil)
    }
  }
  fileprivate func didShowPage() {
    if let routeController, !viewControllers.contains(where: { $0 === routeController }) {
      self.routeController = nil; route = nil
      if pendingRouteUpdate == nil { routeChanged(nil) }
    }
  }
}

/// History sheets keep their own native stack and share it with photo detail.
@MainActor final class IOSHistoryNavigationController: UINavigationController, MediaViewerNavigationOwning {
  var close: () -> Void
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }

  init(model: BackupModel, filter: String = "all", focus: HistoryPhoto? = nil,
    sheet: Bool = false, close: @escaping () -> Void) {
    self.close = close
    let content = UIHostingController(rootView: BackupHistoryView(model: model, filter: filter, initialFocus: focus))
    super.init(rootViewController: content)
    content.view.backgroundColor = MediaGridSurface.background
    content.navigationItem.title = NSLocalizedString("records_title", comment: "")
    content.navigationItem.largeTitleDisplayMode = .never
    if sheet {
      content.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done,
        primaryAction: UIAction { [weak self] _ in self?.close() })
    } else {
      content.navigationItem.backAction = UIAction(title: "") { [weak self] _ in self?.close() }
    }
    navigationBar.tintColor = DuckRole.accentUIColor
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// A history data adapter for the same reusable native media cell as the library.
/// Recorded membership never depends on access to the current photo library.
struct IOSHistoryGrid: UIViewControllerRepresentable {
  let history: BackupHistoryModel
  let router: BackupPhotoRouter
  let model: BackupModel
  let columns: Int?
  let focus: String?
  let support: AnyView
  let dayTitle: (Date) -> String
  let presented: (Bool) -> Void

  func makeUIViewController(context: Context) -> IOSHistoryGridController { IOSHistoryGridController() }
  func updateUIViewController(_ controller: IOSHistoryGridController, context: Context) {
    controller.update(self)
  }
  static func dismantleUIViewController(_ controller: IOSHistoryGridController, coordinator: ()) {
    controller.cancelVisibleRequests()
  }
}

@MainActor final class IOSHistoryGridController: UIViewController, UICollectionViewDelegateFlowLayout, MediaViewerSourceGeometryOwning {
  private var input: IOSHistoryGrid?
  private let layout = UICollectionViewFlowLayout()
  private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
  private var source: UICollectionViewDiffableDataSource<String, String>!
  private var photos: [String: HistoryPhoto] = [:]
  private var groups: [(Date, [HistoryPhoto])] = []
  private var focused: String?
  private var hiddenSource: String?
  private var previewInsets: (content: UIEdgeInsets, adjustment: UIScrollView.ContentInsetAdjustmentBehavior)?
  private var preferredIDs: [String: String] = [:]
  private var lastWidth: CGFloat = 0
  private var snapshotGeneration = 0
  private let supportHost = UIHostingController(rootView: AnyView(EmptyView()))
  private let footerHost = UIHostingController(rootView: AnyView(Text("records_cloud_footer").font(.footnote).foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 20)))

  override func viewDidLoad() {
    super.viewDidLoad()
    MediaGridSurface.configure(view, collection: grid)
    grid.delegate = self
    layout.minimumInteritemSpacing = 2
    layout.minimumLineSpacing = 2
    layout.sectionHeadersPinToVisibleBounds = true
    grid.register(CalendarGridCell.self, forCellWithReuseIdentifier: "media")
    grid.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "support")
    grid.register(HistoryDayHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "day")
    view.addSubview(grid)
    source = UICollectionViewDiffableDataSource<String, String>(collectionView: grid) { [weak self] grid, path, id in
      guard let self else { return nil }
      if id == "support" || id == "footer" {
        let cell = grid.dequeueReusableCell(withReuseIdentifier: "support", for: path)
        let content = id == "support" ? self.input?.support ?? AnyView(EmptyView()) : self.footerHost.rootView
        cell.contentConfiguration = UIHostingConfiguration { content }.margins(.all, 0)
        return cell
      }
      let cell = grid.dequeueReusableCell(withReuseIdentifier: "media", for: path) as! CalendarGridCell
      self.configure(cell, id: id)
      return cell
    }
    source.supplementaryViewProvider = { [weak self] grid, kind, path in
      let header = grid.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "day", for: path) as! HistoryDayHeader
      if let self, self.groups.indices.contains(path.section - 1) {
        header.label.text = self.input?.dayTitle(self.groups[path.section - 1].0)
      }
      return header
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    grid.frame = view.bounds
    if lastWidth != grid.bounds.width { lastWidth = grid.bounds.width; layout.invalidateLayout() }
  }

  func update(_ value: IOSHistoryGrid) {
    loadViewIfNeeded()
    let anchor = grid.indexPathsForVisibleItems.sorted().compactMap { path -> (String, CGFloat)? in
      guard let id = source.itemIdentifier(for: path), photos[id] != nil,
        let frame = grid.layoutAttributesForItem(at: path)?.frame else { return nil }
      return (id, frame.minY - grid.contentOffset.y)
    }.first
    input = value
    grid.frame = view.bounds
    supportHost.rootView = value.support
    groups = value.history.days
    let previousPhotos = photos
    photos = Dictionary(uniqueKeysWithValues: value.history.photos.map { ($0.id, $0) })
    preferredIDs = preferredIDs.filter { photos[$0.value] != nil }
    var snapshot = NSDiffableDataSourceSnapshot<String, String>()
    snapshot.appendSections(["support"])
    snapshot.appendItems(["support"], toSection: "support")
    for (day, items) in groups {
      let section = "day-\(day.timeIntervalSince1970)"
      snapshot.appendSections([section]); snapshot.appendItems(items.map(\.id), toSection: section)
    }
    if !photos.isEmpty { snapshot.appendSections(["footer"]); snapshot.appendItems(["footer"], toSection: "footer") }
    let previous = Set(source.snapshot().itemIdentifiers)
    snapshot.reconfigureItems(snapshot.itemIdentifiers.filter {
      previous.contains($0) && ($0 == "support" || previousPhotos[$0] != photos[$0])
    })
    let changes = previous.symmetricDifference(Set(snapshot.itemIdentifiers)).count
    let animates = view.window != nil && !UIAccessibility.isReduceMotionEnabled
      && !previousPhotos.isEmpty && changes > 0 && changes <= 64 && value.focus == nil
    snapshotGeneration += 1
    let expected = snapshotGeneration
    source.apply(snapshot, animatingDifferences: animates) { [weak self] in
      guard let self, self.snapshotGeneration == expected else { return }
      self.layout.invalidateLayout(); self.grid.layoutIfNeeded()
      if let (id, distance) = anchor, let path = self.source.indexPath(for: id),
        let frame = self.grid.layoutAttributesForItem(at: path)?.frame {
        let bottom = max(-self.grid.adjustedContentInset.top, self.grid.contentSize.height - self.grid.bounds.height + self.grid.adjustedContentInset.bottom)
        let y = min(bottom, max(-self.grid.adjustedContentInset.top, frame.minY - distance))
        self.grid.setContentOffset(CGPoint(x: self.grid.contentOffset.x, y: y), animated: false)
      }
      if let focus = value.focus, focus != self.focused, let path = self.source.indexPath(for: focus) {
        self.grid.scrollToItem(at: path, at: .top, animated: false); self.focused = focus
      }
    }
  }

  func cancelVisibleRequests() {
    for case let cell as CalendarGridCell in grid.visibleCells { cell.cancel?(); cell.cancel = nil }
  }
  private func configure(_ cell: CalendarGridCell, id: String) {
    guard let photo = photos[id], let input else { return }
    let changed = cell.assetID != id
    cell.cancel?(); cell.cancel = nil
    if changed { cell.image.image = nil }
    cell.assetID = id
    cell.contentView.isHidden = hiddenSource == photo.source
    cell.label.isHidden = true; cell.scrim.isHidden = true
    cell.contentView.layer.cornerRadius = 0
    cell.contentView.clipsToBounds = true
    cell.selection(false, enabled: false)
    cell.accessibilityIdentifier = "history.photo." + id
    let state: String? = photo.mark == .sending ? "sending" : photo.mark == .saving ? "saving" : photo.mark == .needsYou ? "needs_you" : nil
    cell.backupState(state, visible: true)
    cell.decorations.media(kind: photo.job?.asset.kind ?? "photo", duration: nil)
    let kind = photo.job?.asset.kind ?? "photo"
    let date = photo.takenAt?.formatted(date: .abbreviated, time: .shortened)
      ?? NSLocalizedString("design_capture_unknown", comment: "")
    cell.accessibilityLabel = [NSLocalizedString("library_filter_" + kind, comment: ""), date,
      photo.mark == .saved ? NSLocalizedString("records_fact_saved", comment: "") : nil].compactMap { $0 }.joined(separator: ", ")
    cell.thumbnail(nil, cloud: false)
    cell.resumeThumbnail = { [weak self, weak cell] in
      guard let self, let cell, cell.assetID == id else { return }
      let asset = photo.job.flatMap { BackupEnvironment.sampleAsset?($0) }
        ?? (BackupEnvironment.usesPhotoLibrary ? PHAsset.fetchAssets(withLocalIdentifiers: [photo.source], options: photoLibraryFetchOptions()).firstObject : nil)
      guard let asset else {
        if let image = BackupEnvironment.sampleThumbnail?(photo.source) {
          cell.thumbnail(ImageRenderer(content: image.resizable().frame(width: 180, height: 180)).uiImage, cloud: false)
        }
        return
      }
      cell.decorations.media(asset: asset)
      if asset.mediaType == .video, asset.duration > 0 {
        cell.accessibilityLabel = [cell.accessibilityLabel, videoDurationLabel(asset.duration)].compactMap { $0 }.joined(separator: ", ")
      }
      cell.thumbnail(input.router.library.thumbnails.poster(for: asset), cloud: false)
      let request = input.router.library.thumbnails.request(asset, pixels: max(40, self.tileSide * self.traitCollection.displayScale)) { [weak cell] image, cloud in
        guard let cell, cell.assetID == id else { return }
        cell.thumbnail(image, cloud: cloud)
      }
      cell.cancel = { input.router.library.thumbnails.cancel(request) }
    }
    cell.resumeThumbnail?()
  }

  func collectionView(_ grid: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt path: IndexPath) {
    if let cell = cell as? CalendarGridCell, cell.cancel == nil { cell.resumeThumbnail?() }
    guard let id = source.itemIdentifier(for: path), let history = input?.history else { return }
    if history.photos.suffix(24).contains(where: { $0.id == id }) { Task { await history.loadMore() } }
  }
  func collectionView(_ grid: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt path: IndexPath) {
    (cell as? CalendarGridCell)?.cancel?(); (cell as? CalendarGridCell)?.cancel = nil
  }
  func collectionView(_ grid: UICollectionView, didSelectItemAt path: IndexPath) {
    guard let input, let id = source.itemIdentifier(for: path), let photo = photos[id], presentedViewController == nil else { return }
    input.router.library.previewFrame = { [weak self] source in self?.frame(for: source) }
    input.router.library.previewVisibility = { [weak self] source in
      self?.setPreviewSource(source)
    }
    input.router.library.previewOwnsVacancy = true
    input.presented(true)
    preferredIDs[photo.source] = id
    let frame = frame(for: photo.source) ?? .zero
    let context = input.history.photos
    let fetched = BackupEnvironment.usesPhotoLibrary ? PHAsset.fetchAssets(withLocalIdentifiers: Array(Set(context.map(\.source))), options: photoLibraryFetchOptions()) : nil
    var assets: [String: PHAsset] = [:]
    fetched?.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }
    for photo in context {
      if let job = photo.job, let sample = BackupEnvironment.sampleAsset?(job) { assets[photo.source] = sample }
    }
    if let asset = assets[photo.source] {
      var seen = Set<String>()
      let collection = context.compactMap { assets[$0.source] }.filter { seen.insert($0.localIdentifier).inserted }
      let poster = (grid.cellForItem(at: path) as? CalendarGridCell)?.image.image
      let item = IOSPreviewItem(asset: asset, frame: frame, poster: poster, background: MediaGridSurface.background)
      let session = MediaPreviewSession(asset: asset, library: input.router.library, poster: poster, reviewAssets: collection)
      let viewer = NativeMediaViewer(item: item, session: session) { input.presented(false) }
      viewer.backupModel = input.model
      presentMediaViewer(viewer, from: self, poster: poster)
    } else {
      let viewer = IOSRecordedPhotoViewer(photo: photo, model: input.model) { input.presented(false) }.makeNativeViewer(frame: { [weak self] in self?.frame(for: $0) }, background: MediaGridSurface.background)
      viewer.session.library.previewOwnsVacancy = true
      viewer.session.library.previewVisibility = { [weak self] source in
        self?.setPreviewSource(source)
      }
      presentMediaViewer(viewer, from: self, poster: nil)
    }
  }
  /// A native pop temporarily changes the shared bar reservations. Keep the
  /// source grid in its established coordinate space until its photo has landed.
  func retainMediaViewerSourceGeometry() {
    guard previewInsets == nil else { return }
    let inset = grid.adjustedContentInset, offset = grid.contentOffset
    previewInsets = (grid.contentInset, grid.contentInsetAdjustmentBehavior)
    grid.contentInsetAdjustmentBehavior = .never
    grid.contentInset = inset
    grid.setContentOffset(offset, animated: false)
  }
  private func setPreviewSource(_ source: String?) {
    hiddenSource = source
    updateVisibleVacancies()
  }
  func releaseMediaViewerSourceGeometry() {
    guard let insets = previewInsets else { return }
    let offset = grid.contentOffset
    previewInsets = nil
    grid.contentInset = insets.content
    grid.contentInsetAdjustmentBehavior = insets.adjustment
    view.layoutIfNeeded()
    grid.setContentOffset(offset, animated: false)
  }
  private func updateVisibleVacancies() {
    for case let cell as CalendarGridCell in grid.visibleCells {
      cell.contentView.isHidden = photos[cell.assetID]?.source == hiddenSource && hiddenSource != nil
    }
  }
  private func frame(for sourceID: String) -> CGRect? {
    guard let id = preferredIDs[sourceID] ?? input?.history.photos.first(where: { $0.source == sourceID })?.id,
      let path = source.indexPath(for: id), let attributes = grid.layoutAttributesForItem(at: path) else { return nil }
    if !grid.bounds.intersects(attributes.frame) {
      grid.scrollToItem(at: path, at: .centeredVertically, animated: false)
      grid.layoutIfNeeded()
    }
    return grid.convert(attributes.frame, to: nil)
  }
  private var tileSide: CGFloat {
    let width = grid.bounds.width
    let columns = max(1, input?.columns ?? Int((width + 2) / 88))
    return max(1, floor((width - CGFloat(columns - 1) * 2) / CGFloat(columns)))
  }
  func collectionView(_ grid: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt path: IndexPath) -> CGSize {
    let width = grid.bounds.width
    if path.section == 0 {
      let height = supportHost.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
      return CGSize(width: width, height: max(1, photos.isEmpty ? max(height, grid.bounds.height - grid.adjustedContentInset.top - grid.adjustedContentInset.bottom) : height))
    }
    if source.snapshot().sectionIdentifiers[path.section] == "footer" {
      return CGSize(width: width, height: footerHost.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }
    return CGSize(width: tileSide, height: tileSide)
  }
  func collectionView(_ grid: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
    guard section > 0, section <= groups.count else { return .zero }
    return CGSize(width: grid.bounds.width, height: UIFont.preferredFont(forTextStyle: .headline).lineHeight + 16)
  }
  func collectionView(_ grid: UICollectionView, layout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
    UIEdgeInsets(top: 0, left: 0, bottom: section > 0 && section <= groups.count ? 20 : 0, right: 0)
  }
}

private final class HistoryDayHeader: UICollectionReusableView {
  let label = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = MediaGridSurface.background
    label.font = .preferredFont(forTextStyle: .headline)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = DuckRole.primaryTextUIColor
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds.insetBy(dx: 16, dy: 8) }
}

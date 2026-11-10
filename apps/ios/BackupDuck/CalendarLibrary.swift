import Photos
import AVFoundation
import SwiftUI
import UIKit

/// Photo-library objects are lazy: resolving even one can synchronously contact
/// the system library service. Only the bounded cache is read on the UI actor;
/// misses are coalesced into background batches before image requests start.
@MainActor final class CalendarAssetResolver<Value: AnyObject> {
  typealias Lookup = ([Int]) -> [Int: Value]
  private let cache: NSCache<NSString, Value> = {
    let cache = NSCache<NSString, Value>(); cache.countLimit = 8000; return cache
  }()
  private let queue = DispatchQueue(label: "app.backupduck.calendar-assets", qos: .userInitiated)
  private var positions: [String: Int] = [:]
  private var lookup: Lookup?
  private var epoch = 0, sequence: UInt64 = 0
  private var pending: [String] = []
  private var queued = Set<String>(), prefetching = Set<String>(), inFlight = Set<String>()
  private struct Subscriber {
    let visible: Bool
    let complete: (Value?) -> Void
  }
  private var callbacks: [String: [UInt64: Subscriber]] = [:]
  private var scheduled = false
  var didResolve: (() -> Void)?
  func reset(positions: [String: Int] = [:], preservingPending: Bool = false, lookup: Lookup? = nil) {
    // A refreshed fetch can describe the same displayed membership. Its cells
    // are then intentionally retained, so rebind their unresolved subscriptions.
    let retained = preservingPending && lookup != nil
      ? callbacks.filter { positions[$0.key] != nil } : [:]
    epoch &+= 1
    self.positions = positions; self.lookup = lookup
    pending = Array(retained.keys).sorted(); queued = Set(pending); prefetching = []; inFlight = []
    callbacks = retained; scheduled = false; cache.removeAllObjects()
    schedule()
  }
  func cached(_ id: String) -> Value? { cache.object(forKey: id as NSString) }
  func insert(_ value: Value, for id: String) { cache.setObject(value, forKey: id as NSString) }
  @discardableResult func request(_ id: String, prefetch: Bool = false, completion: @escaping (Value?) -> Void) -> () -> Void {
    if let value = cached(id) { completion(value); return {} }
    guard positions[id] != nil, lookup != nil else { completion(nil); return {} }
    sequence &+= 1
    let token = sequence
    callbacks[id, default: [:]][token] = Subscriber(visible: !prefetch, complete: completion)
    enqueue(id)
    return { [weak self] in self?.cancel(id, token: token) }
  }
  /// A deliberate command has its own subscription, independent of recycled
  /// cells and speculative image requests. Library and presenter lifetimes
  /// still determine whether its resolved object can be used.
  @discardableResult func performAction(_ id: String, isCurrent: @escaping () -> Bool,
    perform: @escaping (Value) -> Void) -> Bool {
    guard isCurrent(), positions[id] != nil, lookup != nil else { return false }
    request(id) { value in
      guard isCurrent(), let value else { return }
      perform(value)
    }
    return true
  }
  func prefetch(_ ids: [String]) {
    for id in ids where cached(id) == nil && positions[id] != nil {
      // Speculative work must not retain an unbounded list during fast travel.
      if queued.count >= 8000 { break }
      prefetching.insert(id); enqueue(id)
    }
  }
  private func cancel(_ id: String, token: UInt64) {
    callbacks[id]?.removeValue(forKey: token)
    if callbacks[id]?.isEmpty == true {
      callbacks.removeValue(forKey: id)
    }
  }
  private func enqueue(_ id: String) {
    if !queued.contains(id), !inFlight.contains(id) {
      queued.insert(id); pending.append(id)
    }
    schedule()
  }
  private func schedule() {
    guard !scheduled, inFlight.isEmpty, !queued.isEmpty else { return }
    scheduled = true
    DispatchQueue.main.async { [weak self] in self?.drain() }
  }
  private func drain() {
    scheduled = false
    guard inFlight.isEmpty, let lookup else { return }
    pending.removeAll { id in
      if callbacks[id] == nil && !prefetching.contains(id) { queued.remove(id) }
      return !queued.contains(id)
    }
    // Visible subscribers take precedence over optional preheat, while both
    // paths share the same batch and cached result.
    let visible = pending.filter { callbacks[$0]?.values.contains(where: { $0.visible }) == true }
    let visibleIDs = Set(visible)
    let wanted = Array((visible + pending.filter { !visibleIDs.contains($0) }).prefix(256))
    guard !wanted.isEmpty else { return }
    let batch = Set(wanted), version = epoch
    pending.removeAll { batch.contains($0) }; queued.subtract(batch); inFlight = batch
    let indexes = Dictionary(uniqueKeysWithValues: wanted.compactMap { id in positions[id].map { (id, $0) } })
    let uniqueIndexes = Array(Set(indexes.values)).sorted()
    queue.async { [weak self] in
      let values = autoreleasepool { lookup(uniqueIndexes) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.epoch == version else { return }
        self.inFlight = []
        var resolved = false
        for id in wanted {
          guard self.epoch == version else { return }
          let value = indexes[id].flatMap { values[$0] }
          if let value { self.insert(value, for: id); resolved = true }
          self.prefetching.remove(id)
          let tokens = self.callbacks[id]?.keys.sorted() ?? []
          for token in tokens {
            guard self.epoch == version else { return }
            let callback = self.callbacks[id]?.removeValue(forKey: token)
            callback?.complete(value)
          }
          if self.callbacks[id]?.isEmpty == true { self.callbacks.removeValue(forKey: id) }
        }
        guard self.epoch == version else { return }
        if resolved { self.didResolve?() }
        self.schedule()
      }
    }
  }
}

/// Cancellation covers both the host-object lookup and the image request that
/// may start afterward. A late lookup never starts an already-cancelled request.
@MainActor final class CalendarResolvedRequest {
  private(set) var active = true
  var cancelLookup: (() -> Void)?
  private var cancelImage: (() -> Void)?
  func adopt(_ cancel: @escaping () -> Void) {
    if active { cancelImage = cancel } else { cancel() }
  }
  func cancel() {
    guard active else { return }
    active = false; cancelLookup?(); cancelImage?()
    cancelLookup = nil; cancelImage = nil
  }
}

/// Calendar covers are a browsing index over the same PhotoKit fetch. They do
/// not register transfers or change the durable backup scope.
struct IOSCalendarLibrary: UIViewControllerRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @ObservedObject var policy = PreviewNetworkPolicy.shared
  @ObservedObject var backupAction: SelectionBackupAction
  var browseOnly = false
  var allowsPinchZoom = true
  var embedsNavigation = true
  var browseNavigation: CalendarBrowseNavigation?
  var browsePlaceholder: AnyView?
  var selectionChanged: (Bool) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> UIViewController {
    let grid = CalendarGridController()
    if let reference = library.calendarDensityReference { grid.columns = reference }
    if let raw = library.calendarLevelRawValue, let level = CalendarGridLevel(rawValue: raw) { grid.level = level }
    grid.browseOnly = browseOnly
    grid.allowsPinchZoom = allowsPinchZoom
    grid.usesContainingNavigationItem = !embedsNavigation
    grid.browseNavigation = browseNavigation
    context.coordinator.controller = grid
    let c = context.coordinator
    library.viewWillChange = { [weak c] in c?.prepareViewTransition() }
    library.previewPoster = { [weak c] id in
      guard let c, id == c.previewOrigin else { return nil }
      return c.previewPoster
    }
    grid.requestImage = { [weak c] asset, pixels, done in
      guard let c else { done(nil, false); return {} }
      return c.withAsset(asset.id) { [weak c] photo in
        guard let c, let photo else { done(nil, false); return {} }
        let request = c.parent.library.thumbnails.request(
          photo, pixels: pixels,
          contentMode: c.controller?.level == .all && (c.controller?.originalAspect == true || c.controller?.columns == 1)
            ? .aspectFit : .aspectFill
        ) { image, cloud in
          if let cg = image?.cgImage, !cloud {
            ThumbnailTables.remember(asset.id, revision: asset.revision, pixels: pixels, image: cg)
          }
          done(image, cloud)
        }
        return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
      }
    }
    grid.requestUncroppedImage = { [weak c] asset, pixels, done in
      guard let c else { done(nil, false); return {} }
      return c.withAsset(asset.id) { [weak c] photo in
        guard let c, let photo else { done(nil, false); return {} }
        let request = c.parent.library.thumbnails.request(photo, pixels: pixels, contentMode: .aspectFit, completion: done)
        return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
      }
    }
    grid.prefetchImage = { [weak c] asset, pixels, done in
      guard let c else { return {} }
      return c.withAsset(asset.id, prefetch: true) { [weak c] photo in
        guard let c, let photo else { return {} }
        let request = c.parent.library.thumbnails.request(photo, pixels: pixels,
          contentMode: c.controller?.level == .all && (c.controller?.originalAspect == true || c.controller?.columns == 1)
            ? .aspectFit : .aspectFill, priority: .prefetch, completion: done)
        return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
      }
    }
    grid.requestVideo = { [weak c] media, done in
      guard BackupEnvironment.usesPhotoLibrary, let c else { done(nil); return {} }
      return c.withAsset(media.id) { [weak c] asset in
        guard let c, let asset, asset.mediaType == .video else { done(nil); return {} }
        let gate = CalendarCoverRequestGate()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = c.parent.policy.allowed
        options.deliveryMode = .fastFormat
        let manager = PHImageManager.default()
        let request = manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
          Task { @MainActor in if gate.active { done(item) } }
        }
        return { gate.active = false; manager.cancelImageRequest(request) }
      }
    }
    grid.prefetchAssets = { [weak c] ids in c?.prefetchAssets(ids) }
    // Table sizes read UIScreen; resolve them here before the canvas's render
    // queue looks tiles up.
    _ = (ThumbnailTables.overviewSide, ThumbnailTables.detailSide)
    grid.storedImage = { asset, pixels in
      ThumbnailTables.image(asset.id, revision: asset.revision, pixels: pixels).map {
        UIImage(cgImage: $0)
      }
    }
    grid.overviewDiskCache = .shared
    grid.prepareOverviewImage = { asset in
      ThumbnailTables.copiedOverview(asset.id, revision: asset.revision)
    }
    grid.placeholderImage = { asset in
      ThumbnailTables.placeholder(asset.id, revision: asset.revision).map { UIImage(cgImage: $0) }
    }
    grid.onSelectionMode = { [weak c] value in
      DispatchQueue.main.async { c?.parent.selectionChanged(value) }
    }
    grid.onSelection = { [weak c] selection in
      c?.parent.library.selection = selection
      if !selection.isEmpty { c?.parent.backupAction.selectionChanged() }
    }
    grid.onPreview = { [weak c] item, frame in
      guard let c, let asset = c.asset(item.id) else { return }
      let index = c.controller?.assets.firstIndex(where: { $0.id == item.id })
      let visible = index.flatMap { c.controller?.grid.cellForItem(at: IndexPath(item: $0,section: 0)) as? CalendarGridCell }
      let poster = visible?.image.image ?? index.flatMap { c.controller?.denseCanvas.displayedImage($0) }
        ?? c.parent.library.thumbnails.contextPreview(for: asset)
      let version = c.epoch
      Task { [weak c] in
        guard let c, let prepared = await c.parent.library.preparePreviewWindow(containing: item.id)
        else { return }
        guard c.epoch == version, c.controller?.view.window != nil else { return }
        guard prepared.burstIdentifier == asset.burstIdentifier,
          prepared.localIdentifier == asset.localIdentifier || asset.burstIdentifier != nil
        else { return }
        c.previewOrigin = prepared.localIdentifier
        c.previewPoster = poster
        guard let grid = c.controller else { return }
        presentLibraryViewer(prepared, frame: frame,
          poster: c.parent.library.previewPoster?(prepared.localIdentifier) ?? c.parent.library.thumbnails.poster(for: prepared),
          library: c.parent.library, from: grid)
      }
    }
    grid.photoMenu = { [weak c] item in
      guard let c, !c.parent.browseOnly, let asset = c.asset(item.id), let grid = c.controller else { return nil }
      return LibraryPhotoActions.menu(asset: asset, library: c.parent.library,
        model: c.parent.model, presenter: grid)
    }
    grid.photoPreview = { [weak c] item, poster in
      guard let c, let asset = c.asset(item.id) else { return nil }
      return LibraryPhotoPreview(asset: asset, pipeline: c.parent.library.thumbnails, poster: poster)
    }
    grid.photoAccessibilityActions = { [weak c] item in
      guard let c, !c.parent.browseOnly else { return [] }
      return LibraryPhotoActions.accessibilityActions { [weak c] key in
        guard let c, let grid = c.controller else { return false }
        let version = c.epoch
        return c.assetResolver.performAction(item.id, isCurrent: { [weak c, weak grid] in
          guard let c, let grid else { return false }
          return c.epoch == version && c.controller === grid && grid.active && !c.parent.browseOnly
        }) { [weak c, weak grid] asset in
          guard let c, let grid else { return }
          LibraryPhotoActions.perform(key, asset: asset, library: c.parent.library,
            model: c.parent.model, presenter: grid)
        }
      }
    }
    library.previewVisibility = { [weak c] id in
      guard let c, let grid = c.controller else { return }
      let asset = id.flatMap { c.asset($0) }
      grid.setPreviewHidden(asset?.burstIdentifier.map { "burst:" + $0 } ?? id)
    }
    grid.configureReview = { [weak c] review in
      let contentMode: PHImageContentMode = review.originalAspect ? .aspectFit : .aspectFill
      review.requestImage = { [weak c] item, pixels, done in
        guard let c else { done(nil, false); return {} }
        return c.withAsset(item.id) { [weak c] asset in
          guard let c, let asset else { done(nil, false); return {} }
          let request = c.parent.library.thumbnails.request(asset, pixels: pixels, contentMode: contentMode) { image, cloud in
            if let cg = image?.cgImage, !cloud {
              ThumbnailTables.remember(item.id, revision: item.revision, pixels: pixels, image: cg)
            }
            done(image, cloud)
          }
          return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
        }
      }
      review.photoMenu = { [weak c, weak review] item in
        guard let c, let review, let asset = c.asset(item.id) else { return nil }
        return LibraryPhotoActions.menu(asset: asset, library: c.parent.library, model: c.parent.model, presenter: review)
      }
      review.photoAccessibilityActions = { [weak c, weak review] item in
        guard let c, let review, let asset = c.asset(item.id) else { return [] }
        return LibraryPhotoActions.accessibilityActions(asset: asset, library: c.parent.library, model: c.parent.model, presenter: review)
      }
      review.onPreview = { [weak c] review in
        guard let c else { return }
        let photos = review.assets.compactMap { c.asset($0.id) }
        presentSelectedMediaReview(from: review, assets: photos, library: c.parent.library)
      }
    }
    grid.onBackup = { [weak c] in
      guard let c else { return }
      Task { await c.parent.backupAction.request(library: c.parent.library, model: c.parent.model) }
    }
    grid.onVisibleChange = { [weak c] in c?.refreshStates() }
    grid.menu = { [weak c] in
      guard let c else { return [] }
      let actions = LibraryFilter.allCases.map { filter in
        UIAction(
          title: NSLocalizedString(filter.title, comment: ""),
          image: UIImage(systemName: filter.symbol),
          state: c.parent.library.filter == filter ? .on : .off
        ) { _ in Task { await c.parent.library.changeFilter(filter) } }
      }
      var menus = [
        UIMenu(
          title: NSLocalizedString("media_type", comment: ""), options: .displayInline,
          children: actions)
      ]
      // design/library.md: backup views of the same grid.
      let views = LibraryBackupView.allCases.map { view in
        UIAction(
          title: NSLocalizedString(view.title, comment: ""),
          image: UIImage(systemName: view.symbol),
          state: c.parent.library.backupView == view ? .on : .off
        ) { _ in Task { await c.parent.library.changeBackupView(view) } }
      }
      menus.insert(UIMenu(title: NSLocalizedString("library_view_section", comment: ""), options: .displayInline, children: views), at: 0)
      return menus
    }
    if !embedsNavigation { return grid }
    let nav = CalendarNavigationController(rootViewController: grid)
    if browseOnly { nav.setNavigationBarHidden(browseNavigation == nil, animated: false) }
    return nav
  }
  func updateUIViewController(_ nav: UIViewController, context: Context) {
    let c = context.coordinator
    c.parent = self
    library.backupReceiver = model.pairing?.receiverID
    guard let grid = c.controller else { return }
    grid.loadViewIfNeeded()
    grid.allowsPinchZoom = allowsPinchZoom
    grid.configureBrowseNavigation(browseNavigation)
    c.updateBrowsePlaceholder(browsePlaceholder)
    if case .filterEmpty? = library.placeholder {
      if c.emptyHost == nil {
        let host = UIHostingController(rootView: LibraryPlaceholder(kind: .filterEmpty,
          clearFilter: { Task { await library.resetFilters() } }))
        grid.addChild(host)
        host.view.backgroundColor = .clear
        grid.grid.backgroundView = host.view
        host.didMove(toParent: grid)
        c.emptyHost = host
      }
    } else if let host = c.emptyHost {
      host.willMove(toParent: nil); grid.grid.backgroundView = nil
      host.removeFromParent(); c.emptyHost = nil
    }
    grid.canBackup = !backupAction.busy
    grid.grid.isUserInteractionEnabled = !backupAction.busy
    if backupAction.added && library.selection.isEmpty {
      grid.completeSelectedBackup()
    }
    grid.setBackupFeedback(title: backupAction.title, added: backupAction.added)
    let review = grid.selectionReview
    review?.setSelection(library.selection, notify: false)
    review?.setBackupFeedback(title: backupAction.title, enabled: !backupAction.busy, added: backupAction.added)
    var presenter: UIViewController = review ?? grid
    var backupAnchor = review?.backupItem ?? grid.backupItem
    // Selected detail shares this action but owns the visible presentation.
    // Only follow that known viewer; an existing alert must keep its ownership.
    if let review,
      let navigation = review.presentedViewController as? MediaViewerNavigationController,
      let viewer = navigation.topViewController as? NativeMediaViewer,
      viewer.review === review, viewer.viewIfLoaded?.window != nil,
      !navigation.isBeingDismissed, !viewer.closing {
      presenter = viewer
      backupAnchor = viewer.toolbarItems?.first {
        $0.accessibilityIdentifier == "calendar.selected_preview_backup"
      } ?? backupAnchor
    }
    if backupAction.confirmingRepeat, presenter.presentedViewController == nil {
      let dialog = UIAlertController(title: NSLocalizedString("selection_backup_repeat_title", comment: ""),
        message: NSLocalizedString("selection_backup_repeat_note", comment: ""), preferredStyle: .actionSheet)
      dialog.addAction(UIAlertAction(title: NSLocalizedString("selection_backup_repeat_action", comment: ""), style: .default) { _ in
        Task { await backupAction.confirm(library: library, model: model) }
      })
      dialog.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel) { _ in backupAction.cancel() })
      dialog.popoverPresentationController?.barButtonItem = backupAnchor
      presenter.present(dialog, animated: true)
    } else if let error = backupAction.error, presenter.presentedViewController == nil {
      let alert = UIAlertController(title: NSLocalizedString("selection_backup_failed_title", comment: ""), message: error, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: NSLocalizedString("settings_done", comment: ""), style: .default) { _ in backupAction.error = nil })
      presenter.present(alert, animated: true)
    }
    if c.fetch !== library.fetch { c.rebuild() }
    grid.displayedTotal = library.total
    grid.viewTitle = library.backupView == .all ? nil : NSLocalizedString(library.backupView.title, comment: "")
    grid.indexing = library.fetch == nil || library.loading || c.work != nil
    if grid.selected != library.selection {
      grid.selected = library.selection
      grid.refreshSelection()
    }
    if c.networkAllowed != policy.allowed {
      c.networkAllowed = policy.allowed
      grid.stopCoverPlayback()
      grid.grid.reloadData()
    }
    grid.filterActive = library.filter != .all || library.backupView != .all
    grid.filterItem.accessibilityValue = [library.backupView.title, library.filter.title].map { NSLocalizedString($0, comment: "") }.joined(separator: ", ")
    grid.refreshMenu()
    grid.updateChrome()
    if c.queueRevision != model.queueRevision || c.receiver != model.pairing?.receiverID {
      c.queueRevision = model.queueRevision
      c.receiver = model.pairing?.receiverID
      c.refreshStates()
    }
  }
  static func dismantleUIViewController(_ nav: UIViewController, coordinator: Coordinator) {
    coordinator.saveBrowsingAnchor()
    coordinator.work?.cancel()
    coordinator.prefill?.cancel()
    coordinator.refresh.cancel()
    coordinator.assetResolver.reset()
    coordinator.parent.library.viewWillChange = nil
    coordinator.parent.library.previewVisibility = nil
    coordinator.parent.library.previewFrame = nil
    coordinator.parent.library.previewPoster = nil
    coordinator.controller?.restoreNavigation()
    coordinator.controller?.chromeMotion?.stopAnimation(true)
    coordinator.controller?.stopMotion()
    coordinator.controller?.stopRange(revert: true)
    coordinator.controller?.geometryWork?.cancel()
  }
  @MainActor final class Coordinator {
    var parent: IOSCalendarLibrary
    weak var controller: CalendarGridController?
    var emptyHost: UIHostingController<LibraryPlaceholder>?
    var browseHost: UIHostingController<AnyView>?
    func updateBrowsePlaceholder(_ placeholder: AnyView?) {
      guard let grid = controller else { return }
      if let placeholder {
        if let browseHost { browseHost.rootView = placeholder }
        else {
          let host = UIHostingController(rootView: placeholder)
          grid.addChild(host)
          host.view.backgroundColor = DuckRole.backgroundUIColor
          grid.view.addSubview(host.view)
          host.view.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: grid.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: grid.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: grid.view.safeAreaLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: grid.view.safeAreaLayoutGuide.bottomAnchor),
          ])
          host.didMove(toParent: grid)
          browseHost = host
        }
      } else if let browseHost {
        browseHost.willMove(toParent: nil); browseHost.view.removeFromSuperview()
        browseHost.removeFromParent(); self.browseHost = nil
      }
    }
    var fetch: PHFetchResult<PHAsset>?
    var positions: [String: Int] = [:]
    var work: Task<Void, Never>?, epoch = 0
    let refresh = LibraryRefreshScheduler()
    var queueRevision: Int64 = -1, receiver: String?
    var networkAllowed = false, filter: LibraryFilter?
    var pendingTransition: (UIView, UIView)?
    var viewKey: String?
    var previewOrigin: String?
    var previewPoster: UIImage?
    var lastPreheat: CFTimeInterval = 0
    init(_ parent: IOSCalendarLibrary) {
      self.parent = parent
      assetResolver.didResolve = { [weak self] in self?.refreshStates() }
    }
    let assetResolver = CalendarAssetResolver<PHAsset>()
    /// Explicit menus and viewer entry retain their synchronous API. Browsing,
    /// preheat and thumbnail requests use only cache hits or background batches.
    func asset(_ id: String) -> PHAsset? {
      if let cached = assetResolver.cached(id) { return cached }
      guard let index = positions[id], let fetch, index < fetch.count else { return nil }
      let asset = fetch.object(at: index)
      assetResolver.insert(asset, for: id)
      return asset
    }
    func withAsset(_ id: String, prefetch: Bool = false, start: @escaping (PHAsset?) -> (() -> Void)) -> () -> Void {
      let gate = CalendarResolvedRequest()
      gate.cancelLookup = assetResolver.request(id, prefetch: prefetch) { photo in
        guard gate.active else { return }
        gate.cancelLookup = nil
        gate.adopt(start(photo))
      }
      return { gate.cancel() }
    }
    func prefetchAssets(_ ids: [String]) { assetResolver.prefetch(ids) }
    func prepareViewTransition() {
      guard pendingTransition == nil, !UIAccessibility.isReduceMotionEnabled,
        let grid = controller,
        let stage = grid.view.window?.rootViewController?.view,
        let cover = stage.snapshotView(afterScreenUpdates: false) else { return }
      // Capture before the model changes, including the SwiftUI view/count chip
      // outside this native controller. Each fading scene keeps its own labels.
      cover.frame = stage.bounds
      pendingTransition = (stage, cover)
    }
    func saveBrowsingAnchor() {
      guard parent.library.authorized, let viewKey, let anchor = controller?.browsingAnchor() else { return }
      parent.library.calendarBrowseAnchors[viewKey] = anchor
      parent.library.calendarDensityReference = controller?.columns
      parent.library.calendarLevelRawValue = controller?.level.rawValue
    }
    func rebuild() {
      work?.cancel()
      epoch += 1
      fetch = parent.library.fetch
      positions = [:]
      guard fetch != nil else {
        assetResolver.reset()
        work = nil
        controller?.replaceAssets([])
        return
      }
      LaunchTrace.mark("calendar rebuild start")
      guard let membership = parent.library.membership, let grid = controller else { return }
      let key = parent.library.backupView.rawValue + "|" + parent.library.filter.rawValue
      let changedView = viewKey != nil && viewKey != key
      if changedView { saveBrowsingAnchor() }
      let transition = changedView ? pendingTransition : nil
      pendingTransition = nil
      let cover = transition?.1
      if let (stage, cover) = transition { stage.addSubview(cover) }
      positions = membership.positions
      if let fetch {
        assetResolver.reset(positions: positions, preservingPending: grid.assets == membership.rows) { indexes in
          let valid = IndexSet(indexes.filter { $0 >= 0 && $0 < fetch.count })
          return Dictionary(uniqueKeysWithValues: zip(valid, fetch.objects(at: valid)))
        }
      }
      work = nil
      grid.indexing = false
      grid.displayedTotal = parent.library.total
      grid.viewTitle = parent.library.backupView == .all ? nil : NSLocalizedString(parent.library.backupView.title, comment: "")
      grid.filterActive = parent.library.filter != .all || parent.library.backupView != .all
      grid.replaceAssets(membership.rows, newView: changedView || viewKey == nil,
        anchor: parent.library.calendarBrowseAnchors[key])
      viewKey = key
      grid.grid.layoutIfNeeded()
      grid.refreshMenu(); grid.updateChrome()
      if let cover {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
          cover.alpha = 0
        } completion: { _ in cover.removeFromSuperview() }
      }
      LaunchTrace.mark("filter settled (\(membership.rows.count))")
      startPrefill(membership.rows)
      parent.library.previewFrame = { [weak self] id in
        guard let self, let grid = self.controller else { return nil }
        let asset = self.asset(id)
        let key = asset?.burstIdentifier.map { "burst:" + $0 } ?? id
        guard let index = grid.assets.firstIndex(where: { $0.id == key }) else { return nil }
        if grid.level != .all { grid.changeLevel(.all, asset: index, from: nil) }
        let rect = grid.grid.convert(grid.layout.frame(index), to: grid.view)
        if rect.minY < grid.view.safeAreaInsets.top || rect.maxY > grid.view.bounds.height - 90 { grid.locateAsset(index) }
        return grid.grid.convert(grid.layout.frame(index), to: nil)
      }
      refreshStates()
    }
    /// Fills the overview table for every item, newest first, from PhotoKit's
    /// local renditions (never the network) at background priority, so dense
    /// overviews and pinch faces read decoded pixels instead of requesting them.
    var prefill: Task<Void, Never>?
    func startPrefill(_ rows: [CalendarGridAsset]) {
      prefill?.cancel()
      guard BackupEnvironment.usesPhotoLibrary, ThumbnailTables.enabled, ThumbnailTables.overview.available, let fetch, let epoch = ThumbnailTables.storage.epoch else { return }
      let positions = positions
      prefill = Task.detached(priority: .utility) {
        let started = CACurrentMediaTime()
        let missing = rows.reversed().filter {
          !ThumbnailTables.overview.contains(ThumbnailTables.key($0.id, revision: $0.revision))
        }
        LaunchTrace.mark("prefill start (\(missing.count) of \(rows.count) missing)")
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true; options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat; options.resizeMode = .fast
        var stored = 0
        for chunk in stride(from: 0, to: missing.count, by: 256) {
          if Task.isCancelled || !ThumbnailTables.storage.isCurrent(epoch) { return }
          // The budget's share is used up by newer items; older ones load on demand.
          if ThumbnailTables.overview.isFull { break }
          let rows = Array(missing[chunk..<min(missing.count, chunk + 256)])
          let wanted = rows.compactMap { row in positions[row.id].map { ($0, row) } }
            .filter { $0.0 < fetch.count }.sorted { $0.0 < $1.0 }
          guard !wanted.isEmpty else { continue }
          let assets = fetch.objects(at: IndexSet(wanted.map(\.0)))
          let lock = NSLock()
          DispatchQueue.concurrentPerform(iterations: assets.count) { i in
            let row = wanted[i].1
            let edge = ThumbnailTables.prefillPixels
            manager.requestImage(for: assets[i], targetSize: CGSize(width: edge, height: edge),
              contentMode: .aspectFill, options: options) { image, _ in
              guard let image = image?.cgImage else { return }
              ThumbnailTables.overview.store(ThumbnailTables.key(row.id, revision: row.revision), image: image, generation: epoch)
              lock.lock(); stored += 1; lock.unlock()
            }
          }
          if chunk == 0 { LaunchTrace.mark("prefill first chunk") }
        }
        guard !Task.isCancelled, ThumbnailTables.storage.isCurrent(epoch) else { return }
        LaunchTrace.mark(String(format: "prefill done (%d stored, %.1f s)", stored, CACurrentMediaTime() - started))
        await MainActor.run { NotificationCenter.default.post(name: .thumbnailPrefillDone, object: nil) }
      }
    }
    func refreshStates() {
      // Dense canvases request their own visible tiles; preheating thousands of
      // assets on every scroll tick showed up as main-thread time in profiles.
      let dense = controller?.layout.geometry.dense == true
      if let grid = controller, CACurrentMediaTime()-lastPreheat > (dense ? 0.3 : 0.12) {
        lastPreheat = CACurrentMediaTime()
        let viewport = grid.grid.bounds.insetBy(dx: 0,dy: -grid.grid.bounds.height*0.35)
        let range = grid.layout.geometry.visible(in: viewport)
        let visibleCount = grid.layout.geometry.visible(in:grid.grid.bounds).count
        let capacity = dense ? min(1024,max(256,visibleCount/2)) : 48
        let center = grid.layout.geometry.visible(in: grid.grid.bounds).lowerBound
        let first = max(range.lowerBound,center-capacity/4)
        // Mosaic tiles already in the decoded overview table need no PhotoKit
        // preheat; faulting their assets was a large share of scroll time.
        let tabled = dense && ThumbnailTables.enabled
        let nearbyIDs = (first..<max(first,min(range.upperBound,first+capacity))).compactMap { i -> String? in
          guard grid.layout.geometry.tiles.indices.contains(i) else { return nil }
          let row = grid.assets[grid.layout.geometry.tiles[i].asset]
          if tabled, ThumbnailTables.overview.contains(ThumbnailTables.key(row.id, revision: row.revision)) { return nil }
          return row.id
        }
        prefetchAssets(nearbyIDs)
        let nearby = nearbyIDs.compactMap { assetResolver.cached($0) }
        let pixels = grid.level == .all && grid.densityRole.isDense ? max(40,grid.width/CGFloat(grid.layout.geometry.columns)*grid.traitCollection.displayScale) : grid.width/CGFloat(grid.level == .all ? grid.layout.geometry.columns : 1)*grid.traitCollection.displayScale
        parent.library.thumbnails.preheat(nearby,pixels: pixels)
      }
      guard let grid = controller,
        grid.level == .all, !grid.densityRole.isDense
      else { return }
      let ids = grid.grid.indexPathsForVisibleItems.compactMap { p -> String? in
        guard grid.layout.geometry.tiles.indices.contains(p.item) else { return nil }
        return grid.assets[grid.layout.geometry.tiles[p.item].asset].id
      }
      prefetchAssets(ids)
      let pairs = ids.compactMap { id in assetResolver.cached(id).map { (id, $0) } }
      guard !pairs.isEmpty else { return }
      let photos = pairs.map { $0.1 }
      let library = parent.library
      let receiver = parent.model.pairing?.receiverID
      let queueRevision = parent.model.queueRevision
      let version = epoch
      let preparation = "\(parent.model.pendingImports)|\(parent.model.importingSourceID ?? "")"
      refresh.schedule { [weak self, weak grid] in
        let groups = await library.visibleGroups(photos)
        guard let states = await librarySourceStates(groups, receiver: receiver,
          cache: library.tileStates, revision: "\(library.generation)|\(queueRevision)|\(preparation)"), let self,
          self.epoch == version, receiver == self.parent.model.pairing?.receiverID,
          queueRevision == self.parent.model.queueRevision,
          preparation == "\(self.parent.model.pendingImports)|\(self.parent.model.importingSourceID ?? "")", let grid
        else { return }
        for (id, photo) in pairs {
          if let group = groups[photo.localIdentifier] {
            grid.photoStates[id] = group.state(states)
            grid.burstCounts[id] = photo.burstIdentifier != nil ? group.count : nil
          }
        }
        if grid.burstCounts.count > 1600 {
          grid.burstCounts = grid.burstCounts.filter { ids.contains($0.key) }
        }
        if grid.photoStates.count > 1600 {
          grid.photoStates = grid.photoStates.filter { ids.contains($0.key) }
        }
        for path in grid.grid.indexPathsForVisibleItems {
          guard grid.layout.geometry.tiles.indices.contains(path.item) else { continue }
          let id = grid.assets[grid.layout.geometry.tiles[path.item].asset].id
          (grid.grid.cellForItem(at: path) as? CalendarGridCell)?.setGroup(
            count: grid.burstCounts[id], state: grid.photoStates[id], visible: !grid.selecting && grid.level == .all)
        }
      }
    }
  }
}

@MainActor private final class CalendarCoverRequestGate { var active = true }

extension Notification.Name {
  static let thumbnailPrefillDone = Notification.Name("ThumbnailPrefillDone")
}

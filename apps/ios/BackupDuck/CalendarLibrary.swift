import Photos
import AVFoundation
import SwiftUI
import UIKit

/// Calendar covers are a browsing index over the same PhotoKit fetch. They do
/// not register transfers or change the durable backup scope.
struct IOSCalendarLibrary: UIViewControllerRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @ObservedObject var policy = PreviewNetworkPolicy.shared
  let onPreview: (PHAsset, CGRect) -> Void
  let onBackup: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> UINavigationController {
    let grid = CalendarGridController()
    context.coordinator.controller = grid
    let c = context.coordinator
    library.previewPoster = { [weak c] id in
      guard let c, id == c.previewOrigin else { return nil }
      return c.previewPoster
    }
    grid.requestImage = { [weak c] asset, pixels, done in
      guard let c, let photo = c.asset(asset.id) else {
        done(nil, false)
        return {}
      }
      let request = c.parent.library.thumbnails.request(
        photo, pixels: pixels,
        contentMode: c.controller?.level == .all && (c.controller?.originalAspect == true || c.controller?.columns == 1)
          ? .aspectFit : .aspectFill
      ) { image, cloud in
        // Small delivered thumbnails also fill the decoded bitmap tables.
        if let cg = image?.cgImage, !cloud {
          ThumbnailTables.remember(asset.id, revision: asset.revision, pixels: pixels, image: cg)
        }
        done(image, cloud)
      }
      return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
    }
    grid.requestUncroppedImage = { [weak c] asset, pixels, done in
      guard let c, let photo = c.asset(asset.id) else { done(nil,false); return {} }
      let request = c.parent.library.thumbnails.request(photo,pixels: pixels,contentMode: .aspectFit,completion: done)
      return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
    }
    grid.prefetchImage = { [weak c] asset, pixels, done in
      guard let c, let photo = c.asset(asset.id) else { return {} }
      let request = c.parent.library.thumbnails.request(photo, pixels: pixels,
        contentMode: c.controller?.level == .all && (c.controller?.originalAspect == true || c.controller?.columns == 1)
          ? .aspectFit : .aspectFill, priority: .prefetch, completion: done)
      return { [weak c] in c?.parent.library.thumbnails.cancel(request) }
    }
    grid.requestVideo = { [weak c] media, done in
      guard let c, let asset = c.asset(media.id), asset.mediaType == .video else {
        done(nil); return {}
      }
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
    grid.prefetchAssets = { [weak c] ids in c?.prefetchAssets(ids) }
    // Table sizes read UIScreen; resolve them here before the canvas's render
    // queue looks tiles up.
    _ = (ThumbnailTables.overviewSide, ThumbnailTables.detailSide)
    grid.storedImage = { asset, pixels in
      ThumbnailTables.image(asset.id, revision: asset.revision, pixels: pixels).map {
        UIImage(cgImage: $0)
      }
    }
    grid.placeholderImage = { asset in
      ThumbnailTables.placeholder(asset.id, revision: asset.revision).map { UIImage(cgImage: $0) }
    }
    grid.onSelection = { [weak c] selection in c?.parent.library.selection = selection }
    grid.onPreview = { [weak c] item, frame in
      guard let c, let asset = c.asset(item.id) else { return }
      let index = c.controller?.assets.firstIndex(where: { $0.id == item.id })
      let visible = index.flatMap { c.controller?.grid.cellForItem(at: IndexPath(item: $0,section: 0)) as? CalendarGridCell }
      let poster = visible?.image.image
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
        c.parent.onPreview(prepared, frame)
      }
    }
    grid.onReviewBrowse = { [weak c] review in
      guard let c else { return }
      let photos = review.assets.compactMap { c.asset($0.id) }
      presentSelectedMediaReview(from: review,assets: photos,library: c.parent.library)
    }
    grid.onBackup = { [weak c] in c?.parent.onBackup() }
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
      return [
        UIMenu(
          title: NSLocalizedString("media_type", comment: ""), options: .displayInline,
          children: actions)
      ]
    }
    return CalendarNavigationController(rootViewController: grid)
  }
  func updateUIViewController(_ nav: UINavigationController, context: Context) {
    let c = context.coordinator
    c.parent = self
    guard let grid = c.controller else { return }
    grid.loadViewIfNeeded()
    grid.canBackup = model.pairing != nil && !model.importing
    grid.displayedTotal = library.total
    grid.indexing = library.fetch == nil || library.loading || c.work != nil
    if grid.selected != library.selection {
      grid.selected = library.selection
      grid.refreshSelection()
    }
    if c.fetch !== library.fetch { c.rebuild() }
    if c.networkAllowed != policy.allowed {
      c.networkAllowed = policy.allowed
      grid.stopCoverPlayback()
      grid.grid.reloadData()
    }
    if c.filter != library.filter {
      c.filter = library.filter
      grid.refreshMenu()
    }
    grid.updateChrome()
    if c.queueRevision != model.queueRevision || c.receiver != model.pairing?.receiverID {
      c.queueRevision = model.queueRevision
      c.receiver = model.pairing?.receiverID
      c.refreshStates()
    }
  }
  static func dismantleUIViewController(_ nav: UINavigationController, coordinator: Coordinator) {
    coordinator.work?.cancel()
    coordinator.prefill?.cancel()
    coordinator.refresh.cancel()
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
    var fetch: PHFetchResult<PHAsset>?
    var positions: [String: Int] = [:]
    var work: Task<Void, Never>?, epoch = 0
    let refresh = LibraryRefreshScheduler()
    var queueRevision: Int64 = -1, receiver: String?
    var networkAllowed = false, filter: LibraryFilter?
    var previewOrigin: String?
    var previewPoster: UIImage?
    var lastPreheat: CFTimeInterval = 0
    init(_ parent: IOSCalendarLibrary) { self.parent = parent }
    /// PhotoKit materializes single objects slowly (about 0.5 ms each on a
    /// large device library); resolved assets stay in a bounded cache and
    /// dense views resolve whole strips with one bulk fetch.
    let assetCache: NSCache<NSString, PHAsset> = {
      let cache = NSCache<NSString, PHAsset>()
      cache.countLimit = 8000
      return cache
    }()
    func asset(_ id: String) -> PHAsset? {
      if let cached = assetCache.object(forKey: id as NSString) { return cached }
      guard let index = positions[id], let fetch, index < fetch.count else { return nil }
      let asset = fetch.object(at: index)
      assetCache.setObject(asset, forKey: id as NSString)
      return asset
    }
    func prefetchAssets(_ ids: [String]) {
      guard let fetch else { return }
      var wanted: [Int: String] = [:]
      for id in ids where assetCache.object(forKey: id as NSString) == nil {
        if let index = positions[id], index < fetch.count { wanted[index] = id }
      }
      guard wanted.count > 1 else { return }
      let indexes = IndexSet(wanted.keys)
      for (index, asset) in zip(indexes, fetch.objects(at: indexes)) {
        if let id = wanted[index] { assetCache.setObject(asset, forKey: id as NSString) }
      }
    }
    func rebuild() {
      work?.cancel()
      epoch += 1
      let version = epoch
      fetch = parent.library.fetch
      positions = [:]
      assetCache.removeAllObjects()
      guard let fetch else {
        work = nil
        controller?.replaceAssets([])
        return
      }
      LaunchTrace.mark("calendar rebuild start")
      controller?.indexing = true
      controller?.updateChrome()
      let progressive = controller?.assets.isEmpty != false
      work = Task { [weak self] in
        // The newest edge is what opens first; publish it before indexing the rest.
        // The first screen plus one pinch into the 15-column month overview.
        if progressive, fetch.count > 2000 {
          let head = Task.detached(priority: .userInitiated) { Self.index(fetch, upTo: 600) }
          let partial = await withTaskCancellationHandler(
            operation: { await head.value }, onCancel: { head.cancel() })
          guard let self, !Task.isCancelled, self.epoch == version else { return }
          self.positions = partial.1
          LaunchTrace.mark("newest items published (\(partial.0.count))")
          self.controller?.replaceAssets(partial.0)
        }
        let job = Task.detached(priority: .userInitiated) { Self.index(fetch, upTo: fetch.count) }
        let result = await withTaskCancellationHandler(
          operation: { await job.value }, onCancel: { job.cancel() })
        guard let self, !Task.isCancelled, self.epoch == version else { return }
        self.work = nil
        self.positions = result.1
        self.controller?.indexing = false
        LaunchTrace.mark("all items published (\(result.0.count))")
        self.controller?.replaceAssets(result.0)
        self.startPrefill(result.0)
        self.parent.library.previewFrame = { [weak self] id in
          guard let self, let grid = self.controller else { return nil }
          let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [id], options: photoLibraryFetchOptions()
          ).firstObject
          let key = asset?.burstIdentifier.map { "burst:" + $0 } ?? id
          guard let index = grid.assets.firstIndex(where: { $0.id == key }) else { return nil }
          if grid.level != .all { grid.changeLevel(.all, asset: index, from: nil) }
          let path = IndexPath(item: index, section: 0)
          let rect = grid.grid.convert(grid.layout.frame(index), to: grid.view)
          if id != self.previewOrigin || grid.grid.cellForItem(at: path) == nil
            || rect.maxY < grid.view.safeAreaInsets.top || rect.minY > grid.view.bounds.height - 90
          {
            grid.locateAsset(index)
          }
          return grid.grid.convert(grid.layout.frame(index), to: nil)
        }
        self.refreshStates()
      }
    }
    /// Rows in chronological order (oldest first) for the newest `limit` raw
    /// assets, with bursts collapsed to their representative. Batched
    /// enumeration is far cheaper than per-index access on large libraries.
    nonisolated static func index(_ fetch: PHFetchResult<PHAsset>, upTo limit: Int)
      -> ([CalendarGridAsset], [String: Int])
    {
      LaunchTrace.mark("index start (\(limit))")
      var rows: [CalendarGridAsset] = []
      var positions: [String: Int] = [:]
      var rowPositions: [String: Int] = [:]
      rows.reserveCapacity(min(limit, fetch.count))
      let range = IndexSet(integersIn: 0..<min(limit, fetch.count))
      // Partial enumeration faults objects one by one on device (about 0.5 ms
      // each, measured); a bulk fetch of the same range loads them together.
      let objects: [PHAsset] = limit < fetch.count ? fetch.objects(at: range) : []
      func visit(_ asset: PHAsset, _ raw: Int, _ stop: UnsafeMutablePointer<ObjCBool>) {
        if raw % 512 == 0, Task.isCancelled { stop.pointee = true; return }
        let key = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
        let row = CalendarGridAsset(
          id: key, date: asset.creationDate,
          aspect: CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight)),
          videoDuration: asset.mediaType == .video ? videoDurationLabel(asset.duration) : nil,
          live: asset.mediaSubtypes.contains(.photoLive),
          revision: Int64(PhotoLibraryModel.revision(asset)) ?? 0)
        if positions[key] != nil {
          if asset.representsBurst, let i = rowPositions[key] {
            positions[key] = raw
            rows[i] = CalendarGridAsset(id: key, date: row.date, aspect: row.aspect,
              videoDuration: nil, live: row.live, revision: row.revision)
          }
          return
        }
        positions[key] = raw
        rowPositions[key] = rows.count
        rows.append(row)
      }
      if objects.isEmpty {
        fetch.enumerateObjects(at: range, options: []) { asset, raw, stop in visit(asset, raw, stop) }
      } else {
        var stop: ObjCBool = false
        for (raw, asset) in objects.enumerated() {
          visit(asset, raw, &stop)
          if stop.boolValue { break }
        }
      }
      return (Array(rows.reversed()), positions)
    }
    /// Fills the overview table for every item, newest first, from PhotoKit's
    /// local renditions (never the network) at background priority, so dense
    /// overviews and pinch faces read decoded pixels instead of requesting them.
    var prefill: Task<Void, Never>?
    func startPrefill(_ rows: [CalendarGridAsset]) {
      prefill?.cancel()
      guard ThumbnailTables.enabled, ThumbnailTables.overview.available, let fetch else { return }
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
          if Task.isCancelled { return }
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
              ThumbnailTables.overview.store(ThumbnailTables.key(row.id, revision: row.revision), image: image)
              lock.lock(); stored += 1; lock.unlock()
            }
          }
          if chunk == 0 { LaunchTrace.mark("prefill first chunk") }
        }
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
        let nearby = (first..<max(first,min(range.upperBound,first+capacity))).compactMap { i -> PHAsset? in
          guard grid.layout.geometry.tiles.indices.contains(i) else { return nil }
          let row = grid.assets[grid.layout.geometry.tiles[i].asset]
          if tabled, ThumbnailTables.overview.contains(ThumbnailTables.key(row.id, revision: row.revision)) { return nil }
          return asset(row.id)
        }
        let pixels = grid.level == .all && grid.columns >= 10 ? max(40,grid.width/CGFloat(grid.columns)*grid.traitCollection.displayScale) : grid.width/CGFloat(grid.level == .all ? grid.columns : 1)*grid.traitCollection.displayScale
        parent.library.thumbnails.preheat(nearby,pixels: pixels)
      }
      guard let grid = controller, let receiver = parent.model.pairing?.receiverID,
        grid.level == .all, grid.columns < 10
      else { return }
      let ids = grid.grid.indexPathsForVisibleItems.compactMap { p -> String? in
        guard grid.layout.geometry.tiles.indices.contains(p.item) else { return nil }
        return grid.assets[grid.layout.geometry.tiles[p.item].asset].id
      }
      let pairs = ids.compactMap { id in asset(id).map { (id, $0) } }
      let photos = pairs.map { $0.1 }
      let library = parent.library
      let version = epoch
      refresh.schedule { [weak self, weak grid] in
        let groups = await library.visibleGroups(photos)
        guard let states = await librarySourceStates(groups, receiver: receiver), let self,
          self.epoch == version, let grid
        else { return }
        for (id, photo) in pairs {
          if let group = groups[photo.localIdentifier] {
            grid.photoStates[id] = group.state(states)
          }
        }
        if grid.photoStates.count > 1600 {
          grid.photoStates = grid.photoStates.filter { ids.contains($0.key) }
        }
        for path in grid.grid.indexPathsForVisibleItems {
          guard grid.layout.geometry.tiles.indices.contains(path.item) else { continue }
          let id = grid.assets[grid.layout.geometry.tiles[path.item].asset].id
          (grid.grid.cellForItem(at: path) as? CalendarGridCell)?.backupState(
            grid.photoStates[id], visible: !grid.selecting && grid.level == .all)
        }
      }
    }
  }
}

@MainActor private final class CalendarCoverRequestGate { var active = true }

extension Notification.Name {
  static let thumbnailPrefillDone = Notification.Name("ThumbnailPrefillDone")
}

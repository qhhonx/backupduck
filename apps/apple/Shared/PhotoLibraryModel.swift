import Combine
import Foundation
import CryptoKit
import Photos

#if os(macOS)
  import AppKit
  typealias LibraryImage = NSImage
#else
  import UIKit
  typealias LibraryImage = UIImage
#endif

// Use identical membership for browsing, export, thumbnails and scroll anchors.
// PhotoKit otherwise returns only representative burst frames by default.
func photoLibraryFetchOptions() -> PHFetchOptions {
  let options = PHFetchOptions()
  options.includeAllBurstAssets = true
  return options
}

func photoLibraryFetchOptions(for filter: LibraryFilter) -> PHFetchOptions {
  let options = photoLibraryFetchOptions()
  switch filter {
  case .all:
    options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
      PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
  case .photo:
    // PhotoKit treats mask-equals-zero differently for imported assets. Negate
    // its supported positive mask predicate instead of losing ordinary stills.
    options.predicate = NSPredicate(format: "mediaType == %d AND NOT ((mediaSubtype & %d) != 0) AND burstIdentifier == nil",
      PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoLive.rawValue)
  case .motion:
    options.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtype & %d) != 0",
      PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoLive.rawValue)
  case .burst:
    options.predicate = NSPredicate(format: "burstIdentifier != nil")
  case .video:
    options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
  }
  return options
}

enum LibraryFilter: String, CaseIterable, Identifiable {
  case all, photo, motion, video, burst
  var id: String { rawValue }
  var title: String { "library_filter_" + rawValue }
  var symbol: String {
    switch self {
    case .all: "square.grid.2x2"
    case .photo: "photo"
    case .motion: "livephoto"
    case .video: "video"
    case .burst: "square.stack"
    }
  }
}

/// Backup views of the library (design/library.md): the same grid, narrowed by
/// what the core knows about each photo. Not backed up is a view, never a mark.
enum LibraryBackupView: String, CaseIterable, Identifiable {
  case all, notBackedUp, needsYou, recent
  var id: String { rawValue }
  var title: String { "library_view_" + rawValue }
  var symbol: String {
    switch self {
    case .all: "photo.on.rectangle"
    case .notBackedUp: "icloud.slash"
    case .needsYou: "exclamationmark.circle"
    case .recent: "clock.arrow.circlepath"
    }
  }
  /// How far back Recently backed up looks.
  static let recentWindow: TimeInterval = 7 * 24 * 3600
}

@MainActor final class PhotoLibraryModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
  // Resolve current media in the native viewport at presentation/return time.
  var previewFrame: ((String) -> CGRect?)?
  var previewPoster: ((String) -> LibraryImage?)?
  #if os(iOS)
  var previewSourceView: ((String) -> UIView?)?
  /// Catalog-only start position, applied once after the complete index is ready.
  var catalogAnchorFraction: Double?
  #endif

  @Published private(set) var total = 0
  @Published private(set) var loaded = 0
  @Published private(set) var generation = 0
  @Published private(set) var contentGeneration = 0
  @Published private(set) var loading = false
  // Read at creation (a cheap synchronous query) so the first frame shows the
  // library rather than the permission placeholder until `open()` runs.
  @Published private(set) var authorized = PhotoLibraryModel.allowed(PHPhotoLibrary.authorizationStatus(for: .readWrite))
  @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
  @Published private(set) var requestingPermission = false
  @Published private(set) var filter: LibraryFilter = .all
  @Published private(set) var backupView: LibraryBackupView = .all
  private var requestedBackupView: LibraryBackupView = .all
  /// The receiver backup views ask the core about; set by the page that shows the library.
  /// A backup view depends on it, so it reloads when the receiver becomes known or changes.
  var backupReceiver: String? {
    didSet {
      guard backupReceiver != oldValue, requestedBackupView != .all, fetch != nil else { return }
      Task { await reload(resetWindow: true) }
    }
  }
  private var requestedFilter: LibraryFilter = .all
  @Published var viewMode: LibraryViewMode = .all
  @Published var phoneColumns = 3
  @Published var selection: Set<String> = []
  @Published var message: String?
  private(set) var fetch: PHFetchResult<PHAsset>?
  private var presentation = LibraryPresentationIndex()
  private var loadingPage = false
  private var cancelMetadata: (() -> Void)?
  let tileStates = LibrarySourceStateCache()
  private var groups: [String: LibraryGroup] = [:]
  private var groupOrder: [String] = []
  private var requestGeneration = 0
  private var observerRegistered = false
  private var changesTask: Task<Void, Never>?
  var scrollOffset = CGPoint.zero
  var scrollAnchorID: String?
  var scrollAnchorInset: CGFloat = 0
  private(set) var scrollResetGeneration = 0
  let thumbnails = ThumbnailPipeline()
  /// When set, the model browses one album (PhotoKit collection) with the same
  /// filter, sort, paging and thumbnail pipeline as the whole library.
  let collectionID: String?
  init(collection: String? = nil) {
    collectionID = collection
    super.init()
  }

  // Display rows can group multiple burst assets, so loaded < total does not
  // describe the raw PhotoKit cursor's remaining pagination range.
  var hasMoreRows: Bool {
    guard let fetch else { return false }
    return presentation.cursor < fetch.count
  }

  var placeholder: LibraryPlaceholderKind? {
    if !authorized { return .permission(authorizationStatus) }
    if fetch == nil { return .loading }
    if total == 0 { return .empty(filtered: filter != .all) }
    return nil
  }

  func open(requestPermission: Bool = false) async {
    LaunchTrace.mark("library open")
    guard !requestingPermission else { return }
    if requestPermission { requestingPermission = true }
    defer { if requestPermission { requestingPermission = false } }
    let access =
      requestPermission
      ? await PHPhotoLibrary.requestAuthorization(for: .readWrite)
      : PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard applyAuthorization(access) else { return }
    if !observerRegistered {
      PHPhotoLibrary.shared().register(self)
      observerRegistered = true
    }
    if fetch == nil { await reload() }
  }
  nonisolated static func allowed(_ access: PHAuthorizationStatus) -> Bool {
    access == .authorized || access == .limited
  }
  /// The fetch for a backup view: the type-filtered library narrowed by the
  /// core's answer, in the library's own order. Nil when the core cannot answer.
  nonisolated static func narrow(_ fetch: PHFetchResult<PHAsset>, to view: LibraryBackupView,
    filter: LibraryFilter, receiver: String?) async -> PHFetchResult<PHAsset>? {
    let ids: [String]
    switch view {
    case .all:
      return fetch
    case .notBackedUp:
      var received: Set<String> = []
      if let receiver {
        guard let data = try? await Bridge.call(["op": "received_sources", "receiver_id": receiver]),
          let list = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        received = Set(list)
      }
      var remaining: [String] = []
      remaining.reserveCapacity(fetch.count)
      fetch.enumerateObjects { asset, _, _ in
        if !received.contains(asset.localIdentifier) { remaining.append(asset.localIdentifier) }
      }
      ids = remaining
    case .needsYou, .recent:
      guard let receiver else { return PHFetchResult<PHAsset>() }
      guard let found = await taskSources(receiver: receiver, view: view) else { return nil }
      ids = found
    }
    // Same membership and order as the library fetch, so the grid's date groups hold.
    let options = photoLibraryFetchOptions(for: filter)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    return PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
  }

  private struct TaskPage: Decodable { let items: [BackupTaskItem] }

  /// Library sources of the core's attention items, or of items received in
  /// the recent window, newest change first.
  nonisolated static func taskSources(receiver: String, view: LibraryBackupView) async -> [String]? {
    let since = Int64((Date().timeIntervalSince1970 - LibraryBackupView.recentWindow) * 1000)
    var sources: [String] = []
    var after: (Int64, Int64)?
    for _ in 0..<50 {
      var query: [String: Any] = ["op": "backup_tasks", "receiver_id": receiver, "sort": "activity", "descending": true,
        "state": view == .needsYou ? "attention" : "all"]
      if let after { query["after"] = after.0; query["after_value"] = after.1 }
      guard let data = try? await Bridge.call(query), let page = try? JSONDecoder().decode(TaskPage.self, from: data) else { return nil }
      for item in page.items {
        if view == .recent {
          guard let job = item.job, (item.sort_value ?? 0) >= since else { continue }
          if job.state == "received" { sources.append(job.asset.source_id) }
        } else {
          sources.append(item.job?.asset.source_id ?? item.preparation?.source ?? "")
        }
      }
      guard page.items.count == 200, let last = page.items.last else { break }
      if view == .recent, (last.sort_value ?? 0) < since { break }
      after = (last.cursor, last.sort_value ?? 0)
    }
    return sources.filter { !$0.isEmpty }
  }

  /// Sorted fetch for a filter; identical for the launch prewarm and reloads.
  nonisolated static func fetchAssets(_ filter: LibraryFilter, collection: String? = nil) -> PHFetchResult<PHAsset> {
    let options = photoLibraryFetchOptions(for: filter)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    guard let collection else { return PHAsset.fetchAssets(with: options) }
    // A missing or revoked album reads as empty, never as the whole library.
    guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [collection], options: nil).firstObject
    else { return PHAsset.fetchAssets(withLocalIdentifiers: [], options: options) }
    return PHAsset.fetchAssets(in: album, options: options)
  }
  /// The launch fetch, started from app init so it overlaps scene setup instead
  /// of waiting for the library view's first task, with the library's change
  /// token from just before it.
  private static var earlyFetch: Task<(PHFetchResult<PHAsset>, PHPersistentChangeToken), Never>?
  static func prewarm() {
    // `-no-launch-prewarm` keeps the old start for side-by-side launch traces.
    guard earlyFetch == nil, !ProcessInfo.processInfo.arguments.contains("-no-launch-prewarm"),
      allowed(PHPhotoLibrary.authorizationStatus(for: .readWrite)) else { return }
    earlyFetch = Task.detached(priority: .userInitiated) {
      LaunchTrace.mark("early fetch start")
      let token = PHPhotoLibrary.shared().currentChangeToken
      LaunchTrace.mark("early change token")
      let fetch = fetchAssets(.all)
      LaunchTrace.mark("early fetch done (\(fetch.count))")
      return (fetch, token)
    }
  }
  /// Hands over the early fetch once, for the default filter.
  private static func takeEarlyFetch(for filter: LibraryFilter)
    -> Task<(PHFetchResult<PHAsset>, PHPersistentChangeToken), Never>? {
    defer { earlyFetch = nil }
    return filter == .all ? earlyFetch : nil
  }
  @discardableResult func applyAuthorization(_ access: PHAuthorizationStatus) -> Bool {
    authorizationStatus = access
    let allowed = Self.allowed(access)
    if !allowed {
      // Invalidate suspended metadata fetches before clearing visible state.
      requestGeneration += 1
      cancelMetadata?(); cancelMetadata = nil
      fetch = nil
      presentation = LibraryPresentationIndex()
      groups.removeAll(); groupOrder.removeAll()
      loadingPage = false
      total = 0
      loaded = 0
      loading = false
      selection.removeAll()
      scrollOffset = .zero
      scrollAnchorID = nil
      scrollAnchorInset = 0
      scrollResetGeneration += 1
      thumbnails.clear()
      generation += 1
    }
    authorized = allowed
    return allowed
  }
  func changeBackupView(_ next: LibraryBackupView) async {
    guard requestedBackupView != next else { return }
    requestedBackupView = next
    selection.removeAll()
    scrollOffset = .zero
    scrollAnchorID = nil
    scrollAnchorInset = 0
    scrollResetGeneration += 1
    await reload(resetWindow: true)
  }
  func changeFilter(_ next: LibraryFilter) async {
    guard requestedFilter != next else { return }
    requestedFilter = next
    selection.removeAll()
    scrollOffset = .zero
    scrollAnchorID = nil
    scrollAnchorInset = 0
    scrollResetGeneration += 1
    await reload(resetWindow: true)
  }
  func reload(resetWindow: Bool = false) async {
    guard authorized else { return }
    LaunchTrace.mark("library reload start")
    requestGeneration += 1
    cancelMetadata?(); cancelMetadata = nil
    let expected = requestGeneration
    loading = true
    let selectedFilter = requestedFilter
    let selectedView = requestedBackupView
    let receiver = backupReceiver
    let targetRows = resetWindow ? 240 : max(240, loaded)
    let previousCursor = resetWindow ? 0 : presentation.cursor
    let anchor = resetWindow ? nil : scrollAnchorID
    let selected = selection
    let collection = collectionID
    let early = collection == nil && selectedView == .all ? Self.takeEarlyFetch(for: selectedFilter) : nil
    let work = Task.detached(priority: .userInitiated) {
      var fetch: PHFetchResult<PHAsset>
      if let (early, token) = await early?.value {
        fetch = early
        // The model's observer is registered by now: a change before that was
        // not delivered to it, so an advanced token means fetching again.
        if !PHPhotoLibrary.shared().currentChangeToken.isEqual(token) {
          LaunchTrace.mark("early fetch stale")
          fetch = Self.fetchAssets(selectedFilter)
        }
      } else { fetch = Self.fetchAssets(selectedFilter, collection: collection) }
      if selectedView != .all {
        guard let narrowed = await Self.narrow(fetch, to: selectedView, filter: selectedFilter, receiver: receiver) else {
          return (fetch, LibraryPresentationIndex(), Set<String>(), false)
        }
        fetch = narrowed
      }
      let anchorIndex = Self.rawIndex(of: anchor, in: fetch).map { $0 + 1 } ?? 0
      LaunchTrace.mark("library fetch ready")
      var index = LibraryPresentationIndex()
      index.load(fetch, targetRows: targetRows, minimumCursor: max(previousCursor, anchorIndex))
      return (fetch, index, Set(Self.resolveTokens(selected, in: fetch).keys), true)
    }
    cancelMetadata = { work.cancel() }
    let result = await work.value
    LaunchTrace.mark("library fetch done (\(result.0.count) assets)")
    guard expected == requestGeneration, authorized else { return }
    cancelMetadata = nil
    guard result.3 else {
      // The core could not answer: show the whole library rather than a view
      // that would claim photos are or are not backed up.
      loading = false
      requestedBackupView = .all
      message = NSLocalizedString("library_view_failed", comment: "")
      await reload(resetWindow: true)
      return
    }
    backupView = selectedView
    fetch = result.0
    presentation = result.1
    total = result.0.count
    loaded = presentation.rows.count
    filter = selectedFilter
    groups.removeAll(); groupOrder.removeAll()
    // Preserve selected off-screen items while removing deleted/revoked sources.
    selection.formIntersection(result.2.union(selection.subtracting(selected)))
    loadingPage = false
    loading = false
    generation += 1
  }
  func loadMore() {
    guard let fetch, !loading, !loadingPage, presentation.cursor < fetch.count else { return }
    loadingPage = true
    let expected = requestGeneration
    let current = presentation
    Task {
      guard expected == requestGeneration, authorized else { return }
      let work = Task.detached(priority: .userInitiated) {
        var next = current
        let changedCover = next.load(fetch, targetRows: current.rows.count + 240)
        return (next, changedCover)
      }
      cancelMetadata = { work.cancel() }
      let result = await work.value
      guard expected == requestGeneration, authorized else { return }
      cancelMetadata = nil
      presentation = result.0
      loaded = presentation.rows.count
      loadingPage = false
      if result.1 { generation += 1 }
    }
  }
  /// Overview mosaics show the whole library: publish every remaining row with
  /// one bulk read instead of page by page.
  func loadAllRows() async {
    guard let fetch, !loading, !loadingPage, hasMoreRows else { return }
    loadingPage = true
    let expected = requestGeneration, current = presentation
    let job = Task.detached(priority: .userInitiated) {
      var next = current
      next.loadRemaining(fetch)
      return next
    }
    let next = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
    guard expected == requestGeneration, authorized, !Task.isCancelled else { loadingPage = false; return }
    presentation = next
    loaded = next.rows.count
    loadingPage = false
  }
  func previewIndex(of asset: PHAsset) -> Int? {
    index(of: asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier)
  }
  func previewNeighbor(of asset: PHAsset, direction: Int) async -> PHAsset? {
    guard let current = previewIndex(of: asset), current + direction >= 0 else { return nil }
    if current + direction >= loaded, hasMoreRows {
      loadMore()
      for _ in 0..<200 {
        if current + direction < loaded || !loadingPage { break }
        try? await Task.sleep(nanoseconds: 10_000_000)
        if Task.isCancelled { return nil }
      }
    }
    guard let refreshed = previewIndex(of: asset) else { return nil }
    return self.asset(at: refreshed + direction)
  }
  func refreshVisiblePreviews() { contentGeneration &+= 1 }
  /// Calendar covers can address older assets outside the incremental row
  /// window. Expand metadata only; no thumbnail download or backup is started.
  func preparePreviewWindow(containing token: String) async -> PHAsset? {
    guard let fetch, let raw = Self.rawIndex(of: token, in: fetch) else { return nil }
    if let index = index(of: token), index+1 < loaded || !hasMoreRows { return asset(at:index) }
    guard !loading else { return nil }
    requestGeneration &+= 1;cancelMetadata?();cancelMetadata=nil;loadingPage=false
    let expected=requestGeneration, current=presentation
    let job=Task.detached(priority:.userInitiated) {
      var rows=current
      rows.load(fetch,targetRows:max(240,current.rows.count),minimumCursor:min(fetch.count,raw+240))
      return rows
    }
    let next=await withTaskCancellationHandler(operation:{await job.value},onCancel:{job.cancel()})
    guard expected==requestGeneration,authorized,!Task.isCancelled else { return nil }
    presentation=next;loaded=next.rows.count;generation &+= 1
    return index(of:token).flatMap { asset(at:$0) }
  }
  func asset(at index: Int) -> PHAsset? {
    guard let fetch, presentation.rows.indices.contains(index) else { return nil }
    return fetch.object(at: presentation.rows[index].rawIndex)
  }
  /// The fetch index behind a presented row, without faulting its asset.
  func rawIndex(at index: Int) -> Int? {
    presentation.rows.indices.contains(index) ? presentation.rows[index].rawIndex : nil
  }
  func identifier(at index: Int) -> String? {
    guard presentation.rows.indices.contains(index) else { return nil }
    return presentation.rows[index].key
  }
  func index(of identifier: String?) -> Int? {
    guard let identifier else { return nil }
    return presentation.positions[identifier]
  }
  func selectedIndexPaths() -> Set<IndexPath> {
    Set(selection.compactMap { presentation.positions[$0] }.map { IndexPath(item: $0, section: 0) })
  }
  /// The export scheduler expands the accessible burst siblings. Only actual
  /// PhotoKit asset identifiers cross that boundary, never presentation tokens.
  func selectedAssetIdentifiers(_ tokens: Set<String>) async -> [String] {
    guard let fetch else { return [] }
    return await Task.detached(priority: .userInitiated) {
      Array(Self.resolveTokens(tokens, in: fetch).values)
    }.value
  }
  private nonisolated static func resolveTokens(_ tokens: Set<String>, in fetch: PHFetchResult<PHAsset>) -> [String: String] {
    var resolved: [String: String] = [:]
    let ordinary = tokens.filter { !$0.hasPrefix("burst:") }
    if !ordinary.isEmpty {
      let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ordinary), options: photoLibraryFetchOptions())
      assets.enumerateObjects { asset, _, _ in
        if fetch.index(of: asset) != NSNotFound { resolved[asset.localIdentifier] = asset.localIdentifier }
      }
    }
    for token in tokens where token.hasPrefix("burst:") {
      if let index = rawIndex(of: token, in: fetch) { resolved[token] = fetch.object(at: index).localIdentifier }
    }
    return resolved
  }
  private nonisolated static func rawIndex(of token: String?, in fetch: PHFetchResult<PHAsset>) -> Int? {
    guard let token else { return nil }
    let assets: PHFetchResult<PHAsset>
    if token.hasPrefix("burst:") {
      assets = PHAsset.fetchAssets(withBurstIdentifier: String(token.dropFirst(6)), options: photoLibraryFetchOptions())
    } else {
      assets = PHAsset.fetchAssets(withLocalIdentifiers: [token], options: photoLibraryFetchOptions())
    }
    var position: Int?
    assets.enumerateObjects { asset, _, _ in
      let index = fetch.index(of: asset)
      if index != NSNotFound { position = min(position ?? index, index) }
    }
    return position
  }
  /// Resolve only visible groups. The bounded cache contains metadata, not images.
  func visibleGroups(_ assets: [PHAsset]) async -> [String: LibraryGroup] {
    let expected = requestGeneration
    let missing = assets.filter { groups[$0.localIdentifier] == nil }
    let resolved = await Task.detached(priority: .userInitiated) {
      var out: [String: LibraryGroup] = [:]
      for asset in missing {
        var members = [asset]
        if let burst = asset.burstIdentifier {
          let result = PHAsset.fetchAssets(withBurstIdentifier: burst, options: photoLibraryFetchOptions())
          members = result.objects(at: IndexSet(integersIn: 0..<result.count))
        }
        out[asset.localIdentifier] = LibraryGroup(sources: members.map {
          LibrarySource(id: $0.localIdentifier, revision: Self.revision($0))
        }, complete: !members.isEmpty)
      }
      return out
    }.value
    guard !Task.isCancelled, expected == requestGeneration, authorized else { return [:] }
    for (id, group) in resolved where group.complete {
      groups[id] = group
      groupOrder.removeAll { $0 == id }; groupOrder.append(id)
    }
    let visible = Set(assets.map(\.localIdentifier))
    let result = groups.merging(resolved, uniquingKeysWith: { _, new in new }).filter { visible.contains($0.key) }
    while groups.count > 128 || groups.values.reduce(0, { $0 + $1.sources.count }) > 4096 {
      guard !groupOrder.isEmpty else { break }
      groups.removeValue(forKey: groupOrder.removeFirst())
    }
    return result
  }
  nonisolated static func revision(_ asset: PHAsset) -> String {
    String(
      Int64(
        (asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0))
          .timeIntervalSince1970 * 1000))
  }
  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor in
      let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      guard self.applyAuthorization(access), let fetch = self.fetch,
        let details = changeInstance.changeDetails(for: fetch) else { return }
      let structural = !details.hasIncrementalChanges || details.hasMoves
        || !(details.insertedIndexes?.isEmpty ?? true) || !(details.removedIndexes?.isEmpty ?? true)
      if !structural && !self.loading {
        // Availability and metadata callbacks must not recycle the whole grid.
        self.fetch = details.fetchResultAfterChanges
        if !(details.changedIndexes?.isEmpty ?? true) {
          self.groups.removeAll(); self.groupOrder.removeAll()
          self.contentGeneration += 1
        }
        return
      }
      self.changesTask?.cancel()
      self.changesTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await self.reload()
      }
    }
  }
  deinit { if observerRegistered { PHPhotoLibrary.shared().unregisterChangeObserver(self) } }
}

/// Local preheating plus at most three visible iCloud image requests. PhotoKit
/// controls the network fetch size; only requested display images enter our cache.
#if os(iOS)
/// Rebuildable renditions only. Originals and transfer preparation have a separate owner.
actor ThumbnailDiskCache {
  static let shared = ThumbnailDiskCache()
  let directory: URL
  private let defaults: UserDefaults
  private var indexed = false, indexing = false, generation = 0, totalBytes = 0
  private var clearing = false
  private var lastTrim = Date.distantPast
  private var encodingCount = 0
  private var encodingWaiters: [CheckedContinuation<Void,Never>] = []
  private var queuedEncodingBytes = 0
  private var availableWriteBytes: Int64?, capacityChecked = Date.distantPast
  private var entries: [String: (bytes: Int, accessed: Date)] = [:]
  /// The app's cache also owns the decoded bitmap tables; test instances do not.
  private let ownsTables: Bool
  init(directory: URL? = nil, defaults: UserDefaults = .standard) {
    self.directory = directory ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
      .appendingPathComponent("LibraryThumbnails-v1",isDirectory:true)
    self.defaults = defaults
    ownsTables = directory == nil
  }
  private var tableBytes: Int { ownsTables ? ThumbnailTables.usage : 0 }
  private func name(_ key: String) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var bytes: [UInt8] = []; bytes.reserveCapacity(68)
    for byte in SHA256.hash(data: Data(key.utf8)) {
      bytes.append(digits[Int(byte >> 4)]); bytes.append(digits[Int(byte & 15)])
    }
    return String(decoding: bytes, as: UTF8.self) + ".jpg"
  }
  private nonisolated static func scan(_ directory: URL) -> [String: (bytes: Int, accessed: Date)] {
    try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let keys: [URLResourceKey] = [.fileSizeKey,.contentModificationDateKey]
    var result: [String: (bytes: Int, accessed: Date)] = [:]
    for file in (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:keys)) ?? [] {
      guard file.pathExtension == "jpg",let values = try? file.resourceValues(forKeys:Set(keys)) else { continue }
      result[file.lastPathComponent] = (values.fileSize ?? 0,values.contentModificationDate ?? .distantPast)
    }
    return result
  }
  private func adopt(_ scanned: [String: (bytes: Int, accessed: Date)], generation scannedGeneration: Int) {
    guard !indexed, scannedGeneration == generation else { return }
    indexed = true; indexing = false
    // Reads and writes during the scan already updated their own entries.
    entries.merge(scanned) { current, _ in current }
    totalBytes = entries.values.reduce(0) { $0+$1.bytes }
    trim()
  }
  /// Budget accounting needs the full index; serving a read does not. Scanning
  /// tens of thousands of files must never delay the first thumbnails.
  private func indexInBackground() {
    guard !indexed, !indexing else { return }
    indexing = true
    let directory = directory, version = generation
    Task.detached(priority: .utility) { [weak self] in
      let scanned = Self.scan(directory)
      await self?.adopt(scanned, generation: version)
    }
  }
  private func index() {
    guard !indexed else { return }
    adopt(Self.scan(directory), generation: generation)
  }
  /// Phones have ample storage and speed matters more; the default allows a
  /// large rebuildable rendition cache.
  var budgetMB: Int { Self.budgetMB(defaults) }
  nonisolated static func budgetMB(_ defaults: UserDefaults) -> Int {
    let stored = defaults.integer(forKey:"libraryThumbnailBudgetMB")
    return max(64, stored == 0 ? 1024 : stored)
  }
  /// Includes the decoded bitmap tables, which share this cache's budget and clearing.
  func usage() -> Int { index(); return totalBytes + tableBytes }
  func setBudget(_ mb: Int) {
    defaults.set(mb,forKey:"libraryThumbnailBudgetMB")
    if ownsTables { ThumbnailTables.applyBudget(mb*1024*1024) }
    index(); trim()
  }
  func read(_ key: String) async -> (UIImage?, Int) {
    guard !clearing else { return (nil, generation) }
    indexInBackground()
    let filename = name(key), version = generation
    let entry = entries[filename]
    if indexed, entry == nil { return (nil,version) }
    let url = directory.appendingPathComponent(filename)
    let loaded = await Task.detached(priority:.userInitiated) { () -> (UIImage, Int)? in
      guard let data = try? Data(contentsOf:url),let image = UIImage(data:data) else { return nil }
      return (image.preparingForDisplay() ?? image, data.count)
    }.value
    let image = loaded?.0
    guard generation == version else { return (nil,generation) }
    if let loaded { entries[filename] = (entry?.bytes ?? loaded.1,Date()) }
    if image == nil,entry != nil,let corrupt = entries.removeValue(forKey:filename) {
      totalBytes -= corrupt.bytes; try? FileManager.default.removeItem(at:url)
    }
    if image != nil,let entry,Date().timeIntervalSince(entry.accessed) > 60 {
      Task.detached(priority:.utility) { try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:url.path) }
    }
    return (image,version)
  }
  private func releaseEncodingSlot() {
    if encodingWaiters.isEmpty { encodingCount -= 1 }
    else { encodingWaiters.removeFirst().resume() }
  }
  func store(_ image: UIImage,key: String,generation expected: Int) async {
    guard !clearing, expected == generation else { return }; indexInBackground()
    let filename = name(key),url = directory.appendingPathComponent(filename)
    // Encoding must not serialize thousands of foreground reads behind writes.
    let bytes = image.cgImage.map { $0.bytesPerRow*$0.height } ?? Int(image.size.width*image.size.height*image.scale*image.scale*4)
    // Pending JPEG work also retains decoded images. Bound those bytes, not only
    // the number of jobs, so large covers cannot exhaust memory during churn.
    guard entries[filename] == nil,encodingWaiters.count < 1024,queuedEncodingBytes+bytes <= 32*1024*1024 else { return }
    queuedEncodingBytes += bytes
    defer { queuedEncodingBytes -= bytes }
    if encodingCount >= 6 {
      await withCheckedContinuation { encodingWaiters.append($0) }
    } else { encodingCount += 1 }
    defer { releaseEncodingSlot() }
    guard expected == generation,entries[filename] == nil else { return }
    let data = await Task.detached(priority:.utility) { image.jpegData(compressionQuality:0.86) }.value
    guard expected == generation,entries[filename] == nil,let data else { return }
    // Cache writes stop before consuming the last reserve of local disk space.
    if availableWriteBytes == nil || Date().timeIntervalSince(capacityChecked) > 5 {
      availableWriteBytes = (try? directory.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage)
        .map { max(0,$0-128*1024*1024) }
      capacityChecked = Date()
    }
    if let remaining = availableWriteBytes, remaining < data.count { return }
    availableWriteBytes = availableWriteBytes.map { $0-Int64(data.count) }
    do {
      try data.write(to:url,options:.atomic); entries[filename] = (data.count,Date()); totalBytes += data.count
      if indexed, totalBytes + tableBytes > budgetMB*1024*1024 || Date().timeIntervalSince(lastTrim) > 30 { trim() }
    }
    catch { return }
  }
  private func trim() {
    lastTrim = Date()
    var total = totalBytes
    let limit = max(0, budgetMB*1024*1024 - tableBytes), expiry = Date().addingTimeInterval(-30*24*3600)
    guard total > limit || entries.values.contains(where: { $0.accessed < expiry }) else { return }
    for (name,entry) in entries.sorted(by: { $0.value.accessed < $1.value.accessed }) {
      guard total > limit || entry.accessed < expiry else { break }
      try? FileManager.default.removeItem(at:directory.appendingPathComponent(name))
      entries.removeValue(forKey:name); total -= entry.bytes
    }
    totalBytes = total
  }
  @discardableResult func removeAll() async -> Bool {
    guard !clearing else { return false }
    clearing = true
    generation += 1
    let directory = directory
    let removed = await Task.detached(priority: .userInitiated) {
      do {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return true
      } catch { return false }
    }.value
    entries.removeAll(); indexing = false; indexed = removed; totalBytes = 0
    ThumbnailTables.clear()
    clearing = false
    if !removed { index() }
    return removed
  }
}
#endif
/// Decoded thumbnails in one memory-mapped file per size (the Fast Image Cache
/// approach): pixels are stored once, already decoded and row-aligned for Core
/// Animation, and read back as a `CGImage` that points into the mapping, so a
/// hit costs no PhotoKit request, no decode and no copy. Slots are found by
/// hashing the key (identifier plus revision) with a short probe window; each
/// slot's header holds the key tag and a recency tick, so the file needs no
/// separate index and a torn write simply reads as empty. Rebuildable cache
/// data: it lives in Caches and is cleared with thumbnails. A table lives for
/// the process and is never unmapped, because returned images point into it.
final class ThumbnailTable: @unchecked Sendable {
  let side: Int, capacity: Int, rowBytes: Int, entryBytes: Int
  private let headerBytes: Int, length: Int
  private let base: UnsafeMutableRawPointer?
  private let fd: Int32
  let url: URL
  private let lock = NSLock()
  private var tick: UInt32 = 1
  private var used = 0
  private var limitValue: Int
  private static let probes = 8
  nonisolated(unsafe) private static var direct = CGDataProviderDirectCallbacks(version: 0,
    getBytePointer: { info in info.map { UnsafeRawPointer($0) } }, releaseBytePointer: nil,
    getBytesAtPosition: nil, releaseInfo: nil)
  /// Pixels are stored in this colour space. Core Animation converts any other
  /// space to the display's on every commit, so a host whose display is not
  /// sRGB passes the display's own space and converts once while storing.
  let space: CGColorSpace
  private static let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  let writes = DispatchQueue(label: "app.backupduck.thumbnail-table", qos: .utility)
  init(url: URL, side: Int, capacity: Int, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) {
    self.url = url; self.side = side; self.capacity = capacity; limitValue = capacity; self.space = space
    rowBytes = (side * 4 + 63) / 64 * 64
    entryBytes = rowBytes * side
    headerBytes = (capacity * 16 + 16383) / 16384 * 16384
    length = headerBytes + capacity * entryBytes
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    fd = open(url.path, O_RDWR | O_CREAT, 0o644)
    var mapped: UnsafeMutableRawPointer?
    if fd >= 0 {
      var info = stat()
      // A different geometry is a different table; sparse until written.
      if fstat(fd, &info) == 0, Int(info.st_size) != length { ftruncate(fd, 0); ftruncate(fd, off_t(length)) }
      let pointer = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
      if pointer != MAP_FAILED { mapped = pointer }
    }
    base = mapped
    if let base {
      for slot in 0..<capacity {
        tick = max(tick, base.load(fromByteOffset: slot * 16 + 8, as: UInt32.self))
        if base.load(fromByteOffset: slot * 16, as: UInt64.self) != 0 { used += 1 }
      }
    }
  }
  /// The most entries the cache budget allows; when reached, new entries only
  /// replace the least recently used entry in their probe window.
  var limit: Int {
    get { lock.lock(); defer { lock.unlock() }; return limitValue }
    set { lock.lock(); limitValue = min(capacity, max(0, newValue)); lock.unlock() }
  }
  var count: Int { lock.lock(); defer { lock.unlock() }; return used }
  var isFull: Bool { lock.lock(); defer { lock.unlock() }; return used >= limitValue }
  var available: Bool { base != nil }
  static func tag(_ key: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return hash == 0 ? 1 : hash
  }
  private func slot(for tag: UInt64) -> Int? {
    guard let base else { return nil }
    let start = Int(tag % UInt64(capacity))
    for i in 0..<Self.probes {
      let s = (start + i) % capacity
      if base.load(fromByteOffset: s * 16, as: UInt64.self) == tag { return s }
    }
    return nil
  }
  func contains(_ key: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return slot(for: Self.tag(key)) != nil
  }
  /// The stored thumbnail, backed directly by the mapped file.
  func image(_ key: String) -> CGImage? {
    guard let base else { return nil }
    lock.lock()
    guard let s = slot(for: Self.tag(key)) else { lock.unlock(); return nil }
    tick &+= 1
    base.storeBytes(of: tick, toByteOffset: s * 16 + 8, as: UInt32.self)
    lock.unlock()
    // A direct provider hands out the mapped bytes as they are. A data provider
    // probed every entry's pages for readability on creation, which cost more
    // than the rest of an overview scroll frame on the main thread.
    let entry = UnsafeMutableRawPointer(base + headerBytes + s * entryBytes)
    guard let provider = withUnsafePointer(to: &Self.direct, {
      CGDataProvider(directInfo: entry, size: off_t(entryBytes), callbacks: $0)
    }) else { return nil }
    return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
      space: space, bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo), provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
  /// Draws an aspect-filled square into the key's slot on the calling thread.
  func store(_ key: String, image: CGImage) {
    guard let base else { return }
    let tag = Self.tag(key)
    lock.lock()
    if slot(for: tag) != nil { lock.unlock(); return }
    let start = Int(tag % UInt64(capacity)), full = used >= limitValue
    var empty: Int?, oldestSlot: Int?, oldest = UInt32.max
    for i in 0..<Self.probes {
      let s = (start + i) % capacity
      if base.load(fromByteOffset: s * 16, as: UInt64.self) == 0 {
        if empty == nil { empty = s }
        continue
      }
      let t = base.load(fromByteOffset: s * 16 + 8, as: UInt32.self)
      if t < oldest { oldest = t; oldestSlot = s }
    }
    // At the budget limit an entry can only take an occupied slot's place.
    guard let chosen = full ? oldestSlot : empty ?? oldestSlot else { lock.unlock(); return }
    if chosen == empty { used += 1 }
    // Empty while drawing: a reader never adopts a half-written slot.
    base.storeBytes(of: UInt64(0), toByteOffset: chosen * 16, as: UInt64.self)
    lock.unlock()
    guard let context = CGContext(data: base + headerBytes + chosen * entryBytes, width: side, height: side,
      bitsPerComponent: 8, bytesPerRow: rowBytes, space: space, bitmapInfo: Self.bitmapInfo)
    else { return }
    let w = CGFloat(image.width), h = CGFloat(image.height), edge = CGFloat(side)
    let factor = max(edge / max(1, w), edge / max(1, h))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: (edge - w * factor) / 2, y: (edge - h * factor) / 2,
      width: w * factor, height: h * factor))
    lock.lock()
    tick &+= 1
    base.storeBytes(of: tick, toByteOffset: chosen * 16 + 8, as: UInt32.self)
    base.storeBytes(of: tag, toByteOffset: chosen * 16, as: UInt64.self)
    lock.unlock()
  }
  /// Bytes held by stored entries. Counted from slot headers: the sparse file's
  /// allocated blocks lag behind dirty mapped pages until they are written back.
  var usage: Int {
    lock.lock(); defer { lock.unlock() }
    return used == 0 ? 0 : headerBytes + used * entryBytes
  }
  /// Forgets every entry and returns the pixel blocks to the file system while
  /// the mapping stays valid for any image still on screen.
  func clear() {
    guard let base else { return }
    lock.lock(); defer { lock.unlock() }
    memset(base, 0, headerBytes)
    used = 0
    var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: off_t(headerBytes), fp_length: off_t(length - headerBytes))
    _ = fcntl(fd, F_PUNCHHOLE, &hole)
  }
}

#if os(iOS)
/// The overview table holds every library item at mosaic size; the detail table
/// keeps recently used month-overview thumbnails. Entry sizes follow this
/// device's widest possible grid (iPhone SE to iPad), rounded up to 16 pixels,
/// so no device stores more pixels than it shows or upscales its mosaics.
enum ThumbnailTables {
  /// `-no-thumbnail-table` disables the tables for side-by-side measurement.
  static let enabled = !ProcessInfo.processInfo.arguments.contains("-no-thumbnail-table")
  static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ThumbnailTables", isDirectory: true)
  /// Pixels of one tile at `columns` across the widest grid this device shows:
  /// portrait phone width, or the long edge on iPad.
  static func tilePixels(columns: CGFloat) -> Int {
    let screen = UIScreen.main
    let width = UIDevice.current.userInterfaceIdiom == .pad
      ? max(screen.bounds.width, screen.bounds.height) : min(screen.bounds.width, screen.bounds.height)
    let pixels = width / columns * screen.scale
    return max(32, Int((pixels / 16).rounded(.up)) * 16)
  }
  /// The densest (31-column) and month (15-column) overviews.
  static let overviewSide = tilePixels(columns: 31), detailSide = tilePixels(columns: 15)
  static let overview = table("overview", side: overviewSide, capacity: 98_304, share: overviewShare)
  static let detail = table("detail", side: detailSide, capacity: 8_192, share: detailShare)
  static let overviewShare = 0.5, detailShare = 0.2
  private static func table(_ name: String, side: Int, capacity: Int, share: Double) -> ThumbnailTable {
    let table = ThumbnailTable(url: directory.appendingPathComponent("\(name)-\(side).table"), side: side, capacity: capacity)
    table.limit = limit(table, share: share, budget: ThumbnailDiskCache.budgetMB(.standard) * 1024 * 1024)
    return table
  }
  private static func limit(_ table: ThumbnailTable, share: Double, budget: Int) -> Int {
    Int(Double(budget) * share) / table.entryBytes
  }
  /// Shares of the thumbnail cache budget. The overview gets the largest share
  /// because it serves the whole library; renditions use what the tables leave.
  static func applyBudget(_ bytes: Int) {
    for (table, share) in [(overview, overviewShare), (detail, detailShare)] {
      let limit = limit(table, share: share, budget: bytes)
      table.limit = limit
      // A lowered budget starts the table over; it refills newest first.
      if table.count > limit { table.clear() }
    }
  }
  static func key(_ id: String, revision: Int64) -> String { "\(id)|\(revision)" }
  /// The sharpest stored thumbnail for a displayed pixel width.
  static func image(_ id: String, revision: Int64, pixels: CGFloat) -> CGImage? {
    guard enabled, pixels <= CGFloat(detailSide) else { return nil }
    let key = key(id, revision: revision)
    if pixels > CGFloat(overviewSide), let sharp = detail.image(key) { return sharp }
    return overview.image(key)
  }
  /// Any stored thumbnail, sharpest first, to show while a larger one loads.
  static func placeholder(_ id: String, revision: Int64) -> CGImage? {
    guard enabled else { return nil }
    let key = key(id, revision: revision)
    return detail.image(key) ?? overview.image(key)
  }
  /// Stores a delivered small thumbnail in each table it is sharp enough for.
  static func remember(_ id: String, revision: Int64, pixels: CGFloat, image: CGImage) {
    guard enabled, pixels <= CGFloat(detailSide) else { return }
    let key = key(id, revision: revision), edge = min(image.width, image.height)
    overview.writes.async {
      if edge * 5 >= overviewSide * 4 { overview.store(key, image: image) }
      if pixels > CGFloat(overviewSide), edge * 5 >= detailSide * 4 { detail.store(key, image: image) }
    }
  }
  /// The PhotoKit request size that fills an overview entry from local renditions.
  static var prefillPixels: CGFloat { CGFloat(max(64, overviewSide * 2)) }
  static var usage: Int { overview.usage + detail.usage }
  static func clear() { overview.clear(); detail.clear() }
}

/// Bounded background bitmap work keeps native image callbacks cheap on the UI
/// actor. The renderer produces standard-range pixels at the requested tier.
private enum ThumbnailImagePreparation {
  struct Result { let image: UIImage; let small: UIImage }
  static let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "app.backupduck.thumbnail-preparation"
    queue.maxConcurrentOperationCount = min(4, ProcessInfo.processInfo.activeProcessorCount)
    queue.qualityOfService = .userInitiated
    return queue
  }()
  /// Dense mosaics request PhotoKit's own small renditions, which arrive close to
  /// their display size. Decoding them needs no redraw or bounded render queue.
  static let light = DispatchQueue(label: "app.backupduck.thumbnail-light", qos: .userInitiated,
    attributes: .concurrent)
  static func prepareSmall(_ image: UIImage) async -> Result {
    await withCheckedContinuation { continuation in
      light.async {
        let ready = autoreleasepool { image.preparingForDisplay() ?? image }
        continuation.resume(returning: Result(image: ready, small: ready))
      }
    }
  }
  static func prepare(_ image: UIImage, target: CGSize, mode: PHImageContentMode,
    prefetch: Bool) async -> Result {
    await withCheckedContinuation { continuation in
      let work = BlockOperation {
        let result = autoreleasepool {
          let format = UIGraphicsImageRendererFormat()
          format.scale = 1; format.preferredRange = .standard
          func resized(_ source: UIImage, to target: CGSize, fill: Bool) -> UIImage {
            let ratio = fill
              ? max(target.width / max(1, source.size.width), target.height / max(1, source.size.height))
              : min(target.width / max(1, source.size.width), target.height / max(1, source.size.height))
            let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
            let canvas = fill ? target : size
            return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
              source.draw(in: CGRect(x: (canvas.width-size.width)/2, y: (canvas.height-size.height)/2,
                width: size.width, height: size.height))
            }
          }
          let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
          let bounded = pixels.width > target.width || pixels.height > target.height
            ? resized(image, to: target, fill: mode == .aspectFill) : image
          let ready = bounded.preparingForDisplay() ?? bounded
          let small = target.width == 64 && mode == .aspectFill
            && ready.size.width * ready.scale == 64 && ready.size.height * ready.scale == 64
            ? ready : resized(ready, to: CGSize(width: 64, height: 64), fill: true)
          return Result(image: ready, small: small)
        }
        continuation.resume(returning: result)
      }
      work.queuePriority = prefetch ? .low : .high
      work.qualityOfService = prefetch ? .utility : .userInitiated
      queue.addOperation(work)
    }
  }
}

#endif

/// Opt-in launch timing (launch argument `-launch-trace`) for device diagnosis.
/// Milliseconds since process start are printed to the console; nothing is
/// recorded otherwise.
enum LaunchTrace {
  static let enabled = ProcessInfo.processInfo.arguments.contains("-launch-trace")
  private static let processStart: Double = {
    var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let start = info.kp_proc.p_un.__p_starttime
    return Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
  }()
  private static var marked: Set<String> = []
  private static let lock = NSLock()
  static func mark(_ event: String, once: Bool = true) {
    guard enabled else { return }
    lock.lock(); defer { lock.unlock() }
    if once, !marked.insert(event).inserted { return }
    let ms = (Date().timeIntervalSince1970 - processStart) * 1000
    print(String(format: "[launch] %7.1f ms %@", ms, event))
  }
}

@MainActor final class ThumbnailPipeline {
  enum Priority: Int { case prefetch, visible }
  private let manager: PHCachingImageManager
  #if os(iOS)
  var disk: ThumbnailDiskCache? = .shared
  #endif
  private let cache = NSCache<NSString, LibraryImage>()
  private let posters = NSCache<NSString, LibraryImage>()
  private let smallPosters = NSCache<NSString, LibraryImage>()
  private var preheated: [String: PHAsset] = [:]
  private var preheatSize = CGSize.zero
  private struct Pending {
    let asset: PHAsset
    let target: CGSize
    let key: NSString
    let contentMode: PHImageContentMode
    let completion: (LibraryImage?, Bool) -> Void
    var native: PHImageRequestID = PHInvalidImageRequestID
    var cloud = false
    var hasImage = false
    var retriedFast = false
    var triedSmallFallback = false
    var needsCloud = false
    var cancelledLarge = false
    var diskGeneration = 0
    var priority: Priority = .visible
    var queued = false
    var resultVersion = 0
    var requestVersion = 0
    var delivery: Task<Void, Never>?
  }
  private var pending: [PHImageRequestID: Pending] = [:]
  private var owners: [PHImageRequestID:PHImageRequestID] = [:]
  private var subscribers: [PHImageRequestID:[PHImageRequestID:(LibraryImage?,Bool)->Void]] = [:]
  private var inFlight: [NSString:PHImageRequestID] = [:]
  private var localQueue: [PHImageRequestID] = []
  private var localCursor = 0
  private var prefetchQueue: [PHImageRequestID] = []
  private var prefetchCursor = 0
  private var writebackBytes = 0, writebackCount = 0
  private var activeLocal: Set<PHImageRequestID> = []
  private var localPumpScheduled = false
  private var cloudQueue: [PHImageRequestID] = []
  private var activeCloud: Set<PHImageRequestID> = []
  private var policyObservation: AnyCancellable?
  private var cacheObservation: AnyCancellable?
  private var sequence: PHImageRequestID = 0
  private(set) var epoch = 0
  private(set) var requestsStarted = 0
  private(set) var requestsCancelled = 0
  init(cacheBudget: Int = 64 * 1024 * 1024, manager: PHCachingImageManager = PHCachingImageManager()) {
    self.manager = manager
    cache.totalCostLimit = cacheBudget
    // Tiny mosaics can expose thousands of 64-pixel images. Keep the byte
    // budget authoritative instead of evicting still-visible tiles at 500 items.
    cache.countLimit = 8192
    smallPosters.totalCostLimit = min(16 * 1024 * 1024,cacheBudget/4); smallPosters.countLimit = 8192
    #if os(macOS)
    // Without the iPhone's 64-pixel fallback tier, every tier change would show
    // blank tiles. Keep the last delivered image per asset for the visible set of
    // the densest step, so a density change always has pixels to show at once.
    posters.countLimit = 6000; posters.totalCostLimit = 192 * 1024 * 1024
    #else
    posters.countLimit = 80; posters.totalCostLimit = 24 * 1024 * 1024
    #endif
    manager.allowsCachingHighQualityImages = true
    policyObservation = PreviewNetworkPolicy.shared.$choice.dropFirst().sink { [weak self] _ in
      self?.clear()
      #if os(iOS)
      if let disk = self?.disk { Task { await disk.removeAll() } }
      #endif
    }
    cacheObservation = NotificationCenter.default.publisher(for:Notification.Name("LibraryThumbnailsCleared"))
      .sink { [weak self] _ in self?.clear() }
  }
  /// PhotoKit cuts thumbnails up to 352 px from its stored small rendition
  /// (about 5 ms each); slightly larger requests decode the original (about
  /// 35 ms each, measured on device by other PhotoKit grids). Requests just
  /// above that edge, such as three iPhone columns, use the fast rendition.
  static let renditionEdge: CGFloat = 352
  func size(_ requested: CGFloat) -> CGSize {
    var edge = min(1024, max(64, (requested / 64).rounded(.up) * 64))
    if requested > Self.renditionEdge, requested <= 460 { edge = Self.renditionEdge }
    return CGSize(width: edge, height: edge)
  }
  private func smallKey(_ asset: PHAsset) -> NSString {
    "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))" as NSString
  }
  func poster(for asset: PHAsset) -> LibraryImage? {
    if let sample = asset as? any PreviewSample { return sample.previewImage }
    return posters.object(forKey:smallKey(asset)) ?? smallPosters.object(forKey: smallKey(asset))
  }
  /// The caller supplies already prepared 64-pixel fallback pixels.
  private func rememberSmall(_ image: LibraryImage, asset: PHAsset) {
    #if os(iOS)
    smallPosters.setObject(image, forKey: smallKey(asset), cost: imageCost(image, target: CGSize(width: 64, height: 64)))
    #endif
  }
  private func imageCost(_ image: LibraryImage, target: CGSize) -> Int {
    #if os(iOS)
    return image.cgImage.map { $0.bytesPerRow*$0.height } ?? Int(image.size.width*image.size.height*image.scale*image.scale*4)
    #else
    return Int(target.width*target.height*4)
    #endif
  }
  private func options(network: Bool = false, video: Bool = false, pixels: CGFloat = 320) -> PHImageRequestOptions {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = network
    options.deliveryMode = pixels <= 128 ? .fastFormat : video ? .highQualityFormat : .opportunistic
    options.resizeMode = pixels <= 128 ? .fast : .exact
    return options
  }
  @discardableResult func request(
    _ asset: PHAsset, pixels: CGFloat, contentMode: PHImageContentMode = .aspectFill,
    priority: Priority = .visible, completion: @escaping (LibraryImage?, Bool) -> Void
  ) -> PHImageRequestID {
    if let sample = asset as? any PreviewSample {
      completion(sample.previewImage, false)
      return PHInvalidImageRequestID
    }
    let target = size(pixels)
    let key = "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(Int(target.width))|\(contentMode.rawValue)" as NSString
    if let image = cache.object(forKey: key) {
      completion(image, false)
      return PHInvalidImageRequestID
    }
    #if os(iOS)
    let fallback = target.width <= 128 ? smallPosters.object(forKey:smallKey(asset)) : poster(for:asset)
    #else
    let fallback = poster(for:asset)
    #endif
    if let fallback { completion(fallback,false) }
    sequence = sequence == Int32.max ? 1 : sequence + 1
    let id = sequence
    if let owner = inFlight[key],pending[owner] != nil {
      owners[id] = owner; subscribers[owner,default:[:]][id] = completion
      if priority == .visible, pending[owner]?.priority == .prefetch {
        pending[owner]?.priority = .visible
        if pending[owner]?.queued == true { localQueue.append(owner); pumpLocal() }
      }
      return id
    }
    requestsStarted += 1
    owners[id] = id; subscribers[id] = [id:completion]; inFlight[key] = id
    pending[id] = Pending(asset: asset, target: target, key: key, contentMode: contentMode,
      completion:{ [weak self] image,cloud in
        // Snapshot/cell/preheat callers share one rendition request and cancel independently.
        let callbacks = Array(self?.subscribers[id]?.values ?? Dictionary<PHImageRequestID,(LibraryImage?,Bool)->Void>().values)
        callbacks.forEach { $0(image,cloud) }
      })
    pending[id]?.priority = priority
    enqueueLocal(id)
    return id
  }
  /// Disk hits share admission and memory limits with native loads. A large
  /// cache revisit must not decode every queued cover before it can be shown.
  private func startLocal(_ id: PHImageRequestID) {
    guard let item = pending[id] else { return }
    #if os(iOS)
    // PhotoKit's small renditions are faster than our JPEG round trip.
    if let disk, item.target.width > 128 {
      let asset = item.asset, target = item.target, priority = item.priority
      let version = epoch, cacheKey = item.key as String
      Task(priority: priority == .visible ? .userInitiated : .utility) { [weak self] in
        let (image,generation) = await disk.read(cacheKey)
        guard let self,self.epoch == version,let item = self.pending[id] else { return }
        self.pending[id]?.diskGeneration = generation
        if let image {
          let prepared = await ThumbnailImagePreparation.prepare(image, target: item.target,
            mode: item.contentMode, prefetch: item.priority == .prefetch)
          guard self.epoch == version, self.pending[id] != nil else { return }
          LaunchTrace.mark("first disk thumbnail")
          self.cache.setObject(prepared.image, forKey: item.key, cost: self.imageCost(prepared.image, target: item.target))
          self.rememberSmall(prepared.small, asset: item.asset)
          item.completion(prepared.image, false); self.finish(id)
          self.activeLocal.remove(id); self.pumpLocal(); self.pumpCloud()
        } else {
          let fallbackKey = "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|64|\(PHImageContentMode.aspectFill.rawValue)"
          if target.width > 64 {
            let (fallback,_) = await disk.read(fallbackKey)
            guard self.epoch == version,self.pending[id] != nil else { return }
            if let fallback { self.rememberSmall(fallback,asset:asset); item.completion(fallback,false) }
          }
          self.start(id, network: false)
        }
      }
    } else { start(id, network: false) }
    #else
    start(id, network: false)
    #endif
  }
  private func enqueueLocal(_ id: PHImageRequestID) {
    guard let item = pending[id] else { return }
    pending[id]?.queued = true
    if item.priority == .prefetch { prefetchQueue.append(id) } else { localQueue.append(id) }
    pumpLocal()
  }
  private func estimatedBytes(_ item: Pending) -> Int {
    Int(item.target.width * item.target.height * 4) + (item.target.width == 64 ? 0 : 64 * 64 * 4)
  }
  private func hasLocalCapacity(for id: PHImageRequestID) -> Bool {
    guard let item = pending[id] else { return true }
    let active = activeLocal.union(activeCloud)
    let bytes = active.compactMap { pending[$0] }.reduce(writebackBytes) { $0 + estimatedBytes($1) }
    return writebackCount + active.count < 512 && bytes + estimatedBytes(item) <= 32 * 1024 * 1024
  }
  private func nextLocal() -> PHImageRequestID? {
    while localCursor < localQueue.count {
      let id = localQueue[localCursor]
      if let item = pending[id], item.queued, item.priority == .visible { return id }
      localCursor += 1
    }
    while prefetchCursor < prefetchQueue.count {
      let id = prefetchQueue[prefetchCursor]
      if let item = pending[id], item.queued, item.priority == .prefetch {
        // Speculation cannot occupy every native slot before the viewport moves.
        let active = activeLocal.filter { pending[$0]?.priority == .prefetch }.count
        return active < (item.target.width <= 128 ? 24 : 4) ? id : nil
      }
      prefetchCursor += 1
    }
    return nil
  }
  /// Visible work overtakes speculative warmup. Native submissions are batched;
  /// bitmap preparation and durable cache writes have their own bounded work.
  /// Small mosaic renditions are cheap and numerous; larger ones keep the
  /// tighter bound that protects memory and native decoding.
  private func hasSlot(for id: PHImageRequestID) -> Bool {
    guard let item = pending[id] else { return true }
    if item.target.width <= 128 { return activeLocal.count < 96 }
    return activeLocal.filter { (pending[$0]?.target.width ?? 0) > 128 }.count < 24
  }
  private func pumpLocal() {
    guard !localPumpScheduled, let next = nextLocal(), hasSlot(for: next),
      hasLocalCapacity(for: next) else { return }
    localPumpScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.localPumpScheduled = false
      var submitted = 0
      while submitted < 32, let id = self.nextLocal(), self.hasSlot(for: id),
        self.hasLocalCapacity(for: id) {
        if self.pending[id]?.priority == .visible { self.localCursor += 1 }
        else { self.prefetchCursor += 1 }
        self.pending[id]?.queued = false
        self.activeLocal.insert(id)
        self.startLocal(id)
        submitted += 1
      }
      if self.localCursor > 256 || self.localCursor == self.localQueue.count {
        self.localQueue.removeFirst(self.localCursor); self.localCursor = 0
      }
      if self.prefetchCursor > 256 || self.prefetchCursor == self.prefetchQueue.count {
        self.prefetchQueue.removeFirst(self.prefetchCursor); self.prefetchCursor = 0
      }
      self.pumpLocal()
    }
  }
  private func start(_ id: PHImageRequestID, network: Bool, forceQuality: Bool = false, smallFallback: Bool = false) {
    guard let item = pending[id] else { return }
    pending[id]?.cloud = network
    pending[id]?.requestVersion += 1
    let attempt = pending[id]?.requestVersion
    let requestOptions = options(network: network, video: item.asset.mediaType == .video,
      pixels: smallFallback ? 64 : forceQuality ? 320 : item.target.width)
    // Fast format delivers exactly once, even when its result is marked degraded.
    // Waiting for another result leaves all local concurrency slots occupied.
    let singleResult = requestOptions.deliveryMode != .opportunistic
    let request = manager.requestImage(for: item.asset, targetSize: smallFallback ? CGSize(width: 64,height: 64) : item.target,
      contentMode: item.contentMode, options: requestOptions) { [weak self] image, info in
      let cancelled = info?[PHImageCancelledKey] as? Bool == true
      let degraded = info?[PHImageResultIsDegradedKey] as? Bool == true
      let error = info?[PHImageErrorKey] as? NSError
      let cloud = info?[PHImageResultIsInCloudKey] as? Bool == true
        || (error?.domain == PHPhotosErrorDomain && error?.code == PHPhotosError.Code.networkAccessRequired.rawValue)
      Task { @MainActor in
        guard let self, self.pending[id]?.requestVersion == attempt else { return }
        let previous = self.pending[id]?.delivery
        self.pending[id]?.delivery = Task { @MainActor [weak self] in
          await previous?.value
          guard self?.pending[id]?.requestVersion == attempt else { return }
          await self?.receive(id, network: network, image: image, cancelled: cancelled,
            degraded: degraded, cloud: cloud, singleResult: singleResult, smallFallback: smallFallback)
        }
      }
    }
    pending[id]?.native = request
  }
  /// Serialize each native request's callbacks across background preparation;
  /// a final nil result must not discard a preview that is still being decoded.
  private func receive(_ id: PHImageRequestID, network: Bool, image: LibraryImage?,
    cancelled: Bool, degraded: Bool, cloud: Bool, singleResult: Bool, smallFallback: Bool) async {
    guard let item = pending[id], item.cloud == network else { return }
    if !smallFallback, !network, (image == nil || cancelled), item.target.width > 128,
      !item.hasImage, !item.triedSmallFallback {
      pending[id]?.triedSmallFallback = true; pending[id]?.needsCloud = cloud; pending[id]?.cancelledLarge = cancelled
      // PhotoKit may have a local tiny rendition while the larger crop needs
      // the cloud. Reuse the same admission slot and never cache it as large.
      start(id,network: false,smallFallback: true)
      return
    }
    if smallFallback {
      if let image {
        #if os(iOS)
        let version = epoch
        let prepared = await ThumbnailImagePreparation.prepare(image,target: CGSize(width: 64,height: 64),mode: .aspectFill,prefetch: item.priority == .prefetch)
        guard epoch == version, pending[id] != nil else { return }
        let image = prepared.image
        rememberSmall(image,asset: item.asset)
        #endif
        pending[id]?.hasImage = true
        item.completion(image,item.needsCloud)
      }
      activeLocal.remove(id); pumpLocal()
      if (item.needsCloud || item.cancelledLarge) && PreviewNetworkPolicy.shared.allowed && item.priority == .visible {
        cloudQueue.append(id); pumpCloud()
      } else {
        if image == nil { item.completion(nil,item.needsCloud) }
        finish(id)
      }
      return
    }
    if cancelled { self.finish(id); self.activeLocal.remove(id); self.activeCloud.remove(id); self.pumpLocal(); self.pumpCloud(); return }
    if let raw = image {
      #if os(iOS)
      self.pending[id]?.resultVersion += 1
      let resultVersion = self.pending[id]?.resultVersion, version = self.epoch
      let prepared = item.target.width <= 128
        ? await ThumbnailImagePreparation.prepareSmall(raw)
        : await ThumbnailImagePreparation.prepare(raw, target: item.target,
          mode: item.contentMode, prefetch: item.priority == .prefetch)
      guard self.epoch == version, self.pending[id]?.resultVersion == resultVersion else { return }
      let image = prepared.image
      self.rememberSmall(prepared.small, asset: item.asset)
      #else
      let image = raw
      #endif
      self.pending[id]?.hasImage = true
      LaunchTrace.mark("first native thumbnail (\(Int(item.target.width)) px)")
      let posterKey = self.smallKey(item.asset)
      let old = self.posters.object(forKey:posterKey)
      #if os(iOS)
      if old == nil || image.size.width*image.scale >= old!.size.width*old!.scale {
        self.posters.setObject(image,forKey:posterKey,cost:self.imageCost(image,target:item.target))
      }
      #else
      // Keep the sharpest delivery as the cross-tier fallback.
      if old == nil || image.size.width >= old!.size.width {
        self.posters.setObject(image,forKey:posterKey,cost:self.imageCost(image,target:item.target))
      }
      #endif
      if !degraded || singleResult {
        self.cache.setObject(image, forKey: item.key, cost: self.imageCost(image,target: item.target))
        #if os(iOS)
        if let disk = self.disk, item.target.width > 128 {
          let key = item.key as String, generation = item.diskGeneration
          let small = prepared.small
          let smallKey = "\(item.asset.localIdentifier)|\(PhotoLibraryModel.revision(item.asset))|64|\(PHImageContentMode.aspectFill.rawValue)"
          let bytes = self.imageCost(image, target: item.target)
            + (key == smallKey ? 0 : self.imageCost(small, target: CGSize(width: 64, height: 64)))
          self.writebackBytes += bytes; self.writebackCount += 1
          Task(priority: .utility) { [weak self] in
            if key != smallKey { await disk.store(small, key: smallKey, generation: generation) }
            await disk.store(image, key: key, generation: generation)
            guard let self else { return }
            self.writebackBytes -= bytes; self.writebackCount -= 1
            self.pumpLocal(); self.pumpCloud()
          }
        }
        #endif
      }
      item.completion(image, false)
    }
    guard !degraded || singleResult else { return }
    if image == nil && !cloud && !network && item.target.width <= 128 && !item.retriedFast {
      // Fast format can have no existing local rendition. Try the same small
      // target with opportunistic delivery once, without fetching an original.
      self.pending[id]?.retriedFast = true; self.start(id,network: false,forceQuality: true); return
    }
    if !network { self.activeLocal.remove(id); self.pumpLocal() }
    if image == nil && cloud && !network {
      item.completion(nil, true)
      if PreviewNetworkPolicy.shared.allowed, item.priority == .visible {
        self.cloudQueue.append(id); self.pumpCloud()
      } else {
        // Speculative off-screen work remains local; visible requests own
        // the bounded cloud slots.
        self.finish(id)
      }
    } else {
      if image == nil && !item.hasImage { item.completion(nil, cloud) }
      self.finish(id)
      self.activeCloud.remove(id)
      self.pumpCloud()
    }
  }
  private func pumpCloud() {
    while activeCloud.count < 3, let next = cloudQueue.first, hasLocalCapacity(for: next) {
      let id = cloudQueue.removeFirst()
      guard pending[id] != nil else { continue }
      activeCloud.insert(id)
      start(id, network: true)
    }
  }
  private func finish(_ id: PHImageRequestID) {
    if let item = pending.removeValue(forKey:id) {
      item.delivery?.cancel()
      if inFlight[item.key] == id { inFlight.removeValue(forKey:item.key) }
    }
    for subscriber in subscribers.removeValue(forKey:id)?.keys ?? Dictionary<PHImageRequestID,(LibraryImage?,Bool)->Void>().keys {
      owners.removeValue(forKey:subscriber)
    }
  }
  func cancel(_ request: PHImageRequestID) {
    guard let owner = owners.removeValue(forKey:request) else { return }
    subscribers[owner]?.removeValue(forKey:request)
    guard subscribers[owner]?.isEmpty != false,let item = pending[owner] else { return }
    requestsCancelled += 1
    finish(owner)
    if item.native != PHInvalidImageRequestID { manager.cancelImageRequest(item.native) }
    activeLocal.remove(owner); pumpLocal()
    cloudQueue.removeAll { $0 == owner }; activeCloud.remove(owner); pumpCloud()
  }
  func preheat(_ assets: [PHAsset], pixels: CGFloat) {
    let target = size(pixels)
    if preheatSize != target {
      manager.stopCachingImagesForAllAssets()
      preheated.removeAll()
      preheatSize = target
    }
    let next = Dictionary(assets.prefix(pixels <= 128 ? 3072 : 48).map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
    let removed = preheated.filter { next[$0.key] == nil }.map(\.value)
    let added = next.filter { preheated[$0.key] == nil }.map(\.value)
    // Match the visible request's quality while keeping preheating batched.
    for video in [false, true] {
      let old = removed.filter { ($0.mediaType == .video) == video }
      let fresh = added.filter { ($0.mediaType == .video) == video }
      if !old.isEmpty {
        manager.stopCachingImages(for: old, targetSize: target, contentMode: .aspectFill,
          options: options(video: video,pixels: target.width))
      }
      if !fresh.isEmpty {
        manager.startCachingImages(for: fresh, targetSize: target, contentMode: .aspectFill,
          options: options(video: video,pixels: target.width))
      }
    }
    preheated = next
  }
  func clear() {
    epoch &+= 1
    let requests = pending.values.map(\.native)
    pending.values.forEach { $0.delivery?.cancel() }
    pending.removeAll(); owners.removeAll(); subscribers.removeAll(); inFlight.removeAll()
    cloudQueue.removeAll(); activeCloud.removeAll()
    localQueue.removeAll(); localCursor = 0; activeLocal.removeAll()
    prefetchQueue.removeAll(); prefetchCursor = 0
    requests.filter { $0 != PHInvalidImageRequestID }.forEach { manager.cancelImageRequest($0) }
    cache.removeAllObjects(); posters.removeAllObjects(); smallPosters.removeAllObjects()
    manager.stopCachingImagesForAllAssets()
    preheated.removeAll()
  }
}

func taskSymbol(_ state: String?) -> String {
  switch state {
  case "received": "checkmark.circle"
  case "received_previous": "checkmark.circle"
  case "partial": "circle.dotted"
  case "scheduled", "running": "arrow.up.circle"
  case "waiting": "clock.arrow.circlepath"
  case "failed": "exclamationmark.circle"
  case "paused": "pause.circle"
  case "ignored": "minus.circle"
  case "scanned": "photo.stack"
  case "preparing": "arrow.down.circle"
  case "queued": "clock"
  default: "circle.dashed"
  }
}

func videoDurationLabel(_ duration: TimeInterval) -> String {
  let seconds = max(0, Int(duration.rounded()))
  let hours = seconds / 3600
  let minutes = (seconds / 60) % 60
  let remainder = seconds % 60
  return hours > 0
    ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
    : String(format: "%d:%02d", minutes, remainder)
}

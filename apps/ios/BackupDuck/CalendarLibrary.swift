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
    grid.requestImage = { [weak c] asset, pixels, done in
      guard let c, let photo = c.asset(asset.id) else {
        done(nil, false)
        return {}
      }
      let request = c.parent.library.thumbnails.request(
        photo, pixels: pixels,
        contentMode: c.controller?.originalAspect == true && c.controller?.level == .all
          ? .aspectFit : .aspectFill
      ) { image, cloud in done(image, cloud) }
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
    grid.onSelection = { [weak c] selection in c?.parent.library.selection = selection }
    grid.onPreview = { [weak c] item, frame in
      guard let c, let asset = c.asset(item.id) else { return }
      let version = c.epoch
      Task { [weak c] in
        guard let c, let prepared = await c.parent.library.preparePreviewWindow(containing: item.id)
        else { return }
        guard c.epoch == version, c.controller?.view.window != nil else { return }
        guard prepared.burstIdentifier == asset.burstIdentifier,
          prepared.localIdentifier == asset.localIdentifier || asset.burstIdentifier != nil
        else { return }
        c.previewOrigin = prepared.localIdentifier
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
    return UINavigationController(rootViewController: grid)
  }
  func updateUIViewController(_ nav: UINavigationController, context: Context) {
    let c = context.coordinator
    c.parent = self
    guard let grid = c.controller else { return }
    grid.loadViewIfNeeded()
    grid.canBackup = model.pairing != nil && !model.importing
    grid.displayedTotal = library.total
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
    coordinator.refresh.cancel()
    coordinator.parent.library.previewFrame = nil
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
    init(_ parent: IOSCalendarLibrary) { self.parent = parent }
    func asset(_ id: String) -> PHAsset? {
      guard let index = positions[id], let fetch, index < fetch.count else { return nil }
      return fetch.object(at: index)
    }
    func rebuild() {
      work?.cancel()
      epoch += 1
      let version = epoch
      fetch = parent.library.fetch
      positions = [:]
      guard let fetch else {
        controller?.replaceAssets([])
        return
      }
      controller?.indexing = true
      controller?.updateChrome()
      work = Task { [weak self] in
        let job = Task.detached(priority: .userInitiated) {
          var rows: [CalendarGridAsset] = []
          var positions: [String: Int] = [:]
          var rowPositions: [String: Int] = [:]
          for raw in 0..<fetch.count {
            if Task.isCancelled { return (rows, positions) }
            let asset = fetch.object(at: raw)
            let key = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
            if let old = positions[key] {
              if asset.representsBurst {
                positions[key] = raw
                if let i = rowPositions[key] {
                  rows[i] = CalendarGridAsset(
                    id: key, date: asset.creationDate,
                    aspect: CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight)),
                    videoDuration: nil, live: asset.mediaSubtypes.contains(.photoLive))
                }
              }
              _ = old
              continue
            }
            positions[key] = raw
            rowPositions[key] = rows.count
            rows.append(
              CalendarGridAsset(
                id: key, date: asset.creationDate,
                aspect: CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight)),
                videoDuration: asset.mediaType == .video ? videoDurationLabel(asset.duration) : nil,
                live: asset.mediaSubtypes.contains(.photoLive)))
          }
          return (Array(rows.reversed()), positions)
        }
        let result = await withTaskCancellationHandler(
          operation: { await job.value }, onCancel: { job.cancel() })
        guard let self, !Task.isCancelled, self.epoch == version else { return }
        self.positions = result.1
        self.controller?.indexing = false
        self.controller?.replaceAssets(result.0)
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
    func refreshStates() {
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

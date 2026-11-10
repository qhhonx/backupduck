import AppKit
import AVKit
import ImageIO
import SwiftUI

/// File-backed adapter for the shared window-scoped viewer.
@MainActor enum MacFolderViewer {
  static func open(_ photo: FolderPhoto, context: [FolderPhoto], folders: FolderSources) {
    MacPhotoViewerWindow.openFolder(photo, context: context, folders: folders)
  }
}
struct FolderViewer: View {
  @Environment(\.macWorkspaceActive) private var active
  @State var photo: FolderPhoto
  let context: [FolderPhoto]
  @ObservedObject var folders: FolderSources
  @ObservedObject var navigation: MacLibraryNavigation
  var close: (FolderPhoto) -> Void
  @State private var animated = false
  @StateObject private var fileMedia = MacFolderMediaDirectory()
  private var index: Int { context.firstIndex { $0.id == photo.id } ?? 0 }
  private func move(_ step: Int, animated: Bool) {
    let next = index + step
    guard context.indices.contains(next) else { return }
    self.animated = animated; photo = context[next]
  }
  var body: some View {
    MacViewerLayout(navigation: navigation) {
      MacCollectionPager(count: context.count, selectedIndex: index, animated: animated,
        selected: { next in photo = context[next]; animated = false }, page: { position, _ in
          let item = context[position]
          let paging = MacCollectionPaging(index: position, count: context.count,
            move: { move($0, animated: false) }, native: true, swipe: { move($0, animated: true) })
          return AnyView(MacFolderPreviewPage(photo: item, context: context, folders: folders,
            navigation: navigation, media: fileMedia.model(for: item,
              keeping: Array(context[max(0, index - 1)...min(context.count - 1, index + 1)]), folders: folders,
              poster: navigation.viewerFlight.poster(for: item.source_id)),
            close: close, collectionPaging: paging).id(item.id))
        })
    }
    .onAppear { installBack() }
    .onChange(of: photo.id) { _, _ in installBack() }
    .onChange(of: active) { _, visible in if visible { installBack() } }
    .onDisappear { fileMedia.stop(); navigation.viewerCurrent = nil; navigation.viewerShare = nil; navigation.viewerBack = nil }
  }
  private func installBack() {
    guard active else { return }
    navigation.viewerBack = { close(photo) }
  }
}

struct MacFolderPreviewPage: View {
  @Environment(\.macWorkspaceActive) private var active
  @State var photo: FolderPhoto
  let context: [FolderPhoto]
  @ObservedObject var folders: FolderSources
  @ObservedObject var navigation: MacLibraryNavigation
  @ObservedObject var media: MacFolderMedia
  var close: (FolderPhoto) -> Void
  var collectionPaging: MacCollectionPaging? = nil
  var recorded: BackupJob? = nil
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @StateObject private var facts = MacViewerFacts()
  @State private var zoomed = false
  @State private var target: MacDetailPosterTarget?
  var body: some View {
    Group {
      if let player = media.player { MacVideoWithPoster(player: player, image: media.image, flight: active ? navigation.viewerFlight : nil, assetID: photo.source_id, entryReady: media.entryReady, onSwipe: swipe) }
      else if let image = media.image { MacMediaZoom(image: image, livePhoto: nil, playRequest: 0, fitRevision: 0, zoomed: { zoomed = $0 }, flight: active ? navigation.viewerFlight : nil, assetID: photo.source_id, entryReady: media.entryReady, onSwipe: swipe) }
      else if media.failure {
        MacFolderPreviewUnavailable { load(force: true) }
      } else { ProgressView("preview_loading") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MacDetailViewportProbe { target = $0 })
    .overlay { if media.failure, media.image != nil { MediaPreviewFailure { load(force: true) } } }
    .modifier(MacViewerNavigationControls(previousEnabled: (collectionPaging?.hasPrevious ?? (index > 0)) && !zoomed,
      nextEnabled: (collectionPaging?.hasNext ?? (index + 1 < context.count)) && !zoomed,
      previous: { move(-1) }, next: { move(1) }))
    .modifier(MacViewerInspector(navigation: navigation, target: .folder(photo, folders, recorded)))
    .background(MacMediaKeyHandler(close: { close(photo) }) { event in
      if event.modifierFlags.intersection([.command, .option, .control]).isEmpty, !zoomed {
        if event.keyCode == 123 { move(-1); return true }
        if event.keyCode == 124 { move(1); return true }
      }
      return false
    })
    .task(id: "\(photo.id)|\(model.queueRevision)|\(model.summary.received)|\(model.summary.published)|\(folders.revision)") {
      await facts.load(source: photo.source_id, revision: photo.revision, model: model, recorded: recorded, fallback: photo.backup)
      describe()
    }
    .onChange(of: facts.stateKey) { _, _ in describe() }
    .onChange(of: facts.job) { _, _ in describe() }
    .onChange(of: facts.job.flatMap { model.transferProgress[$0.id] }) { _, _ in describe() }
    .onAppear { if active, collectionPaging == nil { navigation.viewerBack = { close(photo) } } }
    .onChange(of: active) { _, visible in
      if visible { describe(); installCommands() }
      else { media.player?.pause() }
    }
    .task(id: "\(photo.id)|\(photo.revision)|\(target?.pixels.width ?? 0)|\(target?.pixels.height ?? 0)|\(target?.profile ?? "")") {
      guard target != nil else { return }; load()
    }
    .onChange(of: media.fileURL) { _, _ in installCommands() }
    .onDisappear { media.player?.pause() }
  }
  private func describe() {
    guard active else { return }
    navigation.viewerHasLive = false
    navigation.viewerTitle = MacViewerTitle.date(photo.date)
    navigation.viewerSubtitle = MacViewerTitle.subtitle(photo.date, index: (collectionPaging?.index ?? index) + 1, total: collectionPaging?.count ?? context.count)
    navigation.viewerState = facts.stateKey(model: model); navigation.viewerProgress = facts.progress(model: model)
  }
  private var index: Int { context.firstIndex { $0.id == photo.id } ?? 0 }
  private func swipe(_ direction: Int) {
    guard !zoomed else { return }
    if let collectionPaging { collectionPaging.moveForHorizontalMotion(direction) }
    else { move(MacCollectionPaging.step(forHorizontalMotion: direction), animated: true) }
  }
  private func move(_ step: Int, animated: Bool = false) {
    guard !zoomed else { return }
    if let collectionPaging {
      if animated, let swipe = collectionPaging.swipe { swipe(step) }
      else { collectionPaging.move(step) }
      return
    }
    let next = index + step
    guard context.indices.contains(next) else { return }
    guard !zoomed else { return }; photo = context[next]
  }
  private func installCommands() {
    guard active else { return }
    if collectionPaging == nil { navigation.viewerBack = { close(photo) } }
    navigation.viewerCurrent = nil
    if folders.isPreview { navigation.viewerShare = { MacViewerSharing.show(media.image) } }
    else if let file = media.fileURL { navigation.viewerShare = { MacViewerSharing.show(file) } }
    else { navigation.viewerShare = nil }
  }
  private func load(force: Bool = false) {
    guard let target else { return }
    media.prepare(photo: photo, folders: folders, target: target,
      poster: navigation.viewerFlight.poster(for: photo.source_id), force: force)
    installCommands()
  }
}

/// Media survives AppKit recycling a hosting controller at the end of a swipe.
/// Only the selected file and its two neighbors belong to the retained directory.
@MainActor final class MacFolderMediaDirectory: ObservableObject {
  private var models: [String: MacFolderMedia] = [:]
  var retainedCount: Int { models.count }
  private static func key(_ photo: FolderPhoto) -> String { photo.id + "|" + photo.revision }
  func model(for photo: FolderPhoto, keeping neighbors: [FolderPhoto], folders: FolderSources, poster: NSImage? = nil) -> MacFolderMedia {
    let keep = Set(neighbors.map(Self.key))
    for key in Array(models.keys) where !keep.contains(key) { models.removeValue(forKey: key)?.cancel() }
    let key = Self.key(photo)
    if let model = models[key] { return model }
    let model = MacFolderMedia(photo: photo, folders: folders, poster: poster)
    if keep.contains(key) { models[key] = model }
    return model
  }
  func stop() { models.values.forEach { $0.cancel() }; models.removeAll() }
}

@MainActor final class MacFolderMedia: ObservableObject {
  @Published private(set) var image: NSImage?
  @Published private(set) var player: AVPlayer?
  @Published private(set) var failure = false
  @Published private(set) var entryReady = false
  @Published private(set) var fileURL: URL?
  private var root: URL?
  private var worker: Task<Void, Never>?
  private var loadGeneration = UUID()
  private var requestedTarget: MacDetailPosterTarget?
  init(photo: FolderPhoto, folders: FolderSources, poster: NSImage? = nil) {
    if folders.isPreview { image = folders.syntheticImage(photo); entryReady = true }
    else {
      // The clicked grid retains presentation while the native leaf attaches.
      // Its poster prevents a loading-page flash but cannot start the flight;
      // only validated detail pixels (or an explicit failure) release entry.
      image = poster ?? FileThumbnailPipeline.shared.memoryPoster(source: photo.folder_id,
        asset: photo.source_id, revision: photo.revision)
    }
  }
  deinit { worker?.cancel(); root?.stopAccessingSecurityScopedResource() }
  func prepare(photo: FolderPhoto, folders: FolderSources, target: MacDetailPosterTarget,
    poster: NSImage?, force: Bool = false) {
    if folders.isPreview { return }
    if !force, requestedTarget == target { return }
    if !force, photo.media_type.hasPrefix("video/"), player != nil { return }
    requestedTarget = target
    worker?.cancel()
    let generation = UUID(); loadGeneration = generation
    failure = false
    if image == nil {
      image = poster ?? FileThumbnailPipeline.shared.memoryPoster(source: photo.folder_id,
        asset: photo.source_id, revision: photo.revision)
    }
    worker = Task { [weak self] in
      await self?.load(photo: photo, folders: folders, target: target, generation: generation)
    }
  }
  func cancel() {
    worker?.cancel(); worker = nil; loadGeneration = UUID(); requestedTarget = nil
    player?.pause()
    root?.stopAccessingSecurityScopedResource(); root = nil
  }
  private func load(photo: FolderPhoto, folders: FolderSources, target: MacDetailPosterTarget, generation: UUID) async {
    guard !Task.isCancelled, loadGeneration == generation else { return }
    guard let source = folders.sources.first(where: { $0.id == photo.folder_id }),
      let sourceRoot = root ?? folders.sourceURL(source) else { failure = true; entryReady = true; return }
    if root == nil { _ = sourceRoot.startAccessingSecurityScopedResource(); root = sourceRoot }
    let file = sourceRoot.appendingPathComponent(photo.relative).standardizedFileURL
    guard file.path.hasPrefix(sourceRoot.path + "/"), file.resolvingSymlinksInPath().path == file.path,
      FileManager.default.isReadableFile(atPath: file.path) else { failure = true; entryReady = true; return }
    fileURL = file
    if photo.media_type.hasPrefix("video/") { player = AVPlayer(url: file); entryReady = true; return }
    let epoch = MacThumbnailTables.storage.epoch
    let budget = MacThumbnailTables.budgetMB * 1024 * 1024
    let tables = MacThumbnailTables.activeTables
    let storage = MacThumbnailTables.storage
    let reserved = await Task.detached(priority: .utility) {
      let used = tables.map(\.usage)
      return storage.tableUsage(active: tables) + zip(tables, used).reduce(0) { total, pair in
        let (table, earlier) = pair
        let header = (table.capacity * 16 + 16383) / 16384 * 16384
        return total + max(0, header + table.limit * table.entryBytes - earlier)
      }
    }.value
    guard !Task.isCancelled, loadGeneration == generation else { return }
    let result = await MacFileDetailPosterCache.shared.load(photo: photo, file: file, root: sourceRoot,
      target: target, epoch: epoch, budget: budget, reserved: reserved)
    guard !Task.isCancelled, loadGeneration == generation else { return }
    if let result { image = NSImage(cgImage: result, size: .zero) }
    failure = result == nil; entryReady = true
  }
}

struct MacFolderPreviewUnavailable: View {
  var retry: () -> Void
  var body: some View {
    ContentUnavailableView { Label("mac_library_preview_unavailable", systemImage: "photo.badge.exclamationmark") }
      actions: { Button("retry_task", action: retry) }
  }
}

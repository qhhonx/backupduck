import AppKit
import Photos
import SwiftUI

extension LibraryFilter {
  func matches(kind: String) -> Bool {
    self == .all || (self == .photo && kind == "photo") || (self == .video && kind == "video")
      || (self == .motion && kind == "motion") || (self == .burst && kind == "burst")
  }
}

@MainActor final class MacHistoryGridState: ObservableObject {
  let navigation = MacLibraryNavigation()
  let thumbnails = ThumbnailPipeline()
  var scrolls: [String: MacGridScrollState] = [:]
  @Published var selection = Set<String>()
  @Published private(set) var imageRevision = 0
  private(set) var assets: [String: PHAsset] = [:]
  private(set) var files: [String: FolderPhoto] = [:]
  private var fileKeys: [String: String] = [:]
  /// Folder identities are resolved once per job revision; a state observation
  /// does not repeat the core lookups. `merging` keeps entries outside `photos`.
  func resolve(_ photos: [HistoryPhoto], merging: Bool = false) async {
    let library = photos.filter { $0.job?.asset.metadata?["source_type"] != "folder" }
    var found = merging ? assets : [:]
    if BackupEnvironment.usesPhotoLibrary {
      let fetch = PHAsset.fetchAssets(withLocalIdentifiers: library.map(\.source), options: nil)
      fetch.enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset }
    } else {
      for photo in library { if let asset = photo.job.flatMap({ BackupEnvironment.sampleAsset?($0) }) { found[photo.source] = asset } }
    }
    var resolved: [String: FolderPhoto] = merging ? files : [:]
    var keys: [String: String] = merging ? fileKeys : [:]
    for photo in photos where photo.job?.asset.metadata?["source_type"] == "folder" {
      guard !Task.isCancelled else { return }
      let key = photo.job?.asset.revision ?? ""
      if fileKeys[photo.id] == key, let known = files[photo.id] { resolved[photo.id] = known; keys[photo.id] = key; continue }
      if let file = await FolderSources.active.historyPhoto(photo) { resolved[photo.id] = file; keys[photo.id] = key }
    }
    guard !Task.isCancelled else { return }
    assets = found; files = resolved; fileKeys = keys; imageRevision &+= 1
  }
}

extension FolderSources {
  /// Resolve persisted folder identity through the core index, with the same
  /// revision check as the file thumbnail and viewer adapters.
  func historyPhoto(_ photo: HistoryPhoto) async -> FolderPhoto? {
    guard let job = photo.job, let source = job.asset.metadata?["source_ref"] else { return nil }
    if isPreview { return previewRows?.first { $0.source_id == photo.source && $0.folder_id == source } }
    guard let entry = try? await previewEntry(source, job: job.id, sourceID: photo.source),
      entry.source_id == photo.source,
      entry.revision == job.asset.revision || job.asset.revision.hasPrefix(entry.revision + "|") else { return nil }
    return FolderPhoto(relative: entry.relative, source_id: entry.source_id, revision: entry.revision,
      size: entry.size, media_type: entry.media_type, modified_ms: entry.modified_ms, folder_id: source,
      capture_ms: photo.takenAt.map { UInt64(max(0, $0.timeIntervalSince1970 * 1000)) } ?? entry.modified_ms,
      date_source: photo.takenAt == nil ? "file_modified" : "embedded", backup: photo.mark == .saved ? "saved"
        : photo.mark == .needsYou ? "needs_you" : photo.mark == .saving ? "saving" : "sending", saved_at_ms: nil)
  }
}

struct MacHistoryGrid: View {
  @Environment(\.macViewerPresentation) private var present
  @ObservedObject var history: BackupHistoryModel
  @ObservedObject var state: MacHistoryGridState
  var filter: String
  var type: LibraryFilter
  var search: String
  var columns: Int
  var initialFocus: HistoryPhoto?
  var initialFocusRevision = 0
  var clearFilters: () -> Void
  var resize: (Int) -> Void
  var retry: () -> Void
  var active = true
  @State private var focusedRevision = -1
  var body: some View {
    let source = MacHistoryGridSource(history: history, state: state, filter: filter, type: type, search: search)
    MacMediaGrid(source: source, navigation: state.navigation, queueRevision: Int64(state.imageRevision),
      receiverID: nil, columns: columns, active: active, sharedSize: .shared, prefillsTables: false, preview: { id in
        guard let photo = source.photos[id] else { return }
        let context = source.identifiers.compactMap { source.photos[$0] }
        present?(.history(photo, context, state, { state.navigation.focus($0) }))
      }, resize: resize)
      .modifier(MacGridInspector(navigation: state.navigation, source: source, active: active))
      .overlay {
        if source.identifiers.isEmpty && (!history.resolved || history.loading || history.hasMore && !history.failed) { ProgressView("library_loading") }
        else if source.identifiers.isEmpty && history.failed {
          ContentUnavailableView { Label("records_load_failed", systemImage: "exclamationmark.triangle") }
            actions: { Button("retry_task", action: retry) }.duckOpticalCenter()
        } else if source.identifiers.isEmpty {
          if type != .all || !search.isEmpty || filter != "all" { MacGridFilterEmpty(clear: clearFilters) }
          else { ContentUnavailableView { DuckIllustration(pose: .empty, size: 112); Text("records_empty") }
            description: { Text("records_empty_note") }.duckOpticalCenter() }
        }
      }
      .task(id: (history.photos + history.attention).map { $0.id + "|" + ($0.job?.asset.revision ?? "") }.joined(separator: ",")) {
        await state.resolve(history.photos + history.attention)
      }
      .task(id: "\(source.contextID)|\(history.photos.count)") {
        if source.identifiers.isEmpty, history.hasMore { await history.loadMore() }
      }
      .task(id: "\(initialFocus?.id ?? "")|\(initialFocusRevision)|\(history.resolved)|\(history.loading)|\(history.failed)|\(history.photos.map(\.id).joined(separator: ","))") {
        guard let initialFocus, focusedRevision != initialFocusRevision, history.resolved, !history.loading, !history.failed else { return }
        if history.matching(initialFocus) == nil, history.hasMore {
          // Loading changes this task's identity; the independent page request
          // can finish, then the next observation resumes the search.
          Task { await history.loadMore() }
          return
        }
        guard !Task.isCancelled, let found = history.matching(initialFocus), source.identifiers.contains(found.id) else { return }
        state.selection = [found.id]
        state.navigation.focus(found.id); focusedRevision = initialFocusRevision
      }
  }
}

@MainActor final class MacHistoryGridSource: MacGridSource {
  let history: BackupHistoryModel
  let state: MacHistoryGridState
  let photos: [String: HistoryPhoto]
  let identifiers: [String]
  let groups: [Int: String]
  var flowHeaders: Set<Int> { Set(groups.keys) }
  private var measured: (width: CGFloat, heights: [Int: CGFloat])?
  let contextID: String
  private let locallyFiltered: Bool
  private let receiverName: String?
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  init(history: BackupHistoryModel, state: MacHistoryGridState, filter: String, type: LibraryFilter, search: String) {
    self.history = history; self.state = state
    locallyFiltered = type != .all || !search.isEmpty
    receiverName = BackupEnvironment.activeModel().peerDevice?.name
    contextID = "\(filter)|\(type.rawValue)|\(search)"
    func matches(_ photo: HistoryPhoto) -> Bool {
      type.matches(kind: photo.job?.asset.kind ?? "photo") && (search.isEmpty
        || (photo.job?.asset.resources.first?.filename ?? "").localizedCaseInsensitiveContains(search))
    }
    func newestFirst(_ lhs: HistoryPhoto, _ rhs: HistoryPhoto) -> Bool {
      let left = lhs.changedAt ?? .distantPast, right = rhs.changedAt ?? .distantPast
      return left == right ? lhs.id < rhs.id : left > right
    }
    let problems = history.causes.map { ($0.0, $0.1.filter(matches).sorted(by: newestFirst)) }
    var rows = problems.flatMap(\.1)
    let known = Set(rows.map(\.id))
    rows += history.photos.filter { !known.contains($0.id) && matches($0) }.sorted(by: newestFirst)
    photos = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }); identifiers = rows.map(\.id)
    var headers: [Int: String] = [:], index = 0
    for (cause, items) in problems where !items.isEmpty {
      headers[index] = String(format: NSLocalizedString(cause.title, comment: ""), items.count.formatted())
      index += items.count
    }
    // A source-neutral separator starts the ordinary records after the final
    // reason group without inventing a date heading or mixing the two rows.
    if index > 0, index < rows.count { headers[index] = "" }
    groups = headers
  }
  func introduction(at index: Int) -> AnyView? {
    guard let title = groups[index] else { return nil }
    if title.isEmpty { return AnyView(Color.clear.frame(height: DuckSpacing.medium)) }
    return AnyView(Text(title).font(.body.weight(.semibold)).foregroundStyle(DuckRole.primaryText)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DuckSpacing.small))
  }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    if let measured, measured.width == width { return measured.heights }
    let heights = groups.keys.reduce(into: [Int: CGFloat]()) { result, index in
      if let content = introduction(at: index) {
        result[index] = MacGridSectionHeader.fittingContentHeight(content, width: width)
      }
    }
    measured = (width, heights)
    return heights
  }
  var contentRevision: String { "\(state.imageRevision)" }
  var selection: Set<String> { get { state.selection } set { state.selection = newValue } }
  var thumbnails: ThumbnailPipeline? { state.thumbnails }
  var scroll: MacGridScrollState {
    if let value = state.scrolls[contextID] { return value }
    let value = MacGridScrollState(); state.scrolls[contextID] = value; return value
  }
  var footer: String {
    guard !history.failed, !history.loading else { return "" }
    if !history.hasMore {
      return MacGridTotals.complete(kinds: identifiers.map { photos[$0]?.job?.asset.kind }).text()
    }
    return locallyFiltered ? "" : MacGridTotals(total: history.total).text()
  }
  var footerNotes: [String] {
    receiverName.map { [String(format: NSLocalizedString("grid_footer_receiver", comment: ""), $0)] } ?? []
  }
  func asset(_ id: String) -> PHAsset? { photos[id].flatMap { state.assets[$0.source] } }
  func informationTarget(_ id: String) -> MacPhotoInformationTarget {
    guard let photo = photos[id] else { return .selection(0) }
    if let file = state.files[id] { return .folder(file, FolderSources.active, photo.job) }
    if let asset = asset(id) { return .library(asset, nil, photo.job) }
    return .recorded(photo)
  }
  func date(_ id: String) -> Date? { photos[id]?.changedAt }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    guard let photo = photos[id] else { return }
    if let file = state.files[id], let folder = FolderSources.active.sources.first(where: { $0.id == file.folder_id }) {
      cell.configureFolder(file, source: folder, pixels: pixels, synthetic: FolderSources.active.syntheticImage(file))
    } else if let asset = asset(id) {
      cell.configure(asset, pipeline: state.thumbnails, pixels: pixels, identifier: id)
    } else { cell.configureUnavailable(id: id, label: photo.job?.asset.resources.first?.filename ?? "", video: photo.job?.asset.kind == "video") }
    cell.setPresentationID(id)
    cell.setState(photo.mark == .sending ? "sending" : photo.mark == .saving ? "saving" : photo.mark == .needsYou ? "needs_you" : nil)
  }
  func loadMore(visible: [String]) {
    if identifiers.suffix(24).contains(where: { visible.contains($0) }) { Task { await history.loadMore() } }
  }
  func preheat(_ ids: [String], pixels: CGFloat) { state.thumbnails.preheat(ids.compactMap(asset), pixels: pixels) }
}

struct MacGridFilterEmpty: View {
  var clear: () -> Void
  var body: some View {
    LibraryPlaceholder(kind: .filterEmpty, clearFilter: clear)
  }
}

/// History retains its mixed-source collection while the existing media adapters
/// own decoding, security-scoped access, zoom and the information inspector.
struct MacHistoryPreview: View {
  @Environment(\.macWorkspaceActive) private var active
  @State var photo: HistoryPhoto
  let collection: [HistoryPhoto]
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  /// The grid's resolved media: previous/next never waits for a lookup.
  @ObservedObject var media: MacHistoryGridState
  var close: (String) -> Void
  @State private var animated = false
  @StateObject private var fileMedia = MacFolderMediaDirectory()
  private var index: Int { collection.firstIndex { $0.id == photo.id } ?? 0 }
  private func move(_ step: Int, animated: Bool) {
    let next = index + step
    guard collection.indices.contains(next) else { return }
    self.animated = animated; photo = collection[next]
  }
  var body: some View {
    MacViewerLayout(navigation: navigation) {
      MacCollectionPager(count: collection.count, selectedIndex: index, animated: animated,
        selected: { next in photo = collection[next]; animated = false }, page: { position, _ in
          let item = collection[position]
          let paging = MacCollectionPaging(index: position, count: collection.count,
            move: { move($0, animated: false) }, native: true, swipe: { move($0, animated: true) })
          return AnyView(page(item, paging: paging).id(item.id))
        })
    }
    .onAppear { installBack() }
    .onChange(of: photo.id) { _, _ in installBack() }
    .onChange(of: active) { _, visible in if visible { installBack() } }
    .onDisappear { fileMedia.stop(); navigation.viewerCurrent = nil; navigation.viewerShare = nil; navigation.viewerBack = nil }
  }
  private func installBack() {
    guard active else { return }
    navigation.viewerBack = { close(photo.id) }
  }
  @ViewBuilder private func page(_ item: HistoryPhoto, paging: MacCollectionPaging) -> some View {
    Group {
      if let file = media.files[item.id] {
        MacFolderPreviewPage(photo: file, context: [file], folders: FolderSources.active,
          navigation: navigation, media: fileMedia.model(for: file,
            keeping: collection[max(0, index - 1)...min(collection.count - 1, index + 1)].compactMap { media.files[$0.id] },
            folders: FolderSources.active, poster: navigation.viewerFlight.poster(for: file.source_id)),
          close: { _ in close(item.id) }, collectionPaging: paging, recorded: item.job)
      } else if let asset = media.assets[item.source] {
        MacPhotoPreview(asset: asset, library: library, navigation: navigation, reviewAssets: [asset],
          recorded: item, collectionPaging: paging, close: { _ in close(item.id) })
      } else {
        MacRecordedPhotoPreview(photo: item, model: BackupEnvironment.activeModel(), navigation: navigation,
          close: { close(item.id) }, collectionPaging: paging)
      }
    }
    .task(id: item.id) {
      if media.files[item.id] == nil && media.assets[item.source] == nil { await media.resolve([item], merging: true) }
    }
  }
}

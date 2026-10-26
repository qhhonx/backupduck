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
  var selection = Set<String>()
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
  var clearFilters: () -> Void
  var resize: (Int) -> Void
  var retry: () -> Void
  @State private var focused: String?
  var body: some View {
    let source = MacHistoryGridSource(history: history, state: state, filter: filter, type: type, search: search)
    MacMediaGrid(source: source, navigation: state.navigation, queueRevision: Int64(state.imageRevision),
      receiverID: nil, columns: columns, prefillsTables: false, preview: { id in
        guard let photo = source.photos[id] else { return }
        let context = source.identifiers.compactMap { source.photos[$0] }
        present?(.history(photo, context, state, { state.navigation.focus($0) }))
      }, resize: resize)
      .overlay {
        if source.identifiers.isEmpty && history.loading { ProgressView("library_loading") }
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
      .task(id: initialFocus?.id) {
        guard let initialFocus, focused != initialFocus.id else { return }
        while !history.photos.contains(where: { $0.id == initialFocus.id }), history.hasMore, !Task.isCancelled {
          let count = history.photos.count; await history.loadMore()
          if count == history.photos.count { break }
        }
        state.navigation.focus(initialFocus.id); focused = initialFocus.id
      }
  }
}

@MainActor final class MacHistoryGridSource: MacGridSource {
  let history: BackupHistoryModel
  let state: MacHistoryGridState
  let photos: [String: HistoryPhoto]
  let identifiers: [String]
  let groups: [Int: String]
  let contextID: String
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  init(history: BackupHistoryModel, state: MacHistoryGridState, filter: String, type: LibraryFilter, search: String) {
    self.history = history; self.state = state
    contextID = "\(filter)|\(type.rawValue)|\(search)"
    func matches(_ photo: HistoryPhoto) -> Bool {
      type.matches(kind: photo.job?.asset.kind ?? "photo") && (search.isEmpty
        || (photo.job?.asset.resources.first?.filename ?? "").localizedCaseInsensitiveContains(search))
    }
    let problems = history.causes.map { ($0.0, $0.1.filter(matches)) }
    var rows = problems.flatMap(\.1)
    let known = Set(rows.map(\.id))
    rows += history.photos.filter { !known.contains($0.id) && matches($0) }
    photos = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }); identifiers = rows.map(\.id)
    var headers: [Int: String] = [:], index = 0
    for (cause, items) in problems where !items.isEmpty {
      headers[index] = String(format: NSLocalizedString(cause.title, comment: ""), items.count.formatted())
      index += items.count
    }
    var previous: Date?
    for (offset, photo) in rows.dropFirst(index).enumerated() {
      let day = Calendar.current.startOfDay(for: photo.changedAt ?? .distantPast)
      if day != previous {
        headers[index + offset] = day == .distantPast ? NSLocalizedString("design_capture_unknown", comment: "")
          : day.formatted(date: .long, time: .omitted)
        previous = day
      }
    }
    groups = headers
  }
  var contentRevision: String { "\(state.imageRevision)" }
  var selection: Set<String> { get { state.selection } set { state.selection = newValue } }
  var thumbnails: ThumbnailPipeline? { state.thumbnails }
  var scroll: MacGridScrollState {
    if let value = state.scrolls[contextID] { return value }
    let value = MacGridScrollState(); state.scrolls[contextID] = value; return value
  }
  var footer: String { NSLocalizedString("records_cloud_footer", comment: "") }
  func asset(_ id: String) -> PHAsset? { photos[id].flatMap { state.assets[$0.source] } }
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
    ContentUnavailableView {
      Label { Text("library_filter_empty").foregroundStyle(DuckRole.primaryText) }
        icon: { Image(systemName: "line.3.horizontal.decrease") }
    }
      description: { Text("library_filter_empty_note") }
      actions: { Button("library_filter_show_all", action: clear).duckPrimaryButton() }
      .duckOpticalCenter()
  }
}

/// History retains its mixed-source collection while the existing media adapters
/// own decoding, security-scoped access, zoom and the information inspector.
struct MacHistoryPreview: View {
  @State var photo: HistoryPhoto
  let collection: [HistoryPhoto]
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  /// The grid's resolved media: previous/next never waits for a lookup.
  @ObservedObject var media: MacHistoryGridState
  var close: (String) -> Void
  private var paging: MacCollectionPaging {
    MacCollectionPaging(index: collection.firstIndex(where: { $0.id == photo.id }) ?? 0,
      count: collection.count, move: { step in
        let index = (collection.firstIndex(where: { $0.id == photo.id }) ?? 0) + step
        if collection.indices.contains(index) { photo = collection[index] }
      })
  }
  var body: some View {
    Group {
      if let file = media.files[photo.id] {
        FolderViewer(photo: file, context: [file], folders: FolderSources.active, navigation: navigation,
          close: { _ in close(photo.id) }, collectionPaging: paging, recorded: photo.job)
      } else if let asset = media.assets[photo.source] {
        MacPhotoPreview(asset: asset, library: library, navigation: navigation, reviewAssets: [asset], recorded: photo,
          collectionPaging: paging, close: { _ in close(photo.id) })
      } else {
        MacRecordedPhotoPreview(photo: photo, model: BackupEnvironment.activeModel(), navigation: navigation,
          close: { close(photo.id) }, collectionPaging: paging)
      }
    }.id(photo.id)
      .task(id: photo.id) {
        if media.files[photo.id] == nil && media.assets[photo.source] == nil { await media.resolve([photo], merging: true) }
      }
  }
}

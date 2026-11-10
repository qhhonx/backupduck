import AppKit
import SwiftUI

struct FolderMediaCounts: Decodable, Equatable {
  var photos: UInt64 = 0
  var videos: UInt64 = 0
  var total: UInt64 { photos + videos }
  static func + (lhs: Self, rhs: Self) -> Self {
    Self(photos: lhs.photos + rhs.photos, videos: lhs.videos + rhs.videos)
  }
}

/// One count phrase for every folder state, scope and preview summary.
func folderMediaCount(_ counts: FolderMediaCounts, bundle: Bundle = .main) -> String {
  let key = counts.videos == 0 ? "folders_media_photos"
    : counts.photos == 0 ? "folders_media_videos" : "folders_media_mixed"
  let format = bundle.localizedString(forKey: key, value: nil, table: nil)
  return counts.photos > 0 && counts.videos > 0
    ? String.localizedStringWithFormat(format, counts.photos, counts.videos)
    : String.localizedStringWithFormat(format, counts.videos == 0 ? counts.photos : counts.videos)
}

struct FolderFacts: Decodable, Equatable {
  var supported: UInt64 = 0
  var supported_kinds: FolderMediaCounts? = nil
  var saved: UInt64 = 0
  var saved_kinds: FolderMediaCounts? = nil
  var in_flight: UInt64 = 0
  var in_flight_kinds: FolderMediaCounts? = nil
  var in_flight_bytes: UInt64 = 0
  var needs_you: UInt64 = 0
  var needs_you_kinds: FolderMediaCounts? = nil
  var not_backed_up: UInt64 = 0
  var not_backed_up_kinds: FolderMediaCounts? = nil
  var available: Bool? = nil
  var unsupported_by_kind: [String: UInt64] = [:]
  func media(_ state: String) -> FolderMediaCounts {
    switch state {
    case "saved": saved_kinds ?? .init(photos: saved)
    case "in_flight": in_flight_kinds ?? .init(photos: in_flight)
    case "needs_you": needs_you_kinds ?? .init(photos: needs_you)
    case "not_backed_up": not_backed_up_kinds ?? .init(photos: not_backed_up)
    default: supported_kinds ?? .init(photos: supported)
    }
  }
}
struct FolderPhoto: Decodable, Identifiable, Equatable {
  let relative: String
  let source_id: String
  let revision: String
  let size: UInt64
  let media_type: String
  let modified_ms: UInt64
  let folder_id: String
  let capture_ms: UInt64
  let date_source: String
  var backup: String
  let saved_at_ms: UInt64?
  var id: String { folder_id + "|" + source_id }
  var date: Date { Date(timeIntervalSince1970: Double(capture_ms) / 1000) }
  var canBackUp: Bool { backup == "not_backed_up" || backup == "needs_you" }
}
struct FolderPhotoPage: Decodable {
  let rows: [FolderPhoto]
  let has_more: Bool
}

enum FolderBrowseScope: Hashable { case all, folder(String) }

/// Browse state only. Membership, filters, counts and durable backup intent come from Rust.
@MainActor final class FolderBrowser: ObservableObject {
  enum ContentState: Equatable {
    case loading, photos, filterEmpty, empty, failed
  }
  struct Section: Identifiable {
    let id: String
    var photos: [FolderPhoto]
    var hasMore: Bool
    var nextOffset: Int
  }
  var configured = false
  @Published var scope: FolderBrowseScope = .all { didSet { scopeChanged(from: oldValue) } }
  private struct ScopeState {
    var filter: LibraryBackupView
    var type: LibraryFilter
    var search: String
    var searchExpanded: Bool
  }
  private var scopeStates: [FolderBrowseScope: ScopeState] = [:]
  private var restoringScope = false
  private var sectionCache: [String: [Section]] = [:]
  private var preheated: [String: UUID] = [:]
  private func scopeChanged(from old: FolderBrowseScope) {
    guard old != scope else { return }
    stopPreheating()
    selections[activeKey] = selection
    if resultKey == activeKey { sectionCache[activeKey] = sections }
    scopeStates[old] = ScopeState(filter: filter, type: type, search: search, searchExpanded: searchExpanded)
    restoringScope = true
    let state = scopeStates[scope] ?? ScopeState(filter: .all, type: .all, search: "", searchExpanded: false)
    filter = state.filter; type = state.type; search = state.search; searchExpanded = state.searchExpanded
    restoringScope = false
    activeKey = key; selection = selections[key] ?? []
    sections = sectionCache[key] ?? []; resultKey = sectionCache[key] == nil ? nil : key
    error = nil; loading = false
    generation += 1
  }
  @Published var filter: LibraryBackupView = .all { didSet { contextChanged() } }
  @Published var type: LibraryFilter = .all { didSet { contextChanged() } }
  /// Kept here, not in the page, so returning to Folders keeps its density.
  @Published var columns = MacLibraryDensity.standard
  var gridScrolls: [String: MacGridScrollState] = [:]
  private var visibleRanges: [String: MacVisibleRange] = [:]
  var visibleRange: MacVisibleRange {
    if let range = visibleRanges[key] { return range }
    let range = MacVisibleRange(); visibleRanges[key] = range; return range
  }
  @Published var searchExpanded = false
  @Published var search = "" { didSet { contextChanged() } }
  @Published var selection = Set<String>()
  @Published private(set) var sections: [Section] = [] {
    didSet {
      visiblePhotos = sections.flatMap(\.photos)
      identifiers = visiblePhotos.map(\.id)
      photosByID = Dictionary(uniqueKeysWithValues: zip(identifiers, visiblePhotos))
    }
  }
  private(set) var visiblePhotos: [FolderPhoto] = []
  private(set) var identifiers: [String] = []
  private(set) var photosByID: [String: FolderPhoto] = [:]
  @Published private(set) var resultKey: String?
  @Published private(set) var loading = false
  @Published var error: String?
  var offsets: [String: CGPoint] = [:]
  private var selections: [String: Set<String>] = [:]
  private var activeKey = "all|all||all"
  private func contextChanged() {
    guard !restoringScope, key != activeKey else { return }
    stopPreheating()
    generation += 1
    if resultKey == activeKey { sectionCache[activeKey] = sections }
    selections[activeKey] = selection
    activeKey = key; selection = selections[key] ?? []
    sections = sectionCache[key] ?? []; resultKey = sectionCache[key] == nil ? nil : key
    error = nil; loading = false
  }
  func preheat(_ photos: [FolderPhoto], sources: [String: FolderSource], pixels: CGFloat) {
    let candidates = photos.prefix(64).map { photo in
      (photo, "\(photo.id)|\(photo.revision)|\(pixels)")
    }
    let keep = Set(candidates.map(\.1))
    for key in preheated.keys.filter({ !keep.contains($0) }) {
      if let token = preheated.removeValue(forKey: key) { FileThumbnailPipeline.shared.cancel(token) }
    }
    for (photo, key) in candidates where preheated[key] == nil {
      guard let source = sources[photo.folder_id] else { continue }
      let token = UUID()
      preheated[key] = token
      FileThumbnailPipeline.shared.request(id: token, source: source, relative: photo.relative,
        assetID: photo.source_id, revision: photo.revision, size: pixels / 2, preheat: true) { _ in }
    }
  }
  func stopPreheating() {
    preheated.values.forEach { FileThumbnailPipeline.shared.cancel($0) }
    preheated.removeAll()
  }
  private var pagingGeneration: Int?
  private var reloadingGeneration: Int?
  private var generation = 0
  var key: String {
    let identity: String
    switch scope { case .all: identity = "all"; case .folder(let id): identity = "folder:" + id }
    return "\(identity)|\(filter.rawValue)|\(search)|\(type.rawValue)"
  }
  var contentState: ContentState {
    if error != nil && visiblePhotos.isEmpty { return .failed }
    guard resultKey == key, !loading else { return .loading }
    guard visiblePhotos.isEmpty else { return .photos }
    // An unmatched prefix is still a pending browse, not an empty result.
    guard !sections.contains(where: \.hasMore) else { return .loading }
    return search.isEmpty && filter == .all && type == .all ? .empty : .filterEmpty
  }
  func clearFilters() { filter = .all; type = .all; search = "" }
  var selected: [FolderPhoto] { sections.flatMap(\.photos).filter { selection.contains($0.id) && $0.canBackUp } }
  /// Submitted photos leave selection in every saved browse context. Photos
  /// selected after the press remain selected if the person changes the view.
  func completeSelection(_ submitted: Set<String>) {
    selection.subtract(submitted)
    for key in Array(selections.keys) { selections[key]?.subtract(submitted) }
  }
  func reload(_ folders: FolderSources) async {
    guard !Task.isCancelled else { return }
    generation += 1
    let current = generation, requestedKey = key
    let requestedSearch = search, requestedFilter = filter, requestedType = type
    let source: String?
    switch scope { case .all: source = nil; case .folder(let id): source = id }
    reloadingGeneration = current
    loading = sections.isEmpty
    defer {
      if reloadingGeneration == current { reloadingGeneration = nil }
      if current == generation { loading = false }
    }
    do {
      let depth = max(100, sections.first?.photos.count ?? 100)
      var section = Section(id: source ?? "all", photos: [], hasMore: true, nextOffset: 0)
      var seen = Set<String>()
      while section.photos.count < depth && section.hasMore {
        let page = try await folders.browse(source, offset: section.nextOffset, limit: min(1_000, depth - section.photos.count),
          search: requestedSearch, filter: requestedFilter, type: requestedType)
        guard current == generation, !Task.isCancelled else { return }
        section.photos += page.rows.filter { seen.insert($0.id).inserted }
        section.nextOffset += page.rows.count
        section.hasMore = page.has_more && !page.rows.isEmpty
      }
      let next = [section]
      sections = next; sectionCache[requestedKey] = next; resultKey = requestedKey; error = nil
    } catch { if current == generation, !Task.isCancelled { self.error = error.localizedDescription } }
  }
  func more(_ id: String, folders: FolderSources) async {
    let current = generation
    guard pagingGeneration != current, reloadingGeneration != current,
      let i = sections.firstIndex(where: { $0.id == id }), sections[i].hasMore else { return }
    pagingGeneration = current
    defer { if pagingGeneration == current { pagingGeneration = nil } }
    let offset = sections[i].nextOffset
    do {
      let page = try await folders.browse(id == "all" ? nil : id, offset: offset, search: search, filter: filter, type: type)
      guard current == generation, !Task.isCancelled, sections[i].nextOffset == offset else { return }
      // The inventory may gain rows ahead of this offset between fetches.
      // A diffable snapshot must never receive the same asset twice.
      var section = sections[i]
      var seen = Set(identifiers)
      section.photos += page.rows.filter { seen.insert($0.id).inserted }
      section.nextOffset += page.rows.count
      section.hasMore = page.has_more && !page.rows.isEmpty
      sections[i] = section
      sectionCache[key] = sections
    } catch { if current == generation, !Task.isCancelled { self.error = error.localizedDescription } }
  }
}

func folderSentence(_ facts: FolderFacts?) -> String {
  guard let facts, facts.available != nil else { return NSLocalizedString("folders_counting", comment: "") }
  if facts.available == false { return NSLocalizedString("folders_disconnected", comment: "") }
  if facts.needs_you > 0 { return String(format: NSLocalizedString("folders_needs_you", comment: ""), facts.needs_you, folderMediaCount(facts.media("needs_you"))) }
  if facts.in_flight > 0 { return String(format: NSLocalizedString("folders_backing_up", comment: ""), folderMediaCount(facts.media("in_flight")), ByteCountFormatter.string(fromByteCount: Int64(clamping: facts.in_flight_bytes), countStyle: .file)) }
  if facts.not_backed_up > 0 { return String(format: NSLocalizedString("folders_not_backed_up", comment: ""), facts.not_backed_up, folderMediaCount(facts.media("not_backed_up"))) }
  return String(format: NSLocalizedString("folders_saved", comment: ""), facts.saved, folderMediaCount(facts.media("saved")))
}

extension FolderSources {
  func location(_ source: FolderSource) -> String {
    let path = source.lastKnownPath ?? displayPath(source)
    let parts = path.split(separator: "/").map(String.init)
    if parts.first == "Volumes", parts.count > 1 {
      return String(format: NSLocalizedString("folders_external_location", comment: ""), parts[1])
    }
    if let index = parts.firstIndex(of: "Pictures") { return parts[index...].joined(separator: " › ") }
    return parts.suffix(2).joined(separator: " › ")
  }
  func syntheticImage(_ photo: FolderPhoto) -> NSImage? { previewImage?(photo.id) }
}

struct FolderCommandActions {
  var add: () -> Void
  var search: () -> Void
  var filter: (LibraryBackupView) -> Void
  var backUp: () -> Void
  var canBackUp: Bool
}
private struct FolderCommandsKey: FocusedValueKey { typealias Value = FolderCommandActions }
extension FocusedValues {
  var folderCommands: FolderCommandActions? {
    get { self[FolderCommandsKey.self] }
    set { self[FolderCommandsKey.self] = newValue }
  }
}
struct MacFolderCommands: Commands {
  @FocusedValue(\.folderCommands) private var actions
  @FocusedValue(\.photoViewerCommands) private var viewer
  @FocusedValue(\.gridInfoCommands) private var gridInfo
  @FocusedValue(\.windowInfoCommands) private var windowInfo
  @FocusedValue(\.historyZoom) private var historyZoom
  @FocusedValue(\.gridSearch) private var gridSearch
  @FocusedValue(\.settingsBack) private var settingsBack
  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("folders_back_up_selected") { actions?.backUp() }.disabled(actions?.canBackUp != true)
      Button("folders_add") { actions?.add() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(actions == nil)
    }
    CommandGroup(after: .textEditing) {
      Button("folders_search") { gridSearch?.open() }.keyboardShortcut("f", modifiers: .command).disabled(gridSearch == nil)
    }
    CommandGroup(after: .pasteboard) {
      Button("library_context_share") { viewer?.share() }.disabled(viewer == nil)
    }
    CommandGroup(after: .sidebar) {
      Button("mac_library_zoom_out") { historyZoom?.smaller() }.disabled(historyZoom?.canShrink != true)
      Button("mac_library_zoom_in") { historyZoom?.larger() }.disabled(historyZoom?.canGrow != true)
      Divider()
      Button(viewer == nil ? "mac_fidelity_back" : "mac_library_back") {
        if let viewer { viewer.back() } else { settingsBack?.back() }
      }
      .keyboardShortcut("[", modifiers: .command)
      .disabled(viewer == nil && settingsBack == nil)
      Divider()
      Button("folders_show_info") {
        if let windowInfo { windowInfo.toggle() }
        else if let viewer { viewer.info() } else { gridInfo?.toggle() }
      }.disabled(windowInfo == nil && viewer == nil && gridInfo == nil).keyboardShortcut("i", modifiers: .command)
      Divider()
      ForEach(LibraryBackupView.allCases) { view in
        Button(LocalizedStringKey(view.title)) { actions?.filter(view) }.disabled(actions == nil)
      }
    }
  }
}

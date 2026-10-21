import AppKit
import SwiftUI

struct FolderFacts: Decodable, Equatable {
  var supported: UInt64 = 0
  var saved: UInt64 = 0
  var in_flight: UInt64 = 0
  var in_flight_bytes: UInt64 = 0
  var needs_you: UInt64 = 0
  var not_backed_up: UInt64 = 0
  var available: Bool? = nil
  var unsupported_by_kind: [String: UInt64] = [:]
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
struct FolderPhotoPage: Decodable { let rows: [FolderPhoto]; let has_more: Bool }

/// Browse state only. Membership, filters, counts and durable backup intent come from Rust.
@MainActor final class FolderBrowser: ObservableObject {
  struct Section: Identifiable {
    let id: String
    var photos: [FolderPhoto]
    var hasMore: Bool
  }
  var configured = false
  @Published var byFolder = true { didSet { contextChanged() } }
  @Published var filter: LibraryBackupView = .all { didSet { contextChanged() } }
  @Published var search = "" { didSet { contextChanged() } }
  @Published var selection = Set<String>()
  @Published private(set) var sections: [Section] = []
  @Published private(set) var loading = false
  @Published var error: String?
  var offsets: [String: CGPoint] = [:]
  private var selections: [String: Set<String>] = [:]
  private var activeKey = "true|all|"
  private func contextChanged() {
    guard key != activeKey else { return }
    selections[activeKey] = selection
    activeKey = key; selection = selections[key] ?? []
  }
  private var loadingSections = Set<String>()
  private var generation = 0
  var key: String { "\(byFolder)|\(filter.rawValue)|\(search)" }
  var selected: [FolderPhoto] { sections.flatMap(\.photos).filter { selection.contains($0.id) && $0.canBackUp } }
  func reload(_ folders: FolderSources) async {
    generation += 1
    let current = generation
    let grouped = byFolder && search.isEmpty
    let ids = grouped ? folders.sources.map(\.id) : ["all"]
    loading = sections.isEmpty
    do {
      var next: [Section] = []
      for id in ids {
        let depth = max(100, sections.first { $0.id == id }?.photos.count ?? 100)
        var rows: [FolderPhoto] = []; var more = true
        while rows.count < depth && more {
          let page = try await folders.browse(id == "all" ? nil : id, offset: rows.count, search: search, filter: filter)
          guard current == generation, !Task.isCancelled else { return }
          rows += page.rows; more = page.has_more
          if grouped { rows = Array(rows.prefix(6)); more = false }
        }
        next.append(Section(id: id, photos: rows, hasMore: more))
      }
      guard current == generation else { return }
      sections = next; error = nil
    } catch { if current == generation { self.error = error.localizedDescription } }
    if current == generation { loading = false }
  }
  func more(_ id: String, folders: FolderSources) async {
    guard let i = sections.firstIndex(where: { $0.id == id }), sections[i].hasMore, !loadingSections.contains(id) else { return }
    loadingSections.insert(id); defer { loadingSections.remove(id) }
    let current = generation, offset = sections[i].photos.count
    do {
      let page = try await folders.browse(id == "all" ? nil : id, offset: offset, search: search, filter: filter)
      guard current == generation, let index = sections.firstIndex(where: { $0.id == id }), sections[index].photos.count == offset else { return }
      sections[index].photos += page.rows; sections[index].hasMore = page.has_more
    } catch { self.error = error.localizedDescription }
  }
}

func folderSentence(_ facts: FolderFacts?) -> String {
  guard let facts, facts.available != nil else { return NSLocalizedString("folders_counting", comment: "") }
  if facts.available == false { return NSLocalizedString("folders_disconnected", comment: "") }
  if facts.needs_you > 0 { return String(format: NSLocalizedString("folders_needs_you", comment: ""), facts.needs_you) }
  if facts.in_flight > 0 { return String(format: NSLocalizedString("folders_backing_up", comment: ""), facts.in_flight, ByteCountFormatter.string(fromByteCount: Int64(clamping: facts.in_flight_bytes), countStyle: .file)) }
  if facts.not_backed_up > 0 { return String(format: NSLocalizedString("folders_not_backed_up", comment: ""), facts.not_backed_up) }
  return String(format: NSLocalizedString("folders_saved", comment: ""), facts.saved)
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
  var view: (Bool) -> Void
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
  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("folders_back_up_selected") { actions?.backUp() }.disabled(actions?.canBackUp != true)
      Button("folders_add") { actions?.add() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(actions == nil)
    }
    CommandGroup(after: .textEditing) {
      Button("folders_search") { actions?.search() }.keyboardShortcut("f", modifiers: .command).disabled(actions == nil)
    }
    CommandMenu("folders_view") {
      Button("folders_by_folder") { actions?.view(true) }.disabled(actions == nil)
      Button("mac_library_all_photos") { actions?.view(false) }.disabled(actions == nil)
      Divider()
      Button("folders_show_info") { MacPhotoViewerWindow.toggleInfo(); MacFolderViewer.toggleInfo() }.keyboardShortcut("i", modifiers: .command)
      Divider()
      ForEach(LibraryBackupView.allCases) { view in
        Button(LocalizedStringKey(view.title)) { actions?.filter(view) }.disabled(actions == nil)
      }
    }
  }
}


/// A2: the toolbar and Find command share the system search field.
struct FolderSearchField: NSViewRepresentable {
  @Binding var text: String
  @Binding var focus: Bool
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = NSLocalizedString("folders_search", comment: "")
    field.setAccessibilityLabel(field.placeholderString)
    field.delegate = context.coordinator
    return field
  }
  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
    if focus {
      DispatchQueue.main.async {
        field.window?.makeFirstResponder(field); focus = false
      }
    }
  }
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: FolderSearchField
    init(_ parent: FolderSearchField) { self.parent = parent }
    func controlTextDidChange(_ note: Notification) {
      if let field = note.object as? NSSearchField { parent.text = field.stringValue }
    }
  }
}

import Combine
import Foundation
import os
import SwiftUI

/// A reviewable state of one production page, shared by the iPhone and Mac
/// catalogs. Scenarios are JSON files in `apps/apple/Catalog/Scenarios`; see
/// `apps/apple/Catalog/README.md` for the format.
struct Scenario: Identifiable {
  struct Action: Identifiable {
    let id = UUID()
    let action: String
    let result: String
  }
  /// One scripted answer for a core command. A list of answers is used in order,
  /// and its last answer repeats.
  struct Response {
    let value: Any?
    let error: String?
    let delay: Double
    /// Command fields this answer is for, such as a records filter. Answers with
    /// `when` are chosen by match, not in order; one without it is the fallback.
    let when: [String: String]?
  }

  let id: String
  /// The root destination: library, backup, receiver or settings; or onboarding.
  let page: String
  /// For onboarding: the screen to start on.
  let step: String?
  /// The records list to open from the hub: all, active, attention or saved.
  let records: String?
  /// Photo access the scenario reports: full (default), limited, denied or undetermined.
  let photoAccess: PhotoAccess
  let title: String
  let expect: [String]
  let actions: [Action]
  let pairing: Data?
  let files: [String: Data]
  let core: [String: [Response]]
  /// Library scenarios answer backup commands from the device's photo library
  /// (`LibraryScenario`); they need photo access and a synthetic library.
  let library: [String: Any]?
  /// The library's backup view to open with (design/library.md).
  var libraryView: LibraryBackupView? { (library?["view"] as? String).flatMap(LibraryBackupView.init(rawValue:)) }

  static func loadAll(from bundle: Bundle = .main) throws -> [Scenario] {
    let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Scenarios") ?? []
    var raw: [String: [String: Any]] = [:]
    for url in urls {
      guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
        let id = object["id"] as? String else { continue }
      raw[id] = object
    }
    return try raw.keys.sorted().compactMap { id in
      let object = try resolve(id, in: raw, seen: [])
      // Bases only supply shared answers; they are not reviewed on their own.
      guard object["page"] != nil else { return nil }
      #if !os(macOS)
        if object["mac_only"] as? Bool == true { return nil }
      #endif
      #if os(macOS)
        // Library scenarios read the photo library. On a Mac that is the
        // reviewer's real library, so they run only on the iOS Simulator.
        if object["library"] != nil || object["step"] as? String == "liveActivity" { return nil }
      #endif
      return try Scenario(object)
    }
  }

  /// Applies `extends`: the child's core answers and files override the base's.
  private static func resolve(_ id: String, in raw: [String: [String: Any]], seen: Set<String>) throws -> [String: Any] {
    guard let object = raw[id] else { throw CatalogError("unknown scenario \(id)") }
    guard let base = object["extends"] as? String else { return object }
    guard !seen.contains(base) else { throw CatalogError("extends cycle at \(id)") }
    var merged = try resolve(base, in: raw, seen: seen.union([id]))
    for (key, value) in object where key != "extends" {
      if ["core", "files"].contains(key), let child = value as? [String: Any] {
        merged[key] = (merged[key] as? [String: Any] ?? [:]).merging(child) { $1 }
      } else {
        merged[key] = value
      }
    }
    return merged
  }

  private init(_ object: [String: Any]) throws {
    id = object["id"] as! String
    guard let page = object["page"] as? String,
      ["library", "backup", "receiver", "settings", "onboarding", "connect", "sources"].contains(page) else {
      throw CatalogError("\(object["id"] ?? "?"): unknown page")
    }
    self.page = page
    step = object["step"] as? String
    records = object["records"] as? String
    photoAccess = PhotoAccess(rawValue: object["photo_access"] as? String ?? "") ?? .full
    title = object["title"] as? String ?? id
    expect = object["expect"] as? [String] ?? []
    actions = (object["actions"] as? [[String: String]] ?? []).map {
      Action(action: $0["action"] ?? "", result: $0["result"] ?? "")
    }
    if let value = object["pairing"], !(value is NSNull) {
      pairing = try JSONSerialization.data(withJSONObject: value)
    } else {
      pairing = nil
    }
    files = try (object["files"] as? [String: Any] ?? [:]).mapValues {
      try JSONSerialization.data(withJSONObject: $0)
    }
    // Timestamps written against `now_ms` move with the real clock, so "Today"
    // in a scenario stays today whenever it is reviewed.
    let shift = (object["now_ms"] as? NSNumber).map { Int64(Date().timeIntervalSince1970 * 1000) - $0.int64Value } ?? 0
    library = object["library"] as? [String: Any]
    let shiftedCore = Scenario.shifted(object["core"], by: shift)
    let mediaCore = library == nil ? SampleImages.fillingDates(shiftedCore) : shiftedCore
    core = (mediaCore as? [String: Any] ?? [:]).mapValues { entry in
      (entry as? [Any] ?? [entry]).map { item in
        let answer = item as? [String: Any] ?? [:]
        return Response(value: answer["value"], error: answer["error"] as? String,
          delay: answer["delay"] as? Double ?? 0,
          when: (answer["when"] as? [String: Any])?.mapValues { "\($0)" })
      }
    }
  }
}

extension Scenario {
  /// Shifts millisecond timestamps (`*_ms` and `sort_value` fields, numbers or
  /// numeric strings) by `offset`.
  static func shifted(_ value: Any?, by offset: Int64, key: String = "") -> Any? {
    guard offset != 0 else { return value }
    let timed = key.hasSuffix("_ms") || key == "sort_value"
    switch value {
    case let object as [String: Any]:
      return object.reduce(into: [String: Any]()) { $0[$1.key] = shifted($1.value, by: offset, key: $1.key) }
    case let list as [Any]:
      return list.map { shifted($0, by: offset, key: key) }
    case let number as NSNumber where timed && CFGetTypeID(number) != CFBooleanGetTypeID():
      return NSNumber(value: number.int64Value + offset)
    case let text as String where timed:
      return Int64(text).map { String($0 + offset) } ?? text
    default:
      return value
    }
  }

  /// Installs this scenario's answers and pairing, seeds its host files in a new
  /// folder and returns an unopened model for it. Each run gets a fresh model.
  @MainActor func makeModel(core: ScenarioCore, credentials: ScenarioCredentials) -> BackupModel {
    core.load(self)
    credentials.load(self)
    let access = photoAccess
    BackupEnvironment.photoAccess = { access }
    // Library scenarios read the (synthetic) photo library; all others never touch it.
    BackupEnvironment.usesPhotoLibrary = library != nil
    BackupEnvironment.sampleThumbnail = library == nil ? SampleImages.image(for:) : nil
    let receiverID = pairing.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["receiver_id"] as? String ?? ""
    core.library = library.map { LibraryScenario(options: .init($0), receiver: receiverID) }
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog/\(id)-\(UUID().uuidString)", isDirectory: true)
    let model = BackupModel(root: root)
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      for (name, data) in files { try data.write(to: root.appendingPathComponent(name), options: .atomic) }
    } catch { model.message = error.localizedDescription }
    return model
  }
}

struct CatalogError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

/// Answers core commands from the current scenario. A command the scenario does
/// not script fails with `catalog_unscripted` and is listed for the reviewer,
/// so a page never silently shows a state nobody specified.
final class ScenarioCore: CoreTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [String: [Scenario.Response]] = [:]
  private var cursor: [String: Int] = [:]
  private var missing: [String] = []
  private var generation = 0
  private let log = Logger(subsystem: "app.backupduck.catalog", category: "core")
  /// Answers derived from the photo library, consulted before the scripted ones.
  var library: LibraryScenario? {
    get { lock.withLock { libraryAnswers } }
    set { lock.withLock { libraryAnswers = newValue } }
  }
  private var libraryAnswers: LibraryScenario?

  func load(_ scenario: Scenario?) {
    lock.withLock {
      responses = scenario?.core ?? [:]
      cursor = [:]
      missing = []
      generation += 1
    }
  }

  var unscripted: [String] { lock.withLock { missing } }

  func call(_ command: String) async throws -> Data {
    let object = (try? JSONSerialization.jsonObject(with: Data(command.utf8))) as? [String: Any]
    let op = object?["op"] as? String ?? "?"
    if let object, let value = library?.answer(object) {
      return try JSONSerialization.data(withJSONObject: ["ok": true, "value": value], options: [.fragmentsAllowed])
    }
    let (answer, loaded): (Scenario.Response?, Int) = lock.withLock {
      guard let list = responses[op], !list.isEmpty else {
        if !missing.contains(op) { missing.append(op) }
        return (nil, generation)
      }
      if list.contains(where: { $0.when != nil }) {
        let matched = list.first { answer in
          answer.when.map { $0.allSatisfy { key, value in object?[key].map { "\($0)" } == value } } ?? false
        } ?? list.first { $0.when == nil }
        if matched == nil, !missing.contains(op) { missing.append(op) }
        return (matched, generation)
      }
      let index = cursor[op, default: 0]
      cursor[op] = index + 1
      return (list[min(index, list.count - 1)], generation)
    }
    guard let answer else {
      log.notice("unscripted \(op, privacy: .public)")
      return try Self.envelope(error: "catalog_unscripted")
    }
    log.debug("answer \(op, privacy: .public) \(answer.error ?? "ok", privacy: .public)")
    if answer.delay > 0 { try await Task.sleep(for: .seconds(answer.delay)) }
    // A scenario switch while this answer waited belongs to the old model.
    guard lock.withLock({ generation }) == loaded else { throw CancellationError() }
    if let error = answer.error { return try Self.envelope(error: error) }
    return try JSONSerialization.data(withJSONObject: ["ok": true, "value": answer.value ?? NSNull()],
      options: [.fragmentsAllowed])
  }

  private static func envelope(error: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["ok": false, "error": error])
  }
}

/// The scenario's pairing record, kept in memory instead of the keychain.
final class ScenarioCredentials: CredentialStore, @unchecked Sendable {
  private let lock = NSLock()
  private var data: Data?
  func load(_ scenario: Scenario?) { lock.withLock { data = scenario?.pairing } }
  func read() throws -> Data? { lock.withLock { data } }
  func save(_ data: Data) throws { lock.withLock { self.data = data } }
}

/// Isolated scope preferences and 500 synthetic albums; no PhotoKit or app defaults.
@MainActor final class ScopeCatalogFixture: ObservableObject {
  let store: BackupScopeStore
  let albums: ScopeAlbumsModel
  let destination: BackupScopeDestination
  let search: String

  init(id: String) {
    destination = id.hasSuffix("types") ? .types : .albums
    search = id.hasSuffix("search") ? "Family" : ""
    let defaults = UserDefaults(suiteName: "catalog.scope." + UUID().uuidString)!
    store = BackupScopeStore(defaults: defaults)
    var rule = BackupScopeRule(types: [.photo, .motion, .video], restrictAlbums: true,
      albums: ["album.0", "album.1", "album.2"])
    let names = ["Trips", "Family", "Favorites"]
    var rows = (0..<500).map { index in
      ScopeAlbum(id: "album.\(index)", name: index < names.count ? names[index] : "Album \(index.formatted())",
        count: index < 3 ? [2000, 1210, 1000][index] : index * 3, system: false,
        cover: index % 7 == 3 ? nil : AlbumCoverSampleAsset("scope.cover.\(index)"))
    }
    if id.hasSuffix("empty") { rows = []; rule.albums = [] }
    if id.hasSuffix("unavailable") {
      rule.albums.insert("album.unavailable")
      rule.albumNames["album.unavailable"] = "Archived family photos"
    }
    store.save(rule)
    albums = ScopeAlbumsModel(albums: rows, denied: id.hasSuffix("denied"))
  }
}

/// Synthetic toolbar specimen; no photo library, original export or transfer.
/// The action/confirmation/feedback controls are the production components.
struct SelectionBackupCatalog: View {
  let mode: String
  @StateObject private var action = SelectionBackupAction()
  @State private var count = 3
  var body: some View {
    NavigationStack {
      List {
        Text("Synthetic selection: \(count) photos")
        Text("Transfer progress belongs to Backup / Overview.").foregroundStyle(.secondary)
        Button("Select Again") { count = 3; action.selectionChanged() }
      }
      .navigationTitle("nav_library")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          DuckSelectionBackupControl(action: action, count: count, request: {
            if mode == "repeat" { action.confirmingRepeat = true }
            else { await submit() }
          }, confirm: {
            action.confirmingRepeat = false
            await submit()
          }).buttonStyle(.borderedProminent)
        }
      }
    }
  }
  private func submit() async {
    await action.perform({
      if mode == "failure" { return false }
      count = 0; return true
    }, failure: { NSLocalizedString("apple_selected_receiver_needed", comment: "") })
  }
}

// Reserved content is injected only by these explicit catalog scenarios.
extension Scenario {
  var reservedSettingsContent: DuckReservedSettingsContent {
    guard ["settings.about-reserved", "settings.feedback-reserved"].contains(id) else { return .production }
    return DuckReservedSettingsContent(
      authorText: NSLocalizedString("settings_author_placeholder", comment: ""),
      feedbackEmail: "feedback@example.invalid",
      appStoreAppID: "0000000000"
    )
  }
}

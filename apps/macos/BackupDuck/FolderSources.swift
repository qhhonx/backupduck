import AppKit
import AVFoundation
import CoreServices
import ImageIO
import SwiftUI

struct FolderRuleError: LocalizedError {
  let detail: String
  var errorDescription: String? { detail }
}

struct FolderIssue: Codable {
  let reason: String
  let detail: String?
}
struct FolderPendingControl: Codable, Equatable {
  var id: String = UUID().uuidString
  var action: String
  var relative: String? = nil
  var revision: String? = nil
}
struct FolderSource: Codable, Identifiable {
  let id: String
  var name: String
  var bookmark: Data
  var automatic: Bool
  var enabled: Bool
  var receiver: String?
  var lastCheck: Date?
  var issues: [String: String] = [:]
  var baselinePending: Bool = false
  // Optional additions preserve decoding of sources saved by earlier versions.
  var issueDetails: [String: FolderIssue]?
  var retryPaths: [String]?
  var includePatterns: [String]?
  var excludePatterns: [String]?
  var lastKnownPath: String?
  var manualCutoffMS: UInt64? = nil
  var baselineCutoffMS: UInt64? = nil
  var pendingControl: FolderPendingControl? = nil
  var automaticActive: Bool { automatic && enabled }
  var manualActive: Bool { enabled && !automatic }
}
struct FolderSummary: Decodable, Equatable {
  let files: UInt64
  let bytes: UInt64
  let unsupported: UInt64
  let scanning: Bool
}

@MainActor final class FolderSources: ObservableObject {
  static let shared = FolderSources(backup: .shared)
  @Published var sources: [FolderSource] = []
  @Published private(set) var loadFailed = false
  @Published var selectedSourceID: String?
  @Published var summaries: [String: FolderSummary] = [:]
  @Published var phases: [String: String] = [:]
  @Published var error: String?
  @Published var actionMessages: [String: String] = [:]
  @Published var starting = Set<String>()
  @Published var recoveringControls = Set<String>()
  @Published var revision = 0
  @Published var indexRevision = 0
  private var watches: [String: FolderWatch] = [:]
  private var access: [String: URL] = [:]
  private var dirty = Set<String>()
  private var scan: String?
  private var fullChecks = Set<String>()
  private var changedFolders: [String: Set<String>] = [:]
  private var loop: Task<Void, Never>?
  private var lastTurn = 0
  private var retryTurn: [String: Int] = [:]
  private var controlRevision: [String: Int] = [:]
  private var savingRules = Set<String>()
  private var debounce: [String: Date] = [:]
  private let backup: BackupModel
  private var file: URL { backup.root.appendingPathComponent("folder-sources.json") }
  private let writeConfiguration: (Data, URL) throws -> Void
  init(backup: BackupModel, writeConfiguration: @escaping (Data, URL) throws -> Void = { data, url in
    try data.write(to: url, options: .atomic)
  }) { self.backup = backup; self.writeConfiguration = writeConfiguration }
  private func persist(_ values: [FolderSource]) throws {
    try writeConfiguration(JSONEncoder().encode(values), file)
  }
  private func call(_ command: [String: Any]) async throws -> Data {
    try await Bridge.call(["op": "folder", "command": command])
  }
  func open() async {
    guard loop == nil else { return }
    while !backup.ready { try? await Task.sleep(nanoseconds: 500_000_000); if Task.isCancelled { return } }
    do {
      loadFailed = false; error = nil
      if FileManager.default.fileExists(atPath: file.path) {
        sources = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: file))
      }
      // Older versions could leave automatic on while the source was paused.
      // Preserve that pause as an off switch in the unified controls.
      let migrated = sources.contains { $0.automatic && !$0.enabled }
      for i in sources.indices where !sources[i].enabled { sources[i].automatic = false }
      // Older manual runs had no saved boundary. Freeze them at upgrade time.
      let cutoff = UInt64(Date().timeIntervalSince1970 * 1000)
      var boundedLegacy = false
      for i in sources.indices where sources[i].manualActive && sources[i].manualCutoffMS == nil {
        sources[i].manualCutoffMS = cutoff; boundedLegacy = true
      }
      for i in sources.indices where sources[i].baselinePending && sources[i].baselineCutoffMS == nil {
        sources[i].baselineCutoffMS = cutoff; boundedLegacy = true
      }
      if migrated || boundedLegacy { save() }
      for source in sources where source.pendingControl != nil { _ = await recoverPendingControl(source.id) }
      for source in sources where source.pendingControl == nil {
        if source.includePatterns != nil || source.excludePatterns != nil {
          _ = try await call(["action": "rules", "source": source.id, "include": source.includePatterns ?? [], "exclude": source.excludePatterns ?? []])
        }
        check(source.id)
      }
      loop = Task { [weak self] in
        while !Task.isCancelled {
          await self?.tick()
          try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
      }
    } catch { loadFailed = true; self.error = error.localizedDescription }
  }
  private func save() {
    do { try persist(sources) }
    catch { self.error = error.localizedDescription }
  }
  // Reject known persistence faults before mutating the native index. This
  // does not claim a cross-store transaction: native SQLite and this derived
  // source configuration remain separate durable stores.
  private func preflightPersistence() throws {
    guard !loadFailed else { throw Bridge.Failure(code: "storage") }
    try persist(sources)
  }
  func add(_ url: URL, automatic: Bool, existing: Bool, include: [String] = [], exclude: [String] = []) async throws {
    guard !loadFailed else { throw Bridge.Failure(code: "storage") }
    let cutoff = UInt64(Date().timeIntervalSince1970 * 1000)
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let managed = backup.root.resolvingSymlinksInPath().path
    guard !path.hasPrefix(managed + "/"), !managed.hasPrefix(path + "/"), path != managed else {
      throw Bridge.Failure(code: "invalid")
    }
    for source in sources {
      var stale = false
      if let other = try? URL(resolvingBookmarkData: source.bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
        let otherPath = other.resolvingSymlinksInPath().standardizedFileURL.path
        guard path != otherPath, !path.hasPrefix(otherPath + "/"), !otherPath.hasPrefix(path + "/") else {
          throw Bridge.Failure(code: "conflict")
        }
      }
    }
    try await validateRules(include: include, exclude: exclude)
    let bookmark = try url.resolvingSymlinksInPath().bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    let source = FolderSource(id: UUID().uuidString, name: url.lastPathComponent, bookmark: bookmark,
      automatic: automatic, enabled: existing || automatic, receiver: backup.pairing?.receiverID, lastCheck: nil, baselinePending: !existing, includePatterns: include, excludePatterns: exclude, lastKnownPath: url.path,
      manualCutoffMS: !automatic && existing ? cutoff : nil,
      baselineCutoffMS: !existing ? cutoff : nil)
    try preflightPersistence()
    _ = try await call(["action": "rules", "source": source.id, "include": include, "exclude": exclude])
    let next = sources + [source]
    do { try persist(next) }
    catch {
      _ = try? await call(["action": "forget", "source": source.id])
      self.error = error.localizedDescription
      throw error
    }
    sources = next; check(source.id)
  }
  func check(_ id: String, userInitiated: Bool = false) {
    guard let source = sources.first(where: { $0.id == id }) else { return }
    dirty.insert(id); fullChecks.insert(id); debounce[id] = .distantPast
    if userInitiated { error = nil }
    guard (try? url(source)) != nil else { markOffline(id); return }
    if userInitiated { actionMessages[id] = "folder_check_requested" }
  }
  func sourceURL(_ source: FolderSource) -> URL? {
    var stale = false
    return try? URL(resolvingBookmarkData: source.bookmark,
      options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil,
      bookmarkDataIsStale: &stale)
  }
  func displayName(_ source: FolderSource) -> String {
    guard let url = sourceURL(source) else { return source.name }
    return url.lastPathComponent
  }
  func displayPath(_ source: FolderSource) -> String {
    let path = sourceURL(source)?.path ?? source.lastKnownPath ?? source.name
    return (path as NSString).abbreviatingWithTildeInPath
  }
  func wake() {
    watches.removeAll()
    for (id, url) in access { url.stopAccessingSecurityScopedResource(); dirty.insert(id) }
    access.removeAll()
    for source in sources { check(source.id) }
  }
  @discardableResult func setAutomatic(_ id: String, _ value: Bool) -> Bool {
    guard let index = sources.firstIndex(where: { $0.id == id }), !loadFailed, sources[index].pendingControl == nil else { return false }
    error = nil
    var next = sources
    next[index].automatic = value; next[index].enabled = value
    if !value { next[index].retryPaths = nil }
    do {
      try persist(next)
      sources = next; controlRevision[id, default: 0] += 1
      if value { check(id) } else { phases[id] = "folder_manual_idle" }
      actionMessages[id] = value ? "folder_automatic_on" : "folder_automatic_off"
      return true
    } catch { self.error = error.localizedDescription; actionMessages[id] = "folder_action_failed"; return false }
  }
  @discardableResult func start(_ id: String) async -> Bool {
    guard !starting.contains(id), !loadFailed,
      let i = sources.firstIndex(where: { $0.id == id }), sources[i].pendingControl == nil else { return false }
    guard backup.ready, let target = backup.pairing else { actionMessages[id] = "folder_pair_first"; return false }
    error = nil
    let cutoff = UInt64(Date().timeIntervalSince1970 * 1000)
    var next = sources
    if !next[i].automaticActive { next[i].automatic = false }
    next[i].enabled = true; next[i].receiver = target.receiverID
    if !next[i].automatic { next[i].manualCutoffMS = cutoff }
    next[i].retryPaths = next[i].issues.keys.sorted(); next[i].baselinePending = false
    next[i].pendingControl = FolderPendingControl(action: "start")
    do { try persist(next); sources = next; controlRevision[id, default: 0] += 1 }
    catch { self.error = error.localizedDescription; actionMessages[id] = "folder_action_failed"; return false }
    return await recoverPendingControl(id)
  }
  @discardableResult func pause(_ id: String) -> Bool {
    guard let i = sources.firstIndex(where: { $0.id == id }), !loadFailed, sources[i].pendingControl == nil else { return false }
    error = nil
    var next = sources
    next[i].enabled = false; next[i].automatic = false; next[i].retryPaths = nil
    do {
      try persist(next)
      sources = next; controlRevision[id, default: 0] += 1
      phases[id] = "folder_paused"; actionMessages[id] = "folder_pause_explanation"
      return true
    } catch { self.error = error.localizedDescription; actionMessages[id] = "folder_action_failed"; return false }
  }
  @discardableResult func retry(_ id: String, relative: String) async -> Bool {
    guard !loadFailed, let i = sources.firstIndex(where: { $0.id == id }),
      sources[i].pendingControl == nil, sources[i].issues[relative] != nil,
      !(sources[i].retryPaths ?? []).contains(relative) else { return false }
    guard backup.ready, let receiver = backup.pairing?.receiverID else { actionMessages[id] = "folder_pair_first"; return false }
    guard sources[i].receiver == nil || sources[i].receiver == receiver else { actionMessages[id] = "folder_receiver_changed"; return false }
    error = nil
    var next = sources
    next[i].receiver = receiver
    next[i].retryPaths = Array(Set((next[i].retryPaths ?? []) + [relative])).sorted()
    next[i].pendingControl = FolderPendingControl(action: "retry", relative: relative)
    do { try persist(next); sources = next; controlRevision[id, default: 0] += 1 }
    catch { self.error = error.localizedDescription; actionMessages[id] = "folder_action_failed"; return false }
    return await recoverPendingControl(id)
  }

  private func validateRules(include: [String], exclude: [String]) async throws {
    let data = try await call(["action": "validate_rules", "include": include, "exclude": exclude])
    let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let detail = result?["error"] as? String { throw FolderRuleError(detail: detail) }
  }
  func saveRules(_ id: String, include: [String], exclude: [String]) async throws {
    guard !loadFailed, let i = sources.firstIndex(where: { $0.id == id }),
      sources[i].pendingControl == nil, !savingRules.contains(id) else { throw Bridge.Failure(code: "conflict") }
    savingRules.insert(id)
    defer { savingRules.remove(id) }
    try await validateRules(include: include, exclude: exclude)
    guard let current = sources.firstIndex(where: { $0.id == id }), sources[current].pendingControl == nil else { throw Bridge.Failure(code: "conflict") }
    var next = sources
    next[current].includePatterns = include; next[current].excludePatterns = exclude; next[current].retryPaths = nil
    next[current].pendingControl = FolderPendingControl(action: "rules")
    try persist(next); sources = next; controlRevision[id, default: 0] += 1
    guard await recoverPendingControl(id) else {
      throw FolderRuleError(detail: error ?? NSLocalizedString("mac_folder_operation_recovery", comment: ""))
    }
  }
  @discardableResult func dismissIssue(_ id: String, relative: String) async -> Bool {
    guard !loadFailed, let i = sources.firstIndex(where: { $0.id == id }), sources[i].pendingControl == nil else { return false }
    guard let version = sources[i].issues[relative] else { return true }
    error = nil
    var next = sources
    next[i].pendingControl = FolderPendingControl(action: "dismiss", relative: relative, revision: version)
    do { try persist(next); sources = next; controlRevision[id, default: 0] += 1 }
    catch { self.error = error.localizedDescription; return false }
    return await recoverPendingControl(id)
  }

  /// A durable intent blocks sending until native idempotent work and the final
  /// JSON acknowledgement both succeed. Replaying never expands a start cutoff
  /// or changes the target frozen in the saved plan.
  @discardableResult func recoverPendingControl(_ id: String) async -> Bool {
    guard !loadFailed, !recoveringControls.contains(id),
      let original = sources.first(where: { $0.id == id }), let pending = original.pendingControl else { return false }
    recoveringControls.insert(id); starting.insert(id)
    defer { recoveringControls.remove(id); starting.remove(id) }
    error = nil
    var applied = false
    do {
      if scan == id { _ = try await call(["action": "cancel"]); scan = nil; dirty.insert(id); fullChecks.insert(id) }
      switch pending.action {
      case "start":
        _ = try await call(["action": "include_existing", "source": id])
        _ = try await call(["action": "retry_ignored", "source": id])
      case "retry":
        guard let relative = pending.relative else { throw Bridge.Failure(code: "invalid") }
        _ = try await call(["action": "retry_ignored", "source": id, "relative": relative])
      case "rules":
        _ = try await call(["action": "rules", "source": id,
          "include": original.includePatterns ?? [], "exclude": original.excludePatterns ?? []])
      case "dismiss":
        guard let relative = pending.relative, let version = pending.revision else { throw Bridge.Failure(code: "invalid") }
        _ = try await call(["action": "dismiss", "source": id, "relative": relative, "revision": version])
      case "remove": _ = try await call(["action": "forget", "source": id])
      default: throw Bridge.Failure(code: "invalid")
      }
      applied = true
      guard let i = sources.firstIndex(where: { $0.id == id }), sources[i].pendingControl?.id == pending.id else { throw Bridge.Failure(code: "conflict") }
      var next = sources
      if pending.action == "dismiss", let relative = pending.relative {
        // The native version tombstone is already durable. This issue list is
        // only a UI cache; even if its JSON save fails we must show the truth.
        if next[i].issues[relative] == pending.revision {
          next[i].issues.removeValue(forKey: relative); next[i].issueDetails?.removeValue(forKey: relative)
          next[i].retryPaths?.removeAll { $0 == relative }
        }
        sources = next
      }
      if pending.action == "remove" { next.remove(at: i) }
      else { next[i].pendingControl = nil }
      try persist(next); sources = next
      if pending.action == "remove" {
        if selectedSourceID == id { selectedSourceID = nil }
        dirty.remove(id); fullChecks.remove(id); watches[id] = nil
        summaries[id] = nil; phases[id] = nil; retryTurn[id] = nil; controlRevision[id] = nil
        access.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        actionMessages[id] = nil
      } else {
        check(id); indexRevision += 1
        if ["start", "retry"].contains(pending.action) {
          if original.receiver != backup.pairing?.receiverID {
            actionMessages[id] = "folder_receiver_changed"; phases[id] = "folder_receiver_changed"
          } else {
            actionMessages[id] = backup.paused ? "folder_global_wait" : pending.action == "start" ? "folder_backup_requested" : "folder_retry_requested"
          }
        } else { actionMessages[id] = nil }
      }
      revision += 1
      return true
    } catch {
      let key = applied && pending.action == "dismiss" ? "mac_folder_ignore_applied_recovery" : "mac_folder_operation_recovery"
      self.error = NSLocalizedString(key, comment: "") + " " + error.localizedDescription
      actionMessages[id] = key
      return false
    }
  }

  func reveal(_ source: FolderSource, relative: String? = nil) {
    guard let root = try? url(source) else { error = NSLocalizedString("folder_offline", comment: ""); return }
    var target = root
    if let relative {
      guard !relative.hasPrefix("/"), relative.split(separator: "/").allSatisfy({ $0 != ".." && $0 != "." }) else { return }
      target = root.appendingPathComponent(relative).standardizedFileURL
      guard target.path.hasPrefix(root.path + "/"), target.resolvingSymlinksInPath().path == target.path else {
        error = NSLocalizedString("folder_issue_missing", comment: ""); return
      }
      guard FileManager.default.fileExists(atPath: target.path), FileManager.default.isReadableFile(atPath: target.path) else {
        error = NSLocalizedString("folder_issue_missing", comment: ""); return
      }
    }
    error = nil
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }
  private func clearIssue(_ id: String, _ relative: String) {
    guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
    sources[i].issues.removeValue(forKey: relative)
    sources[i].issueDetails?.removeValue(forKey: relative)
    sources[i].retryPaths?.removeAll { $0 == relative }
    if sources[i].retryPaths?.isEmpty != false,
      ["folder_retry_requested", "folder_global_wait"].contains(actionMessages[id] ?? "") { actionMessages[id] = nil }
  }
  @discardableResult func remove(_ id: String) async -> Bool {
    guard !loadFailed else { return false }
    guard let i = sources.firstIndex(where: { $0.id == id }) else { return true }
    if sources[i].pendingControl?.action == "remove" { return await recoverPendingControl(id) }
    guard sources[i].pendingControl == nil else { return false }
    error = nil
    var next = sources
    next[i].pendingControl = FolderPendingControl(action: "remove")
    do { try persist(next); sources = next; controlRevision[id, default: 0] += 1 }
    catch { self.error = error.localizedDescription; return false }
    return await recoverPendingControl(id)
  }

  private func available(_ url: URL) -> Bool {
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
      && directory.boolValue && FileManager.default.isReadableFile(atPath: url.path)
  }
  private func url(_ source: FolderSource) throws -> URL {
    if let value = access[source.id], available(value) { return value }
    var stale = false
    let value: URL
    do {
      value = try URL(resolvingBookmarkData: source.bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
    } catch { throw Bridge.Failure(code: "source_unavailable") }
    _ = value.startAccessingSecurityScopedResource()
    guard available(value) else {
      value.stopAccessingSecurityScopedResource(); throw Bridge.Failure(code: "source_unavailable")
    }
    access[source.id]?.stopAccessingSecurityScopedResource(); access[source.id] = value
    watches[source.id] = FolderWatch(url: value) { [weak self] paths, full in
      Task { @MainActor in
        guard let self, self.sources.first(where: { $0.id == source.id })?.automatic == true else { return }
        self.dirty.insert(source.id)
        if full { self.fullChecks.insert(source.id) }
        for path in paths {
          let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
          if parent == value.path { self.fullChecks.insert(source.id) }
          else if parent.hasPrefix(value.path + "/") { self.changedFolders[source.id, default: []].insert(String(parent.dropFirst(value.path.count + 1))) }
          else { self.fullChecks.insert(source.id) }
        }
        self.debounce[source.id] = Date().addingTimeInterval(3)
      }
    }
    if let i = sources.firstIndex(where: { $0.id == source.id }), stale || sources[i].lastKnownPath != value.path {
      if stale { sources[i].bookmark = try value.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) }
      sources[i].lastKnownPath = value.path; save()
    }
    return value
  }
  private func setPhase(_ id: String, _ phase: String) {
    if phases[id] != phase { phases[id] = phase }
  }
  private func markOffline(_ id: String) {
    setPhase(id, "folder_offline")
    // A failed root lookup is not an individual file failure. Keep inventory and receipts.
    dirty.insert(id); fullChecks.insert(id)
    access.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    watches[id] = nil
    if actionMessages[id] != nil { actionMessages[id] = nil }
  }
  private func tick() async {
    guard backup.ready else { return }
    if let id = scan {
      do {
        if sources.first(where: { $0.id == id })?.pendingControl != nil { return }
        guard let source = sources.first(where: { $0.id == id }), (try? url(source)) != nil else {
          throw Bridge.Failure(code: "source_unavailable")
        }
        for _ in 0..<4 {
          let summary = try JSONDecoder().decode(FolderSummary.self, from: await call(["action": "step"]))
          if summaries[id] != summary { summaries[id] = summary }
          if !summary.scanning {
            scan = nil; revision += 1; indexRevision += 1
            if actionMessages[id] == "folder_check_requested" || actionMessages[id] == "folder_check_running" {
              actionMessages[id] = "folder_check_finished"
            }
            if let i = sources.firstIndex(where: { $0.id == id }) {
              sources[i].lastCheck = Date()
              if sources[i].baselinePending {
                var command: [String: Any] = ["action": "baseline", "source": id, "receiver": "@baseline"]
                if let cutoff = sources[i].baselineCutoffMS { command["max_created_ms"] = cutoff }
                _ = try await call(command)
                if let current = sources.firstIndex(where: { $0.id == id }) { sources[current].baselinePending = false }
              }
              save()
            }
            break
          }
        }
      } catch {
        _ = try? await call(["action": "cancel"])
        scan = nil; dirty.insert(id); fullChecks.insert(id)
        if let source = sources.first(where: { $0.id == id }), (try? url(source)) == nil {
          markOffline(id)
        } else {
          setPhase(id, "folder_scan_failed"); debounce[id] = Date().addingTimeInterval(60)
          if ["folder_check_requested", "folder_check_running"].contains(actionMessages[id] ?? "") { actionMessages[id] = "folder_scan_failed" }
        }
      }
    }
    guard !sources.isEmpty else { return }
    lastTurn = (lastTurn + 1) % sources.count
    let source = sources[lastTurn]
    guard !savingRules.contains(source.id), source.pendingControl == nil else { return }
    var currentEntry: FolderEntry?
    var companionEntry: FolderEntry?
    do {
      let root = try url(source)
      if scan == nil, dirty.contains(source.id) || (source.automatic && Date().timeIntervalSince(source.lastCheck ?? .distantPast) > (watches[source.id]?.active == true ? 3600 : 60)) {
        if Date() >= (debounce[source.id] ?? .distantPast) {
          let scopes = fullChecks.contains(source.id) || (changedFolders[source.id]?.count ?? 0) > 256 ? [] : Array(changedFolders[source.id] ?? [])
          _ = try await call(["action": "begin", "source": source.id, "root": root.path, "directories": scopes])
          fullChecks.remove(source.id); changedFolders[source.id] = nil
          scan = source.id; dirty.remove(source.id); setPhase(source.id, "folder_scanning")
          if actionMessages[source.id] == "folder_check_requested" { actionMessages[source.id] = "folder_check_running" }
        }
      }
      if scan == source.id { return }
      let retries = source.retryPaths ?? []
      let retryPath = retries.isEmpty ? nil : retries[(retryTurn[source.id] ?? 0) % retries.count]
      if retryPath != nil { retryTurn[source.id] = (retryTurn[source.id] ?? 0) + 1 }
      guard source.enabled || retryPath != nil else { setPhase(source.id, "folder_manual_idle"); return }
      guard let receiver = backup.pairing?.receiverID else { setPhase(source.id, "folder_pair_first"); return }
      guard source.receiver == receiver || source.receiver == nil else { setPhase(source.id, "folder_receiver_changed"); return }
      if source.receiver == nil, let i = sources.firstIndex(where: { $0.id == source.id }) { sources[i].receiver = receiver; save() }
      if source.baselinePending {
        guard source.lastCheck != nil else { return }
        var command: [String: Any] = ["action": "baseline", "source": source.id, "receiver": "@baseline"]
        if let cutoff = source.baselineCutoffMS { command["max_created_ms"] = cutoff }
        _ = try await call(command)
        if let i = sources.firstIndex(where: { $0.id == source.id }) { sources[i].baselinePending = false; save() }
        return
      }
      guard !backup.paused else { setPhase(source.id, "backup_paused"); return }
      guard backup.summary.queued + backup.summary.running + backup.summary.waiting < 16 else { setPhase(source.id, "folder_queue_wait"); return }
      guard await backup.canPrepareForReceiver() else { setPhase(source.id, "waiting_for_wifi"); return }
      var candidateCommand: [String: Any] = ["action": "candidates", "source": source.id, "receiver": receiver]
      if let retryPath { candidateCommand["relative"] = retryPath }
      let manualCutoff = source.automatic ? nil : source.manualCutoffMS
      let candidateCutoff = retryPath == nil ? manualCutoff : nil
      if let candidateCutoff { candidateCommand["max_created_ms"] = candidateCutoff }
      var entries = try JSONDecoder().decode([FolderEntry].self, from: await call(candidateCommand))
      if let retryPath, entries.isEmpty {
        if let states = try? await states(source.id, relatives: [retryPath]), states[retryPath] != nil, states[retryPath] != "excluded" {
          clearIssue(source.id, retryPath); save(); return
        }
        do { _ = try await call(["action": "entry", "source": source.id, "relative": retryPath]) }
        catch let failure as Bridge.Failure where failure.code == "not_found" {
          if let i = sources.firstIndex(where: { $0.id == source.id }) {
            sources[i].retryPaths?.removeAll { $0 == retryPath }
            sources[i].issueDetails = (sources[i].issueDetails ?? [:]).merging([retryPath: FolderIssue(reason: "missing", detail: nil)]) { _, new in new }
            save()
          }
        }
        if source.enabled {
          candidateCommand.removeValue(forKey: "relative")
          if let manualCutoff { candidateCommand["max_created_ms"] = manualCutoff }
          entries = try JSONDecoder().decode([FolderEntry].self, from: await call(candidateCommand))
        } else { setPhase(source.id, "folder_settling"); return }
      }
      if entries.isEmpty, Date().timeIntervalSince(source.lastCheck ?? .distantPast) < 12 { setPhase(source.id, "folder_settling"); return }
      guard let entry = entries.first(where: { retries.contains($0.relative) || source.issues[$0.relative] != $0.revision }) else {
        var pendingCommand: [String: Any] = ["action": "pending", "source": source.id, "receiver": receiver]
        if let manualCutoff { pendingCommand["max_created_ms"] = manualCutoff }
        let pendingData = try await call(pendingCommand)
        let pending = (try JSONSerialization.jsonObject(with: pendingData) as? [String: Int])?["count"] ?? 0
        if pending > 0 { setPhase(source.id, "folder_cache_wait"); return }
        setPhase(source.id, source.issues.isEmpty ? "folder_up_to_date" : "folder_attention")
        if entries.isEmpty, !source.automatic, Date().timeIntervalSince(source.lastCheck ?? .distantPast) > 12, let i = sources.firstIndex(where: { $0.id == source.id }) { sources[i].enabled = false; save() }
        return
      }
      currentEntry = entry
      setPhase(source.id, "folder_preparing")
      let entryCutoff = entry.relative == retryPath ? nil : manualCutoff
      let prepared = try await FolderMedia.prepare(root: root, entry: entry) { relative in
        var eligibility: [String: Any] = ["action": "eligible", "source": source.id, "relative": relative]
        if let entryCutoff { eligibility["max_created_ms"] = entryCutoff }
        guard let data = try? await self.call(eligibility) else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
      }
      var primary = entry
      if prepared.primary != entry.relative {
        primary = try JSONDecoder().decode(FolderEntry.self, from: await call(["action": "entry", "source": source.id, "relative": prepared.primary]))
      }
      currentEntry = primary
      var command: [String: Any] = ["action": "prepare", "source": source.id, "name": source.name,
        "root": root.path, "relative": primary.relative, "source_id": primary.source_id,
        "revision": primary.revision, "receiver": receiver, "metadata": prepared.metadata]
      if let paired = prepared.paired {
        let companion = try JSONDecoder().decode(FolderEntry.self, from: await call(["action": "entry", "source": source.id, "relative": paired]))
        companionEntry = companion
        command["paired"] = [companion.relative, companion.revision]
      }
      // Recheck global/source pause and target after asynchronous media inspection.
      guard !backup.paused, backup.pairing?.receiverID == receiver,
        let latest = sources.first(where: { $0.id == source.id }),
        latest.pendingControl == nil,
        latest.enabled || (latest.retryPaths ?? []).contains(entry.relative) else { return }
      _ = try await call(command); revision += 1
      clearIssue(source.id, primary.relative)
      if let paired = prepared.paired { clearIssue(source.id, paired) }
      save()
      await backup.refresh(); await BackgroundTransfer.shared.kick()
    } catch FolderMediaError.changed {
      guard (try? url(source)) != nil else { markOffline(source.id); return }
      dirty.insert(source.id); debounce[source.id] = Date().addingTimeInterval(12)
      setPhase(source.id, "folder_settling")
    } catch let failure as Bridge.Failure {
      guard failure.code != "source_unavailable", (try? url(source)) != nil else { markOffline(source.id); return }
      if failure.code == "capacity" {
        for entry in [currentEntry, companionEntry].compactMap({ $0 }) {
          _ = try? await call(["action": "defer", "source": source.id, "relative": entry.relative, "revision": entry.revision])
        }
      }
      if failure.code == "conflict" {
        dirty.insert(source.id); debounce[source.id] = Date().addingTimeInterval(12)
        setPhase(source.id, "folder_settling"); return
      }
      if failure.code == "unsupported" || failure.code == "invalid" { await ignore(source, entry: currentEntry, reason: "invalid_media", detail: failure.localizedDescription) }
      setPhase(source.id, failure.code == "capacity" ? "folder_cache_wait" :
        sources.first(where: { $0.id == source.id })?.issues.isEmpty == false ? "folder_attention" : "folder_action_failed")
    } catch {
      guard (try? url(source)) != nil else { markOffline(source.id); return }
      let failure = error as NSError
      let permission = (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
        || (failure.domain == NSPOSIXErrorDomain && failure.code == 13)
      await ignore(source, entry: currentEntry, reason: permission ? "permission" : "unreadable_media",
        detail: error is FolderMediaError ? nil : error.localizedDescription)
      setPhase(source.id, sources.first(where: { $0.id == source.id })?.issues.isEmpty == false ? "folder_attention" : "folder_action_failed")
    }
  }
  private func ignore(_ source: FolderSource, entry: FolderEntry?, reason: String, detail: String?) async {
    guard let entry, let i = sources.firstIndex(where: { $0.id == source.id }) else { return }
    sources[i].issues[entry.relative] = entry.revision
    sources[i].issueDetails = (sources[i].issueDetails ?? [:]).merging([entry.relative: FolderIssue(reason: reason, detail: detail)]) { _, new in new }
    sources[i].retryPaths?.removeAll { $0 == entry.relative }
    if ["folder_retry_requested", "folder_global_wait"].contains(actionMessages[source.id] ?? "") {
      actionMessages[source.id] = nil
    }
    save()
    _ = try? await call(["action": "ignore", "source": source.id, "relative": entry.relative, "revision": entry.revision])
  }
  func states(_ id: String, relatives: [String]) async throws -> [String: String] {
    try JSONDecoder().decode([String: String].self, from: await call(["action": "states", "source": id, "receiver": backup.pairing?.receiverID ?? "", "relatives": relatives]))
  }
  func children(_ id: String, directory: String, offset: Int, descending: Bool = false) async throws -> FolderChildren {
    try JSONDecoder().decode(FolderChildren.self, from: await call(["action": "children", "source": id,
      "directory": directory, "offset": offset, "descending": descending, "receiver": backup.pairing?.receiverID ?? ""]))
  }
  func previewEntry(_ id: String, job: Int64, sourceID: String) async throws -> FolderEntry? {
    try JSONDecoder().decode(FolderEntry?.self, from: await call(["action": "preview_entry", "source": id, "job": job, "source_id": sourceID]))
  }
  func page(_ id: String, offset: Int, sort: FolderFileSort = .modifiedNewest) async throws -> [FolderEntry] {
    try JSONDecoder().decode([FolderEntry].self, from: await call(["action": "page", "source": id, "offset": offset, "sort": sort.rawValue, "receiver": backup.pairing?.receiverID ?? ""]))
  }
}

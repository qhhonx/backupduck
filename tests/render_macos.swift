// Render production SwiftUI views with synthetic presentation state and a
// temporary Rust store. No Keychain, Photos authorization or network is opened.
import AppKit
import ScreenCaptureKit
import SwiftUI

@main struct MacLayoutCheck {
  @MainActor static var interactiveWindow: NSWindow?
  @MainActor static func main() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let store = FileManager.default.temporaryDirectory.appendingPathComponent("backupduck-layout-" + UUID().uuidString)
    let command = try JSONSerialization.data(withJSONObject: ["op": "open_sender", "root": store.path])
    let pointer = String(decoding: command, as: UTF8.self).withCString { backupduck_call($0) }!
    let response = Data(String(cString: pointer).utf8)
    backupduck_free(pointer)
    guard (try JSONSerialization.jsonObject(with: response) as? [String: Any])?["ok"] as? Bool == true else {
      fatalError("Unable to open isolated layout fixture store")
    }
    let event = try JSONSerialization.data(withJSONObject: ["op": "record_event", "receiver": false,
      "code": "dispatch_waiting", "context": ["queued": 20, "running": 0, "waiting": 5,
        "failed": 2, "paused": true, "active_requests": 0, "execution": "desktop", "reason": "paused"]])
    if let result = String(decoding: event, as: UTF8.self).withCString({ backupduck_call($0) }) {
      backupduck_free(result)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Task { @MainActor in
      do {
        if CommandLine.arguments.contains("--burst-cells") {
          for dark in [false, true] {
            try await capture("burst-cells-" + (dark ? "dark" : "light"),
              view: AnyView(BurstCellsFixture()), output: output,
              size: NSSize(width: 600, height: 230), dark: dark)
          }
          try FileManager.default.removeItem(at: store)
          app.terminate(nil)
          return
        }
        if CommandLine.arguments.contains("--library-only") {
          let states: [(String, LibraryPlaceholderKind)] = [
            ("request", .permission(.notDetermined)), ("denied", .permission(.denied)),
            ("restricted", .permission(.restricted)), ("loading", .loading),
            ("empty", .empty(filtered: false)), ("filtered", .empty(filtered: true)),
          ]
          for (name, state) in states {
            for dark in [false, true] {
              try await capture("library-" + name + (dark ? "-dark" : "-light"),
                view: AnyView(LibraryPlaceholder(kind: state)), output: output,
                size: NSSize(width: 660, height: 520), dark: dark)
            }
          }
          try await capture("library-permission-pending",
            view: AnyView(LibraryPlaceholder(kind: .permission(.notDetermined), requestingAccess: true)),
            output: output, size: NSSize(width: 660, height: 520))
          try FileManager.default.removeItem(at: store)
          print("Rendered six library states in light and dark appearances; no photo access requested.")
          app.terminate(nil)
          return
        }
        if CommandLine.arguments.contains("--help-only") {
          for dark in [false, true] {
            try await capture("help-" + (dark ? "dark" : "light"),
              view: AnyView(BackupHelp()), output: output,
              size: NSSize(width: 620, height: 760), dark: dark)
          }
          try FileManager.default.removeItem(at: store)
          app.terminate(nil)
          return
        }
        let model = BackupModel(root: store.appendingPathComponent("ui"))
        await model.refreshDeviceStatus()
        let originalDeviceID = model.deviceSnapshot!.device.id
        let rejectedName = await model.renameDevice("\n")
        precondition(!rejectedName && model.deviceError != nil, "Invalid names must report an error")
        let savedName = await model.renameDevice("Moonlit Cedar")
        precondition(savedName && model.deviceSnapshot!.device.id == originalDeviceID,
          "Renaming must preserve the device identity")
        await model.refreshDeviceStatus()
        precondition(model.deviceSnapshot!.device.name == "Moonlit Cedar", "Name must persist")
        model.ready = true
        model.paused = true
        // This identity is display-only; the renderer never starts a sender.
        let paired = Pairing(version: 2, receiverID: "layout-fixture", endpoint: "https://receiver.invalid", certificate: "", token: "")
        model.deviceSnapshot = DeviceSnapshot(device: model.deviceSnapshot!.device,
          peers: [DeviceSnapshot.Peer(key: paired.receiverID,
            profile: DeviceProfile(id: String(repeating: "a", count: 64), name: "Amber Otter"),
            last_seen: Int64(Date().timeIntervalSince1970))])
        if CommandLine.arguments.contains("--transfer-layout-only") {
          model.pairing = paired; model.paused = false
          let asset = BackupJob.Asset(metadata: ["source_type": "folder", "source_name": "SD Card", "created_at_ms": "1727400000000"],
            kind: "photo", source_id: "layout-transfer", revision: "1", resources: [.init(filename: "photo.jpg", size: 1000000)])
          var rowHeights: [CGFloat] = []
          for state in ["queued", "running", "waiting", "failed", "received"] {
            let job = BackupJob(id: 1, asset: asset, state: state, confirmedBytes: state == "received" ? 1000000 : 500000,
              errorCode: ["waiting", "failed"].contains(state) ? "network" : nil,
              nextAttemptAt: state == "waiting" ? Int64(Date().addingTimeInterval(30).timeIntervalSince1970) : nil)
            let row = AnyView(TransferRow(job: job, progress: state == "running" ? TransferProgress(sent: 250000, expected: 500000, baseline: 500000, phase: "upload") : nil, retry: {}))
            rowHeights.append(await naturalHeight(row, width: 680))
            try await capture("transfer-row-" + state, view: row, output: output, size: NSSize(width: 700, height: rowHeights.last!))
          }
          precondition(rowHeights.max()! - rowHeights.min()! < 1,
            "Transfer row height must remain stable across progress, retry and receipt transitions: \(rowHeights)")
          var preparationHeights: [CGFloat] = []
          for (active, progress, retry) in [(false, nil as Double?, nil as Int64?), (true, nil, nil),
            (true, 0.45, nil), (false, nil, Int64(Date().addingTimeInterval(30).timeIntervalSince1970))] {
            let item = SourceBrowserItem(cursor: 1, source: "layout-missing-source", revision: "1", retry_at: retry, state: "preparing")
            let row = AnyView(SourceBrowserRow(item: item, active: active, progress: progress))
            preparationHeights.append(await naturalHeight(row, width: 680))
          }
          precondition(preparationHeights.max()! - preparationHeights.min()! < 1,
            "Preparation row height must remain stable with progress, spinner and retry time: \(preparationHeights)")
          let footer = { AnyView(MacBackupFooter(model: model, activeJob: nil, pair: {}, showTransfers: {})) }
          var footerHeights: [CGFloat] = []
          model.summary.total = 10; model.summary.running = 1
          model.preparationReason = "local_cache_budget"
          precondition(model.waitingReason == "local_cache_budget" && model.compactWaitingReason == nil,
            "Preparation waits must remain in details without warning while transfers are active")
          for state in ["running", "preparing", "blocked", "network", "received"] {
            model.importing = state == "preparing"; model.exportProgress = state == "preparing" ? 0.45 : nil
            model.summary.running = ["running", "preparing"].contains(state) ? 1 : 0
            model.summary.received = state == "received" ? 10 : 5
            model.waitingForNetwork = state == "network"
            model.preparationReason = ["running", "blocked"].contains(state) ? "local_cache_budget" : nil
            if state == "blocked" { precondition(model.compactWaitingReason == "local_cache_budget") }
            if state == "network" { precondition(model.compactWaitingReason == "network") }
            footerHeights.append(await naturalHeight(footer(), width: 680))
            try await capture("backup-footer-" + state, view: footer(), output: output, size: NSSize(width: 700, height: footerHeights.last!))
          }
          model.importing = true; model.receiverUnavailable = true
          precondition(model.compactWaitingReason == "receiver_unavailable", "Connection warnings must remain visible during preparation")
          precondition(footerHeights.max()! - footerHeights.min()! < 1,
            "Backup footer height must remain stable across progress and warnings: \(footerHeights)")
          print("Transfer and preparation rows and backup footer retain height across state transitions; active preparation waits stay in details and blocked/connection warnings remain visible.")
          app.terminate(nil)
          return
        }
        if CommandLine.arguments.contains("--folder-only") {
          model.pairing = paired
          let folder = store.appendingPathComponent("Documents")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
          for x in 0..<64 { for y in 0..<48 { bitmap.setColor(x < 32 ? NSColor(deviceRed: 0.1, green: 0.4, blue: 0.9, alpha: 1) : NSColor(deviceRed: 1, green: 0.5, blue: 0.1, alpha: 1), atX: x, y: y) } }
          let png = bitmap.representation(using: .png, properties: [:])!
          try png.write(to: folder.appendingPathComponent("root-photo.png"))
          try FileManager.default.createDirectory(at: folder.appendingPathComponent("Trip/Day 1"), withIntermediateDirectories: true)
          for name in ["Trip/photo.png", "Trip/Day 1/photo.png"] { try png.write(to: folder.appendingPathComponent(name)) }
          let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          let folders = FolderSources(backup: model)
          var source = FolderSource(id: "layout-folder", name: "Documents", bookmark: bookmark,
            automatic: true, enabled: true, receiver: paired.receiverID, lastCheck: Date(),
            issues: [String(repeating: "nested-folder/", count: 12) + "unreadable.jpg": "1"])
          source.issues["root-photo.png"] = "fixture-revision"
          source.issueDetails = ["root-photo.png": FolderIssue(reason: "unreadable_media", detail: nil)]
          let legacyData = try JSONEncoder().encode(source)
          var legacy = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
          legacy.removeValue(forKey: "issueDetails"); legacy.removeValue(forKey: "retryPaths"); legacy.removeValue(forKey: "includePatterns"); legacy.removeValue(forKey: "excludePatterns"); legacy.removeValue(forKey: "lastKnownPath")
          let restored = try JSONDecoder().decode(FolderSource.self, from: JSONSerialization.data(withJSONObject: legacy))
          precondition(restored.issues.count == 2 && restored.issueDetails == nil && restored.retryPaths == nil)
          folders.sources = [source]
          _ = try await Bridge.call(["op": "folder", "command": ["action": "begin", "source": source.id, "root": folder.path]])
          while true {
            let data = try await Bridge.call(["op": "folder", "command": ["action": "step"]])
            if !(try JSONDecoder().decode(FolderSummary.self, from: data)).scanning { break }
          }
          let rootChildren = try await folders.children(source.id, directory: "", offset: 0)
          precondition(rootChildren.rows.map(\.relative) == ["Trip", "root-photo.png"] && !rootChildren.has_more)
          let tripChildren = try await folders.children(source.id, directory: "Trip", offset: 0)
          precondition(tripChildren.rows.map(\.relative) == ["Trip/Day 1", "Trip/photo.png"])
          let preview: NSImage? = await withCheckedContinuation { continuation in
            FileThumbnailPipeline.shared.request(id: UUID(), source: source, relative: "root-photo.png", revision: "test", size: 56) {
              continuation.resume(returning: $0)
            }
          }
          precondition(preview != nil, "System thumbnail generation must succeed for a valid PNG")
          try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"), withDestinationURL: folder.appendingPathComponent("root-photo.png"))
          let linkedPreview: NSImage? = await withCheckedContinuation { continuation in
            FileThumbnailPipeline.shared.request(id: UUID(), source: source, relative: "link.png", revision: "test", size: 56) {
              continuation.resume(returning: $0)
            }
          }
          precondition(linkedPreview == nil, "Previews must not follow file symlinks")
          let systemDocument = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          var localizedSource = source
          localizedSource.bookmark = try systemDocument.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          precondition(folders.displayName(localizedSource) == systemDocument.lastPathComponent)
          folders.summaries[source.id] = try JSONDecoder().decode(FolderSummary.self,
            from: Data(#"{"files":152,"bytes":297061580,"unsupported":3925,"scanning":false}"#.utf8))
          folders.phases[source.id] = "folder_attention"
          folders.check(source.id, userInitiated: true)
          precondition(folders.actionMessages[source.id] == "folder_check_requested")
          folders.pause(source.id)
          precondition(!folders.sources[0].enabled && folders.phases[source.id] == "folder_paused")
          precondition(folders.actionMessages[source.id] == "folder_pause_explanation")
          model.pairing = nil
          await folders.start(source.id)
          precondition(!folders.sources[0].enabled && folders.actionMessages[source.id] == "folder_pair_first")
          model.pairing = paired
          await folders.start(source.id)
          precondition(folders.sources[0].manualActive && !folders.sources[0].issues.isEmpty && model.paused)
          precondition(folders.actionMessages[source.id] == "folder_global_wait" && folders.starting.isEmpty)
          var beganStart = false
          let pendingStart = Task { beganStart = true; await folders.start(source.id) }
          while !beganStart { await Task.yield() }
          folders.pause(source.id)
          await pendingStart.value
          precondition(!folders.sources[0].enabled && folders.actionMessages[source.id] == "folder_pause_explanation",
            "An in-flight start must not undo a later stop")
          folders.setAutomatic(source.id, true)
          precondition(folders.sources[0].automaticActive)
          folders.setAutomatic(source.id, false)
          precondition(!folders.sources[0].enabled && !folders.sources[0].automaticActive)
          await folders.retry(source.id, relative: "root-photo.png")
          precondition(!folders.sources[0].enabled && model.paused)
          precondition(folders.sources[0].retryPaths == ["root-photo.png"])
          precondition(folders.sources[0].issues.count == 2)
          let persisted = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: model.root.appendingPathComponent("folder-sources.json")))
          precondition(persisted[0].retryPaths == ["root-photo.png"] && persisted[0].issueDetails?["root-photo.png"]?.reason == "unreadable_media")
          try await folders.saveRules(source.id, include: ["**/*.png"], exclude: ["Trip/**"])
          precondition(folders.sources[0].includePatterns == ["**/*.png"] && folders.sources[0].retryPaths?.isEmpty != false && model.paused)
          do { try await folders.saveRules(source.id, include: ["["], exclude: []); preconditionFailure("Invalid glob must not save") }
          catch { precondition(folders.sources[0].includePatterns == ["**/*.png"]) }
          await folders.dismissIssue(source.id, relative: "root-photo.png")
          precondition(folders.sources[0].issues.count == 1 && folders.sources[0].issueDetails?["root-photo.png"] == nil)
          let savedRules = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: model.root.appendingPathComponent("folder-sources.json")))
          precondition(savedRules[0].excludePatterns == ["Trip/**"] && savedRules[0].issues.count == 1)
          try await folders.saveRules(source.id, include: [], exclude: [])
          // Reset only the synthetic dismissed record by forgetting and rebuilding its index.
          _ = try await Bridge.call(["op": "folder", "command": ["action": "forget", "source": source.id]])
          _ = try await Bridge.call(["op": "folder", "command": ["action": "begin", "source": source.id, "root": folder.path]])
          while true {
            let data = try await Bridge.call(["op": "folder", "command": ["action": "step"]])
            if !(try JSONDecoder().decode(FolderSummary.self, from: data)).scanning { break }
          }
          let desktop = store.appendingPathComponent("Desktop")
          try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
          let desktopBookmark = try desktop.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          let second = FolderSource(id: "layout-desktop", name: "Desktop", bookmark: desktopBookmark,
            automatic: true, enabled: true, receiver: paired.receiverID, lastCheck: Date())
          folders.sources = [source, second]
          folders.pause(source.id)
          // Persist fixture state for the workspace's normal folder-open path.
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          try JSONEncoder().encode(folders.sources).write(to: model.root.appendingPathComponent("folder-sources.json"))
          folders.check(source.id, userInitiated: true)
          if CommandLine.arguments.contains("--interactive-folder") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "BackupDuck Folder Layout — Synthetic Data"
            window.contentView = NSHostingView(rootView: MacWorkspace(model: model,
              library: PhotoLibraryModel(), initialDestination: .sources, folderSources: folders))
            interactiveWindow = window
            window.center(); window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            print("Isolated folder fixture ready.")
            return
          }
          for dark in [false, true] {
            try await capture("folder-sources-" + (dark ? "dark" : "light"),
              view: AnyView(FolderSourcesPage(folders: folders, backup: model)), output: output,
              size: NSSize(width: 800, height: 680), dark: dark)
          }
          folders.selectedSourceID = source.id
          UserDefaults.standard.set("flat", forKey: "macFolderListLayout")
          UserDefaults.standard.set(true, forKey: "macListThumbnails")
          try await capture("folder-thumbnail", view: AnyView(MacFileThumbnail(source: source,
            relative: "root-photo.png", revision: "test", size: 100)), output: output, size: NSSize(width: 140, height: 140))
          UserDefaults.standard.set(false, forKey: "macListThumbnails")
          try await capture("folder-thumbnail-disabled", view: AnyView(MacFileThumbnail(source: source,
            relative: "root-photo.png", revision: "test", size: 100)), output: output, size: NSSize(width: 140, height: 140))
          UserDefaults.standard.set(true, forKey: "macListThumbnails")
          try await capture("folder-detail", view: AnyView(FolderSourcesPage(folders: folders, backup: model)),
            output: output, size: NSSize(width: 800, height: 680))
          UserDefaults.standard.set("folders", forKey: "macFolderListLayout")
          try await capture("folder-tree", view: AnyView(FolderSourcesPage(folders: folders, backup: model)),
            output: output, size: NSSize(width: 800, height: 680))
          UserDefaults.standard.set("flat", forKey: "macFolderListLayout")
          folders.selectedSourceID = nil
          try await capture("folder-workspace", view: AnyView(MacWorkspace(model: model,
            library: PhotoLibraryModel(), initialDestination: .sources, folderSources: folders)),
            output: output, size: NSSize(width: 1080, height: 740))
          UserDefaults.standard.set("backup", forKey: "macSettingsSection")
          try await capture("folder-settings", view: AnyView(MacPreferences(model: model, folders: folders)),
            output: output, size: NSSize(width: 800, height: 900))
          // Exercise offline checks against both a disappeared directory and an
          // unresolved bookmark, the latter being macOS's unmounted-volume path.
          let removable = store.appendingPathComponent("Removable")
          try FileManager.default.createDirectory(at: removable, withIntermediateDirectories: true)
          let removableBookmark = try removable.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          let offline = FolderSource(id: "layout-offline", name: "Removable", bookmark: removableBookmark,
            automatic: true, enabled: true, receiver: paired.receiverID, lastCheck: Date(), lastKnownPath: removable.path)
          let unavailable = FolderSources(backup: model)
          unavailable.sources = [offline]
          unavailable.summaries[offline.id] = folders.summaries[source.id]
          let inventory = unavailable.summaries[offline.id]
          unavailable.check(offline.id, userInitiated: true)
          precondition(unavailable.actionMessages[offline.id] == "folder_check_requested")
          let onlinePath = unavailable.displayPath(unavailable.sources[0])
          try FileManager.default.removeItem(at: removable)
          unavailable.check(offline.id, userInitiated: true)
          precondition(unavailable.phases[offline.id] == "folder_offline" && unavailable.actionMessages[offline.id] == nil,
            "An offline rescan must clear waiting feedback and report source availability")
          precondition(unavailable.sources[0].issues.isEmpty && unavailable.summaries[offline.id] == inventory,
            "Losing a volume must not invent file failures or discard the inventory")
          unavailable.sources[0].bookmark = Data()
          unavailable.check(offline.id, userInitiated: true)
          precondition(unavailable.phases[offline.id] == "folder_offline" && unavailable.actionMessages[offline.id] == nil)
          precondition(unavailable.displayPath(unavailable.sources[0]) == onlinePath)
          try await capture("folder-offline", view: AnyView(FolderSourcesPage(folders: unavailable, backup: model)),
            output: output, size: NSSize(width: 800, height: 400))
          try FileManager.default.createDirectory(at: removable, withIntermediateDirectories: true)
          unavailable.sources[0].bookmark = try removable.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          unavailable.check(offline.id, userInitiated: true)
          precondition(unavailable.actionMessages[offline.id] == "folder_check_requested",
            "A restored source must accept a new rescan")
          print("Folder mode, retry/rules persistence, offline rescan/reconnect, directory queries and thumbnails passed; rendered both layouts and offline status.")
          app.terminate(nil)
          return
        }
        if CommandLine.arguments.contains("--interactive") {
          model.pairing = paired
          model.summary.total = 120
          model.summary.received = 93
          model.summary.queued = 20
          model.summary.waiting = 5
          model.summary.failed = 2
          let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
          window.title = "BackupDuck Layout Check — Synthetic Data"
          window.contentView = NSHostingView(rootView:
            MacWorkspace(model: model, library: PhotoLibraryModel(), initialDestination: .backup))
          interactiveWindow = window
          window.center()
          window.makeKeyAndOrderFront(nil)
          app.activate(ignoringOtherApps: true)
          print("Interactive fixture window ready. Store: \(store.path)")
          return
        }
        if CommandLine.arguments.contains("--design-review") {
          model.pairing = paired; model.paused = false; model.ready = true
          model.summary.total = 120; model.summary.received = 93; model.summary.published = 91
          model.summary.publication_failed = 2; model.summary.queued = 20; model.summary.waiting = 7
          for dark in [false, true] {
            try await capture("overview-" + (dark ? "dark" : "light"), view: AnyView(MacBackupPage(model: model,
              pair: {}, library: {}, sources: {}, showTransfers: { _ in })), output: output,
              size: NSSize(width: 880, height: 800), dark: dark)
            try await capture("workspace-" + (dark ? "dark" : "light"), view: AnyView(MacWorkspace(model: model,
              library: PhotoLibraryModel(), initialDestination: .backup)), output: output,
              size: NSSize(width: 1180, height: 840), dark: dark)
          }
          let asset = BackupJob.Asset(metadata: ["source_type": "folder", "source_name": "SD Card", "created_at_ms": "1790906400000"],
            kind: "motion", source_id: "layout-transfer", revision: "1", resources: [.init(filename: "旅行_实况.heic", size: 8500000)])
          let job = BackupJob(id: 1, asset: asset, state: "received", confirmedBytes: 8500000,
            errorCode: nil, processing: "failed", processingError: "conversion_required", nextAttemptAt: nil)
          for dark in [false, true] {
            try await capture("transfer-detail-" + (dark ? "dark" : "light"),
              view: AnyView(DuckTransferDetail(job: job, status: NSLocalizedString("state_publication_failed", comment: ""),
                symbol: "exclamationmark.triangle", tone: .failure, retry: {})), output: output,
              size: NSSize(width: 560, height: 650), dark: dark)
          }
          try FileManager.default.removeItem(at: store)
          app.terminate(nil); return
        }
        let overview = { AnyView(MacBackupPage(model: model, pair: {}, library: {}, sources: {}, showTransfers: { _ in })) }
        try await capture("backup-unpaired", view: overview(), output: output)
        model.pairing = paired
        try await capture("backup-empty", view: overview(), output: output)
        model.summary.total = 120
        model.summary.received = 93
        model.summary.queued = 20
        model.summary.waiting = 5
        model.summary.failed = 2
        model.summary.waiting_reason = "network"
        model.summary.next_retry_at = Int64(Date().addingTimeInterval(60).timeIntervalSince1970)
        model.paused = false
        model.pendingImports = 6
        try await capture("backup-waiting", view: overview(), output: output)
        try await capture("backup-waiting-dark", view: overview(), output: output, dark: true)
        model.importing = true
        model.exportProgress = 0.45
        try await capture("backup-preparing", view: overview(), output: output)
        model.importing = false
        for section in [MacSettingsSection.backup, .cache, .diagnostics] {
          UserDefaults.standard.set(section.rawValue, forKey: "macSettingsSection")
          try await capture("settings-" + section.rawValue,
            view: AnyView(MacPreferences(model: model)), output: output,
            size: NSSize(width: 620, height: 580))
        }
        UserDefaults.standard.set(MacSettingsSection.cache.rawValue, forKey: "macSettingsSection")
        try await capture("settings-cache-dark", view: AnyView(MacPreferences(model: model)),
          output: output, size: NSSize(width: 620, height: 580), dark: true)
        try await capture("settings-save-error", view: AnyView(MacPreferences(model: model)),
          output: output, size: NSSize(width: 620, height: 580), action: {
            let original = model.storage!.settings.cache_budget_bytes
            var invalid = model.storage!.settings
            invalid.cache_budget_bytes = 0
            await model.saveStorage(invalid)
            precondition(model.storageError != nil, "Invalid settings must report an error")
            precondition(model.storage!.settings.cache_budget_bytes == original,
              "Rejected settings must not change the stored budget")
          })
        var valid = model.storage!.settings
        valid.cache_budget_bytes = 2 << 30
        await model.saveStorage(valid)
        precondition(model.storageError == nil && model.storage!.settings.cache_budget_bytes == 2 << 30,
          "Valid settings must persist and clear the previous error")
        model.scanningHistory = true
        let deferredImport = await model.importAssets(["synthetic-scan-gate"], requestAuthorization: false)
        model.scanningHistory = false
        precondition(deferredImport && !model.importing, "Discovery during a scan must remain queued without requesting Photos")
        let queuedDuringScan = try await Bridge.call(["op": "pending_sources", "receiver_id": paired.receiverID])
        let queuedResult = try JSONSerialization.jsonObject(with: queuedDuringScan) as! [String: Any]
        precondition(queuedResult["count"] as! Int == 1)
        let started = try await Bridge.call(["op": "history_control", "receiver_id": paired.receiverID, "action": "start"])
        let run = try JSONDecoder().decode(HistoricalImportStatus.self, from: started).run
        _ = try await Bridge.call(["op": "history_batch", "receiver_id": paired.receiverID, "run": run,
          "sources": [["synthetic-history-one", "1"], ["synthetic-history-two", "1"]], "finished": false])
        _ = try await Bridge.call(["op": "history_control", "receiver_id": paired.receiverID, "action": "pause"])
        await model.refreshHistoricalImport()
        precondition(model.historicalImport?.checked == 2 && model.historicalImport?.pending == 2)
        try await capture("history-paused", view: AnyView(Form { HistoricalImportSettings(model: model) }.formStyle(.grouped)), output: output,
          size: NSSize(width: 620, height: 480))
        _ = try await Bridge.call(["op": "history_control", "receiver_id": paired.receiverID, "action": "resume"])
        _ = try await Bridge.call(["op": "history_batch", "receiver_id": paired.receiverID, "run": run, "sources": [], "finished": true])
        await model.refreshHistoricalImport()
        precondition(model.historicalImport?.state == "scanned" && model.historicalImport?.pending == 2,
          "Scan completion must not report pending preparation as complete")
        try await capture("history-scanned", view: AnyView(Form { HistoricalImportSettings(model: model) }.formStyle(.grouped)), output: output,
          size: NSSize(width: 620, height: 480))
        print("Rendered 12 fixture screens; settings, device rename and historical-scan state checks passed.")
        try FileManager.default.removeItem(at: store)
        app.terminate(nil)
      } catch {
        fputs("Layout rendering failed: \(error)\n", stderr)
        exit(1)
      }
    }
    app.run()
  }

  @MainActor static func naturalHeight(_ view: AnyView, width: CGFloat) async -> CGFloat {
    let host = NSHostingView(rootView: AnyView(view.frame(width: width).fixedSize(horizontal: false, vertical: true)))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 240),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; window.orderBack(nil)
    defer { window.orderOut(nil); window.contentView = nil }
    try? await Task.sleep(nanoseconds: 100_000_000)
    host.layoutSubtreeIfNeeded()
    return host.fittingSize.height
  }

  @MainActor static func capture(_ name: String, view: AnyView, output: URL,
    size: NSSize = NSSize(width: 660, height: 720), dark: Bool = false,
    action: (() async -> Void)? = nil) async throws {
    let host = NSHostingView(rootView: view
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, dark ? .dark : .light))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    if CommandLine.arguments.contains("--design-review"), CGPreflightScreenCaptureAccess() {
      window.setFrameOrigin(NSPoint(x: 80, y: 80))
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    } else { window.orderBack(nil) }
    defer { window.orderOut(nil); window.contentView = nil }
    try await Task.sleep(nanoseconds: 500_000_000)
    if let action {
      await action()
      try await Task.sleep(nanoseconds: 200_000_000)
    }
    host.layoutSubtreeIfNeeded()
    if CommandLine.arguments.contains("--design-review"), CGPreflightScreenCaptureAccess() {
      let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
      if let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
        let config = SCStreamConfiguration()
        config.width = Int(size.width * window.backingScaleFactor)
        config.height = Int(size.height * window.backingScaleFactor)
        config.showsCursor = false
        let cg = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: cg)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try data.write(to: output.appendingPathComponent(name + ".png")); return
        }
      }
    }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      throw CocoaError(.coderInvalidValue)
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.coderInvalidValue)
    }
    try data.write(to: output.appendingPathComponent(name + ".png"))
  }
}


private struct BurstCellsFixture: NSViewRepresentable {
  final class Coordinator { var cells: [PhotoCell] = [] }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSView {
    let panel = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 230))
    for (index, state) in ["received", "partial", "failed"].enumerated() {
      let cell = PhotoCell()
      cell.view.frame = NSRect(x: 12 + index * 196, y: 16, width: 184, height: 198)
      cell.view.layer?.backgroundColor = [NSColor.systemTeal, .systemIndigo, .systemBrown][index].cgColor
      cell.setGroup(count: [8, 32, 1200][index], state: state)
      cell.isSelected = index == 1
      panel.addSubview(cell.view)
      cell.viewDidLayout()
      context.coordinator.cells.append(cell)
    }
    return panel
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

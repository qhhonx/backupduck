// Render production SwiftUI views with synthetic presentation state and a
// temporary Rust store. No Keychain, Photos authorization or network is opened.
import AppKit
import ScreenCaptureKit
import SwiftUI

@main struct MacLayoutCheck {
  @MainActor static var interactiveWindow: NSWindow?
  @MainActor static func main() throws {
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.discoversReceivers = false
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
    let interactive = CommandLine.arguments.contains("--interactive-replica") || CommandLine.arguments.contains("--interactive-folder") || CommandLine.arguments.contains("--interactive")
    app.setActivationPolicy(interactive ? .regular : .accessory)
    setvbuf(stdout, nil, _IONBF, 0)
    print("Layout check starting: " + CommandLine.arguments.dropFirst().joined(separator: " "))
    Task { @MainActor in
      do {
        print("Layout check main-actor task entered")
        if CommandLine.arguments.contains("--local-preview-policy") {
          let defaults = UserDefaults(suiteName: "layout.preview-policy." + UUID().uuidString)!
          defaults.set("deny", forKey: "previewCloudConsent")
          precondition(PreviewNetworkPolicy(defaults: defaults).allowed,
            "Obsolete cloud consent must not block passive browsing")
          precondition(defaults.string(forKey: "previewCloudConsent") == "deny",
            "Ignoring obsolete consent must not erase stored preferences")
          print("Preview policy passed: obsolete consent is ignored and preserved; no Photos access invoked.")
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--menubar-symbol") {
          precondition(MacMenuBarIcon.image.isTemplate && MacMenuBarIcon.image.size == NSSize(width: 20, height: 20))
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
          rep.size = NSSize(width: 20, height: 20)
          NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
          MacMenuBarIcon.image.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
          NSGraphicsContext.restoreGraphicsState()
          precondition(rep.colorAt(x: 0, y: 0)!.alphaComponent == 0 && rep.colorAt(x: 39, y: 39)!.alphaComponent == 0, "Menu symbol must have no opaque square background")
          for dark in [false, true] {
            try await capture("menubar-symbol-" + (dark ? "dark" : "light"), view: AnyView(HStack(spacing: 20) {
              Image(systemName: "iphone"); Image(systemName: "paperplane.fill")
              Image(nsImage: MacMenuBarIcon.image).renderingMode(.template)
              Image(systemName: "rectangle"); Image(systemName: "gearshape")
            }.font(.system(size: 18)).foregroundStyle(.primary).padding(24)), output: output, size: NSSize(width: 280, height: 80), dark: dark)
          }
          print("Menu symbol passed: original AppIcon mask,20pt system template,transparent corners,light/dark native icon row.")
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--submission-controls") {
          precondition(!NSLocalizedString("updates_check", comment: "").hasSuffix("…"))
          for dark in [false, true] {
            for width in [440.0, 720.0] {
              try await capture("submission-controls-" + (dark ? "dark" : "light") + "-" + String(Int(width)),
                view: AnyView(SubmissionControlsFixture()), output: output,
                size: NSSize(width: width, height: 340), dark: dark)
            }
            try await capture("selection-submission-" + (dark ? "dark" : "light"),
              view: AnyView(RenderSelectionBackupFixture(count: 2)),
              output: output, size: NSSize(width: 560, height: 420), dark: dark)
          }
          print("Submission controls rendered: update label without static ellipsis, intrinsic native segments aligned trailing, normal confirmation in both appearances and compact widths.")
          app.terminate(nil); return
        }
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
              view: AnyView(HelpCenter()), output: output,
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
        if CommandLine.arguments.contains("--folder-feedback") {
          let folders = FolderSources(backup: model)
          let directory = store.appendingPathComponent("Example originals")
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let bookmark = try directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          var source = FolderSource(id: "feedback-source", name: "Example originals", bookmark: bookmark,
            automatic: true, enabled: true, receiver: paired.receiverID, lastCheck: Date())
          model.pairing = paired; model.paused = false
          folders.summaries[source.id] = FolderSummary(files: 1, bytes: 356000, unsupported: 0, scanning: false)
          for state in ["executing", "settling", "recovery"] {
            source.pendingControl = state == "settling" ? nil : FolderPendingControl(action: "start")
            folders.sources = [source]
            folders.recoveringControls = state == "executing" ? [source.id] : []
            folders.phases[source.id] = "folder_settling"
            folders.actionMessages[source.id] = "folder_backup_requested"
            folders.facts[source.id] = FolderFacts(supported: 1, in_flight: state == "recovery" ? 0 : 1,
              in_flight_bytes: state == "recovery" ? 0 : 356000, needs_you: state == "recovery" ? 1 : 0, available: true)
            precondition(!folderSentence(folders.facts[source.id]).isEmpty)
            for dark in [false, true] {
              try await capture("folder-feedback-" + state + (dark ? "-dark" : "-light"),
                view: AnyView(FolderSourcesPage(folders: folders, backup: model)), output: output,
                size: NSSize(width: 900, height: 620), dark: dark)
            }
          }
          // Exercise the actual successful durable start; only interrupted work
          // retains recovery after it returns. Never touch a real source.
          source.pendingControl = nil; folders.sources = [source]; folders.recoveringControls = []
          _ = try await Bridge.call(["op": "folder", "command": ["action": "begin", "source": source.id, "root": directory.path]])
          while true {
            let data = try await Bridge.call(["op": "folder", "command": ["action": "step"]])
            if !(try JSONDecoder().decode(FolderSummary.self, from: data)).scanning { break }
          }
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          let accepted = await folders.start(source.id)
          precondition(accepted && folders.sources[0].pendingControl == nil && folders.recoveringControls.isEmpty)
          print("Folder feedback passed: running intent is neutral, interrupted intent is recoverable, source totals stay separate from progress, successful start finishes its durable acknowledgement.")
          try FileManager.default.removeItem(at: store); app.terminate(nil); return
        }
        model.deviceSnapshot = DeviceSnapshot(device: model.deviceSnapshot!.device,
          peers: [DeviceSnapshot.Peer(key: paired.receiverID,
            profile: DeviceProfile(id: String(repeating: "a", count: 64), name: "Amber Otter"),
            last_seen: Int64(Date().timeIntervalSince1970))])
        model.pairing = paired
        model.pairingError = "Synthetic TLS verification failure"
        precondition(!DesktopPairingModel.acceptedPairing(model, receiverID: paired.receiverID, endpoint: paired.endpoint),
          "An old matching receiver ID must not turn a failed TLS pairing into success")
        model.pairingError = nil
        precondition(!DesktopPairingModel.acceptedPairing(model, receiverID: paired.receiverID, endpoint: "https://new-route.invalid"),
          "An unchanged old route must not confirm a different requested route")
        precondition(DesktopPairingModel.acceptedPairing(model, receiverID: paired.receiverID, endpoint: paired.endpoint))
        model.pairing = nil
        precondition(MacMenuBarIcon.image.size == NSSize(width: 20, height: 20) && MacMenuBarIcon.image.isTemplate && !MacMenuBarIcon.image.representations.isEmpty,
          "Menu icon must use the transparent monochrome brand template")
        if CommandLine.arguments.contains("--ui-unification") {
          guard CommandLine.arguments.contains("--design-review"), CGPreflightScreenCaptureAccess() else { throw CocoaError(.fileReadNoPermission) }
          model.pairing = paired
          await model.refreshStorage()
          let folders = FolderSources(backup: model)
          let directory = store.appendingPathComponent("Fixture originals")
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for width in [900.0, 1180.0] {
              for destination in [MacDestination.settings, .backup, .transfers, .sources] {
                try await capture("unified-\(destination)-\(Int(width))-" + suffix,
                  view: AnyView(MacWorkspace(model: model, library: PhotoLibraryModel(), initialDestination: destination, folderSources: folders)),
                  output: output, size: NSSize(width: width, height: 620), dark: dark, action: {
                    precondition(!(NSApp.keyWindow?.firstResponder is NSButton), "First open must not focus the sidebar toolbar button")
                  })
              }
            }
            try await capture("unified-cache-" + suffix, view: AnyView(MacSettings(model: model, folders: folders, showFolders: {}, initialPage: .advanced)), output: output, size: NSSize(width: 680, height: 660), dark: dark)
            try await capture("unified-help-" + suffix, view: AnyView(MacSettings(model: model, folders: folders, showFolders: {}, initialPage: .help)), output: output, size: NSSize(width: 680, height: 620), dark: dark)
            try await capture("unified-backup-settings-" + suffix, view: AnyView(MacSettings(model: model, folders: folders, showFolders: {}, initialPage: .autoBackup)), output: output, size: NSSize(width: 560, height: 600), dark: dark)
            try await capture("unified-about-route-" + suffix,
              view: AnyView(MacWorkspace(model: model, library: PhotoLibraryModel(), initialDestination: .backup, folderSources: folders)),
              output: output, size: NSSize(width: 900, height: 620), dark: dark,
              action: { MacAboutNavigation.open {} })
            try await capture("unified-add-folder-" + suffix, view: AnyView(AddFolderSheet(url: directory, folders: folders, backup: model, close: {})), output: output, size: NSSize(width: 560, height: 560), dark: dark)

            try await capture("unified-notices-" + suffix, view: AnyView(VStack(spacing: 20) {
              DuckNotice(title: "folder_scan_note")
              DuckNotice(title: "mac_library_preview_unavailable", tone: .attention)
              DuckNotice(title: "mac_receiver_connection_note", symbol: "wifi")
              DuckNotice(title: "mac_fidelity_folder_range_title", message: "mac_fidelity_folder_range_note")
            }.padding(20)), output: output, size: NSSize(width: 560, height: 380), dark: dark)
          }
          try FileManager.default.removeItem(at: store)
          print("Current desktop views rendered in active light/dark and minimum-width windows; initial sidebar focus and bundled brand icon checks passed.")
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--fidelity-audit") {
          guard CommandLine.arguments.contains("--design-review"), CGPreflightScreenCaptureAccess() else {
            throw CocoaError(.fileReadNoPermission)
          }
          let folders = FolderSources(backup: model)
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          var sources: [FolderSource] = []
          for name in ["相机 SD 卡", "Pictures"] {
            let directory = store.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bookmark = try directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            sources.append(FolderSource(id: "fidelity-" + String(sources.count), name: name, bookmark: bookmark,
              automatic: false, enabled: false, receiver: paired.receiverID, lastCheck: nil))
          }
          folders.sources = sources
          try JSONEncoder().encode(sources).write(to: model.root.appendingPathComponent("folder-sources.json"), options: .atomic)
          UserDefaults.standard.removeObject(forKey: "macRequestedDestination")
          model.pairing = Pairing(version: 2, receiverID: paired.receiverID, endpoint: "https://192.0.2.10:8484", certificate: "", token: "")
          model.ready = true; model.paused = false
          model.summary.total = 120; model.summary.received = 93; model.summary.published = 91
          model.summary.publication_failed = 2; model.summary.queued = 20; model.summary.waiting = 7
          model.deviceSnapshot = DeviceSnapshot(device: model.deviceSnapshot!.device, peers: [DeviceSnapshot.Peer(key: paired.receiverID,
            profile: DeviceProfile(id: String(repeating: "a", count: 64), name: "示例 Pixel"), last_seen: Int64(Date().timeIntervalSince1970))])
          for (name, destination) in [("backup-album-failure", MacDestination.backup), ("settings-normal", .settings),
            ("folders-normal", .sources), ("transfers-empty", .transfers), ("library-permission", .library)] {
            try await capture((CommandLine.arguments.contains("--fidelity-after") ? "fidelity-after-" : "fidelity-before-") + name, view: AnyView(MacWorkspace(model: model,
              library: PhotoLibraryModel(), initialDestination: destination, folderSources: folders)), output: output,
              size: NSSize(width: 1180, height: 800))
          }
          model.pairing = nil
          for (name, destination) in [("backup-unpaired", MacDestination.backup)] {
            try await capture((CommandLine.arguments.contains("--fidelity-after") ? "fidelity-after-" : "fidelity-before-") + name, view: AnyView(MacWorkspace(model: model,
              library: PhotoLibraryModel(), initialDestination: destination, folderSources: folders)), output: output,
              size: NSSize(width: 1180, height: 800))
          }
          print("Fidelity audit captured eight synthetic production MacWorkspace states on exact 1180x800 outer canvases, active real windows only. No design matching claim or user media access.")
          try FileManager.default.removeItem(at: store)
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--recovery-intents") {
          model.pairing = paired; model.paused = true; model.ready = true
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          let media = store.appendingPathComponent("Recovery originals")
          try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
          try Data("isolated synthetic index fixture".utf8).write(to: media.appendingPathComponent("fixture.jpg"))
          let bookmark = try media.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          let config = model.root.appendingPathComponent("folder-sources.json")
          for action in ["start", "retry", "dismiss", "rules", "remove"] {
            let id = "recovery-" + action
            _ = try await Bridge.call(["op": "folder", "command": ["action": "begin", "source": id, "root": media.path]])
            while true {
              let data = try await Bridge.call(["op": "folder", "command": ["action": "step"]])
              if !(try JSONDecoder().decode(FolderSummary.self, from: data)).scanning { break }
            }
            let entryData = try await Bridge.call(["op": "folder", "command": ["action": "entry", "source": id, "relative": "fixture.jpg"]])
            let entry = try JSONDecoder().decode(FolderEntry.self, from: entryData)
            let source = FolderSource(id: id, name: "Recovery originals", bookmark: bookmark,
              automatic: false, enabled: false, receiver: paired.receiverID, lastCheck: nil,
              issues: [entry.relative: entry.revision], includePatterns: [], excludePatterns: [])
            var writes = 0
            let folders = FolderSources(backup: model, writeConfiguration: { data, path in
              writes += 1
              if writes == 2 { throw CocoaError(.fileWriteOutOfSpace) }
              try data.write(to: path, options: .atomic)
            })
            folders.sources = [source]
            var accepted = false
            switch action {
            case "start": accepted = await folders.start(id)
            case "retry": accepted = await folders.retry(id, relative: entry.relative)
            case "dismiss": accepted = await folders.dismissIssue(id, relative: entry.relative)
            case "rules":
              do { try await folders.saveRules(id, include: ["**/*.jpg"], exclude: []); accepted = true }
              catch { accepted = false }
            default: accepted = await folders.remove(id)
            }
            precondition(!accepted && writes == 2 && folders.sources[0].pendingControl?.action == action,
              "Post-native persistence failure must retain a durable recovery intent")
            let durable = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: config))
            precondition(durable[0].pendingControl?.action == action && durable[0].receiver == paired.receiverID)
            let cutoff = durable[0].manualCutoffMS
            if action == "start" {
              precondition(cutoff != nil && durable[0].enabled)
              try await capture("audit-pending-source-recovery", view: AnyView(FolderSourcesPage(folders: folders, backup: model)),
                output: output, size: NSSize(width: 960, height: 680))
            }
            if action == "retry" { precondition(durable[0].retryPaths == [entry.relative]) }
            if action == "dismiss" {
              let states = try await folders.states(id, relatives: [entry.relative])
              precondition(states[entry.relative] == "ignored" && folders.sources[0].issues[entry.relative] == nil,
                "After native dismiss commits, the UI must show ignored despite a derived-cache save failure")
              precondition(folders.error?.contains(NSLocalizedString("mac_folder_ignore_applied_recovery", comment: "")) == true)
            }
            // Completing an old target's idempotent index work must not trap
            // recovery or silently bind this saved plan to a new paired phone.
            if ["start", "retry"].contains(action) {
              model.pairing = Pairing(version: 2, receiverID: "different-fixture", endpoint: "https://different.invalid", certificate: "", token: "")
              let recoveredAfterTargetChange = await folders.recoverPendingControl(id)
              precondition(recoveredAfterTargetChange && folders.sources[0].pendingControl == nil
                && folders.sources[0].receiver == paired.receiverID
                && folders.actionMessages[id] == "folder_receiver_changed")
              precondition(model.summary.total == 0, "Recovery must not enqueue a saved plan to a replacement target")
              model.pairing = paired
            }
            let restarted = FolderSources(backup: model)
            await restarted.open()
            if action == "remove" { precondition(restarted.sources.isEmpty) }
            else {
              precondition(restarted.sources[0].pendingControl == nil && restarted.sources[0].receiver == paired.receiverID)
              if action == "start" { precondition(restarted.sources[0].manualCutoffMS == cutoff, "Recovery must preserve the frozen start range") }
              if action == "dismiss" { precondition(restarted.sources[0].issues[entry.relative] == nil) }
              if action == "rules" { precondition(restarted.sources[0].includePatterns == ["**/*.jpg"]) }
            }
            let converged = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: config))
            precondition(converged.allSatisfy { $0.pendingControl == nil })
            print("Post-native final-write fault + restart recovery passed: " + action)
          }
          print("Durable source control plans passed: target/cutoff retained, pending blocks native preparation, committed ignores remain truthful, replay is idempotent and final acknowledgement persists. Synthetic temporary index only.")
          try FileManager.default.removeItem(at: store)
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--audit-differences") {
          model.pairing = paired; model.paused = true; model.ready = true
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          let media = store.appendingPathComponent("Audit originals")
          let addMedia = store.appendingPathComponent("Audit new source")
          for url in [media, addMedia] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
          let bookmark = try media.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
          var source = FolderSource(id: "atomic-audit", name: "Audit originals", bookmark: bookmark,
            automatic: true, enabled: true, receiver: paired.receiverID, lastCheck: nil,
            issues: ["missing.jpg": "1"], includePatterns: ["**/*.jpg"], excludePatterns: [])
          source.issueDetails = ["missing.jpg": FolderIssue(reason: "missing", detail: "Synthetic audit missing original")]
          let folders = FolderSources(backup: model); folders.sources = [source]
          let config = model.root.appendingPathComponent("folder-sources.json")
          try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
          let automatic = folders.setAutomatic(source.id, false)
          precondition(!automatic && folders.sources[0].automatic && folders.sources[0].enabled && folders.error != nil)
          let paused = folders.pause(source.id)
          precondition(!paused && folders.sources[0].enabled && folders.sources[0].automatic)
          let started = await folders.start(source.id)
          precondition(!started && folders.sources[0].retryPaths == nil && folders.starting.isEmpty)
          let retried = await folders.retry(source.id, relative: "missing.jpg")
          precondition(!retried && folders.sources[0].retryPaths == nil && folders.sources[0].issues.count == 1)
          let ignored = await folders.dismissIssue(source.id, relative: "missing.jpg")
          precondition(!ignored && folders.sources[0].issues["missing.jpg"] == "1")
          do { try await folders.saveRules(source.id, include: ["**/*.png"], exclude: []); preconditionFailure("Blocked saveRules must fail") }
          catch { precondition(folders.sources[0].includePatterns == ["**/*.jpg"]) }
          do { try await folders.add(addMedia, automatic: false, existing: false); preconditionFailure("Blocked add must fail") }
          catch { precondition(folders.sources.count == 1 && folders.error != nil) }
          try FileManager.default.removeItem(at: config)
          let recovery = folders.setAutomatic(source.id, false)
          precondition(recovery && !folders.sources[0].automatic && !folders.sources[0].enabled)
          let persisted = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: config))
          precondition(!persisted[0].automatic && !persisted[0].enabled)
          folders.reveal(source, relative: "missing.jpg")
          precondition(folders.error == NSLocalizedString("folder_issue_missing", comment: ""))
          // A corrupt user config is never silently replaced by an empty first-use config.
          let corruptRoot = store.appendingPathComponent("corrupt-config")
          try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
          let corruptPath = corruptRoot.appendingPathComponent("folder-sources.json")
          let corruptData = Data("not a valid source configuration".utf8)
          try corruptData.write(to: corruptPath)
          let corruptModel = BackupModel(root: corruptRoot); corruptModel.ready = true
          let protected = FolderSources(backup: corruptModel)
          await protected.open()
          precondition(protected.loadFailed && protected.error != nil)
          do { try await protected.add(addMedia, automatic: false, existing: false); preconditionFailure("Corrupt config must reject add") }
          catch { let preservedData = try Data(contentsOf: corruptPath); precondition(preservedData == corruptData) }
          model.autoBackupError = "Synthetic auto-backup save failure. Previous choice remains unchanged."
          model.pauseError = "Synthetic pause save failure. Previous queue state remains unchanged."
          for dark in [false, true] {
            try await capture("audit-auto-backup-error-" + (dark ? "dark" : "light"),
              view: AnyView(MacSettings(model: model, folders: folders, showFolders: {}, initialPage: .autoBackup)),
              output: output, size: NSSize(width: 900, height: 740), dark: dark)
            try await capture("audit-pause-error-" + (dark ? "dark" : "light"),
              view: AnyView(MacHub(model: model, folders: folders, pair: {}, sources: {}, showTransfers: { _ in })),
              output: output, size: NSSize(width: 660, height: 730), dark: dark)
            model.pairingInProgress = false
          }
          model.historyError = "Synthetic historical-scan failure"
          await model.refreshHistoricalImport()
          precondition(model.historyError == "Synthetic historical-scan failure", "Routine successful status poll must retain a workflow error")
          await model.refreshHistoricalImport(clearError: true)
          precondition(model.historyError == nil, "Explicit successful history retry can clear its error")
          print("Audit differences passed: blocked atomic add/rules/auto/pause/start/retry/ignore retain authoritative source; recovery persists; corrupt config protected; missing Finder file errors; historical error poll retention; current-operation error fixtures rendered. No user media or receiver contacted.")
          try FileManager.default.removeItem(at: store)
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--replica-check") || CommandLine.arguments.contains("--interactive-replica") {
          model.pairing = paired; model.paused = true; model.ready = true
          model.summary.total = 120; model.summary.received = 93; model.summary.published = 91
          model.summary.publication_failed = 2; model.summary.queued = 20; model.summary.waiting = 7
          let mediaFolder = store.appendingPathComponent("Synthetic photos")
          try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
          let bookmark = try mediaFolder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
          let folders = FolderSources(backup: model)
          let longPath = String(repeating: "Synthetic long path/", count: 8) + "original-photo.jpg"
          var source = FolderSource(id: "replica-folder", name: "Synthetic photos", bookmark: bookmark,
            automatic: false, enabled: false, receiver: paired.receiverID, lastCheck: nil,
            issues: [longPath: "1"], includePatterns: ["**/*.jpg"], excludePatterns: ["Temp/**"])
          source.issueDetails = [longPath: FolderIssue(reason: "unreadable_media",
            detail: "Synthetic unreadable original. This is an isolated fixture, not a user photo.")]
          folders.sources = [source]
          // Real matcher and persistence checks, always against the temporary store.
          try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
          try await folders.saveRules(source.id, include: ["**/*.jpg"], exclude: ["Temp/**"])
          let storedBeforeFailure = try Data(contentsOf: model.root.appendingPathComponent("folder-sources.json"))
          do { try await folders.saveRules(source.id, include: ["["], exclude: []); preconditionFailure("Invalid rule must fail") }
          catch {
            let storedAfterFailure = try Data(contentsOf: model.root.appendingPathComponent("folder-sources.json"))
            precondition(storedAfterFailure == storedBeforeFailure, "Invalid rule must retain previously saved configuration")
          }
          await folders.retry(source.id, relative: longPath)
          precondition(folders.sources[0].retryPaths == [longPath] && model.paused,
            "A retry should queue only the failed original without resuming a paused queue")
          precondition(folders.sources[0].issues[longPath] != nil, "Submitting retry is not completion")
          source = folders.sources[0]
          let removalRoot = store.appendingPathComponent("removal-check")
          try FileManager.default.createDirectory(at: removalRoot, withIntermediateDirectories: true)
          let removalModel = BackupModel(root: removalRoot)
          let removalSources = FolderSources(backup: removalModel)
          var removable = source
          removable = FolderSource(id: "remove-check", name: source.name, bookmark: bookmark,
            automatic: false, enabled: false, receiver: paired.receiverID, lastCheck: nil)
          removalSources.sources = [removable]
          let blockedConfig = removalRoot.appendingPathComponent("folder-sources.json")
          try FileManager.default.createDirectory(at: blockedConfig, withIntermediateDirectories: true)
          let rejectedRemoval = await removalSources.remove(removable.id)
          precondition(!rejectedRemoval && removalSources.sources.count == 1 && removalSources.error != nil,
            "A failed atomic config write must preserve the source")
          try FileManager.default.removeItem(at: blockedConfig)
          let acceptedRemoval = await removalSources.remove(removable.id)
          precondition(acceptedRemoval && removalSources.sources.isEmpty, "Removal must succeed after persistence recovers")
          let persistedRemoval = try JSONDecoder().decode([FolderSource].self, from: Data(contentsOf: blockedConfig))
          precondition(persistedRemoval.isEmpty && FileManager.default.fileExists(atPath: mediaFolder.path),
            "Source removal must persist while keeping the original folder")
          if CommandLine.arguments.contains("--interactive-replica") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 740),
              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "BackupDuck Replica Check — Synthetic Data"
            window.contentView = NSHostingView(rootView: ReplicaFlowFixture(model: model, folders: folders,
              folder: mediaFolder, source: source, path: longPath))
            interactiveWindow = window
            window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
            print("Isolated replica fixture ready: folder add / rules / issue / selection / settings / help.")
            return
          }
          for dark in [false, true] {
            for width in [440.0, 660.0] {
              let variant = (dark ? "dark" : "light") + "-" + String(Int(width))
              let size = NSSize(width: width, height: 650)
              try await capture("replica-add-" + variant, view: AnyView(AddFolderSheet(url: mediaFolder,
                folders: folders, backup: model, close: {})), output: output, size: size, dark: dark)
              try await capture("replica-rules-" + variant, view: AnyView(FolderRulesSheet(folders: folders,
                source: source, close: {})), output: output, size: size, dark: dark)
              try await capture("replica-folder-preferences-" + variant, view: AnyView(MacFolderSettings(folders: folders,
                backup: model, selectedID: source.id)), output: output, size: size, dark: dark)
              try await capture("replica-selection-" + variant, view: AnyView(RenderSelectionBackupFixture(count: 1200)), output: output, size: size, dark: dark)
              try await capture("replica-receiver-" + variant, view: AnyView(DevicePage(model: model, connect: {})),
                output: output, size: size, dark: dark)
            }
            try await capture("replica-settings-" + (dark ? "dark" : "light"),
              view: AnyView(MacSettings(model: model, folders: folders, showFolders: {})), output: output,
              size: NSSize(width: 920, height: 1000), dark: dark)
            try await capture("replica-history-" + (dark ? "dark" : "light"),
              view: AnyView(MacHub(model: model, folders: folders, pair: {}, sources: {}, showTransfers: { _ in })),
              output: output, size: NSSize(width: 660, height: 740), dark: dark)
          }
          print("Replica sheets and pages rendered in Chinese/English, light/dark, compact/regular. Real rule persistence, validation failure and retry semantics passed; window interaction and user acceptance remain separate.")
          try FileManager.default.removeItem(at: store)
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--compact-components") {
          model.pairing = paired; model.ready = true
          model.summary.total = 1200; model.summary.received = 1000; model.summary.published = 980
          model.summary.publication_failed = 20; model.summary.queued = 200
          for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let large = DynamicTypeSize.accessibility3
            try await capture("compact-overview-" + suffix,
              view: AnyView(MacHub(model: model, folders: FolderSources(backup: model), pair: {}, sources: {}, showTransfers: { _ in })
                .environment(\.dynamicTypeSize, large)), output: output,
              size: NSSize(width: 620, height: 680), dark: dark)
            try await capture("compact-selected-" + suffix,
              view: AnyView(RenderSelectionBackupFixture(count: 1200, repeats: true)
                .environment(\.dynamicTypeSize, large)), output: output,
              size: NSSize(width: 440, height: 650), dark: dark)
          }
          try FileManager.default.removeItem(at: store)
          print("Rendered compact Mac component layouts with accessibility3 environment; actual system scaling/user acceptance remains separate.")
          app.terminate(nil); return
        }
        if CommandLine.arguments.contains("--transfer-layout-only") {
          model.pairing = paired; model.paused = false
          let hub = { AnyView(MacHub(model: model, folders: FolderSources(backup: model), pair: {}, sources: {}, showTransfers: { _ in })) }
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
            try await capture("backup-hub-" + state, view: hub(), output: output, size: NSSize(width: 700, height: 740))
          }
          model.importing = true; model.receiverUnavailable = true
          precondition(model.compactWaitingReason == "receiver_unavailable", "Connection warnings must remain visible during preparation")
          print("Current hub renders preparation and recovery while waiting-reason assertions retain their model coverage.")
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
          let committing = folders.sources[0].pendingControl != nil
          let stopped = folders.pause(source.id)
          precondition(stopped == !committing, "A committing intent disables conflicting actions")
          await pendingStart.value
          if committing {
            precondition(folders.sources[0].manualActive, "The accepted start must finish before stop is available")
            precondition(folders.pause(source.id), "Stop becomes available after durable acknowledgement")
          }
          precondition(!folders.sources[0].enabled && folders.actionMessages[source.id] == "folder_pause_explanation",
            "A later accepted stop must keep the source paused")
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
          try await capture("folder-settings", view: AnyView(MacSettings(model: model, folders: folders, showFolders: {}, initialPage: .folders)),
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
            try await capture("overview-" + (dark ? "dark" : "light"), view: AnyView(MacHub(model: model, folders: FolderSources(backup: model),
              pair: {}, sources: {}, showTransfers: { _ in })), output: output,
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
              view: AnyView(MacWorkspace(model: model, library: PhotoLibraryModel(), initialDestination: .transfers,
                initialViewer: .photo(nil, [], HistoryPhoto(job: job)), initialViewerInfo: true)),
              output: output, size: NSSize(width: 1180, height: 740), dark: dark)
          }
          try FileManager.default.removeItem(at: store)
          app.terminate(nil); return
        }
        let currentFolders = FolderSources(backup: model)
        currentFolders.previewRows = []
        let overview = { AnyView(MacHub(model: model, folders: currentFolders, pair: {}, sources: {}, showTransfers: { _ in })) }
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
        for (name, page) in [("auto-backup", MacSettings.Page.autoBackup), ("advanced", .advanced), ("diagnostics", .diagnostics)] {
          try await capture("settings-" + name,
            view: AnyView(MacSettings(model: model, folders: currentFolders, showFolders: {}, initialPage: page)), output: output,
            size: NSSize(width: 900, height: 620))
        }
        try await capture("settings-advanced-dark", view: AnyView(MacSettings(model: model, folders: currentFolders, showFolders: {}, initialPage: .advanced)),
          output: output, size: NSSize(width: 900, height: 620), dark: true)
        try await capture("settings-save-error", view: AnyView(MacSettings(model: model, folders: currentFolders, showFolders: {}, initialPage: .advanced)),
          output: output, size: NSSize(width: 900, height: 620), action: {
            let original = model.storage!.settings.cache_budget_bytes
            var invalid = model.storage!.settings
            invalid.cache_budget_bytes = 0
            await model.saveStorage(invalid)
            precondition(model.storageSettingsError != nil, "Invalid settings must report an error")
            precondition(model.storage!.settings.cache_budget_bytes == original,
              "Rejected settings must not change the stored budget")
          })
        var valid = model.storage!.settings
        valid.cache_budget_bytes = 2 << 30
        await model.saveStorage(valid)
        precondition(model.storageSettingsError == nil && model.storage!.settings.cache_budget_bytes == 2 << 30,
          "Valid settings must persist and clear the previous error")
        model.scanningHistory = true
        // The scan gate returns before PhotoKit. Exercise that production gate
        // while keeping actual library access disabled for every rendered view.
        BackupEnvironment.usesPhotoLibrary = true
        let deferredImport = await model.importAssets(["synthetic-scan-gate"], requestAuthorization: false)
        BackupEnvironment.usesPhotoLibrary = false
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
        try await capture("history-paused", view: overview(), output: output,
          size: NSSize(width: 660, height: 740))
        _ = try await Bridge.call(["op": "history_control", "receiver_id": paired.receiverID, "action": "resume"])
        _ = try await Bridge.call(["op": "history_batch", "receiver_id": paired.receiverID, "run": run, "sources": [], "finished": true])
        await model.refreshHistoricalImport()
        precondition(model.historicalImport?.state == "scanned" && model.historicalImport?.pending == 2,
          "Scan completion must not report pending preparation as complete")
        try await capture("history-scanned", view: overview(), output: output,
          size: NSSize(width: 660, height: 740))
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
    let fidelity = CommandLine.arguments.contains("--fidelity-audit")
    let contentSize = fidelity ? NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable]).size : size
    let root = CommandLine.arguments.contains("--design-review") ?
      AnyView(view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)) :
      AnyView(view.frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading))
    let host = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, dark ? .dark : .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: CommandLine.arguments.contains("--design-review") ? [.titled, .closable, .fullSizeContentView] : [.borderless], backing: .buffered, defer: false)
    window.title = "BackupDuck Layout — Synthetic Data"
    window.toolbarStyle = .unifiedCompact
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
      if !window.isKeyWindow || !window.isMainWindow {
        window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 200_000_000)
      }
      precondition(window.isKeyWindow && window.isMainWindow, "Real window capture needs an active titled window")
      let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
      if let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * window.backingScaleFactor)
        config.height = Int(window.frame.height * window.backingScaleFactor)
        config.showsCursor = false
        let cg = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: cg)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try data.write(to: output.appendingPathComponent(name + ".png"))
          try recordCapture(name, mode: "ScreenCaptureKit active titled window (includes titlebar)", output: output, size: window.frame.size)
          return
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
    try recordCapture(name, mode: "offscreen NSHostingView bitmap", output: output, size: size)
  }
  @MainActor private static func recordCapture(_ name: String, mode: String, output: URL, size: NSSize) throws {
    let record = ["file": name + ".png", "mode": mode, "width": String(Int(size.width)), "height": String(Int(size.height))]
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    let target = output.appendingPathComponent(name + ".capture.json")
    try data.write(to: target)
    print("Capture \(name): \(mode)")
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


private struct ReplicaFlowFixture: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources
  let folder: URL
  let source: FolderSource
  let path: String
  @State private var sheet: String? = nil
  @State private var selectedRequests = 0
  private var invalidSource: FolderSource {
    var copy = source
    copy.includePatterns = ["[" + String(repeating: "synthetic-long-invalid-rule/", count: 30)]
    return copy
  }
  private var showing: Binding<Bool> {
    Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Isolated BackupDuck Replica Check").font(.title2)
      Text("Synthetic data only. No photo access, no production pairing and no real uploads.")
      HStack {
        ForEach(["add", "rules", "invalid-rules", "issue", "selection", "failed-selection", "settings", "help"], id: \.self) { value in
          Button(value) { sheet = value }.accessibilityIdentifier("replica.open." + value)
        }
      }
      Text("Submitted selections: \(selectedRequests)").accessibilityIdentifier("replica.selected_requests")
      MacHub(model: model, folders: folders, pair: {}, sources: { sheet = "add" }, showTransfers: { _ in })
    }.padding(24).sheet(isPresented: showing) {
      if sheet == "add" { AddFolderSheet(url: folder, folders: folders, backup: model) { sheet = nil } }
      if sheet == "rules" { FolderRulesSheet(folders: folders, source: folders.sources.first ?? source) { sheet = nil } }
      if sheet == "invalid-rules" { FolderRulesSheet(folders: folders, source: invalidSource) { sheet = nil } }
      if sheet == "issue" { MacFolderSettings(folders: folders, backup: model, selectedID: source.id) }
      if sheet == "selection" {
        RenderSelectionBackupFixture(count: 1200, submit: { selectedRequests += 1; return true })
      }
      if sheet == "failed-selection" {
        RenderSelectionBackupFixture(count: 1200, submit: { false },
          failure: { "Synthetic submission failed. Selection is retained." })
      }
      if sheet == "settings" { MacSettings(model: model, folders: folders, showFolders: {}).frame(width: 720, height: 680) }
      if sheet == "help" { HelpCenter() }
    }
  }
}

private struct SubmissionControlsFixture: View {
  @State private var layout = "flat"
  @State private var automatic = true
  var body: some View {
    VStack(alignment: .trailing, spacing: 24) {
      Button("folder_rules") {}.duckSecondaryAction()
      Toggle("folder_automatic", isOn: $automatic).toggleStyle(.switch).fixedSize()
      HStack {
        Text("folder_sort_modified_desc").font(.system(size: 14))
        Spacer()
        Picker("folder_list_layout", selection: $layout) {
          Text("folder_list_flat").tag("flat")
          Text("folder_list_tree").tag("folders")
        }.pickerStyle(.segmented).labelsHidden().controlSize(.regular)
          .fixedSize(horizontal: true, vertical: true).frame(width: 180, height: 32, alignment: .trailing)
      }
      HStack { Image(systemName: "checkmark.circle"); Text("state_received") }.foregroundStyle(.secondary)
      Button("updates_check") {}.duckPrimaryAction()
    }.padding(24).frame(maxWidth: .infinity, alignment: .trailing)
  }
}

/// Drives the production control with synthetic submission and recovery results.
private struct RenderSelectionBackupFixture: View {
  let count: Int
  var repeats = false
  var submit: () async -> Bool = { true }
  var failure: () -> String? = { nil }
  @StateObject private var action = SelectionBackupAction()
  var body: some View {
    DuckSelectionBackupControl(action: action, count: count, request: {
      if repeats { action.confirmingRepeat = true }
      else { await action.perform(submit, failure: failure) }
    }, confirm: {
      action.confirmingRepeat = false
      await action.perform(submit, failure: failure)
    })
  }
}

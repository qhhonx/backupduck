import Foundation
import Photos

/// Backup answers derived from the device's own photo library, for library
/// scenarios on the iOS Simulator with a synthetic library (see README). The
/// core's answers must name real photo identifiers for the library's views and
/// marks to show anything, and a scenario file cannot know them in advance.
///
/// The newest photos are still on their way; most older ones were received;
/// a few need the user; the recently received ones changed in the last days.
struct LibraryScenario {
  struct Options {
    /// Newest photos not yet received (sending or waiting).
    var arriving = 8
    /// Of the remaining photos, every Nth was never backed up.
    var gapEvery = 9
    /// Received photos still awaiting gallery publication.
    var saving = 4
    /// Received photos whose publication needs the user.
    var publicationFailed = 1
    /// Received photos without a publication observation.
    var unknown = 1
    /// Photos that need the user (failed), taken from the gaps.
    var needsYou = 4
    /// Received photos whose latest change falls in the recent window.
    var recent = 30
    init(_ object: [String: Any]) {
      arriving = object["arriving"] as? Int ?? arriving
      gapEvery = object["gap_every"] as? Int ?? gapEvery
      needsYou = object["needs_you"] as? Int ?? needsYou
      recent = object["recent"] as? Int ?? recent
      saving = object["saving"] as? Int ?? saving
      publicationFailed = object["publication_failed"] as? Int ?? publicationFailed
      unknown = object["unknown"] as? Int ?? unknown
    }
  }

  private(set) var jobs: [[String: Any]] = []
  private(set) var received: [String] = []
  private(set) var states: [String: String] = [:]
  private(set) var observations: [String: [String: Any]] = [:]
  let receiver: String

  init(options: Options, receiver: String) {
    self.receiver = receiver
    guard BackupEnvironment.usesPhotoLibrary else { return }
    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let assets = PHAsset.fetchAssets(with: fetchOptions)
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    var gaps = 0
    var recentLeft = options.recent
    var receivedCount = 0
    for index in 0..<assets.count {
      let asset = assets.object(at: index)
      let id = asset.localIdentifier
      let taken = Int64((asset.creationDate ?? .now).timeIntervalSince1970 * 1000)
      let kind = asset.mediaType == .video ? "video" : asset.mediaSubtypes.contains(.photoLive) ? "motion" : "photo"
      if index < options.arriving {
        let state = index == 0 ? "running" : "queued"
        append(id: id, kind: kind, state: state, changed: now - Int64(index) * 60_000, taken: taken, index: index)
        states[id] = state
        observe(asset, index: index, transfer: state, tile: "sending")
      } else if (index - options.arriving) % options.gapEvery == options.gapEvery - 1 {
        gaps += 1
        if gaps <= options.needsYou {
          append(id: id, kind: kind, state: "failed", changed: now - Int64(gaps) * 3_600_000, taken: taken, index: index,
            error: gaps % 2 == 0 ? "source_unavailable" : "integrity")
          states[id] = "failed"
          observe(asset, index: index, transfer: "failed", tile: "needs_you")
        }
      } else {
        // Only `recent` photos changed inside the recent window; the rest were
        // received a day after capture, and never later than eight days ago.
        let older = min(taken + 86_400_000, now - 8 * 86_400_000)
        let changed = recentLeft > 0 ? now - Int64(options.recent - recentLeft + 1) * 4 * 3_600_000 : older
        recentLeft -= 1
        let processing: String = receivedCount < options.saving ? "pending"
          : receivedCount < options.saving + options.publicationFailed ? "failed"
          : receivedCount < options.saving + options.publicationFailed + options.unknown ? "not_requested" : "complete"
        let tile = processing == "pending" ? "saving" : processing == "failed" ? "needs_you"
          : processing == "complete" ? "saved" : "unknown"
        receivedCount += 1
        append(id: id, kind: kind, state: "received", changed: min(changed, now), taken: taken, index: index, processing: processing)
        observe(asset, index: index, transfer: "received", tile: tile, processing: processing)
        received.append(id)
        states[id] = "received"
      }
    }
  }

  private mutating func observe(_ asset: PHAsset, index: Int, transfer: String, tile: String, processing: String? = nil) {
    observations[asset.localIdentifier] = [
      "job_id": index + 1, "revision": PhotoLibraryModel.revision(asset),
      "transfer_state": transfer, "received": transfer == "received", "preparing": false,
      "processing": processing as Any, "error_code": transfer == "failed" ? "integrity" : NSNull(),
      "processing_error": processing == "failed" ? "publication_failed" : NSNull(), "tile_state": tile,
    ]
  }

  private mutating func append(id: String, kind: String, state: String, changed: Int64, taken: Int64, index: Int,
    error: String? = nil, processing: String? = nil) {
    jobs.append([
      "id": index + 1,
      "asset": ["kind": kind, "source_id": id, "revision": "1",
        "resources": [["filename": "IMG_\(6000 + index).HEIC", "size": 4_000_000]],
        "metadata": ["created_at_ms": String(taken), "source_type": "library"]],
      "state": state, "confirmed_bytes": state == "received" ? 4_000_000 : 0,
      "error_code": error as Any, "processing": processing as Any, "processing_error": NSNull(),
      "state_changed_at_ms": changed, "sort_value": changed, "receiver_id": receiver,
    ])
  }

  /// Answers for the commands that depend on the library, or nil to fall back
  /// to the scenario's scripted answers.
  func answer(_ command: [String: Any]) -> Any? {
    switch command["op"] as? String {
    case "source_job":
      guard command["receiver_id"] as? String == receiver,
        let id = command["source_id"] as? String else { return NSNull() }
      return jobs.first { ($0["asset"] as? [String: Any])?["source_id"] as? String == id } ?? NSNull()
    case "received_sources":
      return received
    case "library_source_states":
      return command["receiver_id"] as? String == receiver ? observations : [:]
    case "source_states":
      let sources = command["sources"] as? [[Any]] ?? []
      var result: [String: String] = [:]
      for pair in sources { if let id = pair.first as? String, let state = states[id] { result[id] = state } }
      return result
    case "backup_tasks":
      return tasks(command)
    case "backup_summary":
      return tasks(["state": "all"])["summary"]
    case "jobs":
      return (command["after"] as? NSNumber)?.int64Value ?? 0 > 0 ? [] : jobs
    default:
      return nil
    }
  }

  private func tasks(_ command: [String: Any]) -> [String: Any] {
    let category = command["state"] as? String ?? "all"
    let ordered = jobs.sorted { ($0["state_changed_at_ms"] as! Int64) > ($1["state_changed_at_ms"] as! Int64) }
    let filtered = ordered.filter { job in
      let state = job["state"] as! String
      switch category {
      case "attention": return state == "failed" || job["processing"] as? String == "failed"
      case "saved": return state == "received"
      case "active": return state == "running" || state == "queued"
      default: return true
      }
    }
    var page = filtered
    if let after = command["after_value"] as? NSNumber {
      page = filtered.filter { ($0["state_changed_at_ms"] as! Int64) < after.int64Value }
    }
    let items = page.prefix(200).map { job in
      ["id": "job-\(job["id"]!)", "cursor": job["id"]!, "sort_value": job["state_changed_at_ms"]!, "job": job, "preparation": NSNull()]
    }
    let count = { (state: String) in jobs.filter { $0["state"] as? String == state }.count }
    let summary: [String: Any] = [
      "waiting_reason": NSNull(), "next_retry_at": NSNull(), "total": jobs.count, "received": count("received"),
      "published": jobs.filter { $0["processing"] as? String == "complete" }.count,
      "publication_failed": jobs.filter { $0["processing"] as? String == "failed" }.count, "waiting": 0, "failed": count("failed"),
      "queued": count("queued"), "running": count("running"), "paused": 0, "confirmed_bytes": count("received") * 4_000_000,
    ]
    return ["items": Array(items), "summary": summary]
  }
}

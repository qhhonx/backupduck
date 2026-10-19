import Combine
import Foundation
import UserNotifications

/// Notifications only when the user is needed or a long task ends
/// (design/flows.md § Every day; interaction.md I5): earlier photos all backed
/// up, the Pixel unreachable for a day, the Pixel out of space, and Live Photos
/// that need a decision. Never routine "backed up" notices. Each says what
/// happened and opens the app, whose hub shows the same state (P3).
@MainActor final class BackupNotifier {
  static let shared = BackupNotifier()
  private var watching: AnyCancellable?
  private let defaults = UserDefaults.standard
  private let center = UNUserNotificationCenter.current()

  /// What the notifier has already said, so a condition is announced once.
  struct Memory: Codable, Equatable {
    var unreachable = false
    var full = false
    var convert = 0
    var earlierDone: Bool?
  }

  enum Change: Equatable {
    case post(id: String, after: TimeInterval?)
    case withdraw(id: String)
  }

  /// The pure decision: the changes for this state, and what to remember.
  static func changes(status: BackupHubStatus, earlier: HistoricalImportStatus?, memory: inout Memory) -> [Change] {
    var result: [Change] = []
    let unreachable = status == .problem(.receiverUnreachable)
    if unreachable && !memory.unreachable { result.append(.post(id: "unreachable", after: 24 * 60 * 60)) }
    if !unreachable && memory.unreachable { result.append(.withdraw(id: "unreachable")) }
    memory.unreachable = unreachable

    let full = status == .problem(.receiverFull)
    if full && !memory.full { result.append(.post(id: "full", after: nil)) }
    memory.full = full

    if case .problem(.conversionNeeded(let count)) = status {
      if count > memory.convert { result.append(.post(id: "convert", after: nil)) }
      memory.convert = count
    } else {
      memory.convert = 0
    }

    if let earlier {
      let done = earlier.state == "scanned" && earlier.pending == 0 && earlier.checked > 0
      if done && memory.earlierDone == false { result.append(.post(id: "earlier", after: nil)) }
      memory.earlierDone = done
    }
    return result
  }

  /// Starts watching the model. Off in the design catalog.
  func start(_ model: BackupModel) {
    guard BackupEnvironment.usesPhotoLibrary, watching == nil else { return }
    watching = model.objectWillChange
      .debounce(for: .seconds(1), scheduler: RunLoop.main)
      .sink { [weak self, weak model] _ in if let model { self?.evaluate(model) } }
  }

  func evaluate(_ model: BackupModel) {
    guard model.ready, model.pairing != nil else { return }
    var memory = (defaults.data(forKey: "notify.memory")).flatMap { try? JSONDecoder().decode(Memory.self, from: $0) } ?? Memory()
    let status = model.hubStatus
    let changes = Self.changes(status: status, earlier: model.historicalImport, memory: &memory)
    defaults.set(try? JSONEncoder().encode(memory), forKey: "notify.memory")
    let name = model.peerDevice?.name ?? "Pixel"
    for change in changes {
      switch change {
      case .withdraw(let id): center.removePendingNotificationRequests(withIdentifiers: [id])
      case .post(let id, let after):
        let title: String, body: String
        switch id {
        case "unreachable": title = format("notify_unreachable_title", name); body = localized("notify_unreachable_body")
        case "full": title = localized("notify_full_title"); body = localized("notify_full_body")
        case "convert": title = format("notify_convert_title", memory.convert.formatted()); body = localized("notify_convert_body")
        default: title = localized("notify_earlier_title"); body = localized("notify_earlier_body")
        }
        post(id, title: title, body: body, after: after)
      }
    }
  }

  private func post(_ id: String, title: String, body: String, after seconds: TimeInterval?) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let trigger = seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    let center = center
    Task {
      // People who skipped first run's question are asked when the first notice
      // is due, which is a moment they need it; an earlier answer is kept.
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
      try? await center.add(request)
    }
  }

  private func localized(_ key: String) -> String { NSLocalizedString(key, comment: "") }
  private func format(_ key: String, _ value: String) -> String { String(format: localized(key), value) }
}

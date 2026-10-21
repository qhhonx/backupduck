import Combine
import Foundation
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Projects core facts onto system notifications; never schedules backup work.
/// See design/apple-notifications.md for timing, permission and destination rules.
@MainActor final class BackupNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  static let shared = BackupNotifier()
  enum Notice: String, CaseIterable, Codable { case unreachable, full, convert, earlier }
  struct Route: Equatable {
    let id = UUID()
    let notice: Notice
    let receiver: String
  }
  @Published var route: Route?
  @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
  @Published private(set) var permissionError: String?
  private var watching: AnyCancellable?
  private let defaults = UserDefaults.standard
  private let center = UNUserNotificationCenter.current()
  private var evaluating = false
  private var needsEvaluation = false
  private let memoryKey = "notify.v2.memory"

  struct Memory: Codable, Equatable {
    var receiver: String?
    var unreachableSince: Date?
    var unreachableNotified = false
    var full = false
    var convert = 0
    var run: Int64?
    var earlierDone: Bool?

    mutating func retry(_ notice: Notice) {
      switch notice {
      case .unreachable: unreachableNotified = false
      case .full: full = false
      case .convert: convert = 0
      case .earlier: earlierDone = false
      }
    }
  }
  enum Change: Equatable { case post(Notice), withdraw(Notice) }

  /// A day-old observation alone is not enough: the host must observe the
  /// problem again before posting. No unverified timer fires while suspended.
  static func changes(status: BackupHubStatus, earlier: HistoricalImportStatus?, connection: ReceiverConnection,
    now: Date, allowed: Bool, memory: inout Memory) -> [Change] {
    var result: [Change] = []
    if status == .problem(.receiverUnreachable) {
      if memory.unreachableSince == nil { memory.unreachableSince = now }
      if let since = memory.unreachableSince, now.timeIntervalSince(since) >= 86_400,
        allowed, !memory.unreachableNotified {
        result.append(.post(.unreachable)); memory.unreachableNotified = true
      }
    } else if connection == .ready || status == .paused || status == .notPaired {
      if memory.unreachableSince != nil { result.append(.withdraw(.unreachable)) }
      memory.unreachableSince = nil; memory.unreachableNotified = false
    }

    if status == .problem(.receiverFull) {
      if allowed && !memory.full { result.append(.post(.full)); memory.full = true }
    } else if memory.full {
      result.append(.withdraw(.full)); memory.full = false
    }
    if case .problem(.conversionNeeded(let count)) = status {
      if allowed && count > memory.convert { result.append(.post(.convert)); memory.convert = count }
    } else if memory.convert > 0 {
      result.append(.withdraw(.convert)); memory.convert = 0
    }
    if let earlier {
      if memory.run != earlier.run {
        memory.run = earlier.run; memory.earlierDone = nil
        result.append(.withdraw(.earlier))
      }
      // Unknown publication counts cannot establish completion. A first
      // observation of an already completed scan stays quiet.
      if earlier.state != "scanned" || earlier.published != nil {
        let done = earlier.isSaved && earlier.checked > 0
        if done && memory.earlierDone == false && allowed { result.append(.post(.earlier)) }
        memory.earlierDone = done
      }
    }
    return result
  }

  func configure() {
    center.delegate = self
    // Remove the interrupted implementation's unverified scheduled reminders.
    if !defaults.bool(forKey: "notify.v2.migrated") {
      center.removePendingNotificationRequests(withIdentifiers: Notice.allCases.map(\.rawValue))
      center.removeDeliveredNotifications(withIdentifiers: Notice.allCases.map(\.rawValue))
      defaults.set(true, forKey: "notify.v2.migrated")
    }
  }

  /// Starts at launch, including OS background wakes. Catalogs stay isolated.
  func start(_ model: BackupModel) {
    guard BackupEnvironment.usesPhotoLibrary, watching == nil else { return }
    configure()
    watching = model.objectWillChange
      .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
      .sink { [weak self, weak model] _ in
        Task { @MainActor in if let model { await self?.evaluate(model) } }
      }
    Task { await evaluate(model) }
  }

  func refreshAuthorization() async {
    let value = await center.notificationSettings().authorizationStatus
    if authorization != value { authorization = value }
  }
  func requestPermission() async {
    permissionError = nil
    do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
    catch { permissionError = NSLocalizedString("notifications_permission_failed", comment: "") }
    await refreshAuthorization()
  }

  func evaluate(_ model: BackupModel) async {
    needsEvaluation = true
    guard !evaluating else { return }
    evaluating = true
    defer { evaluating = false }
    repeat {
      needsEvaluation = false
      await evaluateCurrent(model)
    } while needsEvaluation
  }

  private func evaluateCurrent(_ model: BackupModel) async {
    await refreshAuthorization()
    guard model.ready else { return }
    var memory = defaults.data(forKey: memoryKey).flatMap { try? JSONDecoder().decode(Memory.self, from: $0) } ?? Memory()
    let receiver = model.pairing?.receiverID
    if memory.receiver != receiver {
      withdraw(Notice.allCases)
      memory = Memory(receiver: receiver)
    }
    guard let receiver else {
      withdraw(Notice.allCases)
      defaults.removeObject(forKey: memoryKey)
      return
    }
    guard model.queueRevision >= 0 else { return }
    let allowed = authorization == .authorized || authorization == .provisional
    let changes = Self.changes(status: model.hubStatus, earlier: model.historicalImport,
      connection: model.receiverConnection, now: Date(), allowed: allowed, memory: &memory)
    for change in changes {
      switch change {
      case .withdraw(let notice): withdraw([notice])
      case .post(let notice):
        do {
          try await center.add(request(notice, receiver: receiver,
            name: model.peerDevice?.name ?? "Pixel", conversions: memory.convert))
        } catch { memory.retry(notice) }
        guard model.pairing?.receiverID == receiver else {
          withdraw(Notice.allCases); needsEvaluation = true; return
        }
      }
    }
    defaults.set(try? JSONEncoder().encode(memory), forKey: memoryKey)
  }

  private func withdraw(_ notices: [Notice]) {
    let ids = notices.map { "backupduck." + $0.rawValue }
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
  }
  private func request(_ notice: Notice, receiver: String, name: String, conversions: Int) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    let prefix = "notify_" + notice.rawValue
    let title = NSLocalizedString(prefix + "_title", comment: "")
    switch notice {
    case .unreachable: content.title = String(format: title, name)
    case .convert: content.title = String(format: title, conversions.formatted())
    case .full, .earlier: content.title = title
    }
    content.body = NSLocalizedString(prefix + "_body", comment: "")
    content.sound = .default
    content.userInfo = ["notice": notice.rawValue, "receiver": receiver]
    return UNNotificationRequest(identifier: "backupduck." + notice.rawValue, content: content, trigger: nil)
  }

  static func destination(notice: String?, receiver: String?, current: String?) -> Notice? {
    guard let receiver, receiver == current, let notice else { return nil }
    return Notice(rawValue: notice)
  }
  func takeRoute(receiver: String?) -> Notice? {
    guard let route else { return nil }
    self.route = nil
    return Self.destination(notice: route.notice.rawValue, receiver: route.receiver, current: receiver)
  }
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let notice = response.notification.request.content.userInfo["notice"] as? String,
      let receiver = response.notification.request.content.userInfo["receiver"] as? String,
      let value = Notice(rawValue: notice) else { return }
    await MainActor.run { route = Route(notice: value, receiver: receiver) }
  }
}

/// One explicit system-owned setting, available after skipping first run.
/// Passive notification evaluation never prompts for permission.
struct BackupNotificationPreferences: View {
  @ObservedObject private var notifier = BackupNotifier.shared
  @Environment(\.openURL) private var openURL
  var body: some View {
    Section {
      Button(notifier.authorization == .notDetermined ? "notifications_allow" : "notifications_settings") {
        Task {
          if notifier.authorization == .notDetermined { await notifier.requestPermission() }
          else {
            #if os(macOS)
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
            #else
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            #endif
          }
        }
      }
    } header: { Text("notifications_title") }
    footer: {
      Text(notifier.permissionError ?? NSLocalizedString("notifications_note", comment: ""))
    }
    .task { await notifier.refreshAuthorization() }
  }
}

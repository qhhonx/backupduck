import ActivityKit
import Foundation

/// Display-only scope. All counts and actions originate in the Rust sender.
struct BackupActivityAttributes: ActivityAttributes {
  enum Phase: String, Codable, Hashable {
    case finding, preparing, sending, saving, paused, waiting, attention, saved
    var title: String { "activity_" + rawValue }
    var symbol: String {
      switch self {
      case .finding, .preparing: "photo.stack"
      case .sending: "arrow.up.circle"
      case .saving: "clock"
      case .paused: "pause.circle"
      case .waiting: "wifi.exclamationmark"
      case .attention: "exclamationmark.triangle"
      case .saved: "checkmark.circle"
      }
    }
  }
  struct ContentState: Codable, Hashable {
    var remaining: Int
    var total: Int
    var phase: Phase
    var determinate: Bool
    var observedAt: Date
    var actionFailed = false
    var progress: Double? {
      guard determinate, total > 0 else { return nil }
      return min(1, max(0, Double(total - remaining) / Double(total)))
    }
    func sameFacts(as other: Self) -> Bool {
      remaining == other.remaining && total == other.total && phase == other.phase
        && determinate == other.determinate && actionFailed == other.actionFailed
    }
  }
  let receiver: String
  let receiverName: String
  let session: String
  let baselinePublished: Int
  let initialRemaining: Int
  var url: URL {
    var value = URLComponents()
    value.scheme = "backupduck"; value.host = "backup"
    value.queryItems = [URLQueryItem(name: "receiver", value: receiver)]
    return value.url!
  }
}

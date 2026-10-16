import Foundation
import StoreKit
import SwiftUI

/// TestFlight builds show the tester feedback group above About. The group is
/// the Telegram community linked from the website.
@MainActor final class TesterFeedback: ObservableObject {
  static let shared = TesterFeedback()
  static let group = URL(string: "https://t.me/+MCA62rlSwZplMGI1")!
  @Published private(set) var available = false
  private var checked = false
  func check() async {
    guard !checked else { return }
    checked = true
    // `-tester-feedback` shows the entry in any build, to check its layout.
    if ProcessInfo.processInfo.arguments.contains("-tester-feedback") { available = true; return }
    #if os(iOS)
    // TestFlight installs carry a sandbox receipt; App Store, Xcode and
    // device-installed builds do not.
    available = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    #elseif BACKUPDUCK_APP_STORE
    // Only the store target asks StoreKit, and only with a receipt present, so a
    // build without one never prompts for an App Store sign-in.
    guard let receipt = Bundle.main.appStoreReceiptURL, FileManager.default.fileExists(atPath: receipt.path),
      let result = try? await AppTransaction.shared else { return }
    switch result {
    case .verified(let transaction), .unverified(let transaction, _):
      available = transaction.environment == .sandbox
    }
    #endif
  }
}

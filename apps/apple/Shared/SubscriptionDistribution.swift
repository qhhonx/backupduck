import Foundation
import StoreKit
import SwiftUI

#if (BACKUPDUCK_IN_HOUSE && BACKUPDUCK_TESTFLIGHT) || (BACKUPDUCK_APP_STORE_SUBMISSION && (BACKUPDUCK_IN_HOUSE || BACKUPDUCK_TESTFLIGHT))
#error("Select exactly one BackupDuck package configuration.")
#endif

/// Distribution controls Pro presentation and the source of access.
enum DuckProDistributionChannel: Equatable {
  case unknown, directDownload, development, sandbox, inHouse, testFlight, submissionSandbox, appStore

  enum TransactionEnvironment {
    case production, sandbox, xcode, unknown

    init(_ environment: AppStore.Environment) {
      if environment == .production { self = .production }
      else if environment == .sandbox { self = .sandbox }
      else if environment == .xcode { self = .xcode }
      else { self = .unknown }
    }
  }
  enum Evidence {
    case unavailable
    case unverified
    case verified(environment: TransactionEnvironment, bundleID: String)
  }

  var includesTestAccess: Bool { self == .inHouse || self == .testFlight }
  var allowsPurchases: Bool { self == .appStore || self == .submissionSandbox }
  var allowsPro: Bool { includesTestAccess || allowsPurchases }

  func acceptsPurchase(in environment: TransactionEnvironment) -> Bool {
    switch (self, environment) {
    case (.appStore, .production), (.submissionSandbox, .sandbox): return true
    default: return false
    }
  }

  static func resolve(storeTarget: Bool, bundleID: String, evidence: Evidence,
    submissionArchive: Bool = false) -> Self {
    guard storeTarget else { return .directDownload }
    guard case .verified(let environment, let transactionBundleID) = evidence,
      !bundleID.isEmpty, transactionBundleID == bundleID else { return .unknown }
    switch environment {
    case .production: return .appStore
    case .sandbox: return submissionArchive ? .submissionSandbox : .sandbox
    case .xcode: return .development
    case .unknown: return .unknown
    }
  }
}

/// Test packages include Pro at launch. Store builds use verified app transactions.
@MainActor final class DuckProDistribution: ObservableObject {
  static let shared = DuckProDistribution()
  @Published private(set) var channel: DuckProDistributionChannel
  var allowsPro: Bool { channel.allowsPro }
  private var checking = false

  private static var isSubmissionArchive: Bool {
    #if BACKUPDUCK_APP_STORE_SUBMISSION
    true
    #else
    false
    #endif
  }

  private init() {
    #if BACKUPDUCK_IN_HOUSE
    channel = .inHouse
    #elseif BACKUPDUCK_TESTFLIGHT
    channel = .testFlight
    #elseif os(macOS) && !BACKUPDUCK_APP_STORE
    channel = .directDownload
    #elseif targetEnvironment(simulator)
    channel = .development
    #else
    channel = .unknown
    #endif
  }

  func check() async {
    guard channel == .unknown, !checking else { return }
    // Use the signed app-transaction lookup without a receipt-refresh or
    // explicit account-authentication fallback. Errors leave commerce off.
    checking = true
    defer { checking = false }
    do {
      let result = try await AppTransaction.shared
      switch result {
      case .verified(let transaction):
        channel = DuckProDistributionChannel.resolve(storeTarget: true,
          bundleID: Bundle.main.bundleIdentifier ?? "",
          evidence: .verified(environment: .init(transaction.environment), bundleID: transaction.bundleID),
          submissionArchive: Self.isSubmissionArchive)
      case .unverified:
        channel = .unknown
      }
    } catch {
      channel = .unknown
    }
  }
}

private struct DuckProEnabledKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Catalog supplies its preview value; app hosts apply their distribution policy.
  var duckProEnabled: Bool {
    get { self[DuckProEnabledKey.self] }
    set { self[DuckProEnabledKey.self] = newValue }
  }
}

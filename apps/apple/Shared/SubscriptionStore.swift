import Combine
import Foundation
import Security
import StoreKit

/// Access is an execution constraint; it never rewrites a person's queue or preferences.
enum DuckSubscriptionAccess: Equatable {
  case unrestricted
  case welcome(until: Date)
  case paid(until: Date)
  case expired(since: Date?)

  var permitsBackup: Bool {
    if case .expired = self { return false }
    return true
  }
}

enum DuckSubscriptionPurchaseOutcome: Equatable {
  case idle, purchased, pending, cancelled, failed
}

/// One verified StoreKit observation. Renewal intent does not extend entitlement.
struct DuckSubscriptionEntitlement: Equatable {
  let expiration: Date
  let revoked: Bool
  var willAutoRenew: Bool?
  var signedDate: Date = .distantPast
  var purchaseDate: Date = .distantPast
  var transactionID: UInt64?
  var renewalDate: Date?

  /// Refunds of an earlier period must not revoke a later verified renewal.
  func supersedes(_ previous: Self) -> Bool {
    if purchaseDate != previous.purchaseDate { return purchaseDate > previous.purchaseDate }
    if signedDate != previous.signedDate { return signedDate > previous.signedDate }
    return transactionID == previous.transactionID
  }

  func grantsAccess(at date: Date) -> Bool { !revoked && expiration > date }
}

enum DuckSubscriptionAccessPolicy {
  static let welcomeDuration: TimeInterval = 7 * 24 * 60 * 60

  static func resolve(enabled: Bool, welcomeStart: Date?, entitlement: DuckSubscriptionEntitlement?,
    now: Date) -> DuckSubscriptionAccess {
    guard enabled else { return .unrestricted }
    if let entitlement, entitlement.grantsAccess(at: now) { return .paid(until: entitlement.expiration) }
    // A previous purchase never creates a fresh welcome period after refund or expiry.
    if let entitlement { return .expired(since: entitlement.expiration <= now ? entitlement.expiration : nil) }
    guard let welcomeStart, welcomeStart <= now else { return .expired(since: nil) }
    let end = welcomeStart.addingTimeInterval(welcomeDuration)
    return now < end ? .welcome(until: end) : .expired(since: end)
  }
}

/// StoreKit 2 is the sole paid-entitlement authority. There is no application billing server.
@MainActor final class DuckSubscriptionStore: ObservableObject {
  enum Mode { case production, localTesting }
  static let monthlyProductID = DuckSubscriptionPlan.monthly.productID
  static let localTestingBundleID = "app.backupduck.storekittest"

  @Published private(set) var statusPresentation = DuckSubscriptionStatusPresentation(state: .checking)
  @Published private(set) var offerPresentation = DuckSubscriptionOfferPresentation(monthlyPrice: nil)
  @Published private(set) var access: DuckSubscriptionAccess = .unrestricted
  @Published private(set) var purchaseOutcome: DuckSubscriptionPurchaseOutcome = .idle
  @Published private(set) var commerceEnabled = false

  private let mode: Mode
  private var products: [DuckSubscriptionPlan: Product] = [:]
  private var entitlements: [DuckSubscriptionPlan: DuckSubscriptionEntitlement] = [:]
  private var entitlement: DuckSubscriptionEntitlement? {
    let now = Date()
    return DuckSubscriptionPlan.allCases.compactMap { entitlements[$0] }.reduce(nil) { best, candidate in
      guard let best else { return candidate }
      let candidateActive = candidate.grantsAccess(at: now)
      if candidateActive != best.grantsAccess(at: now) { return candidateActive ? candidate : best }
      return candidate.supersedes(best) ? candidate : best
    }
  }
  private var welcomeStart: Date?
  private var updatesTask: Task<Void, Never>?
  private var expiryTask: Task<Void, Never>?
  private var operationInProgress = false
  private var refreshGeneration = 0
  private var started = false
  private var statusError = false
  private var restoration: DuckSubscriptionRestoreState = .idle
  private var productError: String?
  private let vault = DuckSubscriptionWelcomeVault()

  init(mode: Mode = .production) { self.mode = mode }

  deinit {
    updatesTask?.cancel()
    expiryTask?.cancel()
  }

  /// Start listening before reading history so a purchase arriving during startup is observed.
  func start() async {
    if !started {
      started = true
      updatesTask = Task { [weak self] in
        for await result in Transaction.updates {
          guard !Task.isCancelled else { return }
          guard let self else { return }
          await self.receive(result)
        }
      }
    }
    await refresh()
  }

  /// Foreground refresh never invokes AppStore.sync or asks for account authentication.
  func refresh() async {
    refreshGeneration += 1
    let generation = refreshGeneration
    let enabled = await authorizeCommerce()
    guard generation == refreshGeneration else { return }
    commerceEnabled = enabled
    guard enabled else {
      products.removeAll()
      entitlements.removeAll()
      welcomeStart = nil
      access = .unrestricted
      statusError = true
      project()
      return
    }
    access = DuckSubscriptionAccessPolicy.resolve(enabled: true, welcomeStart: welcomeStart,
      entitlement: entitlement, now: Date())

    var observations: [DuckSubscriptionPlan: DuckSubscriptionEntitlement] = [:]
    var verificationFailed = false
    for await result in Transaction.currentEntitlements {
      switch result {
      case .verified(let transaction):
        guard let plan = DuckSubscriptionPlan(productID: transaction.productID),
          accepts(transaction), let value = observation(transaction) else { continue }
        if observations[plan].map({ value.supersedes($0) }) ?? true { observations[plan] = value }
      case .unverified(let transaction, _):
        if DuckSubscriptionPlan(productID: transaction.productID) != nil { verificationFailed = true }
      }
    }
    // Look up each plan independently so an older refund cannot replace another plan's paid access.
    for plan in DuckSubscriptionPlan.allCases where observations[plan] == nil {
      guard let latest = await Transaction.latest(for: plan.productID) else { continue }
      switch latest {
      case .verified(let transaction):
        if accepts(transaction) { observations[plan] = observation(transaction) }
      case .unverified: verificationFailed = true
      }
    }
    guard generation == refreshGeneration else { return }
    for (plan, observation) in observations { record(observation, for: plan) }
    statusError = verificationFailed
    do {
      welcomeStart = try await vault.loadOrCreateStart()
    } catch {
      // Paid access is independent of welcome persistence. A failed welcome grant stays closed.
      welcomeStart = nil
      statusError = true
    }
    guard generation == refreshGeneration else { return }

    do {
      let fetched = try await Product.products(for: DuckSubscriptionPlan.allCases.map(\.productID))
      guard generation == refreshGeneration else { return }
      products = [:]
      for product in fetched {
        guard let plan = DuckSubscriptionPlan(productID: product.id), Self.matches(product, plan: plan) else { continue }
        products[plan] = product
      }
      productError = products.isEmpty ? "subscription_price_retry_note" : nil
    } catch {
      guard generation == refreshGeneration else { return }
      productError = "subscription_price_retry_note"
    }
    // Both periods share one subscription group and one status feed.
    if let subscription = (products[.monthly] ?? products[.annual])?.subscription {
      do {
        let statuses = try await subscription.status
        guard generation == refreshGeneration else { return }
        for status in statuses {
          guard case .verified(let transaction) = status.transaction, accepts(transaction),
            case .verified(let renewal) = status.renewalInfo,
            renewal.currentProductID == transaction.productID,
            let plan = DuckSubscriptionPlan(productID: transaction.productID),
            renewal.environment == transaction.environment else { continue }
          guard var value = observation(transaction) else { continue }
          value.willAutoRenew = renewal.willAutoRenew
          value.signedDate = max(value.signedDate, renewal.signedDate)
          if status.state != .subscribed && status.state != .inGracePeriod {
            // A signed inactive renewal state cannot be revived by an old future expiration.
            value = .init(expiration: value.expiration, revoked: true, willAutoRenew: renewal.willAutoRenew, signedDate: value.signedDate,
              purchaseDate: value.purchaseDate, transactionID: value.transactionID)
          }
          if status.state == .inGracePeriod, let graceEnd = renewal.gracePeriodExpirationDate,
            graceEnd > value.expiration {
            value = .init(expiration: graceEnd, revoked: value.revoked, willAutoRenew: renewal.willAutoRenew, signedDate: value.signedDate,
              purchaseDate: value.purchaseDate, transactionID: value.transactionID)
          }
          if status.state == .subscribed && renewal.willAutoRenew {
            value.renewalDate = transaction.expirationDate
          }
          record(value, for: plan)
        }
      } catch {
        // Signed, still-valid access survives a transient status/product-network failure.
      }
    }
    guard generation == refreshGeneration else { return }
    if purchaseOutcome == .pending, entitlement?.grantsAccess(at: Date()) == true {
      purchaseOutcome = .purchased
    }
    project()
  }

  func purchase(_ plan: DuckSubscriptionPlan = .monthly) async {
    guard !operationInProgress else { return }
    if purchaseOutcome == .pending { await refresh(); return }
    operationInProgress = true
    productError = nil
    purchaseOutcome = .idle
    project()
    defer { operationInProgress = false; project() }
    // Recheck immediately before purchase. A local preview must never reach a live store.
    guard await authorizeCommerce() else {
      await refresh()
      purchaseOutcome = .failed
      productError = "subscription_price_retry_note"
      return
    }
    guard let product = products[plan] else {
      purchaseOutcome = .failed
      productError = "subscription_price_retry_note"
      return
    }
    do {
      switch try await product.purchase() {
      case .success(let result):
        guard case .verified(let transaction) = result, transaction.productID == plan.productID,
          accepts(transaction) else {
          purchaseOutcome = .failed
          productError = "subscription_note_error"
          return
        }
        let purchased = observation(transaction)
        if let purchased { record(purchased, for: plan) }
        let usable = purchased?.grantsAccess(at: Date()) == true
        purchaseOutcome = usable ? .purchased : .failed
        if !usable { productError = "subscription_note_error" }
        project()
        await transaction.finish()
        await refresh()
      case .pending:
        purchaseOutcome = .pending
      case .userCancelled:
        purchaseOutcome = .cancelled
      @unknown default:
        purchaseOutcome = .failed
        productError = "subscription_note_error"
      }
    } catch StoreKitError.userCancelled {
      purchaseOutcome = .cancelled
    } catch let error as SKError where error.code == .paymentCancelled {
      purchaseOutcome = .cancelled
    } catch {
      purchaseOutcome = .failed
      productError = "subscription_note_error"
    }
  }

  /// The only account-sync path, invoked by the person's Restore Purchases action.
  func restore() async {
    guard !operationInProgress else { return }
    guard await authorizeCommerce() else { await refresh(); return }
    operationInProgress = true
    restoration = .restoring
    project()
    defer { operationInProgress = false; project() }
    do {
      try await AppStore.sync()
      await refresh()
      restoration = entitlement?.grantsAccess(at: Date()) == true ? .idle : .nothingFound
    } catch {
      restoration = .failed
    }
  }

  private static func matches(_ product: Product, plan: DuckSubscriptionPlan) -> Bool {
    guard product.type == .autoRenewable, let period = product.subscription?.subscriptionPeriod else { return false }
    return period.value == 1 && period.unit == (plan == .monthly ? .month : .year)
  }

  private func record(_ observation: DuckSubscriptionEntitlement, for plan: DuckSubscriptionPlan) {
    if entitlements[plan].map({ observation.supersedes($0) }) ?? true { entitlements[plan] = observation }
  }

  private func authorizeCommerce() async -> Bool {
    switch mode {
    case .production:
      await DuckProDistribution.shared.check()
      return DuckProDistribution.shared.allowsPro
    case .localTesting:
      #if BACKUPDUCK_SUBSCRIPTION_TESTING
      guard Bundle.main.bundleIdentifier == Self.localTestingBundleID else { return false }
      guard let result = try? await AppTransaction.shared,
        case .verified(let transaction) = result else { return false }
      return transaction.environment == .xcode && transaction.bundleID == Self.localTestingBundleID
      #else
      return false
      #endif
    }
  }

  private func accepts(_ transaction: Transaction) -> Bool {
    guard DuckSubscriptionPlan(productID: transaction.productID) != nil,
      transaction.productType == .autoRenewable else { return false }
    switch mode {
    case .production:
      return commerceEnabled && transaction.appBundleID == Bundle.main.bundleIdentifier &&
        DuckProDistribution.shared.channel.acceptsPurchase(in: .init(transaction.environment))
    case .localTesting:
      #if BACKUPDUCK_SUBSCRIPTION_TESTING
      return Bundle.main.bundleIdentifier == Self.localTestingBundleID && transaction.environment == .xcode
      #else
      return false
      #endif
    }
  }

  private func observation(_ transaction: Transaction) -> DuckSubscriptionEntitlement? {
    guard let expiration = transaction.expirationDate else { return nil }
    return .init(expiration: transaction.revocationDate.map { min($0, expiration) } ?? expiration,
      revoked: transaction.revocationDate != nil || transaction.isUpgraded, signedDate: transaction.signedDate,
      purchaseDate: transaction.purchaseDate, transactionID: transaction.id)
  }

  private func receive(_ result: VerificationResult<Transaction>) async {
    guard await authorizeCommerce() else { return }
    switch result {
    case .verified(let transaction):
      guard accepts(transaction), let plan = DuckSubscriptionPlan(productID: transaction.productID) else { return }
      if let updated = observation(transaction) { record(updated, for: plan) }
      if entitlement?.grantsAccess(at: Date()) == true { purchaseOutcome = .purchased }
      project()
      await transaction.finish()
      await refresh()
    case .unverified(let transaction, _):
      guard DuckSubscriptionPlan(productID: transaction.productID) != nil else { return }
      statusError = true
      project()
    }
  }

  private func project(now: Date = Date()) {
    access = DuckSubscriptionAccessPolicy.resolve(enabled: commerceEnabled, welcomeStart: welcomeStart,
      entitlement: entitlement, now: now)
    let state: DuckSubscriptionStatusPresentation.State
    let date: Date?
    switch access {
    case .paid(let until):
      state = entitlement?.willAutoRenew == false ? .renewalOff : .active
      date = state == .renewalOff ? until : entitlement?.renewalDate
    case .welcome(let until):
      state = purchaseOutcome == .pending ? .pending : .welcome
      date = state == .welcome ? until : nil
    case .expired(let since):
      state = purchaseOutcome == .pending ? .pending : .expired
      date = state == .expired ? since : nil
    case .unrestricted:
      state = statusError ? .unavailable : .checking
      date = nil
    }
    let presentedState: DuckSubscriptionStatusPresentation.State = statusError && !access.permitsBackup ? .unavailable : state
    statusPresentation = .init(state: presentedState,
      date: date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) },
      monthlyPrice: nil,
      message: statusError && state != .unavailable ? "subscription_note_unavailable" : nil,
      restoration: restoration)
    let monthly = products[.monthly]
    let annual = products[.annual]
    let equivalent = annual.map { ($0.price / 12).formatted($0.priceFormatStyle) }
    let savings: String?
    if let monthly, let annual, monthly.priceFormatStyle.currencyCode == annual.priceFormatStyle.currencyCode,
      monthly.price > 0, annual.price <= monthly.price * 12 * 99 / 100 {
      let fraction = 1 - annual.price / (monthly.price * 12)
      savings = fraction.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
    } else {
      savings = nil
    }
    offerPresentation = .init(monthlyPrice: monthly?.displayPrice, annualPrice: annual?.displayPrice,
      annualMonthlyEquivalent: equivalent, annualSavings: savings, busy: operationInProgress,
      pending: purchaseOutcome == .pending, error: productError, restoration: restoration)
    expiryTask?.cancel()
    let deadline: Date?
    switch access {
    case .welcome(let until), .paid(let until): deadline = until
    case .unrestricted, .expired: deadline = nil
    }
    if let deadline {
      let delay = max(0, deadline.timeIntervalSince(now))
      expiryTask = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        guard let self else { return }
        self.expiryTask = nil
        self.project()
        await self.refresh()
      }
    }
  }

  #if BACKUPDUCK_SUBSCRIPTION_TESTING
  /// Available exclusively in the separately identified development application.
  func setLocalWelcomeStart(_ date: Date) async {
    guard mode == .localTesting, Bundle.main.bundleIdentifier == Self.localTestingBundleID else { return }
    do { try await vault.saveStart(date); await refresh() }
    catch { statusError = true; project() }
  }

  func clearLocalWelcome() async {
    guard mode == .localTesting, Bundle.main.bundleIdentifier == Self.localTestingBundleID else { return }
    do { try await vault.deleteStart(); await refresh() }
    catch { statusError = true; project() }
  }
  #endif
}

/// Device-only Keychain survives ordinary app updates and is separate for the development bundle.
private struct DuckSubscriptionWelcomeVault {
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.backupduck") + ".subscription",
      kSecAttrAccount as String: "welcome-start-v1"]
  }

  func loadOrCreateStart() async throws -> Date {
    try await Task.detached(priority: .userInitiated) { try loadOrCreateStartSync() }.value
  }

  func saveStart(_ date: Date) async throws {
    try await Task.detached(priority: .userInitiated) { try saveStartSync(date) }.value
  }

  func deleteStart() async throws {
    try await Task.detached(priority: .userInitiated) { try deleteStartSync() }.value
  }

  private func loadOrCreateStartSync() throws -> Date {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data,
      let seconds = Double(String(decoding: data, as: UTF8.self)), seconds.isFinite, seconds > 0 {
      let start = Date(timeIntervalSince1970: seconds)
      guard start <= Date() else { throw VaultError.invalidStart }
      return start
    }
    guard status == errSecItemNotFound else { throw VaultError.status(status) }
    let start = Date()
    try saveStartSync(start)
    return start
  }

  private func saveStartSync(_ date: Date) throws {
    let data = Data(String(date.timeIntervalSince1970).utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw VaultError.status(status) }
    var insertion = query
    insertion[kSecValueData as String] = data
    insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(insertion as CFDictionary, nil)
    guard added == errSecSuccess else { throw VaultError.status(added) }
  }

  private func deleteStartSync() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.status(status) }
  }

  private enum VaultError: Error { case status(OSStatus), invalidStart }
}

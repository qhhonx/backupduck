import SwiftUI
import StoreKit

/// The testing override requires both a private build condition and an isolated identity.
enum DuckSubscriptionHostMode {
  static var isLocalTesting: Bool {
    #if BACKUPDUCK_SUBSCRIPTION_TESTING
    Bundle.main.bundleIdentifier == DuckSubscriptionStore.localTestingBundleID
    #else
    false
    #endif
  }
  static var isUnitTestHost: Bool {
    #if BACKUPDUCK_SUBSCRIPTION_TESTING
    isLocalTesting && (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil)
    #else
    false
    #endif
  }
  static var opensSettings: Bool {
    isLocalTesting && (isUnitTestHost || ProcessInfo.processInfo.arguments.contains("--subscription-testing-settings"))
  }
}

@MainActor final class DuckSubscriptionHost: ObservableObject {
  let store = DuckSubscriptionStore(mode: DuckSubscriptionHostMode.isLocalTesting ? .localTesting : .production)
  private var startedCommerce = false
  private var startingCommerce = false
  var enabled: Bool { DuckSubscriptionHostMode.isLocalTesting || DuckProDistribution.shared.allowsPro }

  func open(_ model: BackupModel) async {
    if DuckSubscriptionHostMode.isUnitTestHost { await model.setSubscriptionAccess(allowed: false); return }
    if enabled {
      if startedCommerce { await apply(model) }
      else { await startCommerce(model) }
    } else {
      await model.setSubscriptionAccess(allowed: true)
    }
    await model.open()
  }
  func updateChannel(_ model: BackupModel) async {
    guard !DuckSubscriptionHostMode.isUnitTestHost else { return }
    guard enabled else {
      await model.setSubscriptionAccess(allowed: true)
      return
    }
    if !startedCommerce { await startCommerce(model) }
    else { await apply(model); await store.refresh() }
  }
  private func startCommerce(_ model: BackupModel) async {
    guard !startingCommerce else { return }
    startingCommerce = true
    defer { startingCommerce = false }
    await model.setSubscriptionAccess(allowed: false)
    await store.start()
    startedCommerce = true
    await apply(model)
  }
  func apply(_ model: BackupModel) async {
    guard enabled else { await model.setSubscriptionAccess(allowed: true); return }
    guard startedCommerce else { await model.setSubscriptionAccess(allowed: false); return }
    switch store.access {
    case .unrestricted: await model.setSubscriptionAccess(allowed: true)
    case .welcome(let until), .paid(let until): await model.setSubscriptionAccess(allowed: true, validUntil: until)
    case .expired: await model.setSubscriptionAccess(allowed: false)
    }
  }
}

/// Native pages receive live observations and explicit StoreKit executors.
struct DuckSubscriptionHostContent: ViewModifier {
  @ObservedObject var host: DuckSubscriptionHost
  @ObservedObject var store: DuckSubscriptionStore
  @ObservedObject private var distribution = DuckProDistribution.shared
  @Environment(\.openURL) private var openURL
  private var actions: DuckSubscriptionActions {
    .init(subscribe: { plan in Task { await store.purchase(plan) } }, reload: { Task { await store.refresh() } },
      restore: { Task { await store.restore() } },
      privacy: { openURL(DuckSupport.privacy) },
      terms: { openURL(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) })
  }
  func body(content: Content) -> some View {
    content
      .environment(\.duckProEnabled, host.enabled)
      .environment(\.duckSubscriptionSettings, host.enabled ? .init(presentation: store.statusPresentation,
        detail: AnyView(DuckSubscriptionLiveDetail(store: store, actions: actions))) : nil)
      .environment(\.duckSubscriptionBackup, host.enabled && !store.access.permitsBackup ?
        .init(offer: { close in AnyView(DuckSubscriptionLiveOffer(store: store, actions: actions, close: close)) }) : nil)

  }
}

/// Pushed UIKit/AppKit destinations keep observing the store after the parent row changes.
private struct DuckSubscriptionLiveDetail: View {
  @ObservedObject var store: DuckSubscriptionStore
  let actions: DuckSubscriptionActions
  @Environment(\.openURL) private var openURL
  @State private var managing = false
  @State private var testing = false
  var body: some View {
    DuckSubscriptionStatusPage(presentation: store.statusPresentation, offer: store.offerPresentation,
      purchaseActions: actions, action: {
        guard store.statusPresentation.isPaid else { Task { await store.refresh() }; return }
        if DuckSubscriptionHostMode.isLocalTesting { testing = true } else {
          #if os(iOS)
          managing = true
          #else
          openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
          #endif
        }
      }, restore: { Task { await store.restore() } })
      .toolbar {
        #if BACKUPDUCK_SUBSCRIPTION_TESTING
        if DuckSubscriptionHostMode.isLocalTesting {
          ToolbarItem { Button("subscription_testing_title") { testing = true } }
        }
        #endif
      }
      #if os(iOS)
      .manageSubscriptionsSheet(isPresented: $managing)
      .onChange(of: managing) { wasPresented, isPresented in
        if wasPresented && !isPresented { Task { await store.refresh() } }
      }
      #endif
      .sheet(isPresented: $testing) {
        #if BACKUPDUCK_SUBSCRIPTION_TESTING
        DuckSubscriptionTestingPanel(store: store) { testing = false }
        #endif
      }
  }
}

private struct DuckSubscriptionLiveOffer: View {
  @ObservedObject var store: DuckSubscriptionStore
  let actions: DuckSubscriptionActions
  let close: () -> Void
  var body: some View {
    DuckSubscriptionOffer(presentation: store.offerPresentation, actions: actions, cancel: close)
  }
}

#if BACKUPDUCK_SUBSCRIPTION_TESTING
/// Local welcome controls never fabricate a paid transaction or invoke StoreKitTest in the app.
private struct DuckSubscriptionTestingPanel: View {
  @ObservedObject var store: DuckSubscriptionStore
  let close: () -> Void
  var body: some View {
    DuckSheetLayout(title: "subscription_testing_title", closeOnly: true, cancel: close) {
      VStack(alignment: .leading, spacing: DuckSpacing.medium) {
        Text("subscription_testing_note").foregroundStyle(DuckRole.secondaryText)
        LabeledContent("subscription_testing_environment", value: String(localized: store.commerceEnabled ? "subscription_testing_ready" : "subscription_testing_missing"))
        Button("subscription_testing_welcome") { Task { await store.setLocalWelcomeStart(Date()) } }
        Button("subscription_testing_expired") { Task { await store.setLocalWelcomeStart(Date().addingTimeInterval(-8 * 24 * 60 * 60)) } }
        Button("subscription_testing_reset") { Task { await store.clearLocalWelcome() } }
        Button("subscription_retry") { Task { await store.refresh() } }
      }
    } actions: { EmptyView() }
  }
}
#endif

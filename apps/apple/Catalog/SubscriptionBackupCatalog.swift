import SwiftUI

/// The production hub with explicit synthetic access context, never admission logic.
struct SubscriptionBackupCatalog: ViewModifier {
  let scenarioID: String
  private var enabled: Bool { !scenarioID.hasSuffix("-testflight") && !scenarioID.hasSuffix("-direct") }
  func body(content: Content) -> some View {
    if scenarioID.hasPrefix("hub.subscription-expired") {
      content
        .environment(\.duckProEnabled, enabled)
        .environment(\.duckSubscriptionSettings, SubscriptionSettingsCatalog.context(for: "subscription.settings-expired"))
        .environment(\.duckSubscriptionBackup, DuckSubscriptionBackupContext(offer: { close in
          AnyView(SubscriptionBackupOfferCatalog(close: close))
        }))
    } else { content }
  }
}

private struct SubscriptionBackupOfferCatalog: View {
  let close: () -> Void
  @State private var feedback: String?
  private var actions: DuckSubscriptionActions {
    .init(subscribe: { _ in feedback = NSLocalizedString("subscription_catalog_purchase", comment: "") },
      reload: { feedback = NSLocalizedString("subscription_catalog_reload", comment: "") },
      restore: { feedback = NSLocalizedString("subscription_catalog_restore", comment: "") },
      privacy: { feedback = NSLocalizedString("subscription_catalog_legal", comment: "") },
      terms: { feedback = NSLocalizedString("subscription_catalog_legal", comment: "") })
  }
  var body: some View {
    DuckSubscriptionOffer(presentation: .init(monthlyPrice: "¥2.00", annualPrice: "¥12.00", annualMonthlyEquivalent: "¥1.00", annualSavings: "50%"), actions: actions, cancel: {
      record("dismissed")
      close()
    })
    .onAppear { record("presented") }
    .alert("subscription_catalog_title", isPresented: Binding(
      get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
      Button("settings_done") { feedback = nil }
    } message: { Text(feedback ?? "") }
  }

  /// Review evidence only: all values belong to this synthetic model instance.
  @MainActor private func record(_ phase: String) {
    let model = BackupEnvironment.activeModel()
    var facts: [String: Any] = ["phase": phase, "paused": model.paused,
      "autoBackup": model.autoBackup, "jobs": model.jobs.map { ["id": $0.id, "state": $0.state] as [String: Any] },
      "total": model.summary.total,
      "commands": (BackupEnvironment.core as? ScenarioCore)?.commands ?? []]
    if let history = model.historicalImport {
      var value: [String: Any] = ["run": history.run, "state": history.state,
        "checked": history.checked, "pending": history.pending]
      if let published = history.published { value["published"] = published }
      facts["history"] = value
    }
    if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]) {
      let path = model.root.appendingPathComponent("catalog-backup-subscription-\(phase).json")
      try? data.write(to: path, options: .atomic)
    }
  }
}

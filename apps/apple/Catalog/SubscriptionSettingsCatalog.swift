import SwiftUI

/// Complete production Settings, with synthetic Pro facts and no purchase APIs.
enum SubscriptionSettingsCatalog {
  static func handles(_ id: String) -> Bool { id == "subscription.settings" || id.hasPrefix("subscription.settings-") }
  static func context(for id: String) -> DuckSubscriptionSettingsContext {
    let state: DuckSubscriptionStatusPresentation.State
    if id.contains("nonmember") || id.hasSuffix("failure") || id.hasSuffix("overview") { state = .notSubscribed }
    else if id.contains("active") { state = .active }
    else if id.contains("renewal-off") { state = .renewalOff }
    else if id.contains("expired") { state = .expired }
    else { state = .welcome }
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateStyle = .medium
    let presentation = DuckSubscriptionStatusPresentation(state: state,
      date: state == .notSubscribed ? nil : formatter.string(from: Date(timeIntervalSince1970: state == .expired ? 1_793_491_200 : 1_794_441_600)),
      monthlyPrice: nil)
    return .init(presentation: presentation,
      detail: AnyView(SubscriptionSettingsCatalogDetail(presentation: presentation)),
      openDetailInitially: id.hasSuffix("-detail"))
  }
}

private struct SubscriptionSettingsCatalogDetail: View {
  let presentation: DuckSubscriptionStatusPresentation
  @State private var feedback: String?
  private var offer: DuckSubscriptionOfferPresentation {
    let usStorefront = Locale.current.region?.identifier == "US"
    return .init(monthlyPrice: usStorefront ? "$1.99" : "¥2.00",
      annualPrice: usStorefront ? "$11.99" : "¥12.00",
      annualMonthlyEquivalent: usStorefront ? "$1.00" : "¥1.00",
      annualSavings: usStorefront ? "49%" : "50%")
  }
  private var actions: DuckSubscriptionActions {
    .init(subscribe: { _ in feedback = NSLocalizedString("subscription_catalog_purchase", comment: "") },
      reload: { feedback = NSLocalizedString("subscription_catalog_reload", comment: "") },
      restore: { feedback = NSLocalizedString("subscription_catalog_restore", comment: "") },
      privacy: { feedback = NSLocalizedString("subscription_catalog_legal", comment: "") },
      terms: { feedback = NSLocalizedString("subscription_catalog_legal", comment: "") })
  }
  var body: some View {
    Group {
      if presentation.state == .notSubscribed {
        DuckSubscriptionOverviewPage(presentation: offer, actions: actions)
      } else {
        DuckSubscriptionStatusPage(presentation: presentation,
          offer: presentation.maySubscribe ? offer : nil,
          purchaseActions: actions,
          action: { feedback = NSLocalizedString("subscription_catalog_status", comment: "") },
          restore: actions.restore)
      }
    }
    .alert("subscription_catalog_title", isPresented: Binding(
      get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
        Button("settings_done") { feedback = nil }
      } message: { Text(feedback ?? "") }
  }
}

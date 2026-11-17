import SwiftUI

/// All prices, dates and action outcomes below are synthetic review data.
/// This driver never invokes StoreKit, the network or a real photo library.
struct SubscriptionCatalog: View {
  let scenarioID: String
  @State private var showingOffer = false
  @State private var showingStatus = false
  @State private var feedback: String?
  @State private var restoration: DuckSubscriptionRestoreState = .idle

  private var suffix: String { scenarioID.components(separatedBy: ".").last ?? "welcome" }
  private var price: String { suffix.hasSuffix("us") ? "$1.99" : "¥2.00" }
  private var status: DuckSubscriptionStatusPresentation {
    let state: DuckSubscriptionStatusPresentation.State = suffix == "expired-work" ? .expired : DuckSubscriptionStatusPresentation.State(rawValue: suffix) ?? .welcome
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Frozen date: this is not an estimate of any person's entitlement.
    let date = formatter.string(from: Date(timeIntervalSince1970: state == .expired ? 1_793_491_200 : 1_794_441_600))
    return .init(state: state,
      date: [.welcome, .active, .renewalOff, .expired].contains(state) ? date : nil,
      monthlyPrice: [.active].contains(state) ? price : nil,
      restoration: fixtureRestoration)
  }
  private var offer: DuckSubscriptionOfferPresentation {
    .init(monthlyPrice: suffix == "offer-unavailable" ? nil : price,
      annualPrice: suffix == "offer-unavailable" ? nil : (suffix.hasSuffix("us") ? "$11.99" : "¥12.00"),
      annualMonthlyEquivalent: suffix.hasSuffix("us") ? "$1.00" : "¥1.00",
      annualSavings: suffix == "offer-unavailable" ? nil : (suffix.hasSuffix("us") ? "49%" : "50%"),
      busy: suffix == "offer-busy",
      error: suffix == "offer-error" ? NSLocalizedString("subscription_note_error", comment: "") : nil,
      restoration: fixtureRestoration)
  }
  var body: some View {
    NavigationStack {
      if suffix.hasPrefix("offer") || suffix == "settings" {
        entry
      } else {
        statusPage
      }
    }
    #if os(iOS)
    .tint(DuckRole.accent)
    #else
    .accentColor(DuckRole.accent)
    #endif
    .sheet(isPresented: $showingOffer) {
      DuckSubscriptionOffer(presentation: offer, actions: actions, cancel: { showingOffer = false })
    }
    .alert("subscription_catalog_title", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
      Button("settings_done") { feedback = nil }
    } message: { Text(feedback ?? "") }
    .onAppear { showingOffer = suffix.hasPrefix("offer") }
  }

  private var entry: some View {
    VStack(spacing: DuckSpacing.medium) {
      Text("subscription_catalog_title").font(.title2.bold())
      Text("subscription_catalog_purchase").foregroundStyle(DuckRole.secondaryText)
      Button("subscription_view_offer") { showingOffer = true }.duckPrimaryButton()
    }.padding(DuckSpacing.large).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  private var actions: DuckSubscriptionActions {
    .init(subscribe: { _ in feedback = NSLocalizedString("subscription_catalog_purchase", comment: "") },
      reload: { feedback = NSLocalizedString("subscription_catalog_reload", comment: "") },
      restore: { restore() },
      privacy: { feedback = NSLocalizedString("subscription_catalog_legal", comment: "") },
      terms: { feedback = NSLocalizedString("subscription_catalog_legal", comment: "") })
  }
  private var fixtureRestoration: DuckSubscriptionRestoreState {
    switch suffix {
    case "restore-running": .restoring
    case "restore-empty": .nothingFound
    case "restore-failed": .failed
    default: restoration
    }
  }
  private func restore() {
    restoration = .restoring
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1))
      restoration = .nothingFound
    }
  }
  private var statusPage: some View {
    DuckSubscriptionStatusPage(presentation: status,
      offer: status.maySubscribe ? offer : nil, purchaseActions: actions,
      action: { feedback = NSLocalizedString("subscription_catalog_status", comment: "") },
      restore: { restore() })
  }
}

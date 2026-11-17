import SwiftUI

/// Optional, host-verified expiry presentation. Absence preserves the normal hub.
/// This context does not grant access or change queue/discovery execution.
struct DuckSubscriptionBackupContext {
  let offer: (@escaping () -> Void) -> AnyView
}

private struct DuckSubscriptionBackupContextKey: EnvironmentKey {
  static let defaultValue: DuckSubscriptionBackupContext? = nil
}

extension EnvironmentValues {
  var duckSubscriptionBackup: DuckSubscriptionBackupContext? {
    get { self[DuckSubscriptionBackupContextKey.self] }
    set { self[DuckSubscriptionBackupContextKey.self] = newValue }
  }
}

/// The working page owns one access consequence and one deliberate next action.
struct DuckBackupSubscriptionCard: View {
  let open: () -> Void
  var body: some View {
    DuckStateCard(symbol: "pause.circle.fill", tone: DuckRole.secondaryText,
      title: Text("subscription_state_expired"), note: Text("subscription_expired_continuity"), trailing: {
        #if os(macOS)
        purchaseEntry
        #endif
      }, action: {
        #if os(iOS)
        purchaseEntry
        #endif
      })
      .accessibilityIdentifier("subscription.backup.expired")
  }
  private var purchaseEntry: some View {
    Button("subscription_subscribe_continue", action: open).duckPrimaryButton()
      .accessibilityIdentifier("subscription.backup.continue")
  }
}

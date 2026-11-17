import SwiftUI

/// Optional store-host content. Absence preserves the existing settings surface.
struct DuckSubscriptionSettingsContext {
  let presentation: DuckSubscriptionStatusPresentation
  let detail: AnyView
  /// Explicit native-route driver for Catalog captures; ordinary hosts leave it off.
  var openDetailInitially = false
}

private struct DuckSubscriptionSettingsContextKey: EnvironmentKey {
  static let defaultValue: DuckSubscriptionSettingsContext? = nil
}

extension EnvironmentValues {
  var duckSubscriptionSettings: DuckSubscriptionSettingsContext? {
    get { self[DuckSubscriptionSettingsContextKey.self] }
    set { self[DuckSubscriptionSettingsContextKey.self] = newValue }
  }
}

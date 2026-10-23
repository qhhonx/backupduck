import SwiftUI

/// The iPhone app's root tabs. The app and the design catalog share these
/// labels so a catalog page sits in the same tab chrome as in production.
enum IOSAppTab: Int, CaseIterable, Identifiable {
  case library = 0, backup = 1, settings = 3
  var id: Int { rawValue }
  var title: LocalizedStringKey {
    switch self {
    case .library: "nav_photos"
    case .backup: "nav_backup"
    case .settings: "nav_settings"
    }
  }
  var symbol: String {
    switch self {
    case .library: "photo.on.rectangle.angled"
    case .backup: "arrow.triangle.2.circlepath"
    case .settings: "gearshape"
    }
  }
  var label: some View { Label(title, systemImage: symbol) }

}

extension View {
  @ViewBuilder func duckLibraryTabMinimization(selected: Bool) -> some View {
    if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(selected ? .onScrollUp : .never) }
    else { self }
  }
  @ViewBuilder func duckTabSurface() -> some View {
    if #available(iOS 26.0, *) { self }
    else {
      self.toolbarBackground(DuckColors.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
  }
  @ViewBuilder func duckLibraryViewport() -> some View {
    if #available(iOS 26.0, *) { self.ignoresSafeArea(.container, edges: .bottom) }
    else { self }
  }
}

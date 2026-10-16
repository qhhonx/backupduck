import AppKit
import Photos
import SwiftUI

/// Same real permission/loading/empty states as the shared library, composed
/// with the Mac reference's 26/14pt centered empty state and reading notice.
struct MacLibraryPlaceholder: View {
  let kind: LibraryPlaceholderKind
  var requestingAccess = false
  var requestAccess: () -> Void = {}
  var clearFilter: () -> Void = {}
  @State private var settingsUnavailable = false
  var body: some View {
    ScrollView {
      switch kind {
      case .loading:
        DuckLoadingState("library_loading").padding(28)
      case .permission(let access):
        VStack(spacing: 20) {
          DuckBrandMark(size: 64)
          Text("photos_access_title").font(.system(size: 26, weight: .semibold))
          Text(LocalizedStringKey(access == .restricted ? "photos_access_restricted" : access == .denied ? "photos_access_denied_mac" : "photos_access_description"))
            .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
          if access == .denied {
            Button("photos_open_settings", action: openSettings).duckPrimaryAction()
              .accessibilityIdentifier("photos.settings")
          } else if access == .notDetermined {
            Button("photos_allow", action: requestAccess).duckPrimaryAction()
              .disabled(requestingAccess).accessibilityIdentifier("photos.request")
            if requestingAccess { ProgressView("photos_waiting_permission").accessibilityIdentifier("photos.permission_pending") }
          }
          if settingsUnavailable { DuckNotice(title: "photos_settings_unavailable", tone: .failure) }
        }.multilineTextAlignment(.center).frame(maxWidth: 440).padding(.horizontal, 24).padding(.vertical, 50)
          .frame(maxWidth: .infinity)
      case .empty(let filtered):
        VStack(spacing: 20) {
          Text(LocalizedStringKey(filtered ? "library_empty" : "library_empty_all")).font(.system(size: 26, weight: .semibold))
          Text(LocalizedStringKey(filtered ? "library_empty_filter_description" : "library_empty_description"))
            .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
          if filtered {
            Button("library_show_all", action: clearFilter).duckSecondaryAction()
              .accessibilityIdentifier("library.clear_filter")
          }
        }.multilineTextAlignment(.center).frame(maxWidth: 440).padding(.horizontal, 24).padding(.vertical, 50)
          .frame(maxWidth: .infinity)
      }
    }.accessibilityIdentifier("library.placeholder")
  }
  private func openSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"), NSWorkspace.shared.open(url) {
      settingsUnavailable = false; return
    }
    guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
      settingsUnavailable = true; return
    }
    settingsUnavailable = !NSWorkspace.shared.open(settings)
  }
}

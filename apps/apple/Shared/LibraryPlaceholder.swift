import Photos
import SwiftUI
#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum LibraryPlaceholderKind {
  case filterEmpty
  case loading
  case permission(PHAuthorizationStatus)
  case empty(filtered: Bool)
}

/// Shared first-run and empty-state content. Actions follow current permission
/// state; a denied request cannot display the system authorization dialog again.
struct LibraryPlaceholder: View {
  let kind: LibraryPlaceholderKind
  var requestingAccess = false
  var requestAccess: () -> Void = {}
  var clearFilter: () -> Void = {}
  @State private var settingsUnavailable = false

  var body: some View {
    Group {
      switch kind {
      case .loading:
        DuckLoadingState("library_loading")
      case .permission(let access):
        ContentUnavailableView {
          Label("photos_access_title", systemImage: "photo.on.rectangle.angled")
            .foregroundStyle(DuckRole.primaryText)
        } description: {
          Text(permissionDescription(access))
          if settingsUnavailable { Text("photos_settings_unavailable") }
        } actions: {
          if access == .denied {
            Button("photos_open_settings") { Task { settingsUnavailable = !(await openPhotoSettings()) } }
              .duckPrimaryButton().accessibilityIdentifier("photos.settings")
          } else if access == .notDetermined {
            Button("photos_allow", action: requestAccess).duckPrimaryButton()
              .disabled(requestingAccess).accessibilityIdentifier("photos.request")
            if requestingAccess {
              ProgressView("photos_waiting_permission").accessibilityIdentifier("photos.permission_pending")
            }
          }
        }
      case .filterEmpty:
        ContentUnavailableView {
          Label("library_filter_empty", systemImage: "line.3.horizontal.decrease.circle")
            .foregroundStyle(DuckRole.primaryText)
        } description: {
          Text("library_filter_empty_note")
        } actions: {
          Button("library_filter_show_all", action: clearFilter).duckPrimaryButton()
            .accessibilityIdentifier("library.clear_filter")
        }
      case .empty(let filtered):
        ContentUnavailableView {
          if filtered { Label("library_empty", systemImage: "line.3.horizontal.decrease.circle") }
          else {
            DuckIllustration(pose: .empty, size: 112)
            Text("library_empty_all")
          }
        } description: {
          Text(LocalizedStringKey(filtered ? "library_empty_filter_description" : "library_empty_description"))
        } actions: {
          if filtered {
            Button("library_show_all", action: clearFilter).buttonStyle(.bordered)
              .accessibilityIdentifier("library.clear_filter")
          } else { Button("retry_task", action: requestAccess).buttonStyle(.bordered) }
        }
      }
    }
    #if os(macOS)
    // Settings row geometry must not become the unavailable label's icon layout.
    .labeledContentStyle(.automatic)
    #endif
    .duckOpticalCenter()
    .accessibilityIdentifier("library.placeholder")
  }

  private func permissionDescription(_ access: PHAuthorizationStatus) -> LocalizedStringKey {
    if access == .restricted { return "photos_access_restricted" }
    if access == .denied {
      #if os(macOS)
        return "photos_access_denied_mac"
      #else
        return "photos_access_denied"
      #endif
    }
    return "photos_access_description"
  }

  @MainActor private func openPhotoSettings() async -> Bool {
    #if os(macOS)
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"),
        NSWorkspace.shared.open(url) { return true }
      guard let application = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.systempreferences") else { return false }
      return NSWorkspace.shared.open(application)
    #else
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
      return await UIApplication.shared.open(url)
    #endif
  }
}

import Photos
import SwiftUI

/// Both Apple hosts share the system unavailable-state structure.
struct MacLibraryPlaceholder: View {
  let kind: LibraryPlaceholderKind
  var requestingAccess = false
  var requestAccess: () -> Void = {}
  var clearFilter: () -> Void = {}
  var body: some View {
    LibraryPlaceholder(kind: kind, requestingAccess: requestingAccess,
      requestAccess: requestAccess, clearFilter: clearFilter)
  }
}

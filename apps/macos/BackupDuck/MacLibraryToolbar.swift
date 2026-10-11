import SwiftUI

/// One content toolbar: browsing controls yield to the selection action group.
struct MacLibraryToolbar: View {
  let total: Int
  let selected: Int
  @Binding var selecting: Bool
  @Binding var filter: LibraryFilter
  @Binding var tileSize: Double
  var canBackup: Bool
  var finish: () -> Void
  var backup: () -> Void
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(selecting ? String(format: NSLocalizedString("library_selected_count", comment: ""), selected) :
        String(format: NSLocalizedString("library_count_formatted", comment: ""), total.formatted()))
        .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).monospacedDigit()
        .accessibilityIdentifier("library.count")
      Spacer(minLength: 8)
      if selecting {
        Button("settings_done") { selecting = false; finish() }.duckSecondaryAction()
          .accessibilityIdentifier("library.selection_mode")
        Button("apple_library_backup_selected", action: backup)
          .duckPrimaryAction().disabled(!canBackup).accessibilityIdentifier("library.backup_selected")
      } else {
        Picker("media_type", selection: $filter) {
          ForEach(LibraryFilter.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
        }.labelsHidden().frame(width: 110).controlSize(.regular)
        HStack(spacing: 8) {
          Image(systemName: "square.grid.3x3").foregroundStyle(DuckColors.textSecondary)
          Slider(value: $tileSize, in: 100...260, step: 20).frame(width: 80).help("thumbnail_size")
        }.frame(height: 32).accessibilityIdentifier("library.thumbnail_size")
        Button("library_select") { selecting = true }.duckSecondaryAction()
          .accessibilityIdentifier("library.selection_mode")
      }
    }.frame(minHeight: 32)
  }
}

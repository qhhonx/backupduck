import SwiftUI

/// Shared sender guidance; storage and cloud policies belong to the receiver.
struct BackupHelp: View {
  @Environment(\.dismiss) private var dismiss
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .headline) private var titleSize = 19
  #endif
  var body: some View {
    #if os(macOS)
      VStack(spacing: 0) {
        DuckSheetHeader(title: "help_title",close: { dismiss() })
        Divider()
        helpContent
        Divider()
        HStack {
          Spacer()
          Button("settings_done") { dismiss() }.duckSecondaryAction()
            .keyboardShortcut(.cancelAction)
        }.padding(20)
      }.frame(minWidth: 480, idealWidth: 620, minHeight: 480, idealHeight: 620, maxHeight: 760)
        .background(DuckColors.canvas)
    #else
      helpContent
    #endif
  }
  private var helpContent: some View {
    #if os(iOS)
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        iosTopic("help_start_title", "help_start_body")
        iosTopic("help_scope_title", "help_scope_body")
        iosTopic("background_section", "background_explanation")
        Text("background_force_quit").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
        iosTopic("help_receipt_title", "help_receipt_body")
        iosTopic("help_recover_title", "help_recover_body")
        iosTopic("help_permission_title", "help_permission_body")
        iosTopic("help_space_title", "help_space_body")
        iosTopic("help_support_title", "help_support_body")
      }.iosPrototypePageBody()
    }.accessibilityIdentifier("settings.help.content")
    #else
    Form {
      topic("help_start_title", "help_start_body")
      #if os(macOS)
        topic("mac_nav_library", "mac_help_library")
        topic("mac_nav_sources", "mac_help_folders")
        topic("mac_all_sources", "mac_global_pause_note")
      #else
        topic("help_scope_title", "help_scope_body")
      #endif
      Section {
        #if os(iOS)
          Text("background_explanation")
          Text("background_force_quit")
        #else
          Text("mac_running_note")
        #endif
      } header: { Text("background_section") }
      #if os(macOS)
        topic("help_receipt_title", "mac_help_receipt")
      #else
        topic("help_receipt_title", "help_receipt_body")
      #endif
      topic("help_recover_title", "help_recover_body")
      #if os(macOS)
        topic("help_permission_title", "mac_help_permissions")
      #else
        topic("help_permission_title", "help_permission_body")
      #endif
      topic("help_space_title", "help_space_body")
      topic("help_support_title", "help_support_body")
    }
    .formStyle(.grouped)
    .navigationTitle("help_title")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .accessibilityIdentifier("settings.help.content")
    #endif
  }
  #if os(iOS)
  private func iosTopic(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).iosPrototypeText(size: titleSize, weight: .semibold, lineHeight: 1.4)
      Text(body).iosPrototypeText(size: bodySize, lineHeight: 1.7).foregroundStyle(DuckColors.textSecondary).textSelection(.enabled)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  #endif

  private func topic(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
    Section { Text(body).textSelection(.enabled) } header: { Text(title) }
  }
}

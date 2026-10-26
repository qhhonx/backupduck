import SwiftUI

/// Help organized by what the user wants to do and by what went wrong
/// (interaction.md I2 explanation, I8 copy), never by internal module. Each
/// topic opens a short article in the user's words.
struct HelpCenter: View {
  @State private var search = ""

  struct Topic: Identifiable, Hashable {
    let id: String
    let symbol: String
    var title: LocalizedStringKey { LocalizedStringKey("help2_" + id + "_title") }
    private var bodyKey: String {
      let key = "help2_" + id + "_body"
      #if os(macOS)
      let variant = key + "_mac"
      if NSLocalizedString(variant, comment: "") != variant { return variant }
      #endif
      return key
    }
    var body: LocalizedStringKey { LocalizedStringKey(bodyKey) }
    var searchable: String {
      NSLocalizedString("help2_\(id)_title", comment: "") + " " + NSLocalizedString(bodyKey, comment: "")
    }
  }

  static let tasks = [
    Topic(id: "confirm", symbol: "checkmark.circle"), Topic(id: "faster", symbol: "bolt"),
    Topic(id: "switch", symbol: "arrow.triangle.2.circlepath"), Topic(id: "some", symbol: "photo.on.rectangle"),
    Topic(id: "space", symbol: "externaldrive"),
  ]
  static let problems = [
    Topic(id: "offline", symbol: "wifi.exclamationmark"), Topic(id: "missing", symbol: "questionmark.circle"),
    Topic(id: "live", symbol: "livephoto"), Topic(id: "stopped", symbol: "pause.circle"),
  ]

  var body: some View {
    Group {
      #if os(macOS)
      Form { sections }.formStyle(.grouped)
      #else
      List { sections }.listStyle(.insetGrouped)
      #endif
    }
    #if os(iOS)
    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("help2_search"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    #else
    .searchable(text: $search, prompt: Text("help2_search"))
    #endif
    .navigationTitle("settings_help_center")
  }

  @ViewBuilder private var sections: some View {
    section("help2_tasks", topics: Self.tasks)
    section("help2_problems", topics: Self.problems)
  }

  @ViewBuilder private func section(_ title: LocalizedStringKey, topics: [Topic]) -> some View {
    let visible = search.isEmpty ? topics : topics.filter { $0.searchable.localizedCaseInsensitiveContains(search) }
    if !visible.isEmpty {
      Section(title) {
        ForEach(visible) { topic in
          DuckSettingsLink(title: Text(topic.title)) { HelpArticle(topic: topic) } label: {
            Label(topic.title, systemImage: topic.symbol)
          }.accessibilityIdentifier("help." + topic.id)
        }
      }
    }
  }
}

/// One help article: a title and a few short paragraphs.
struct HelpArticle: View {
  let topic: HelpCenter.Topic
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DuckSpacing.small) {
        Image(systemName: topic.symbol).font(.title).foregroundStyle(DuckRole.accent).accessibilityHidden(true)
        Text(topic.title).font(.title2.weight(.bold))
        Text(topic.body).font(.body).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: 640, alignment: .leading)
      .padding(DuckSpacing.large)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(DuckRole.background)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}

/// Contextual recovery uses the same article as Settings, with native dismissal.
struct LivePhotoHelpSheet: View {
  @Environment(\.dismiss) private var dismiss
  private let topic = HelpCenter.Topic(id: "live", symbol: "livephoto")

  var body: some View {
    #if os(iOS)
    NavigationStack {
      HelpArticle(topic: topic)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            DuckSheetConfirmButton(title: "settings_done") { dismiss() }
          }
        }
    }
    .presentationDetents([.medium, .large])
    #else
    VStack(spacing: 0) {
      HelpArticle(topic: topic)
      HStack {
        Spacer()
        Button("settings_done") { dismiss() }.duckPrimaryButton()
          .keyboardShortcut(.defaultAction)
      }.padding(DuckSpacing.large)
    }
    .frame(width: 520, height: 400)
    #endif
  }
}

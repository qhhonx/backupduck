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
    var body: LocalizedStringKey { LocalizedStringKey("help2_" + id + "_body") }
    var searchable: String {
      NSLocalizedString("help2_\(id)_title", comment: "") + " " + NSLocalizedString("help2_\(id)_body", comment: "")
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
    List {
      section("help2_tasks", topics: Self.tasks)
      section("help2_problems", topics: Self.problems)
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("help2_search"))
    #else
    .searchable(text: $search, prompt: Text("help2_search"))
    #endif
    .navigationTitle("settings_help_center")
    .navigationDestination(for: Topic.self) { HelpArticle(topic: $0) }
  }

  @ViewBuilder private func section(_ title: LocalizedStringKey, topics: [Topic]) -> some View {
    let visible = search.isEmpty ? topics : topics.filter { $0.searchable.localizedCaseInsensitiveContains(search) }
    if !visible.isEmpty {
      Section(title) {
        ForEach(visible) { topic in
          NavigationLink(value: topic) { Label(topic.title, systemImage: topic.symbol) }
            .accessibilityIdentifier("help." + topic.id)
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

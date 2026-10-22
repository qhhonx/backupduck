import SwiftUI

/// The production Lock Screen card on explicit synthetic sender facts. The
/// actual WidgetKit surface, intent dispatch and OS lifecycle are separate gates.
struct LiveActivityCatalogPage: View {
  @ObservedObject var model: BackupModel
  var stale = false
  var body: some View {
    let attributes = BackupActivityAttributes(receiver: model.pairing?.receiverID ?? "catalog",
      receiverName: model.peerDevice?.name ?? "Test Pixel", session: "catalog",
      baselinePublished: 0, initialRemaining: 100)
    let state = BackupActivityProjection.state(summary: model.summary, history: model.historicalImport,
      paused: model.paused, status: model.hubStatus, attributes: attributes, now: Date())
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DuckSpacing.large) {
          Text("Lock Screen card · synthetic data").font(.headline)
          if model.ready {
            BackupActivityCard(attributes: attributes, state: state, stale: stale)
              .allowsHitTesting(false)
              .accessibilityIdentifier("activity.lockScreenContent")
            Text("Compact content · synthetic data").font(.headline)
            HStack(spacing: DuckSpacing.small) {
              BackupActivityRing(state: state, stale: stale, compact: true)
                .frame(width: DuckSpacing.large, height: DuckSpacing.large)
              BackupActivityCompactCount(state: state, stale: stale)
            }.accessibilityIdentifier("activity.compactContent")
            Text("Minimal content · synthetic data").font(.headline)
            BackupActivityRing(state: state, stale: stale, compact: true)
              .frame(width: DuckSpacing.large, height: DuckSpacing.large)
              .accessibilityIdentifier("activity.minimalContent")
          } else { ProgressView("hub_opening") }
          Text("These are the production Lock Screen, compact and minimal contents. WidgetKit owns their containers. Preview actions are disabled. System delivery and lock-screen actions require separate acceptance.")
            .font(.footnote).foregroundStyle(.secondary)
        }.padding(DuckSpacing.medium)
      }.background(DuckRole.background).navigationTitle("Live Activity")
    }
  }
}

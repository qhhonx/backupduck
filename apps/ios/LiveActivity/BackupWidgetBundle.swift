import ActivityKit
import SwiftUI
import WidgetKit

@main struct BackupWidgetBundle: WidgetBundle {
  var body: some Widget { BackupActivityWidget() }
}
struct BackupActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BackupActivityAttributes.self) { context in
      BackupActivityCard(attributes: context.attributes, state: context.state, stale: context.isStale)
        .widgetURL(context.attributes.url)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          BackupActivityCard(attributes: context.attributes, state: context.state, stale: context.isStale)
        }
      } compactLeading: {
        BackupActivityRing(state: context.state, stale: context.isStale, compact: true)
          .frame(width: DuckSpacing.large, height: DuckSpacing.large)
      } compactTrailing: {
        BackupActivityCompactCount(state: context.state, stale: context.isStale)
      } minimal: {
        BackupActivityRing(state: context.state, stale: context.isStale, compact: true)
          .frame(width: DuckSpacing.large, height: DuckSpacing.large)
      }
      .widgetURL(context.attributes.url)
      .keylineTint(DuckRole.accent)
    }
  }
}

private enum BackupActivityPreview {
  static let attributes = BackupActivityAttributes(receiver: "synthetic-pixel", receiverName: "Test Pixel",
    session: "synthetic-batch", baselinePublished: 0, initialRemaining: 100)
  static let sending = BackupActivityAttributes.ContentState(remaining: 60, total: 100,
    phase: .sending, determinate: true, observedAt: Date(timeIntervalSince1970: 1_000))
  static let saving = BackupActivityAttributes.ContentState(remaining: 10, total: 100,
    phase: .saving, determinate: true, observedAt: Date(timeIntervalSince1970: 1_000))
  static let paused = BackupActivityAttributes.ContentState(remaining: 60, total: 100,
    phase: .paused, determinate: true, observedAt: Date(timeIntervalSince1970: 1_000))
}

#Preview("Lock Screen · synthetic", as: .content, using: BackupActivityPreview.attributes) {
  BackupActivityWidget()
} contentStates: {
  BackupActivityPreview.sending
  BackupActivityPreview.saving
  BackupActivityPreview.paused
}

#Preview("Compact · synthetic", as: .dynamicIsland(.compact), using: BackupActivityPreview.attributes) {
  BackupActivityWidget()
} contentStates: {
  BackupActivityPreview.sending
  BackupActivityPreview.saving
  BackupActivityPreview.paused
}

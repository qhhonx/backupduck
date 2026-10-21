import SwiftUI
import AppIntents
import WidgetKit

/// Shared by the real WidgetKit presentation and the synthetic native catalog.
struct BackupActivityCard: View {
  let attributes: BackupActivityAttributes
  let state: BackupActivityAttributes.ContentState
  var stale = false

  private var headline: String {
    if stale { return NSLocalizedString("activity_stale", comment: "") }
    if state.actionFailed { return NSLocalizedString("activity_action_failed", comment: "") }
    if state.phase == .saved { return NSLocalizedString(state.phase.title, comment: "") }
    return String(format: NSLocalizedString(state.phase == .finding ? "activity_known_remaining" : "activity_remaining", comment: ""), state.remaining.formatted())
  }

  private var detail: String {
    if stale || state.actionFailed { return attributes.receiverName }
    return String(format: NSLocalizedString("activity_" + state.phase.rawValue + "_receiver", comment: ""), attributes.receiverName)
  }

  var body: some View {
    HStack(alignment: .center, spacing: DuckSpacing.small) {
      BackupActivityRing(state: state, stale: stale)
        .frame(width: DuckSpacing.xxLarge, height: DuckSpacing.xxLarge)
      VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
        Text(verbatim: headline).font(.headline).monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      if stale || state.actionFailed || state.phase == .attention || state.phase == .saved || state.phase == .saving {
        Link(destination: attributes.url) {
          actionLabel("activity_open", symbol: "arrow.up.right")
        }.buttonStyle(.bordered).buttonBorderShape(.circle)
      } else {
        Button(intent: SetBackupPauseIntent(receiver: attributes.receiver, session: attributes.session, paused: state.phase != .paused)) {
          actionLabel(state.phase == .paused ? "hub_resume" : "hub_pause", symbol: state.phase == .paused ? "play.fill" : "pause.fill")
        }.buttonStyle(.bordered).buttonBorderShape(.circle)
      }
    }
    .foregroundStyle(.primary)
    .tint(DuckRole.accent)
    .padding(DuckSpacing.medium)
  }

  private func actionLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
    Label(title, systemImage: symbol).labelStyle(.iconOnly).font(.body.weight(.semibold))
  }
}

/// Known publication progress only: unknown/stale states keep the same geometry
/// with a state glyph rather than a fabricated percentage or looping spinner.
struct BackupActivityRing: View {
  let state: BackupActivityAttributes.ContentState
  var stale = false
  var compact = false
  private var strokeWidth: CGFloat { compact ? DuckSpacing.xxSmall / 2 : DuckSpacing.xxSmall }
  var body: some View {
    ZStack {
      Circle().stroke(DuckRole.separator, lineWidth: strokeWidth)
      if !stale, let progress = state.progress {
        Circle().trim(from: 0, to: progress)
          .stroke(DuckRole.accent, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      if stale || state.progress == nil || state.phase != .sending {
        Image(systemName: stale ? "clock.badge.exclamationmark" : state.phase.symbol)
          .font(.caption).foregroundStyle(stale ? .primary : state.phase == .saved ? DuckRole.saved : state.phase == .attention ? DuckRole.attention : .primary)
          .accessibilityHidden(true)
      }
    }
    .padding(strokeWidth)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(LocalizedStringKey(stale ? "activity_stale" : state.phase.title)))
    .accessibilityValue(Text(!stale ? state.progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "" : ""))
  }
}

/// Shared with the compact trailing region; the surrounding Island is system-owned.
struct BackupActivityCompactCount: View {
  let state: BackupActivityAttributes.ContentState
  var stale = false
  var body: some View {
    if stale { Image(systemName: "ellipsis").accessibilityLabel(Text("activity_stale")) }
    else {
      Text(state.remaining, format: .number).monospacedDigit()
        .accessibilityLabel(Text(String(format: NSLocalizedString("activity_remaining", comment: ""), state.remaining.formatted())))
    }
  }
}

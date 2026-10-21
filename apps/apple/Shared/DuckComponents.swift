import SwiftUI
import Photos

/// Shared settings geometry on iPhone and Mac. Descriptive rows may grow.
enum DuckPreferenceMetrics {
  #if os(iOS)
  static let rowHeight: CGFloat = 52
  #else
  static let rowHeight: CGFloat = 41
  #endif
  static let desktopControlHeight: CGFloat = 24
  static let desktopVerticalInset: CGFloat = (rowHeight - desktopControlHeight) / 2
}

/// Standalone loading feedback fills its content region. Indicators attached
/// to an action or preference control retain their own inline geometry.
struct DuckLoadingState: View {
  let title: LocalizedStringKey
  init(_ title: LocalizedStringKey) { self.title = title }
  var body: some View {
    ProgressView(title)
      .frame(maxWidth: .infinity, minHeight: DuckPreferenceMetrics.rowHeight, alignment: .center)
      .multilineTextAlignment(.center)
  }
}

/// Shared visual primitives; business state stays in the model.
struct DuckSurface<Content: View>: View {
  var contentInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
  @ViewBuilder var content: () -> Content
  var body: some View {
    content().padding(contentInsets).frame(maxWidth: .infinity, alignment: .leading)
      .background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius))
  }
}

enum DuckTone {
  case action, saved, attention, failure, neutral
  var color: Color {
    switch self {
    case .action: return DuckRole.accent
    case .saved: return DuckRole.saved
    case .attention: return DuckRole.attention
    case .failure: return DuckRole.failure
    case .neutral: return DuckRole.secondaryText
    }
  }

}

struct DuckStatusBadge: View {
  let text: String
  let symbol: String
  let tone: DuckTone
  var body: some View {
    HStack(spacing: DuckSpacing.xxSmall) {
      Image(systemName: symbol).foregroundStyle(tone.color).accessibilityHidden(true)
      Text(text).foregroundStyle(.primary)
    }.font(.caption.weight(.medium)).accessibilityElement(children: .combine)
  }
}

struct DuckBrandMark: View {
  var size: CGFloat = 64
  private var image: Image? {
    guard let url = Bundle.main.url(forResource: "DuckBrand", withExtension: "png") else { return nil }
    #if os(macOS)
      guard let value = NSImage(contentsOf: url) else { return nil }
      return Image(nsImage: value)
    #else
      guard let value = UIImage(contentsOfFile: url.path) else { return nil }
      return Image(uiImage: value)
    #endif
  }
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.3).fill(DuckColors.brandAccentBackground)
      if let image { image.resizable().scaledToFit().padding(size * 0.15) }
      else { Image(systemName: "bird.fill").font(.system(size: size * 0.5)).foregroundStyle(DuckColors.brandAccent) }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}

struct DuckBackupProgress: View {
  @ObservedObject var model: BackupModel
  var showTransfers: () -> Void
  var title: LocalizedStringKey = "apple_backup_progress"
  #if os(macOS)
    @ScaledMetric(relativeTo: .title) private var countSize: CGFloat = 48
    private var actionAlignment: HorizontalAlignment { .trailing }
    private var trackHeight: CGFloat { 6 }
    private var showsTrack: Bool { model.summary.total > 0 }
  #else
    @ScaledMetric(relativeTo: .headline) private var sectionSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 13
    @ScaledMetric(relativeTo: .title) private var countSize: CGFloat = 42
    private var actionAlignment: HorizontalAlignment { .leading }
    private var trackHeight: CGFloat { 3 }
    private var showsTrack: Bool { model.summary.total > 0 && model.summary.running > 0 && !model.paused }
  #endif
  @ViewBuilder private var progressTitle: some View {
    #if os(iOS)
    Text(title).font(.headline.weight(.semibold))
    #else
    Text(title).font(.headline)
    #endif
  }
  private var statusActionTitle: LocalizedStringKey? {
    nil
  }
  private var fraction: Double {
    model.summary.total > 0 ? Double(model.summary.published) / Double(model.summary.total) : 0
  }
  var body: some View {
    #if os(macOS)
      macProgress
    #else
    VStack(alignment: .leading, spacing: 12) {
      iosProgressHeader
      DuckSurface {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(model.summary.published.formatted()).font(.largeTitle.weight(.semibold)).monospacedDigit()
          Text(String(format: NSLocalizedString("design_saved_of", comment: ""), model.summary.total))
            #if os(iOS)
              .font(.footnote)
            #else
              .font(.callout)
            #endif
            .foregroundStyle(DuckColors.textSecondary)
        }
        if showsTrack {
          DuckProgressTrack(fraction: fraction, height: trackHeight).accessibilityLabel(Text("state_published"))
        }
        HStack {
          Text(String(format: NSLocalizedString("design_in_progress", comment: ""),
            model.summary.count(for: "active"),
            model.summary.failed + model.summary.publication_failed))
            #if os(iOS)
              .font(.body)
            #else
              .font(.caption)
            #endif
            .foregroundStyle(DuckColors.textSecondary)
          Spacer(minLength: 0)
        }
        DuckActions(alignment: actionAlignment) {
          Button {
            guard !model.changingPause else { return }
            Task { await model.setPaused(!model.paused) }
          } label: {
            Label(LocalizedStringKey(model.paused ? "resume_backup" : "pause_backup"), systemImage: model.paused ? "play" : "pause")
              #if os(iOS)
                .frame(maxWidth: .infinity)
              #endif
          }
          #if os(iOS)
            .iosPrototypeAction(primary: true)
          #else
            .duckPrimaryAction()
          #endif
          .disabled(!model.ready || model.pairing == nil || model.changingPause)
          Button(action: showTransfers) {
            Text("transfer_tasks")
              #if os(iOS)
                .frame(maxWidth: .infinity)
              #endif
          }
          #if os(iOS)
            .iosPrototypeAction()
          #else
            .duckSecondaryAction()
          #endif
            .accessibilityIdentifier("backup.all_tasks")
        }

        if let error = model.pauseError {
          DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
            .accessibilityIdentifier("backup.pause_error")
        }
      }
      }
    }
    #endif
  }
  #if os(iOS)
  private var iosProgressHeader: some View {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline) {
            progressTitle.fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            BackupStatusIndicator(model: model, actionTitle: statusActionTitle)
          }
          VStack(alignment: .leading, spacing: 8) {
            progressTitle
            BackupStatusIndicator(model: model, actionTitle: statusActionTitle)
          }
        }
  }
  #endif
  #if os(macOS)
  private var macPhase: LocalizedStringKey { LocalizedStringKey(backupAggregateStatus(model).key) }
  private var macProgress: some View {
    DuckSurface {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center) {
          Text(title).font(.headline.weight(.semibold))
          Spacer()
          BackupStatusIndicator(model: model, compactMac: true, actionTitle: macPhase)
        }.frame(minHeight: 24).padding(.bottom, 12)
        VStack(alignment: .leading, spacing: 10) {
          Text(model.summary.published.formatted()).font(.largeTitle.weight(.semibold)).monospacedDigit()
          Text(String(format: NSLocalizedString("design_saved_of", comment: ""), model.summary.total))
            .font(.body).foregroundStyle(DuckColors.textSecondary)
        }.padding(.top, 20).padding(.bottom, 8)
        if showsTrack { DuckProgressTrack(fraction: fraction, height: 6).padding(.vertical, 20) }
        Text(String(format: NSLocalizedString("design_in_progress", comment: ""),
          model.summary.count(for: "active"),
          model.summary.failed + model.summary.publication_failed))
          .font(.body).foregroundStyle(DuckColors.textSecondary).frame(minHeight: 23, alignment: .leading)
        DuckActions(alignment: .trailing) {
          Button { Task { await model.setPaused(!model.paused) } } label: {
            Label(LocalizedStringKey(model.paused ? "resume_backup" : "pause_backup"), systemImage: model.paused ? "play" : "pause")
          }.duckPrimaryAction().disabled(!model.ready || model.pairing == nil || model.changingPause)
          Button("nav_transfers", action: showTransfers).duckSecondaryAction()
        }.padding(.top, 16)

        if let error = model.pauseError {
          DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
            .accessibilityIdentifier("backup.pause_error").padding(.top, 12)
        }
      }
    }
  }
  #endif

}

struct DuckLibrarySource: View {
  @ObservedObject var model: BackupModel
  var compactMac = false
  @Environment(\.dynamicTypeSize) private var textSize
  private var enabled: Binding<Bool> {
    Binding(get: { model.autoBackup }, set: { value in Task { await model.setAutoBackup(value) } })
  }
  private var source: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("source_system_library").font(.headline)
        Text("design_source_media").font(.caption).foregroundStyle(DuckColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      controls
        .disabled(!model.ready || model.changingAutoBackup || model.pairing == nil)

      if let error = model.autoBackupError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .accessibilityIdentifier("backup.source_auto_error")
      }
    }.accessibilityIdentifier("backup.source_library")
  }
  private var controls: some View {
    Group {
      #if os(macOS)
      if compactMac {
        MacPreferenceRow(title: "auto_backup_new", note: "mac_fidelity_help_new_boundary") {
          Toggle("auto_backup_new", isOn: enabled).labelsHidden().toggleStyle(.switch)
        }
      } else { standardControls }
      #else
      standardControls
      #endif
    }
  }
  private var standardControls: some View {
    Group {
      if textSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 16) {
          source
          Toggle("auto_backup_new", isOn: enabled)
        }
      } else {
        HStack(spacing: 12) {
          source
          Spacer(minLength: 8)
          VStack(alignment: .trailing, spacing: 4) {
            Text("auto_backup_new").font(.caption).foregroundStyle(DuckColors.textSecondary)
            Toggle("auto_backup_new", isOn: enabled).labelsHidden()
          }
        }
      }
    }
  }
}

struct DuckRecentTransfers: View {
  @ObservedObject var model: BackupModel
  @StateObject private var browser = TaskBrowserModel()
  var showTransfers: () -> Void
  #if os(iOS)
  @ScaledMetric(relativeTo: .headline) private var sectionSize = 19
  #endif
  var body: some View {
    #if os(macOS)
    MacContentSection(title: "design_recent_transfers", actionTitle: "apple_view_all",
      actionIdentifier: "backup.all_tasks", action: showTransfers) {
      entries
    }.task(id: "\(model.queueRevision)|\(model.pairing?.receiverID ?? "")") { await refresh() }
    #else
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("design_recent_transfers")
          #if os(iOS)
          .font(.headline.weight(.semibold))
          #else
          .font(.headline)
          #endif
        Spacer()
        Button(action: showTransfers) {
          HStack(spacing: 4) { Text("apple_view_all"); Image(systemName: "chevron.right").font(.caption) }
        }.buttonStyle(.plain).foregroundStyle(DuckColors.action).font(.callout).accessibilityIdentifier("backup.all_tasks")
      }
      entries
    }.task(id: "\(model.queueRevision)|\(model.pairing?.receiverID ?? "")") { await refresh() }
    #endif
  }
  @ViewBuilder private var entries: some View {
      if browser.failed {
        Text("tasks_load_failed").foregroundStyle(DuckColors.failure)
        Button("retry_task") { Task { await refresh() } }
      } else if browser.loading && browser.items.isEmpty {
        ProgressView().frame(maxWidth: .infinity)
      } else if browser.items.isEmpty {
        Text("tasks_empty").font(.callout).foregroundStyle(DuckColors.textSecondary)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(browser.items.prefix(3).enumerated()), id: \.element.id) { index, item in
            BackupTaskRow(item: item, model: model, topInset: index == 0 ? 0 : 12)
            Divider()
          }
        }
      }
  }
  private func refresh() async {
    await browser.refresh(filter: "all", receiver: model.pairing?.receiverID, descending: true, sort: "added")
  }
}

/// Short actions share a single layout contract; do not squeeze large text.
struct DuckActions<Content: View>: View {
  var alignment: HorizontalAlignment = .leading
  @ViewBuilder var content: () -> Content
  @Environment(\.dynamicTypeSize) private var textSize
  var body: some View {
    Group {
      if textSize.isAccessibilitySize {
        VStack(alignment: alignment, spacing: 12, content: content)
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .center, spacing: 12, content: content)
          VStack(alignment: alignment, spacing: 12, content: content)
        }
      }
    }
    // Preserve intrinsic button widths on desktop while matching the authored
    // action edge. iOS labels explicitly expand to the available row width.
    .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
  }
}
private struct DuckSheetActionsKey: EnvironmentKey {
  static let defaultValue = false
}
extension EnvironmentValues {
  var duckSheetActions: Bool {
    get { self[DuckSheetActionsKey.self] }
    set { self[DuckSheetActionsKey.self] = newValue }
  }
}

extension View {
  func duckAction() -> some View { controlSize(.regular).tint(DuckRole.accent) }
  func duckPrimaryAction() -> some View { modifier(DuckNativeAction(primary: true)) }
  func duckSecondaryAction() -> some View { modifier(DuckNativeAction(primary: false)) }
}

private struct DuckNativeAction: ViewModifier {
  var primary: Bool
  @Environment(\.duckSheetActions) private var sheet
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
    if sheet { content.buttonStyle(.automatic) }
    else if primary { content.buttonStyle(.borderedProminent).controlSize(.large).tint(DuckRole.accent) }
    else { content.buttonStyle(.bordered).controlSize(.small).tint(DuckRole.accent) }
    #else
    if primary && sheet {
      content.buttonStyle(.borderedProminent).controlSize(.regular).keyboardShortcut(.defaultAction)
    } else if primary {
      content.buttonStyle(.borderedProminent).controlSize(.regular)
    } else {
      content.buttonStyle(.bordered).controlSize(sheet ? .regular : .small)
    }
    #endif
  }
}

#if os(macOS)
/// Compatibility for callers: AppKit owns drawing, focus and pressed states.
struct DuckDesktopActionStyle: PrimitiveButtonStyle {
  var prominent = false
  func makeBody(configuration: Configuration) -> some View {
    Button(configuration).modifier(DuckNativeAction(primary: prominent))
  }
}
#endif

/// Explanations and failures remain in the window where the action happened.
struct DuckNotice: View {
  let title: LocalizedStringKey
  var message: LocalizedStringKey? = nil
  var tone: DuckTone = .neutral
  var symbol: String = "info.circle"
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: DuckSpacing.xSmall) {
      Image(systemName: symbol).font(.body).foregroundStyle(tone.color).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
        Text(title).font(.body).foregroundStyle(.primary)
        if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
      }.fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
  }
}

/// Standalone header uses the system navigation bar on iOS; Mac titles are content.
struct DuckSheetHeader: View {
  let title: LocalizedStringKey
  var busy = false
  var back: (() -> Void)? = nil
  var titleIdentifier = "sheet.title"
  var closeIdentifier = "sheet.close"
  var close: () -> Void
  var body: some View {
    #if os(iOS)
    Color.clear.frame(height: 0)
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          DuckSheetDismissButton(action: close).disabled(busy).accessibilityIdentifier(closeIdentifier)
        }
      }
    #else
    Text(title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading).padding(DuckSpacing.large)
      .accessibilityIdentifier(titleIdentifier)
    #endif
  }
}

#if os(iOS)
struct DuckSheetDismissButton: View {
  var title: LocalizedStringKey = "cancel"
  var action: () -> Void
  var body: some View {
    if #available(iOS 26.0, *) {
      Button(role: .close, action: action)
    } else {
      Button(title, action: action)
    }
  }
}
struct DuckSheetConfirmButton: View {
  let title: LocalizedStringKey
  var action: () -> Void
  var body: some View {
    if #available(iOS 26.0, *) {
      Button(role: .confirm, action: action)
        .accessibilityLabel(Text(title))
    } else {
      Button("settings_done", action: action).accessibilityLabel(Text(title))
    }
  }
}
#endif

/// Sheet actions fill their phone column; desktop actions keep intrinsic width.
struct DuckSheetAction: View {
  let title: LocalizedStringKey
  var primary = true
  var action: () -> Void
  var body: some View {
    #if os(iOS)
    if primary { DuckSheetConfirmButton(title: title, action: action) }
    else { Button(title, action: action) }
    #else
    if primary { Button(title,action: action).duckPrimaryAction() }
    else { Button(title,action: action).duckSecondaryAction() }
    #endif
  }
}

/// A0/A4: the system owns the sheet frame and controls on both platforms.
struct DuckSheetLayout<Content: View, Actions: View>: View {
  let title: LocalizedStringKey
  var busy = false
  var error: String? = nil
  var desktopWidth: CGFloat = 560
  var desktopMinHeight: CGFloat = 360
  var desktopIdealHeight: CGFloat = 560
  var back: (() -> Void)? = nil
  var expandable = true
  var closeOnly = false
  var form = false
  var cancel: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content
  @ViewBuilder var actions: () -> Actions
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var textSize
  #if os(iOS)
  @State private var measuredHeights: [String: CGFloat] = [:]
  private var fittedHeight: CGFloat {
    guard let body = measuredHeights["body"] else { return 560 }
    return min(max(220, body + 76), UIScreen.main.bounds.height * 0.85)
  }
  #endif
  private var sheetContent: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.medium) {
      if let error {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .textSelection(.enabled).accessibilityIdentifier("sheet.error")
      }
      content()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  var body: some View {
    #if os(iOS)
    NavigationStack {
      ScrollView { sheetContent.padding(DuckSpacing.medium).duckSheetMeasure("body") }
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: closeOnly ? .confirmationAction : .cancellationAction) {
          DuckSheetDismissButton(title: closeOnly ? "settings_done" : "cancel", action: { (cancel ?? { dismiss() })() })
            .disabled(busy).accessibilityIdentifier("sheet.close")
        }
        ToolbarItemGroup(placement: .navigation) {
          if let back { Button("mac_fidelity_back", action: back) }
        }
        ToolbarItemGroup(placement: .confirmationAction) {
          actions().environment(\.duckSheetActions, true)
        }
      }
    }
    .interactiveDismissDisabled(busy)
    .presentationDetents(textSize.isAccessibilitySize ? [.large] : expandable ? [.height(fittedHeight), .large] : [.height(fittedHeight)])
    .iosPrototypeSheetHost()
    .onPreferenceChange(DuckSheetHeightPreference.self) { measuredHeights = $0 }
    #else
    VStack(alignment: .leading, spacing: DuckSpacing.medium) {
      HStack {
        if let back { Button("mac_fidelity_back", action: back).buttonStyle(.bordered) }
        Text(title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("sheet.title")
      }
      if form {
        Form {
          if let error { DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle") }
          content()
        }.formStyle(.grouped)
      } else { ScrollView { sheetContent } }
      HStack {
        Spacer(minLength: 0)
        if let cancel {
          Button("cancel", action: cancel).buttonStyle(.bordered).keyboardShortcut(.cancelAction).disabled(busy)
        }
        actions().environment(\.duckSheetActions, true)
      }.controlSize(.regular)
    }.padding(DuckSpacing.large)
      .frame(width: desktopWidth)
      .frame(minHeight: desktopMinHeight, idealHeight: desktopIdealHeight, maxHeight: 760)
      .interactiveDismissDisabled(busy)
    #endif
  }
}

struct DuckSelectedBackup: View {
  let count: Int
  @Binding var rebackup: Bool
  var failureMessage: () -> String? = { nil }
  var confirm: () async -> Bool
  @State private var busy = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  #endif
  var body: some View {
    DuckSheetLayout(title: "backup_selected_confirm_title", busy: busy, error: error, desktopMinHeight: 360, desktopIdealHeight: 420, cancel: { dismiss() }) {
      #if os(iOS)
      Text(String(format: NSLocalizedString("apple_selected_items", comment: ""), count)).font(.body)
      Toggle(isOn: $rebackup) {
        VStack(alignment: .leading, spacing: 5) {
          Text("backup_selected_rebackup_received").font(.body.weight(.semibold))
        }
      }.toggleStyle(.switch).disabled(busy).accessibilityIdentifier("selection.force_resend")
      #else
      Text(String(format: NSLocalizedString("apple_selected_items", comment: ""), count)).font(.headline.weight(.semibold))
      HStack(alignment: .center, spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          Text("backup_selected_rebackup_received").font(.body.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
        Toggle("backup_selected_rebackup_received", isOn: $rebackup).labelsHidden().toggleStyle(.checkbox)
          .disabled(busy).accessibilityIdentifier("selection.force_resend")
      }.padding(.vertical, 14)
      #endif
      Text(LocalizedStringKey(rebackup ? "backup_selected_rebackup_note" : "backup_selected_confirm_note"))
        #if os(iOS)
        .font(.footnote)
        #else
        .font(.caption)
        #endif
        .foregroundStyle(DuckColors.textSecondary).fixedSize(horizontal: false, vertical: true)
      if busy {
        ProgressView("apple_selected_submitting")
          .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
          .accessibilityIdentifier("selection.preparing")
      }
    } actions: {
      #if os(iOS)
      DuckSheetConfirmButton(title: "backup_selected_confirm_action", action: submit).disabled(count == 0 || busy)
        .accessibilityIdentifier("selection.confirm")
      #else
      Button("backup_selected_confirm_action", action: submit)
        .duckPrimaryAction().disabled(count == 0 || busy)
        .accessibilityIdentifier("selection.confirm")
      #endif
    }
  }
  private func submit() {
    guard !busy else { return }
    busy = true
    error = nil
    Task { @MainActor in
      let accepted = await confirm()
      busy = false
      if accepted { dismiss() }
      else { error = failureMessage() ?? NSLocalizedString("apple_selected_backup_failed", comment: "") }
    }
  }
}

struct DuckPairingSteps: View {
  var desktop = false
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var titleSize = 16
  @ScaledMetric(relativeTo: .callout) private var detailSize = 14
  #endif
  private var stepSpacing: CGFloat {
    #if os(iOS)
    18
    #else
    16
    #endif
  }
  var body: some View {
    VStack(alignment: .leading, spacing: stepSpacing) {
      step(1, "apple_pair_step_open", "apple_pair_step_open_note")
      step(2, "apple_pair_step_scan", desktop ? "desktop_pair_instructions" : "receiver_pair_instructions")
    }
  }
  private func step(_ number: Int, _ title: LocalizedStringKey, _ note: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(number.formatted())
        #if os(iOS)
          .font(.body.weight(.semibold))
        #else
          .font(.callout.weight(.semibold))
        #endif
        .monospacedDigit()
        .frame(width: 28, height: 28).background(DuckColors.actionBackground, in: Circle())
        .foregroundStyle(DuckColors.action)
      VStack(alignment: .leading, spacing: 6) {
        #if os(iOS)
        Text(title).font(.title2.weight(.semibold))
        Text(note).font(.subheadline).foregroundStyle(DuckColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        #else
        Text(title).font(.headline)
        Text(note).font(.callout).foregroundStyle(DuckColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        #endif
      }
    }
  }
}

/// Compact identity summary. Detailed physical readings use the optional
/// paired device-status endpoint; never infer them from transfer receipts.
struct DuckReceiverSummary: View {
  @ObservedObject var model: BackupModel
  #if os(iOS)
  @ScaledMetric(relativeTo: .headline) private var titleSize = 19
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  #endif
  var body: some View {
    #if os(iOS)
    DuckSurface {
      VStack(alignment: .leading, spacing: 16) {
        Text(model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: "")).font(.title2.weight(.semibold))
        Text("receiver_address").font(.footnote).foregroundStyle(DuckColors.textSecondary)
        if let pairing = model.pairing { Text(pairing.endpoint).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
      }
    }
    #else
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "externaldrive.badge.wifi").font(.title2).foregroundStyle(DuckColors.action)
          .frame(width: 44, height: 44).background(DuckColors.actionBackground, in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 6) {
          Text(model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: "")).font(.headline)
          ReceiverStatusIndicator(model: model)
        }
      }
      if let pairing = model.pairing {
        VStack(alignment: .leading, spacing: 6) {
          Text("receiver_address").font(.caption).foregroundStyle(DuckColors.textSecondary)
          Text(pairing.endpoint).font(.callout.monospaced()).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    #endif
  }
}


/// Display-only progress with verified counts, independent of the system accent
/// preference. It does not animate missing progress or occupy extra task rows.
struct DuckProgressTrack: View {
  let fraction: Double
  var height: CGFloat = 4
  private var value: Double { fraction.isFinite ? min(1, max(0, fraction)) : 0 }
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(DuckColors.subtle)
        Capsule().fill(DuckColors.action).frame(width: geometry.size.width * value)
      }
    }.frame(height: height)
      .accessibilityElement(children: .ignore)
      .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
  }
}


/// Read-only source detail. Showing a source photo never implies it reached
/// Pixel or Google Photos, and never changes selection or queues a backup.
struct DuckPhotoDetail: View {
  let asset: PHAsset
  @Environment(\.dismiss) private var dismiss
  @StateObject private var preview: MediaPreviewModel
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  init(asset: PHAsset) { self.asset = asset; _preview = StateObject(wrappedValue: MediaPreviewModel(asset: asset)) }
  var body: some View {
    DuckSheetLayout(title: "apple_photo_detail", closeOnly: true) {
      if let image = preview.image {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 300)
        #else
        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300)
        #endif
      } else if preview.failure { DuckNotice(title: "apple_photo_preview_unavailable", tone: .attention, symbol: "photo") }
      else if preview.loading { DuckLoadingState("library_loading") }
      PhotoMetadataPanel(preview: preview)
      DuckNotice(title: "apple_photo_source_note", symbol: "cloud")
    } actions: {
      #if os(macOS)
      DuckSheetAction(title: "settings_done") { dismiss() }
      #endif
    }
      .task(id: asset.localIdentifier) { preview.load(asset); preview.loadMetadata() }
      .onChange(of: policy.choice) { _, _ in preview.load(); preview.loadMetadata() }
      .onDisappear { preview.cancel() }
  }
}

#if os(iOS)
private struct DuckSheetHeightPreference: PreferenceKey {
  static let defaultValue: [String: CGFloat] = [:]
  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
private extension View {
  func duckSheetMeasure(_ section: String) -> some View {
    background(GeometryReader { proxy in Color.clear.preference(key: DuckSheetHeightPreference.self, value: [section: proxy.size.height]) })
  }
}
#endif

/// Selection changes the mark, never the identity or opacity of a form row.
struct DuckChoiceButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { configuration.label }
}

#if os(iOS)
/// Shared image-choice treatment for gallery, album covers and selected review.
@MainActor enum DuckMediaSelection {
  static let size: CGFloat = 23
  static let inset: CGFloat = 6
  static let selectedOpacity: CGFloat = 0.72
  private static let checkmark = UIImage(systemName: "checkmark.circle.fill")
  private static let tint = UIColor(DuckColors.action)
  static func configure(_ badge: UIImageView) {
    badge.image = checkmark
    badge.tintColor = tint
    badge.backgroundColor = .white
    badge.layer.cornerRadius = size/2
    badge.clipsToBounds = true
    badge.contentMode = .scaleAspectFit
    badge.isAccessibilityElement = false
  }
  static func frame(in bounds: CGRect) -> CGRect {
    CGRect(x: bounds.maxX-inset-size,y: bounds.maxY-inset-size,width: size,height: size)
  }
  static func apply(_ selected: Bool, enabled: Bool, badge: UIImageView, image: UIImageView) {
    configure(badge)
    badge.isHidden = !enabled || !selected
    image.alpha = selected && enabled ? selectedOpacity : 1
  }
}
#endif

import SwiftUI
import Photos

/// Shared settings geometry on iPhone and Mac. Descriptive rows may grow.
enum DuckPreferenceMetrics {
  #if os(iOS)
  static let rowHeight: CGFloat = 52
  #else
  static let rowHeight: CGFloat = 48
  #endif
  static let desktopControlHeight: CGFloat = 24
  static let desktopVerticalInset: CGFloat = (rowHeight - desktopControlHeight) / 2
}

/// Shared visual primitives; business state stays in the model.
struct DuckSurface<Content: View>: View {
  var contentInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
  @ViewBuilder var content: () -> Content
  var body: some View {
    content().padding(contentInsets).frame(maxWidth: .infinity, alignment: .leading)
      .background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay { RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border, lineWidth: 1) }
  }
}

enum DuckTone {
  case action, saved, attention, failure, neutral
  var color: Color {
    switch self {
    case .action: return DuckColors.action
    case .saved: return DuckColors.saved
    case .attention: return DuckColors.attention
    case .failure: return DuckColors.failure
    case .neutral: return DuckColors.textSecondary
    }
  }
  var background: Color {
    switch self {
    case .action: return DuckColors.actionBackground
    case .saved: return DuckColors.savedBackground
    case .attention: return DuckColors.attentionBackground
    case .failure: return DuckColors.failureBackground
    case .neutral: return DuckColors.subtle
    }
  }
}

struct DuckStatusBadge: View {
  let text: String
  let symbol: String
  let tone: DuckTone
  var body: some View {
    Label(text, systemImage: symbol).font(.caption.weight(.medium))
      .foregroundStyle(tone.color).padding(.horizontal, 8).padding(.vertical, 5)
      .background(tone.background, in: RoundedRectangle(cornerRadius: 7))
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
    Text(title).iosPrototypeText(size: sectionSize, weight: .semibold, lineHeight: 1.4)
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
          Text(model.summary.published.formatted()).font(.system(size: countSize, weight: .semibold)).monospacedDigit()
          Text(String(format: NSLocalizedString("design_saved_of", comment: ""), model.summary.total))
            #if os(iOS)
              .iosPrototypeText(size: captionSize, lineHeight: 1.6)
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
              .iosPrototypeText(size: bodySize)
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
          Text(title).font(.system(size: 16, weight: .semibold))
          Spacer()
          BackupStatusIndicator(model: model, compactMac: true, actionTitle: macPhase)
        }.frame(minHeight: 24).padding(.bottom, 12)
        VStack(alignment: .leading, spacing: 10) {
          Text(model.summary.published.formatted()).font(.system(size: countSize, weight: .semibold)).monospacedDigit()
          Text(String(format: NSLocalizedString("design_saved_of", comment: ""), model.summary.total))
            .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
        }.padding(.top, 20).padding(.bottom, 8)
        if showsTrack { DuckProgressTrack(fraction: fraction, height: 6).padding(.vertical, 20) }
        Text(String(format: NSLocalizedString("design_in_progress", comment: ""),
          model.summary.count(for: "active"),
          model.summary.failed + model.summary.publication_failed))
          .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).frame(minHeight: 23, alignment: .leading)
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
          .iosPrototypeText(size: sectionSize, weight: .semibold, lineHeight: 1.4)
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
extension View {
  func duckAction() -> some View {
    #if os(iOS)
      return self.controlSize(.large).tint(DuckColors.action).frame(minHeight: 44)
    #else
      return self.controlSize(.regular).font(.system(size: 14)).tint(DuckColors.action).frame(minHeight: 32)
    #endif
  }
}

#if os(macOS)
struct DuckDesktopActionStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 14, weight: .medium))
      .padding(.horizontal, 14).frame(minHeight: 32)
      .foregroundStyle(prominent ? Color.white : DuckColors.action)
      .background(prominent ? DuckColors.action : DuckColors.subtle, in: RoundedRectangle(cornerRadius: 8))
      .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: 8))
  }
}
#endif
extension View {
  func duckPrimaryAction() -> some View {
    #if os(macOS)
    self.buttonStyle(DuckDesktopActionStyle(prominent: true)).duckAction()
    #else
    self.buttonStyle(.borderedProminent).duckAction()
    #endif
  }
  func duckSecondaryAction() -> some View {
    #if os(macOS)
    self.buttonStyle(DuckDesktopActionStyle()).duckAction()
    #else
    self.buttonStyle(.bordered).duckAction()
    #endif
  }
}

/// Explanations and failures remain in the window where the action happened.
struct DuckNotice: View {
  let title: LocalizedStringKey
  var message: LocalizedStringKey? = nil
  var tone: DuckTone = .neutral
  var symbol: String = "info.circle"
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var titleSize = 16
  @ScaledMetric(relativeTo: .callout) private var messageSize = 14
  #endif
  var body: some View {
    HStack(alignment: noticeAlignment, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(tone.color)
        #if os(macOS)
          .font(.system(size: 16)).frame(width: 18)
        #else
          .font(.system(size: titleSize, weight: .regular)).frame(width: titleSize)
        #endif
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        #if os(iOS)
        Text(title).iosPrototypeText(size: titleSize, weight: .semibold, lineHeight: 1.6)
        if let message { Text(message).iosPrototypeText(size: messageSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary) }
        #else
        Text(title).font(.system(size: 14))
        if let message { Text(message).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary) }
        #endif
      }.fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(noticeInset)
      .background(tone.background, in: RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .combine)
  }
  private var noticeAlignment: VerticalAlignment {
    #if os(iOS)
    .firstTextBaseline
    #else
    .firstTextBaseline
    #endif
  }
  private var noticeInset: CGFloat {
    #if os(macOS)
    12
    #else
    14
    #endif
  }
}

/// Native sheet contract: stable header, scrollable content, fixed action region.
/// Uses system presentation/material rather than embedding a web prototype.
struct DuckSheetLayout<Content: View, Actions: View>: View {
  let title: LocalizedStringKey
  var busy = false
  var error: String? = nil
  var desktopWidth: CGFloat = 560
  var desktopMinHeight: CGFloat = 360
  var desktopIdealHeight: CGFloat = 560
  @ViewBuilder var content: () -> Content
  @ViewBuilder var actions: () -> Actions
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var textSize
  #if os(iOS)
  @ScaledMetric(relativeTo: .title2) private var titleSize = 22
  @State private var measuredHeights: [String: CGFloat] = [:]
  @State private var selectedDetent: PresentationDetent = .height(560)
  private var fittedHeight: CGFloat {
    guard measuredHeights["body"] != nil else { return 560 }
    return min(max(220, measuredHeights.values.reduce(0, +) + 12), UIScreen.main.bounds.height * 0.92 - 34)
  }
  #endif
  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: headerAlignment, spacing: 12) {
        #if os(iOS)
        Text(title).iosPrototypeText(size: titleSize, weight: .bold, lineHeight: 1.3).fixedSize(horizontal: false, vertical: true)
        #else
        Text(title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        #endif
        Spacer(minLength: 8)
        Button { dismiss() } label: {
          Image(systemName: "xmark")
            #if os(iOS)
              .font(.system(size: 22)).foregroundStyle(DuckColors.action)
            #endif
            .frame(width: closeSize, height: closeSize).contentShape(Rectangle())
        }.buttonStyle(.plain).duckAction().accessibilityLabel(Text("close"))
          .disabled(busy)
      }.padding(20)
      #if os(iOS)
        .duckSheetMeasure("header")
      #endif
      Divider()
      if let error {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .textSelection(.enabled).padding(.horizontal, 20).padding(.top, 12)
          .accessibilityIdentifier("sheet.error")
          #if os(iOS)
            .duckSheetMeasure("error")
          #endif
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        #if os(iOS)
          .duckSheetMeasure("body")
        #endif
      }
      Divider()
      DuckActions(alignment: footerAlignment, content: actions).frame(maxWidth: .infinity, alignment: .trailing).padding(20)
      #if os(iOS)
        .duckSheetMeasure("actions")
      #endif
    }.background(DuckColors.surface).tint(DuckColors.action)
      #if os(iOS)
        .foregroundStyle(DuckColors.text)
      #endif
      .interactiveDismissDisabled(busy)
      #if os(macOS)
        .background(MacSheetInitialFocus().frame(width: 0, height: 0))
        .frame(width: desktopWidth)
        .frame(minHeight: desktopMinHeight, idealHeight: desktopIdealHeight, maxHeight: 760)
      #else
        .presentationDetents(textSize.isAccessibilitySize ? [.large] : [.height(fittedHeight), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20).iosPrototypeSheetHost()
        .onPreferenceChange(DuckSheetHeightPreference.self) { values in
          measuredHeights = values
          selectedDetent = textSize.isAccessibilitySize ? .large : .height(fittedHeight)
        }
      #endif
  }
  private var headerAlignment: VerticalAlignment {
    #if os(iOS)
    .top
    #else
    .center
    #endif
  }
  private var closeSize: CGFloat {
    #if os(iOS)
    44
    #else
    32
    #endif
  }
  private var footerAlignment: HorizontalAlignment {
    #if os(macOS)
    .trailing
    #else
    .leading
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
    DuckSheetLayout(title: "backup_selected_confirm_title", busy: busy, error: error, desktopMinHeight: 360, desktopIdealHeight: 420) {
      #if os(iOS)
      Text(String(format: NSLocalizedString("apple_selected_items", comment: ""), count)).iosPrototypeText(size: bodySize)
      Toggle(isOn: $rebackup) {
        VStack(alignment: .leading, spacing: 5) {
          Text("backup_selected_rebackup_received").iosPrototypeText(size: bodySize, weight: .semibold)
        }
      }.toggleStyle(IOSCheckboxToggleStyle()).disabled(busy).accessibilityIdentifier("selection.force_resend")
      #else
      Text(String(format: NSLocalizedString("apple_selected_items", comment: ""), count)).font(.system(size: 16, weight: .semibold))
      HStack(alignment: .center, spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          Text("backup_selected_rebackup_received").font(.system(size: 14, weight: .semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
        Toggle("backup_selected_rebackup_received", isOn: $rebackup).labelsHidden().toggleStyle(.checkbox)
          .disabled(busy).accessibilityIdentifier("selection.force_resend")
      }.padding(.vertical, 14)
      #endif
      Text(LocalizedStringKey(rebackup ? "backup_selected_rebackup_note" : "backup_selected_confirm_note"))
        #if os(iOS)
        .iosPrototypeText(size: captionSize, lineHeight: 1.6)
        #else
        .font(.system(size: 12))
        #endif
        .foregroundStyle(DuckColors.textSecondary).fixedSize(horizontal: false, vertical: true)
      if busy {
        ProgressView("apple_selected_submitting")
          .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
          .accessibilityIdentifier("selection.preparing")
      }
    } actions: {
      #if os(iOS)
      Button { dismiss() } label: { Text("cancel").frame(maxWidth: .infinity) }
        .iosPrototypeAction().disabled(busy).keyboardShortcut(.cancelAction)
      Button(action: submit) { Text("backup_selected_confirm_action").frame(maxWidth: .infinity) }
        .iosPrototypeAction(primary: true).disabled(count == 0 || busy)
        .accessibilityIdentifier("selection.confirm")
      #else
      Button("cancel") { dismiss() }.duckSecondaryAction()
        .disabled(busy).keyboardShortcut(.cancelAction)
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
          .font(.system(size: 14, weight: .semibold))
        #else
          .font(.callout.weight(.semibold))
        #endif
        .monospacedDigit()
        .frame(width: 28, height: 28).background(DuckColors.actionBackground, in: Circle())
        .foregroundStyle(DuckColors.action)
      VStack(alignment: .leading, spacing: 6) {
        #if os(iOS)
        Text(title).iosPrototypeText(size: titleSize, weight: .semibold)
        Text(note).iosPrototypeText(size: detailSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
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
        Text(model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: "")).iosPrototypeText(size: titleSize, weight: .semibold, lineHeight: 1.4)
        Text("receiver_address").iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
        if let pairing = model.pairing { Text(pairing.endpoint).iosPrototypeText(size: bodySize).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
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
    DuckSheetLayout(title: "apple_photo_detail") {
      if let image = preview.image {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 300)
        #else
        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300)
        #endif
      } else if preview.failure { DuckNotice(title: "apple_photo_preview_unavailable", tone: .attention, symbol: "photo") }
      else if preview.loading { ProgressView("library_loading") }
      PhotoMetadataPanel(preview: preview)
      DuckNotice(title: "apple_photo_source_note", symbol: "cloud")
    } actions: { Button("settings_done") { dismiss() }.duckSecondaryAction() }
      .task(id: asset.localIdentifier) { preview.load(asset); preview.loadMetadata() }
      .onChange(of: policy.choice) { _, _ in preview.load(); preview.loadMetadata() }
      .onDisappear { preview.cancel() }.previewCloudConsent()
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

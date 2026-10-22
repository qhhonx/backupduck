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
  var desktopFitsContent = false
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
          .fixedSize(horizontal: false, vertical: desktopFitsContent)
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
      .frame(minHeight: desktopFitsContent ? nil : desktopMinHeight, idealHeight: desktopFitsContent ? nil : desktopIdealHeight, maxHeight: 760)
      .fixedSize(horizontal: false, vertical: desktopFitsContent)
      .interactiveDismissDisabled(busy)
    #endif
  }
}

/// Presentation state for a single press, never a second task queue. Rust owns
/// accepted work; these identifiers exist only while its consequence is confirmed.
@MainActor final class SelectionBackupAction: ObservableObject {
  @Published private(set) var busy = false
  @Published private(set) var added = false
  @Published var confirmingRepeat = false
  @Published var error: String?
  private var pending: (tokens: Set<String>, ids: [String], repeats: Set<String>, receiver: String)?

  var title: String {
    added ? NSLocalizedString("selection_backup_added", comment: "")
      : busy ? NSLocalizedString("apple_selected_submitting", comment: "") : ""
  }
  func selectionChanged() { if !busy { added = false } }
  func cancel() { pending = nil; confirmingRepeat = false }

  func request(library: PhotoLibraryModel, model: BackupModel, sources: [String]? = nil) async {
    guard !busy, !confirmingRepeat, !(sources?.isEmpty ?? library.selection.isEmpty) else { return }
    busy = true; added = false; error = nil
    defer { busy = false }
    do {
      guard let receiver = model.pairing?.receiverID else {
        throw SelectionFailure(NSLocalizedString("apple_selected_receiver_needed", comment: ""))
      }
      let tokens = sources == nil ? library.selection : []
      let ids: [String]
      if let sources { ids = sources }
      else { ids = await library.selectedAssetIdentifiers(tokens) }
      guard !ids.isEmpty else { throw SelectionFailure(NSLocalizedString("error_source_unavailable", comment: "")) }
      let repeats = try await model.selectedBackupRepeatSources(ids, receiver: receiver)
      guard model.pairing?.receiverID == receiver else {
        throw SelectionFailure(NSLocalizedString("apple_selected_receiver_needed", comment: ""))
      }
      pending = (tokens, ids, repeats, receiver)
      if !repeats.isEmpty { confirmingRepeat = true }
      else { await register(library: library, model: model) }
    } catch { self.error = error.localizedDescription }
  }
  func confirm(library: PhotoLibraryModel, model: BackupModel) async {
    guard !busy, pending != nil else { return }
    confirmingRepeat = false; busy = true
    defer { busy = false }
    await register(library: library, model: model)
  }
  private func register(library: PhotoLibraryModel, model: BackupModel) async {
    guard let pending else { return }
    defer { self.pending = nil }
    guard model.pairing?.receiverID == pending.receiver else {
      error = NSLocalizedString("apple_selected_receiver_needed", comment: ""); return
    }
    if await model.backupSelectedAssets(pending.ids, rebackupReceived: !pending.repeats.isEmpty,
      repeatSources: pending.repeats) {
      library.selection.subtract(pending.tokens)
      added = true
    } else {
      error = model.message ?? NSLocalizedString("apple_selected_backup_failed", comment: "")
    }
  }
  /// Folders use the same in-place feedback with their existing durable endpoint.
  func perform(_ submit: () async -> Bool, failure: () -> String?) async {
    guard !busy else { return }
    busy = true; added = false; error = nil
    defer { busy = false }
    if await submit() { added = true }
    else { error = failure() ?? NSLocalizedString("apple_selected_backup_failed", comment: "") }
  }
  private struct SelectionFailure: LocalizedError {
    var errorDescription: String?
    init(_ reason: String) { errorDescription = reason }
  }
}

/// A5/I5: only a repeat send asks; registration replaces this toolbar action.
struct DuckSelectionBackupButton: View {
  @ObservedObject var action: SelectionBackupAction
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  var body: some View {
    DuckSelectionBackupControl(action: action, count: library.selection.count,
      request: { await action.request(library: library, model: model) },
      confirm: { await action.confirm(library: library, model: model) })
      .onChange(of: library.selection) { _, ids in if !ids.isEmpty { action.selectionChanged() } }
  }
}

/// The native toolbar control is also exercised with synthetic Catalog inputs.
struct DuckSelectionBackupControl: View {
  @ObservedObject var action: SelectionBackupAction
  let count: Int
  var request: () async -> Void
  var confirm: () async -> Void
  var body: some View {
    Button {
      Task { await request() }
    } label: {
      Text(action.title.isEmpty
        ? String(format: NSLocalizedString("selection_backup_count", comment: ""), count)
        : action.title)
    }
    .disabled(action.busy || action.added || count == 0)
    .accessibilityIdentifier("library.backup_selected")
    .confirmationDialog("selection_backup_repeat_title", isPresented: $action.confirmingRepeat, titleVisibility: .visible) {
      Button("selection_backup_repeat_action") { Task { await confirm() } }
      Button("cancel", role: .cancel) { action.cancel() }
    } message: { Text("selection_backup_repeat_note") }
    .alert("selection_backup_failed_title", isPresented: Binding(get: { action.error != nil }, set: { if !$0 { action.error = nil } })) {
      Button("settings_done") { action.error = nil }
    } message: { Text(action.error ?? "") }
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

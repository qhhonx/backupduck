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

/// Preference rows supply their own vertical metrics; groups only clip the
/// shared surface and inset the leading label and trailing control.
struct DuckPreferenceGroup<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(spacing: 0, content: content).padding(.horizontal, DuckSpacing.medium)
      .background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: DuckRadius.card))
  }
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
enum DuckTone {
  case action, saved, attention, failure, neutral
  var glyphColor: Color {
    switch self {
    case .action: return DuckRole.accent
    case .saved: return DuckRole.saved
    case .attention: return DuckRole.attentionGlyph
    case .failure: return DuckRole.failure
    case .neutral: return DuckRole.secondaryText
    }
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
  func duckPrimaryAction() -> some View { modifier(DuckNativeAction(primary: true)) }
  func duckSecondaryAction() -> some View { modifier(DuckNativeAction(primary: false)) }
}

private struct DuckNativeAction: ViewModifier {
  var primary: Bool
  @Environment(\.duckSheetActions) private var sheet
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
    if sheet { content.buttonStyle(.automatic) }
    else if primary { content.buttonStyle(.borderedProminent).controlSize(.large).tint(DuckRole.accentFill) }
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

/// Explanations and failures remain in the window where the action happened.
struct DuckNotice: View {
  let title: LocalizedStringKey
  var message: LocalizedStringKey? = nil
  var tone: DuckTone = .neutral
  var symbol: String = "info.circle"
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: DuckSpacing.xSmall) {
      Image(systemName: symbol).font(.body).foregroundStyle(tone.glyphColor).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
        Text(title).font(.body).foregroundStyle(.primary)
        if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
      }.fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
  }
}

#if os(iOS)
struct DuckSheetDismissButton: View {
  var title: LocalizedStringKey = "cancel"
  var action: () -> Void
  var body: some View {
    if #available(iOS 26.0, *) {
      Button(role: .cancel, action: action)
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
/// Mac sheet widths: the standard task sheet, and a single-field editor.
enum DuckSheetMetrics {
  static let width: CGFloat = 560
  static let compactWidth: CGFloat = 420
}

struct DuckSheetLayout<Content: View, Actions: View>: View {
  let title: LocalizedStringKey
  var busy = false
  var error: String? = nil
  var desktopWidth: CGFloat = DuckSheetMetrics.width
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
          if closeOnly {
            DuckSheetConfirmButton(title: "settings_done", action: { (cancel ?? { dismiss() })() })
              .disabled(busy).accessibilityIdentifier("sheet.close")
          } else {
            DuckSheetDismissButton(action: { (cancel ?? { dismiss() })() })
              .disabled(busy).accessibilityIdentifier("sheet.close")
          }
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
      }.buttonStyle(.bordered).controlSize(.regular)
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
      showAdded()
    } else {
      error = model.message ?? NSLocalizedString("apple_selected_backup_failed", comment: "")
    }
  }
  /// Folders use the same in-place feedback with their existing durable endpoint.
  func perform(_ submit: () async -> Bool, failure: () -> String?) async {
    guard !busy else { return }
    busy = true; added = false; error = nil
    defer { busy = false }
    if await submit() { showAdded() }
    else { error = failure() ?? NSLocalizedString("apple_selected_backup_failed", comment: "") }
  }
  #if os(macOS)
  private var feedbackTask: Task<Void, Never>?
  #endif
  private func showAdded() {
    added = true
    #if os(macOS)
    feedbackTask?.cancel()
    feedbackTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      self?.added = false
    }
    #endif
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

#if os(iOS)
struct DuckSheetHeightPreference: PreferenceKey {
  static let defaultValue: [String: CGFloat] = [:]
  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
extension View {
  func duckSheetMeasure(_ section: String) -> some View {
    background(GeometryReader { proxy in Color.clear.preference(key: DuckSheetHeightPreference.self, value: [section: proxy.size.height]) })
  }
}
#endif

#if os(iOS)
/// Shared image-choice treatment for gallery, album covers and selected review.
/// The photo grid's selection mark, for SwiftUI tiles.
struct DuckMediaSelectionMark: View {
  var body: some View {
    Image(systemName: "checkmark.circle.fill").resizable()
      .foregroundStyle(DuckRole.accent)
      .background(Circle().fill(DuckMedia.onMedia).padding(1))
      .frame(width: DuckMediaSelection.size, height: DuckMediaSelection.size)
      .padding(DuckMediaSelection.inset)
      .accessibilityHidden(true)
  }
}

@MainActor enum DuckMediaSelection {
  static let size: CGFloat = 23
  static let inset: CGFloat = 6
  static let selectedOpacity: CGFloat = 0.72
  private static let checkmark = UIImage(systemName: "checkmark.circle.fill")
  private static let tint = DuckRole.accentUIColor
  static func configure(_ badge: UIImageView) {
    badge.image = checkmark
    badge.tintColor = tint
    badge.backgroundColor = DuckMedia.onMediaUIColor
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

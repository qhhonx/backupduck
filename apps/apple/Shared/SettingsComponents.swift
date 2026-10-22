import SwiftUI

/// The icon tile at the start of a settings row (design/settings.md). It helps
/// users find a row and never carries state.
struct DuckSettingsIcon: View {
  let symbol: String
  let color: Color
  #if os(macOS)
  private let side = DuckSettingsMetrics.iconSide
  private let symbolFont = Font.footnote.weight(.semibold)
  #else
  @ScaledMetric(relativeTo: .body) private var side: CGFloat = 29
  private let symbolFont = Font.callout.weight(.semibold)
  #endif

  var body: some View {
    Image(systemName: symbol)
      .font(symbolFont)
      .foregroundStyle(.white)  // design-exception: white glyph on a colored icon tile
      .frame(width: side, height: side)
      .background(color, in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// A settings row label: icon tile and title.
struct DuckSettingsLabel: View {
  let title: LocalizedStringKey
  let symbol: String
  let color: Color
  var body: some View {
    #if os(macOS)
      // The system label spacing crowds the icon tile on the Mac.
      HStack(spacing: 10) { DuckSettingsIcon(symbol: symbol, color: color); Text(title) }
    #else
      HStack(alignment: .center, spacing: DuckSpacing.small + DuckSpacing.xSmall) {
        DuckSettingsIcon(symbol: symbol, color: color)
        Text(title)
      }
    #endif
  }
}


/// Values the settings rows show, derived once from the model.
@MainActor struct DuckSettingsValues {
  let model: BackupModel

  /// "On", "Off", "Pair First", or "—" while the engine opens.
  var autoBackup: String {
    guard model.ready else { return "—" }
    guard model.pairing != nil else { return NSLocalizedString("settings_pair_first", comment: "") }
    return NSLocalizedString(model.autoBackup ? "settings_on" : "settings_off", comment: "")
  }

  /// "Backs up to Pixel 8 Pro", "No receiver yet", or nothing while the engine opens.
  var pairedSubtitle: String? {
    guard model.ready else { return nil }
    guard model.pairing != nil else { return NSLocalizedString("settings_no_receiver", comment: "") }
    return String(format: NSLocalizedString("settings_backs_up_to", comment: ""),
      model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: ""))
  }

  /// The paired receiver's name for footers.
  var receiverName: String { model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: "") }

  static var releaseVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "BackupDuckReleaseVersion") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  }

  static var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let release = info["BackupDuckReleaseVersion"] as? String ?? info["CFBundleShortVersionString"] as? String ?? "—"
    return String(format: NSLocalizedString("settings_version_footer", comment: ""), release, info["CFBundleVersion"] as? String ?? "—")
  }
}

#if os(macOS)
/// Redesigned Mac settings geometry (design/visual-language.md, V7): rows 41 pt
/// apart in both the category list and the grouped detail, 24 pt icon tiles, a
/// list column of about 290 pt.
/// The legacy preference pages keep DuckPreferenceMetrics until they are replaced.
enum DuckSettingsMetrics {
  static let rowHeight: CGFloat = 41
  static let iconSide: CGFloat = 24
  static let listWidth: CGFloat = 290
  /// A one-line row in a Mac grouped Form is about 36 pt with the form's own
  /// insets (macOS 26); this padding brings it to `rowHeight`.
  static let formRowPadding: CGFloat = 2.5
}

#endif

/// Shared leading-label preference rows, growing with wrapped or accessibility text.
/// Padding rather than a fixed minimum, so wrapped text still grows.
struct DuckPreferenceRowStyle: LabeledContentStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 12) {
      configuration.label
      Spacer(minLength: 12)
      configuration.content.foregroundStyle(.secondary)
    }
    #if os(macOS)
    .padding(.vertical, DuckSettingsMetrics.formRowPadding)
    #else
    .frame(minHeight: DuckPreferenceMetrics.rowHeight)
    #endif
  }
}

/// Leading label, trailing switch, at the same height.
struct DuckPreferenceToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 12) {
      configuration.label
      Spacer(minLength: 12)
      Toggle("", isOn: configuration.$isOn).toggleStyle(.switch).labelsHidden()
    }
    #if os(macOS)
    .padding(.vertical, DuckSettingsMetrics.formRowPadding)
    #else
    .frame(minHeight: DuckPreferenceMetrics.rowHeight)
    #endif
    .accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
    }
  }
}

/// Which design a host shows. The app keeps the current pages until roadmap
/// step 6; the design catalog switches to the redesigned ones.
enum DesignPreview {
  nonisolated(unsafe) static var proposedDesign = false
}

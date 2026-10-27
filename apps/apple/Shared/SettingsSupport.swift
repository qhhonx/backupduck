import SwiftUI
import QuickLook
#if os(iOS)
import MessageUI
#else
import AppKit
#endif

/// Shared destinations for the approved Settings bottom and About composition.
enum DuckSupport {
  static let website = URL(string: "https://backupduck.app")!
  static let privacy = URL(string: "https://backupduck.app/privacy.html")!
  static let source = URL(string: "https://github.com/qhhonx/backupduck")!
  static let license = source.appendingPathComponent("blob/main/LICENSE")
}

/// Missing owner content removes the entire reserved surface from production.
struct DuckReservedSettingsContent {
  var authorText: String?
  var feedbackEmail: String?
  var appStoreAppID: String?

  static let production = Self(
    authorText: nil, // TODO: Add the owner's approved author text.
    feedbackEmail: nil, // TODO: Add the support email address.
    appStoreAppID: nil // TODO: Add BackupDuck's App Store app ID.
  )

  var reviewURL: URL? {
    guard let appStoreAppID else { return nil }
    return URL(string: "https://apps.apple.com/app/id\(appStoreAppID)?action=write-review")
  }
}

private struct DuckReservedSettingsContentKey: EnvironmentKey {
  static let defaultValue = DuckReservedSettingsContent.production
}
extension EnvironmentValues {
  var duckReservedSettingsContent: DuckReservedSettingsContent {
    get { self[DuckReservedSettingsContentKey.self] }
    set { self[DuckReservedSettingsContentKey.self] = newValue }
  }
}

struct DuckRateBackupDuckRow: View {
  @Environment(\.duckReservedSettingsContent) private var content
  var body: some View {
    if let url = content.reviewURL {
      Link(destination: url) {
        HStack {
          DuckSettingsLabel(title: "settings_rate", symbol: "star.fill", color: DuckGlyph.orange)
          Spacer(minLength: DuckSpacing.small)
          DuckSettingsOutgoingArrow()
        }.frame(maxWidth: .infinity).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .accessibilityIdentifier("settings.rate")
    }
  }
}

/// Identity uses the approved app icon, shared by both Apple About pages.
struct DuckAboutIdentitySection: View {
  var body: some View {
    Section {
      VStack(spacing: DuckSpacing.small) {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit()
          .frame(width: 64, height: 64).accessibilityHidden(true)
        #else
        Image("BrandAppIcon").resizable().scaledToFit().frame(width: 72, height: 72)
          // The launch tile uses the continuous iOS icon corner proportion.
          .clipShape(RoundedRectangle(cornerRadius: 72 * 0.225, style: .continuous)).accessibilityHidden(true)
        #endif
        Text("brand_name").font(.title2.weight(.semibold))
        Text("about_tagline").font(.subheadline).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, DuckSpacing.small)
    }.listRowBackground(Color.clear)
  }
}

struct DuckAboutAuthorSection: View {
  @Environment(\.duckReservedSettingsContent) private var content
  var body: some View {
    if let authorText = content.authorText {
      Section {
        VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
          Text("settings_author_words").font(.headline)
          Text(authorText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, DuckSpacing.xSmall)
      }.accessibilityIdentifier("about.author")
    }
  }
}

struct DuckAboutLinksSection: View {
  var body: some View {
    Section {
      DuckSettingsWebLink("settings_privacy", destination: DuckSupport.privacy).accessibilityIdentifier("about.privacy")
      DuckSettingsLink(title: Text("settings_source_licenses")) { DuckLicensesPage() } label: { Text("settings_source_licenses") }
        .accessibilityIdentifier("about.licenses")
      DuckSettingsWebLink("official_website", destination: DuckSupport.website).accessibilityIdentifier("about.website")
    } footer: {
      Text("settings_privacy_promise").foregroundStyle(.secondary)
    }.foregroundStyle(.primary)
  }
}

/// Web destinations retain preference-row typography and disclose leaving the app.
struct DuckSettingsWebLink: View {
  let title: LocalizedStringKey
  let destination: URL
  init(_ title: LocalizedStringKey, destination: URL) {
    self.title = title; self.destination = destination
  }
  var body: some View {
    Link(destination: destination) {
      HStack(alignment: .center) {
        Text(title).foregroundStyle(.primary)
        Spacer(minLength: DuckSpacing.small)
        DuckSettingsOutgoingArrow()
      }.frame(maxWidth: .infinity).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}

/// Only destinations outside the app carry this trailing mark on both hosts.
struct DuckSettingsOutgoingArrow: View {
  var body: some View {
    Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.secondary)
      .accessibilityHidden(true)
  }
}

/// A release version is a single fact; update status belongs below it when available.
struct DuckAboutVersionLabel: View {
  var status: LocalizedStringKey? = nil
  var body: some View {
    LabeledContent {
      Text(DuckSettingsValues.releaseVersion).foregroundStyle(.secondary)
    } label: {
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        Text("settings_version").foregroundStyle(.primary)
        if let status { Text(status).font(.subheadline).foregroundStyle(.secondary) }
      }
    }
  }
}

struct DuckLicensesPage: View {
  var body: some View {
    Form {
      Section {
        DuckSettingsWebLink("settings_source_code", destination: DuckSupport.source)
        Text("settings_source_license_note").foregroundStyle(.secondary)
        DuckSettingsLink(title: Text("settings_license")) {
          ScrollView {
            if let url = Bundle.main.url(forResource: "BackupDuckLicense", withExtension: "txt"),
              let license = try? String(contentsOf: url, encoding: .utf8) {
              Text(license).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(DuckSpacing.medium)
            } else {
              DuckSettingsWebLink("settings_license_online", destination: DuckSupport.license).padding(DuckSpacing.medium)
            }
          }.navigationTitle("settings_license")
        } label: { Text(verbatim: "PolyForm Noncommercial 1.0.0") }
        DuckSettingsWebLink("settings_license_online", destination: DuckSupport.license)
      }
      Section {
        DuckSettingsLink(title: Text("settings_third_party_licenses")) { DuckThirdPartyLicensesPage() } label: {
          Text("settings_third_party_licenses")
        }.accessibilityIdentifier("licenses.thirdParty")
      }
    }
    #if os(macOS)
    .formStyle(.grouped)
    #else
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .navigationTitle("settings_source_licenses")
    .foregroundStyle(.primary)
  }
}

/// Bundled notices remain readable without a network connection.
struct DuckThirdPartyLicensesPage: View {
  private var text: String? {
    #if os(iOS)
    let name = "ThirdPartyNotices-ios"
    #elseif BACKUPDUCK_APP_STORE
    let name = "ThirdPartyNotices-mac"
    #else
    let name = "ThirdPartyNotices-mac-sparkle"
    #endif
    guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }
  var body: some View {
    Group {
      if let text {
        DuckNoticeText(text: text)
      } else {
        Text("settings_third_party_unavailable").padding(DuckSpacing.medium)
      }
    }
    .navigationTitle("settings_third_party_licenses")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}

/// Native text layout keeps long offline notices selectable and scrollable.
#if os(iOS)
private struct DuckNoticeText: UIViewRepresentable {
  let text: String
  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.isEditable = false
    view.isSelectable = true
    view.font = .preferredFont(forTextStyle: .body)
    view.adjustsFontForContentSizeCategory = true
    view.backgroundColor = .clear
    view.textColor = .label
    view.textContainerInset = UIEdgeInsets(top: DuckSpacing.medium, left: DuckSpacing.medium,
      bottom: DuckSpacing.medium, right: DuckSpacing.medium)
    view.accessibilityIdentifier = "licenses.text"
    return view
  }
  func updateUIView(_ view: UITextView, context: Context) {
    if view.text != text { view.text = text }
  }
}
#else
private struct DuckNoticeText: NSViewRepresentable {
  let text: String
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let view = NSTextView()
    view.isEditable = false
    view.isSelectable = true
    view.isRichText = false
    view.drawsBackground = false
    view.font = .preferredFont(forTextStyle: .body)
    view.textColor = .labelColor
    view.textContainerInset = NSSize(width: DuckSpacing.medium, height: DuckSpacing.medium)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainer?.widthTracksTextView = true
    view.setAccessibilityIdentifier("licenses.text")
    scroll.documentView = view
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? NSTextView else { return }
    if view.string != text { view.string = text }
  }
}
#endif

/// Catalogs request the same native menu that a full-row press opens in production.
private struct DuckFeedbackPreviewKey: EnvironmentKey {
  static let defaultValue = false
}
extension EnvironmentValues {
  var duckFeedbackPreview: Bool {
    get { self[DuckFeedbackPreviewKey.self] }
    set { self[DuckFeedbackPreviewKey.self] = newValue }
  }
}

struct DuckFeedbackMenu: View {
  @Environment(\.duckReservedSettingsContent) private var content
  @Environment(\.duckFeedbackPreview) private var preview
  @Environment(\.openURL) private var openURL
  @State private var email = false
  var body: some View {
    Group {
      if content.feedbackEmail == nil {
        Link(destination: TesterFeedback.group) { rowLabel }
          .buttonStyle(.plain)
          .accessibilityIdentifier("settings.feedback")
      } else {
        rowLabel
          .accessibilityHidden(true)
          .overlay {
            DuckFeedbackMenuButton(preview: preview, join: { openURL(TesterFeedback.group) }, email: { email = true })
          }
      }
    }
    #if os(macOS)
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    #endif
    // On iPhone the system row insets and height, as on every other settings
    // row, so the icon tile lines up with the rows above and below.
    .sheet(isPresented: $email) {
      if let recipient = content.feedbackEmail { DuckFeedbackDiagnosticsSheet(recipient: recipient) }
    }
  }

  private var rowLabel: some View {
    HStack(alignment: .center, spacing: DuckSpacing.small) {
      DuckSettingsLabel(title: "settings_send_feedback", symbol: "bubble.left.and.bubble.right.fill", color: DuckGlyph.blue)
      Spacer(minLength: DuckSpacing.small)
      if content.feedbackEmail == nil {
        DuckSettingsOutgoingArrow()
      } else {
        #if os(iOS)
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
          .accessibilityHidden(true)
        #endif
      }
    }
    .foregroundStyle(.primary)
    #if os(macOS)
    .frame(maxWidth: .infinity, minHeight: DuckPreferenceMetrics.rowHeight)
    #else
    .frame(maxWidth: .infinity)
    #endif
    .contentShape(Rectangle())
  }
}

#if os(iOS)
private struct DuckFeedbackMenuButton: UIViewRepresentable {
  var preview: Bool
  var join: () -> Void
  var email: (() -> Void)?
  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .custom)
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = NSLocalizedString("settings_send_feedback", comment: "")
    button.accessibilityIdentifier = "settings.feedback"
    return button
  }
  func updateUIView(_ button: UIButton, context: Context) {
    var actions = [UIAction(title: NSLocalizedString("settings_feedback_join", comment: ""), image: UIImage(systemName: "person.2")) { _ in join() }]
    if let email {
      actions.append(UIAction(title: NSLocalizedString("settings_feedback_email", comment: ""), image: UIImage(systemName: "envelope")) { _ in email() })
    }
    button.menu = UIMenu(children: actions)
    if preview && !context.coordinator.opened {
      context.coordinator.opened = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak button] in
        guard let button, button.window != nil else { return }
        button.performPrimaryAction()
      }
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator { var opened = false }
}
#else
private struct DuckFeedbackMenuButton: NSViewRepresentable {
  var preview: Bool
  var join: () -> Void
  var email: (() -> Void)?
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
    button.isBordered = false
    button.setAccessibilityLabel(NSLocalizedString("settings_send_feedback", comment: ""))
    button.setAccessibilityIdentifier("settings.feedback")
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.join = join; context.coordinator.email = email
    if preview && !context.coordinator.opened {
      context.coordinator.opened = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak button] in
        guard let button, button.window != nil else { return }
        button.performClick(nil)
      }
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator: NSObject {
    var opened = false
    var join: () -> Void = {}
    var email: (() -> Void)?
    @objc func open(_ button: NSButton) {
      let menu = NSMenu()
      var actions = [("settings_feedback_join", "person.2", #selector(joinGroup))]
      if email != nil { actions.append(("settings_feedback_email", "envelope", #selector(composeEmail))) }
      for (title, symbol, action) in actions {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
      }
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }
    @objc func joinGroup() { join() }
    @objc func composeEmail() { email?() }
  }
}
#endif

private struct DuckFeedbackDiagnosticsSheet: View {
  let recipient: String
  private var mailto: URL {
    var parts = URLComponents()
    parts.scheme = "mailto"
    parts.path = recipient
    parts.queryItems = [URLQueryItem(name: "subject", value: NSLocalizedString("settings_feedback_subject", comment: ""))]
    return parts.url!
  }
  @StateObject private var export = ActivityLogExportModel()
  @State private var preview: URL?
  @Environment(\.dismiss) private var dismiss
  #if os(iOS)
  @State private var composing = false
  @State private var composeFailed = false
  #else
  @StateObject private var mail = DuckMailService()
  #endif

  var body: some View {
    DuckSheetLayout(title: "settings_send_feedback", busy: export.preparing, closeOnly: true) {
      Text("settings_feedback_attachment_note").foregroundStyle(.secondary)
      Text("logs_privacy_note").font(.callout).foregroundStyle(.secondary)
      if export.preparing {
        DuckLoadingState("logs_export_preparing")
      } else if export.failed {
        ContentUnavailableView {
          Label("logs_export_failed", systemImage: "exclamationmark.circle")
        } actions: {
          Button("retry_task") { Task { await export.prepare() } }.buttonStyle(.bordered)
        }
      } else if let url = export.url {
        Button { preview = url } label: { Label(url.lastPathComponent, systemImage: "doc.text") }
          .accessibilityIdentifier("settings.feedback_attachment")
        #if os(iOS)
        if MFMailComposeViewController.canSendMail() {
          Button("settings_feedback_compose") { composing = true }
        } else {
          Text("settings_feedback_share_note").font(.callout).foregroundStyle(.secondary)
          Link("settings_feedback_open_mail", destination: mailto)
          ShareLink(item: url) { Label("logs_export_share", systemImage: "square.and.arrow.up") }
        }
        if composeFailed { Text("settings_feedback_mail_failed").foregroundStyle(DuckRole.failure) }
        #else
        if mail.failed { Text("settings_feedback_mail_failed").foregroundStyle(DuckRole.failure) }
        #endif
      }
    } actions: {
      #if os(macOS)
      Button("settings_done") { dismiss() }.buttonStyle(.bordered)
      #endif
      if let url = export.url {
        #if os(macOS)
        Button("settings_feedback_compose") { mail.compose(url: url, recipient: recipient) }
          .buttonStyle(.borderedProminent)
        #endif
      }
    }
    .quickLookPreview($preview)
    .task { await export.prepare() }
    #if os(iOS)
    .sheet(isPresented: $composing) {
      if let url = export.url {
        DuckMailComposer(url: url, recipient: recipient) { failed in composing = false; composeFailed = failed }
      }
    }
    #endif
  }
}

#if os(iOS)
private struct DuckMailComposer: UIViewControllerRepresentable {
  let url: URL
  let recipient: String
  var completion: (Bool) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let controller = MFMailComposeViewController()
    controller.mailComposeDelegate = context.coordinator
    controller.setToRecipients([recipient])
    controller.setSubject(NSLocalizedString("settings_feedback_subject", comment: ""))
    do {
      let data = try Data(contentsOf: url)
      controller.addAttachmentData(data, mimeType: "application/json", fileName: url.lastPathComponent)
    } catch {
      DispatchQueue.main.async { completion(true) }
    }
    return controller
  }
  func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) { self.completion = completion }
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
      completion(result == .failed || error != nil)
    }
  }
}
#else
@MainActor private final class DuckMailService: NSObject, ObservableObject, NSSharingServiceDelegate {
  @Published var failed = false
  private var service: NSSharingService?
  func compose(url: URL, recipient: String) {
    failed = false
    guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [url]) else {
      failed = true; return
    }
    self.service = service
    service.delegate = self
    service.recipients = [recipient]
    service.subject = NSLocalizedString("settings_feedback_subject", comment: "")
    service.perform(withItems: [url])
  }
  func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
    failed = true
  }
}
#endif

import Photos
import SwiftUI
import UIKit
import UserNotifications

/// First run on iPhone (design/flows.md § First run). One decision per screen,
/// the primary action in a fixed place, system prompts explained first, and the
/// first photo landing as the first reward. Shown in the design catalog until
/// migration step 6 puts it in front of the app.
struct IOSOnboarding: View {
  enum Step: String, CaseIterable { case welcome, install, connect, connected, photos, choose, first }

  @ObservedObject var model: BackupModel
  var finish: () -> Void = {}
  @State private var step: Step
  @State private var autoBackup = true
  @State private var working = false
  @State private var landed = false
  /// The title follows the flight, so it never claims the photo landed before the user sees it land.
  @State private var announced = false
  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let downloadPage = "https://backupduck.app/#download"

  init(model: BackupModel, start: Step = .welcome, finish: @escaping () -> Void = {}) {
    self.model = model
    self.finish = finish
    _step = State(initialValue: start)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        content.padding(.horizontal, 24).padding(.top, 32).frame(maxWidth: 520).frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      actions.padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: 520)
    }
    .background(DuckRole.background.ignoresSafeArea())
    .tint(DuckRole.accent)
    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
    .onAppear { if step == .first { checkLanded() } }
    .onChange(of: model.summary.published) { _, _ in checkLanded() }
  }

  // MARK: - Content

  @ViewBuilder private var content: some View {
    switch step {
    case .welcome:
      VStack(alignment: .leading, spacing: 20) {
        DuckIllustration(pose: .welcome, size: 120).frame(maxWidth: .infinity)
        Text("onboarding_title").font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
        Text("onboarding_subtitle").font(.title3).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 14) {
          stepRow(1, "onboarding_step_install", "onboarding_step_install_note")
          stepRow(2, "onboarding_step_connect", "onboarding_step_connect_note")
          stepRow(3, "onboarding_step_backup", "onboarding_step_backup_note")
        }
        Text("onboarding_fine_print").font(.caption2).foregroundStyle(.secondary)
      }
    case .install:
      VStack(alignment: .leading, spacing: 16) {
        DuckStepMark(number: 1, scale: 1.25)
        Text("onboarding_install_title").font(.title.weight(.bold))
        Text("onboarding_install_body").foregroundStyle(.secondary)
        VStack(spacing: 8) {
          DuckQRCode(text: Self.downloadPage).frame(width: 200, height: 200).padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20)) // design-exception: QR codes need a white quiet zone in both appearances
          Text(verbatim: "backupduck.app").font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
        }.frame(maxWidth: .infinity).padding(.top, 8)
      }
    case .connect:
      VStack(alignment: .leading, spacing: 16) {
        DuckStepMark(number: 2, scale: 1.25)
        Text("onboarding_connect_title").font(.title.weight(.bold))
        Text("onboarding_connect_body").foregroundStyle(.secondary)
        IOSPixelScanner(model: model) { go(.connected) }
      }
    case .connected:
      VStack(spacing: 16) {
        DuckIllustration(pose: .pairing, size: 160).padding(.top, 40)
        Text(String(format: NSLocalizedString("onboarding_connected_title", comment: ""),
          model.peerDevice?.name ?? "Pixel")).font(.title.weight(.bold)).multilineTextAlignment(.center)
        Text("onboarding_connected_body").foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.frame(maxWidth: .infinity)
    case .photos:
      VStack(alignment: .leading, spacing: 16) {
        DuckStepMark(number: 3, scale: 1.25)
        Text("onboarding_photos_title").font(.title.weight(.bold))
        VStack(alignment: .leading, spacing: 12) {
          Label("onboarding_photos_direct", systemImage: "arrow.right.circle")
          Label("onboarding_photos_private", systemImage: "lock")
          Label("onboarding_photos_quality", systemImage: "sparkles")
        }.font(.body)
      }
    case .choose:
      VStack(alignment: .leading, spacing: 16) {
        Text("onboarding_choose_title").font(.title.weight(.bold))
        if DesignPreview.proposedLook {
          VStack(alignment: .leading, spacing: 6) {
            Toggle("onboarding_choose_auto", isOn: $autoBackup).font(.headline)
            Text("onboarding_choose_auto_note").font(.footnote).foregroundStyle(.secondary)
          }.duckLookCard()
          // Photos lead (visual-language.md): the question shows the user's own photos.
          VStack(alignment: .leading, spacing: 10) {
            OnboardingLibraryStrip()
            Text(earlierQuestion).font(.headline)
            Text("onboarding_choose_earlier_note").font(.footnote).foregroundStyle(.secondary)
          }.duckLookCard()
        } else {
          VStack(alignment: .leading, spacing: 6) {
            Toggle("onboarding_choose_auto", isOn: $autoBackup).font(.headline)
            Text("onboarding_choose_auto_note").font(.footnote).foregroundStyle(.secondary)
          }.padding(16).background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: 16))
          VStack(alignment: .leading, spacing: 6) {
            Text(earlierQuestion).font(.headline)
            Text("onboarding_choose_earlier_note").font(.footnote).foregroundStyle(.secondary)
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: 16))
        }
      }
    case .first:
      VStack(spacing: 24) {
        FirstPhotoFlight(
          sourceID: model.jobs.first?.asset.source_id,
          senderName: UIDevice.current.localizedModel, receiverName: model.peerDevice?.name ?? "Pixel",
          landed: landed
        ) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { announced = true } }
        .padding(.top, 48)
        // The waiting line leaves when the flight starts; the title arrives after
        // it, in the same place, so the two never overlap.
        ZStack(alignment: .top) {
          if !landed {
            Text("onboarding_first_waiting").foregroundStyle(.secondary).transition(.opacity)
          }
          if announced {
            VStack(spacing: 12) {
              Text("onboarding_first_title").font(.title.weight(.bold)).multilineTextAlignment(.center)
              Text("onboarding_first_notify").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
          }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: landed)
      }.frame(maxWidth: .infinity)
    }
  }

  private var earlierQuestion: String {
    guard let count = BackupEnvironment.libraryCount() else { return NSLocalizedString("onboarding_choose_earlier_unknown", comment: "") }
    return String(format: NSLocalizedString("onboarding_choose_earlier", comment: ""), count.formatted())
  }

  private func stepRow(_ number: Int, _ title: LocalizedStringKey, _ note: LocalizedStringKey) -> some View {
    HStack(alignment: .center, spacing: 12) {
      DuckStepMark(number: number)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(note).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Actions

  @ViewBuilder private var actions: some View {
    VStack(spacing: 8) {
      switch step {
      case .welcome:
        primary("onboarding_start") { go(model.pairing == nil ? .install : .photos) }
      case .install:
        primary("onboarding_install_done") { go(.connect) }
      case .connect:
        EmptyView() // The scanner carries its own action.
      case .connected:
        primary("onboarding_continue") { go(.photos) }
      case .photos:
        primary("onboarding_continue") {
          working = true
          Task { _ = await model.authorizePhotos(); working = false; go(.choose) }
        }
      case .choose:
        primary("onboarding_choose_all") { Task { await choose(earlier: true) } }
        secondary("onboarding_choose_new_only") { Task { await choose(earlier: false) } }
      case .first:
        if announced {
          primary("onboarding_notify") {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]); finish() }
          }
          secondary("onboarding_later") { finish() }
        }
      }
    }
    .disabled(working)
  }

  private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).frame(maxWidth: .infinity) }
      .buttonStyle(.borderedProminent).controlSize(.large)
  }

  private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(title, action: action).controlSize(.large)
  }

  private func go(_ next: Step) {
    step = next
    if next == .first { checkLanded() }
  }

  /// A first run starts with nothing saved, so any photo saved to the Pixel's
  /// Photos is the first one.
  private func checkLanded() {
    guard step == .first, !landed, model.summary.published > 0 else { return }
    landed = true
  }

  private func choose(earlier: Bool) async {
    working = true
    if autoBackup { await model.setAutoBackup(true) }
    if earlier { await model.controlHistoricalImport("start") }
    working = false
    // Only earlier photos send at once; new photos may not arrive for a while.
    if earlier { go(.first) } else { finish() }
  }
}

/// The four most recent photos of the library, as one rounded strip. In the
/// design catalog, which never reads the library, sample pictures stand in.
private struct OnboardingLibraryStrip: View {
  @State private var sources: [String] = []
  var body: some View {
    GeometryReader { geometry in
      let gap: CGFloat = 3
      let side = (geometry.size.width - gap * 3) / 4
      HStack(spacing: gap) {
        ForEach(Array(sources.prefix(4).enumerated()), id: \.offset) { _, id in
          AssetThumbnail(sourceID: id, size: side, cornerRadius: 0)
        }
      }
    }
    .aspectRatio(4, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .task {
      guard BackupEnvironment.usesPhotoLibrary else { sources = (1...4).map { "onboarding-sample-\($0)" }; return }
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = 4
      let fetch = PHAsset.fetchAssets(with: .image, options: options)
      sources = (0..<fetch.count).map { fetch.object(at: $0).localIdentifier }
    }
  }
}

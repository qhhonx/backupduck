import SwiftUI

struct IOSReceiverPage: View {
  @ObservedObject var model: BackupModel
  @State private var scanner = false
  @ScaledMetric(relativeTo: .title2) private var heroSize = 26
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        IOSPrototypeHeader("nav_receiver")
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if model.pairing == nil {
              Text("apple_pair_title").iosPrototypeText(size: heroSize, weight: .semibold, lineHeight: 1.3)
              Text("apple_pair_subtitle").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
              DuckSurface {
                VStack(alignment: .leading, spacing: 16) {
                  DuckBrandMark(size: 76)
                  DuckPairingSteps()
                }
              }
            } else if let pairing = model.pairing {
              DuckSurface {
                VStack(alignment: .leading, spacing: 16) {
                  Text(model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: ""))
                    .iosPrototypeText(size: heroSize, weight: .semibold, lineHeight: 1.3)
                  ReceiverStatusIndicator(model: model, textOnly: true)
                  Text("receiver_address").font(.caption).foregroundStyle(DuckColors.textSecondary)
                  Text(pairing.endpoint).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                  Text("receiver_direct_description").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
                }
              }
            }
            Button { scanner = true } label: {
              Text(LocalizedStringKey(model.pairing == nil ? "pair_receiver" : "pair_another_receiver")).frame(maxWidth: .infinity)
            }.iosPrototypeAction(primary: true).accessibilityIdentifier("receiver.scan")
            if let error = model.pairingError {
              DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "link")
                .accessibilityIdentifier("receiver.connection_error")
            } else if model.pairing != nil, model.receiverConnection == .authentication {
              DuckNotice(title: "receiver_connection_authentication", tone: .failure, symbol: "exclamationmark.triangle")
                .accessibilityIdentifier("receiver.connection_error")
            } else if model.pairing != nil, model.receiverConnection == .unavailable || model.receiverUnavailable || model.waitingForNetwork {
              DuckNotice(title: model.receiverConnection == .unavailable ? "receiver_connection_unavailable_note" : "receiver_connection_network", tone: .attention, symbol: "wifi")
                .accessibilityIdentifier("receiver.connection_error")
            }

          }.iosPrototypePageBody()
        }
      }.background(DuckColors.canvas).foregroundStyle(DuckColors.text).toolbar(.hidden, for: .navigationBar).symbolVariant(.none)
        .sheet(isPresented: $scanner) { IOSPairingFlow(model: model) }
    }
  }
}

/// Scanning, TLS validation and recovery stay in one visible native workflow.
/// Closing this sheet never means pairing succeeded; only the model confirms it.
struct IOSPairingFlow: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var cameraFailure: PairingCameraFailure?
  @State private var cameraID = UUID()
  @State private var captured = false
  @State private var paired = false
  @State private var settingsUnavailable = false
  @State private var requestError: String?
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  var body: some View {
    DuckSheetLayout(title: "apple_scan_title", busy: model.pairingInProgress,
      error: captured ? (requestError ?? model.pairingError) : nil) {
      if paired {
        DuckNotice(title: "apple_pair_success", tone: .saved, symbol: "checkmark.circle")
        DuckReceiverSummary(model: model)
      } else {
        if model.pairingInProgress {
          DuckNotice(title: "receiver_indicator_pairing", message: "apple_pair_validating_note")
            .accessibilityIdentifier("pairing.validating")
          ProgressView().controlSize(.small)
        } else if captured, requestError != nil || model.pairingError != nil {
          DuckNotice(title: "receiver_local_network", symbol: "wifi")
        } else if let failure = cameraFailure {
          DuckNotice(title: failure == .permission ? "apple_camera_restricted" : "apple_camera_unavailable",
            message: failure == .permission ? "apple_camera_restricted_note" : "apple_camera_unavailable_note",
            tone: .attention, symbol: "camera")
            .accessibilityIdentifier("pairing.camera_error")
          if settingsUnavailable { Text("photos_settings_unavailable").foregroundStyle(DuckColors.failure) }
        } else {
          Text("receiver_pair_instructions").font(.callout)
          PairingScanner(scanned: accept, failed: { cameraFailure = $0 })
            .id(cameraID).frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
              .frame(width: 130, height: 130).allowsHitTesting(false).accessibilityHidden(true) }
            .accessibilityIdentifier("pairing.camera")
          Text("apple_scan_frame_note").iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
        }
        if !model.pairingInProgress { DuckPairingSteps() }
      }
    } actions: {
      if paired {
        Button { dismiss() } label: { Text("settings_done").frame(maxWidth: .infinity) }
          .iosPrototypeAction(primary: true)
          .accessibilityIdentifier("pairing.done")
      } else if model.pairingInProgress {
        Button {} label: { Text("receiver_indicator_pairing").frame(maxWidth: .infinity) }
          .iosPrototypeAction(primary: true).disabled(true)
      } else {
        Button { dismiss() } label: { Text("cancel").frame(maxWidth: .infinity) }.iosPrototypeAction()
          .disabled(model.pairingInProgress)
        if cameraFailure == .permission {
          Button {
            Task {
              settingsUnavailable = false
              guard let url = URL(string: UIApplication.openSettingsURLString) else {
                settingsUnavailable = true
                return
              }
              settingsUnavailable = !(await UIApplication.shared.open(url))
            }
          } label: { Text("photos_open_settings").frame(maxWidth: .infinity) }.iosPrototypeAction(primary: true)
        } else if cameraFailure != nil || captured {
          Button(action: reset) { Text("apple_scan_again").frame(maxWidth: .infinity) }.iosPrototypeAction(primary: true)
            .disabled(model.pairingInProgress).accessibilityIdentifier("pairing.retry")
        }
      }
    }
    .onAppear { if !model.pairingInProgress { model.pairingError = nil } }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active, cameraFailure == .permission { reset() }
    }
  }
  private func reset() {
    model.pairingError = nil
    requestError = nil
    cameraFailure = nil
    captured = false
    settingsUnavailable = false
    cameraID = UUID()
  }
  private func accept(_ payload: String) {
    guard !captured, !model.pairingInProgress else { return }
    captured = true
    Task {
      paired = await model.pair(payload)
      if !paired {
        // Present an actionable QR explanation instead of a Cocoa JSON-decoder
        // sentence. The model remains authoritative for TLS and trust checks.
        let parseable = (try? JSONDecoder().decode(Pairing.self, from: Data(payload.utf8))) != nil
        requestError = parseable
          ? model.pairingError ?? NSLocalizedString("desktop_pair_failed", comment: "")
          : NSLocalizedString("error_invalid_input", comment: "")
      }
    }
  }
}

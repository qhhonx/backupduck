import SwiftUI
import UIKit
import AVFoundation

/// The scanner and a guided flow can share recovery intent so the flow keeps
/// its primary action in the same bottom slot as its other steps.
@MainActor final class IOSPixelScannerState: ObservableObject {
  @Published var scanError: String?
  @Published var cameraFailure: PairingCameraFailure?
  @Published var scannerID = UUID()
  @Published var working = false
  @Published var payload: String?
  @Published var connectionAttempt = 0
  @Published var connectionNeedsSettings = false
  var needsSettings: Bool { cameraFailure == .permission || connectionNeedsSettings }
  var needsRecovery: Bool { scanError != nil || cameraFailure != nil }
  func retry() {
    scanError = nil; cameraFailure = nil; connectionNeedsSettings = false
    if payload != nil { connectionAttempt += 1 } else { scannerID = UUID() }
  }
  func scanAgain() { payload = nil; retry() }
  func cameraAuthorizationChanged(_ authorized: Bool) {
    if cameraFailure == .permission && authorized { scanAgain() }
  }
}

/// Shared by first run and later connect/reconnect. Camera recovery stays in
/// the scanner by default; guided flows can place it in their fixed footer.
struct IOSPixelScanner: View {
  @ObservedObject var model: BackupModel
  var connected: () -> Void
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var state: IOSPixelScannerState
  var showsRecoveryActions: Bool

  init(model: BackupModel, state: IOSPixelScannerState? = nil,
    showsRecoveryActions: Bool = true, connected: @escaping () -> Void) {
    self.model = model; self.connected = connected
    self.showsRecoveryActions = showsRecoveryActions
    _state = StateObject(wrappedValue: state ?? IOSPixelScannerState())
  }

  var body: some View {
    Group {
      if let cameraFailure = state.cameraFailure {
        ContentUnavailableView {
          Label(cameraFailure == .permission ? "apple_camera_restricted" : "apple_camera_unavailable", systemImage: "camera")
        } description: {
          Text(cameraFailure == .permission ? "apple_camera_restricted_note" : "apple_camera_unavailable_note")
        } actions: {
          if showsRecoveryActions {
            if cameraFailure == .permission {
              Button("photos_open_settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                .duckPrimaryButton()
            } else { retryButton }
          }
        }
      } else if let scanError = state.scanError {
        ContentUnavailableView {
          Label("connect_failed", systemImage: "exclamationmark.triangle")
        } description: {
          Text(scanError)
        } actions: {
          if showsRecoveryActions {
            if state.needsSettings {
              Button("photos_open_settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }.duckPrimaryButton()
              Button("retry_task") { state.retry() }.buttonStyle(.bordered)
            } else { retryButton }
            if state.payload != nil { Button("apple_scan_again") { state.scanAgain() } }
          }
        }
      } else if state.payload != nil {
        DuckLoadingState("connect_connecting").frame(height: 300)
      } else {
        PairingScanner(scanned: accept, failed: { state.cameraFailure = $0 })
          .id(state.scannerID).frame(height: 300)
          .clipShape(RoundedRectangle(cornerRadius: DuckRadius.card))
          .overlay { if state.working { ProgressView().controlSize(.large) } }
      }
    }
    .task(id: state.connectionAttempt) {
      guard let payload = state.payload, state.scanError == nil else { return }
      await connect(payload)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active && BackupEnvironment.usesCamera {
        state.cameraAuthorizationChanged(AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
      }
    }
  }
  private var retryButton: some View {
    Button(state.payload == nil ? "apple_scan_again" : "retry_task") { state.retry() }.duckPrimaryButton()
  }

  private func accept(_ payload: String) {
    guard !state.working, state.payload == nil else { return }
    guard (try? JSONDecoder().decode(Pairing.self, from: Data(payload.utf8))) != nil else {
      state.scanError = NSLocalizedString("connect_code_unreadable", comment: "")
      return
    }
    state.payload = payload
    state.connectionAttempt += 1
  }

  private func connect(_ payload: String) async {
    guard !state.working else { return }
    state.working = true
    state.scanError = nil
    let paired = await model.pair(payload)
    state.working = false
    guard !Task.isCancelled else { return }
    if paired { connected() }
    else {
      state.connectionNeedsSettings = model.pairingNeedsSettings
      state.scanError = model.pairingError ?? NSLocalizedString("desktop_pair_failed", comment: "")
    }
  }

}

/// Connecting from the hub or Devices after first run: the same words, scanner
/// and success screen as first run, without the first-run steps.
struct IOSConnectSheet: View {
  @ObservedObject var model: BackupModel
  /// The Pixel no longer recognizes this iPhone: say so and keep earlier backups' reassurance.
  var reconnect = false
  var scanner: IOSPixelScannerState? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var connected = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if connected {
            VStack(spacing: 16) {
              DuckIllustration(pose: .pairing, size: 160).padding(.top, 32)
              Text(String(format: NSLocalizedString("onboarding_connected_title", comment: ""), model.peerDevice?.name ?? "Pixel"))
                .font(.title2.bold()).multilineTextAlignment(.center)
              Text("onboarding_connected_body").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
          } else {
            Text(reconnect ? "connect_again_title" : "onboarding_connect_title").font(.title2.bold())
            Text(reconnect ? "connect_again_body" : "onboarding_connect_body").foregroundStyle(.secondary)
            IOSPixelScanner(model: model, state: scanner) { withAnimation(.smooth(duration: 0.25)) { connected = true } }
          }
        }
        .padding(24)
      }
      .background(DuckRole.background)
      .toolbar {
        ToolbarItem(placement: connected ? .confirmationAction : .cancellationAction) {
          if connected { DuckSheetConfirmButton(title: "records_done") { dismiss() } }
          else { DuckSheetDismissButton { dismiss() } }
        }
      }
    }
    .tint(DuckRole.accent)
  }
}

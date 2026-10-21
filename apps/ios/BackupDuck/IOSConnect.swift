import SwiftUI
import UIKit

/// Scanning the Pixel's code, shared by first run and every later connect or
/// reconnect (design/navigation.md, design/flows.md § First run step 3). It owns
/// the camera states and the one action each needs: try again, or open Settings
/// when camera access is off.
struct IOSPixelScanner: View {
  @ObservedObject var model: BackupModel
  var connected: () -> Void
  @Environment(\.openURL) private var openURL
  @State private var scanError: String?
  @State private var cameraFailure: PairingCameraFailure?
  @State private var scannerID = UUID()
  @State private var working = false

  var body: some View {
    Group {
      if let cameraFailure {
        ContentUnavailableView {
          Label(cameraFailure == .permission ? "apple_camera_restricted" : "apple_camera_unavailable", systemImage: "camera")
        } description: {
          Text(cameraFailure == .permission ? "apple_camera_restricted_note" : "apple_camera_unavailable_note")
        } actions: {
          if cameraFailure == .permission {
            Button("photos_open_settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
              .duckPrimaryButton()
          } else { retryButton }
        }
      } else if let scanError {
        ContentUnavailableView {
          Label("desktop_pair_failed", systemImage: "exclamationmark.triangle")
        } description: {
          Text(scanError)
        } actions: { retryButton }
      } else {
        PairingScanner(scanned: accept, failed: { cameraFailure = $0 })
          .id(scannerID).frame(height: 300)
          .clipShape(RoundedRectangle(cornerRadius: DuckRadius.card))
          .overlay { if working { ProgressView().controlSize(.large) } }
      }
    }
  }
  private var retryButton: some View {
    Button("apple_scan_again") { scanError = nil; cameraFailure = nil; scannerID = UUID() }.duckPrimaryButton()
  }

  private func accept(_ payload: String) {
    guard !working else { return }
    working = true
    scanError = nil
    Task {
      let paired = await model.pair(payload)
      working = false
      if paired { connected() }
      else {
        let parseable = (try? JSONDecoder().decode(Pairing.self, from: Data(payload.utf8))) != nil
        scanError = parseable ? model.pairingError ?? NSLocalizedString("desktop_pair_failed", comment: "")
          : NSLocalizedString("connect_code_unreadable", comment: "")
      }
    }
  }
}

/// Connecting from the hub or Devices after first run: the same words, scanner
/// and success screen as first run, without the first-run steps.
struct IOSConnectSheet: View {
  @ObservedObject var model: BackupModel
  /// The Pixel no longer recognizes this iPhone: say so and keep earlier backups' reassurance.
  var reconnect = false
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
            IOSPixelScanner(model: model) { withAnimation(.smooth(duration: 0.25)) { connected = true } }
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

import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

var senderDeviceType: String {
  #if os(macOS)
    return "Mac"
  #else
    return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
  #endif
}

struct DeviceProfile: Codable, Equatable {
  let id: String
  let name: String
}
struct DeviceSnapshot: Decodable {
  struct Peer: Decodable {
    let key: String
    let profile: DeviceProfile
    let last_seen: Int64
  }
  let device: DeviceProfile
  let peers: [Peer]
}
extension BackupModel {
  /// Names are optional display metadata, scoped to the job's stored target id.
  /// A different current pairing must not relabel an older task.
  func receiverDeviceName(for job: BackupJob) -> String? {
    guard let id = job.receiverID, !id.isEmpty,
      let name = deviceSnapshot?.peers.first(where: { $0.key == id })?.profile.name,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return name
  }
  var peerDevice: DeviceProfile? {
    guard let pairing else { return nil }
    return deviceSnapshot?.peers.first { $0.key == pairing.receiverID }?.profile
  }
  func refreshDeviceStatus() async {
    do {
      let data = try await Bridge.call(["op": "device_status",
        "root": root.appendingPathComponent("queue").path,
        "language": Locale.current.language.languageCode?.identifier ?? "en"])
      deviceSnapshot = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
      deviceError = nil
    } catch { deviceError = NSLocalizedString("device_load_failed", comment: "") }
  }
  func renameDevice(_ name: String) async -> Bool {
    guard !savingDevice else { return false }
    savingDevice = true
    deviceError = nil
    defer { savingDevice = false }
    do {
      let data = try await Bridge.call(["op": "device_status",
        "root": root.appendingPathComponent("queue").path,
        "name": name])
      deviceSnapshot = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
      lastDeviceExchange = .distantPast
      Task { await syncDeviceProfile(force: true) }
      return true
    } catch let error as Bridge.Failure where error.code == "invalid_input" {
      deviceError = NSLocalizedString("device_name_invalid", comment: "")
      return false
    } catch {
      deviceError = NSLocalizedString("device_save_failed", comment: "")
      return false
    }
  }
  func syncDeviceProfile(force: Bool = false) async {
    guard ready, networkingStarted, let target = pairing, !exchangingDevice,
      force || Date().timeIntervalSince(lastDeviceExchange) >= 60 else { return }
    exchangingDevice = true
    lastDeviceExchange = Date()
    defer { exchangingDevice = false }
    do {
      _ = try await Bridge.call(["op": "exchange_device", "device_type": senderDeviceType,
        "pairing": try JSONSerialization.jsonObject(with: JSONEncoder().encode(target))])
      // The remembered peer is scoped by the receiver's certificate identity.
      await refreshDeviceStatus()
    } catch {
      // A nickname is optional display metadata. Keep the offline name and do
      // not change queue state or replace a meaningful transfer error.
    }
  }
}

struct DeviceNameEditor: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @State var name: String
  @State private var originalName = ""
  @State private var confirmDiscard = false
  private var dirty: Bool { name != originalName }
  private func cancel() {
    if dirty { confirmDiscard = true } else { dismiss() }
  }
  private var valid: Bool {
    let scalars = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
    return !scalars.isEmpty && scalars.count <= 40 && !scalars.contains {
      CharacterSet.controlCharacters.contains($0) || (0x2028...0x202e).contains($0.value) || (0x2066...0x2069).contains($0.value)
    }
  }
  var body: some View {
    // One field: the Mac sheet is as tall as its content, at the narrow sheet width.
    DuckSheetLayout(title: "device_rename", busy: model.savingDevice, error: model.deviceError,
      desktopWidth: DuckSheetMetrics.compactWidth, desktopFitsContent: true, form: true, cancel: cancel) {
      Section {
        TextField("device_name", text: $name)
          .accessibilityIdentifier("device.name").disabled(model.savingDevice)
      } footer: {
        Text("device_name_note").font(.footnote).foregroundStyle(.secondary)
      }
      if !valid { DuckNotice(title: "device_name_invalid", tone: .failure, symbol: "exclamationmark.circle") }
      if model.savingDevice { DuckLoadingState("apple_working") }
    } actions: {
      #if os(iOS)
      DuckSheetConfirmButton(title: "device_save") { Task { if await model.renameDevice(name) { dismiss() } } }
        .disabled(model.savingDevice || !valid).accessibilityIdentifier("device.name_save")
      #else
      Button("device_save") { Task { if await model.renameDevice(name) { dismiss() } } }
        .duckPrimaryAction().disabled(model.savingDevice || !valid).accessibilityIdentifier("device.name_save")
      #endif
    }
    .interactiveDismissDisabled(model.savingDevice || dirty)
    #if os(iOS)
    .confirmationDialog("device_discard_title", isPresented: $confirmDiscard, titleVisibility: .visible) {
      Button("device_discard", role: .destructive) { dismiss() }
      Button("cancel", role: .cancel) {}
    }
    #else
    .alert("device_discard_title", isPresented: $confirmDiscard) {
      Button("cancel", role: .cancel) {}
      Button("device_discard") { dismiss() }.keyboardShortcut(.defaultAction)
    }
    #endif
    .onAppear { originalName = name; model.deviceError = nil }
  }
}

import Foundation
import Photos
import SwiftUI

/// The Rust core boundary: one JSON command in, one result envelope out
/// (`{"ok": true, "value": …}` or `{"ok": false, "error": code}`).
protocol CoreTransport: Sendable {
  func call(_ command: String) async throws -> Data
}

/// Where the pairing record is kept.
protocol CredentialStore: Sendable {
  func read() throws -> Data?
  func save(_ data: Data) throws
  /// Removes a record left behind by a deleted installation.
  func discardLeftover() throws
}
extension CredentialStore {
  func discardLeftover() throws {}
}

/// What the sender takes from outside its own process. The app uses the linked
/// Rust library, the system keychain and Bonjour. The design catalog installs
/// scenario providers here once at launch, before any model is created, so the
/// production model and pages render reviewable states unchanged.
enum BackupEnvironment {
  nonisolated(unsafe) static var core: any CoreTransport = NativeCore()
  nonisolated(unsafe) static var credentials: any CredentialStore = SystemKeychain()
  /// The model whose pairing a photo's backup facts are read for. The catalog
  /// points it at the scenario's model.
  nonisolated(unsafe) static var activeModel: @MainActor () -> BackupModel = { .shared }
  nonisolated(unsafe) static var activeNotifier: @MainActor () -> BackupNotifier = { .shared }
  /// Bonjour browsing proposes new receiver routes. Off where no real receiver exists.
  nonisolated(unsafe) static var discoversReceivers = true
  /// Reading and observing the photo library (thumbnails, change observers).
  /// Off in the catalog, so it never touches the device's real photos or prompts.
  nonisolated(unsafe) static var usesPhotoLibrary = true
  /// Stand-in pictures for photo identifiers where the photo library is not
  /// used: the catalog draws synthetic images so reviews show photos (P1).
  nonisolated(unsafe) static var sampleThumbnail: ((String) -> Image?)? = nil
  /// Asks for photo access (the system prompt when undecided); true for full or limited access.
  nonisolated(unsafe) static var requestPhotoAccess: @MainActor () async -> Bool = {
    guard usesPhotoLibrary else { return false }
    let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return access == .authorized || access == .limited
  }
  /// The current photo access, without asking.
  nonisolated(unsafe) static var photoAccess: @MainActor () -> PhotoAccess = {
    guard usesPhotoLibrary else { return .undetermined }
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized: return .full
    case .limited: return .limited
    case .notDetermined: return .undetermined
    default: return .denied
    }
  }
  /// How many photos and videos the library holds, or nil before access is granted.
  nonisolated(unsafe) static var libraryCount: @MainActor () -> Int? = {
    guard usesPhotoLibrary else { return nil }
    let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard access == .authorized || access == .limited else { return nil }
    return PHAsset.fetchAssets(with: nil).count
  }
}

/// The linked Rust library. Calls run off the main thread; the library returns
/// an owned C string that is released after copying.
struct NativeCore: CoreTransport {
  func call(_ command: String) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        guard let pointer = command.withCString({ backupduck_call($0) }) else {
          continuation.resume(throwing: Bridge.Failure(code: "internal"))
          return
        }
        let output = Data(String(cString: pointer).utf8)
        backupduck_free(pointer)
        continuation.resume(returning: output)
      }
    }
  }
}

enum PhotoAccess: String { case full, limited, denied, undetermined }

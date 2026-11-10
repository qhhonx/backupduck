import Foundation

/// One publication epoch for rebuildable thumbnails, including queued work.
/// A clear freezes publication before removing files; only work started after
/// it finishes may refill the cache. Pixel leases have their own lifetime.
final class ThumbnailCacheStorage: @unchecked Sendable {
  let directory: URL
  private let lock = NSLock()
  private let publicationLock = NSLock()
  private var version = 0
  private var clearing = false
  init(directory: URL) { self.directory = directory }
  var generation: Int { lock.lock(); defer { lock.unlock() }; return version }
  var epoch: Int? { lock.lock(); defer { lock.unlock() }; return clearing ? nil : version }
  func isCurrent(_ expected: Int) -> Bool {
    lock.lock(); defer { lock.unlock() }; return !clearing && expected == version
  }
  /// Publication may perform file I/O, but never owns the state lock that UI
  /// callers use. Clearing closes admission first, then drains admitted work.
  func withCurrent<T>(_ expected: Int, _ operation: () -> T) -> T? {
    publicationLock.lock(); defer { publicationLock.unlock() }
    guard isCurrent(expected) else { return nil }
    return operation()
  }
  private func waitForPublications() {
    publicationLock.lock(); publicationLock.unlock()
  }
  func invalidate() { lock.lock(); if !clearing { version &+= 1 }; lock.unlock() }
  func beginClear() -> Int? {
    lock.lock(); defer { lock.unlock() }
    guard !clearing else { return nil }
    version &+= 1; clearing = true
    return version
  }
  func endClear(_ expected: Int) {
    lock.lock(); defer { lock.unlock() }
    if clearing, version == expected { clearing = false }
  }
  private func managedFiles(detail: Bool = false) throws -> [URL] {
    let pattern = detail ? "^[0-9a-f]{64}\\.detail$|^[A-Za-z0-9-]+\\.detailtmp$"
      : "^(?:mac-)?(?:overview|detail)(?:-[a-z0-9]+)?-[0-9]+\\.table$"
    var info = stat()
    guard lstat(directory.path, &info) == 0 else {
      if errno == ENOENT { return [] }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTDIR))
    }
    return try FileManager.default.contentsOfDirectory(at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).filter { url in
      guard url.lastPathComponent.range(of: pattern, options: .regularExpression) != nil,
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      else { return false }
      return values.isRegularFile == true && values.isSymbolicLink != true
    }
  }
  /// Live tables include dirty mapped pixels that allocated-block counts can
  /// lag behind. Old geometries and display profiles are counted from disk.
  func tableUsage(active: [ThumbnailTable]) -> Int {
    let paths = Set(active.filter(\.available).map { $0.url.standardizedFileURL.path })
    var bytes = active.reduce(0) { $0 + $1.usage }
    for file in (try? managedFiles()) ?? [] where !paths.contains(file.standardizedFileURL.path) {
      var info = stat()
      if lstat(file.path, &info) == 0 { bytes += Int(info.st_blocks) * 512 }
    }
    return bytes
  }
  var detailUsage: Int {
    ((try? managedFiles(detail: true)) ?? []).reduce(0) { total, file in
      total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }
  /// Called after beginClear. Only recognized regular files are owned here;
  /// unrelated files and symbolic-link targets are never followed or removed.
  @discardableResult func clearTables(active: [ThumbnailTable]) -> String? {
    waitForPublications()
    let files: [URL]
    do { files = try managedFiles() }
    catch { return error.localizedDescription }
    var failure: String?
    let paths = Set(active.filter(\.available).map { $0.url.standardizedFileURL.path })
    for table in active {
      let error = table.clear(invalidatingWrites: false)
      if failure == nil { failure = error }
    }
    for file in files where !paths.contains(file.standardizedFileURL.path) {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
          if failure == nil { failure = NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription }
          continue
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
          if failure == nil { failure = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY)).localizedDescription }
          continue
        }
        var ownedFile = stat(), currentFile = stat()
        guard fstat(descriptor, &ownedFile) == 0, lstat(file.path, &currentFile) == 0,
          ownedFile.st_ino == currentFile.st_ino, ownedFile.st_dev == currentFile.st_dev else {
          if failure == nil { failure = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY)).localizedDescription }
          continue
        }
        do { try FileManager.default.removeItem(at: file) }
        catch { if failure == nil { failure = error.localizedDescription } }
    }
    return failure
  }
  @discardableResult func clearDetails() -> String? {
    waitForPublications()
    var failure: String?
    do {
      for file in try managedFiles(detail: true) {
        do { try FileManager.default.removeItem(at: file) }
        catch { if failure == nil { failure = error.localizedDescription } }
      }
    } catch { if failure == nil { failure = error.localizedDescription } }
    return failure
  }
}

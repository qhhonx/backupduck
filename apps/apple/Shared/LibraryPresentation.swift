import Foundation
import Photos

/// Each drag is applied to its starting snapshot, so reversing the finger
/// restores items outside the current range rather than toggling them again.
struct LibraryRangeSelection {
  let baseline: Set<String>
  let adding: Bool
  func applying(_ identifiers: [String]) -> Set<String> {
    adding ? baseline.union(identifiers) : baseline.subtracting(identifiers)
  }
}

/// Incremental metadata index. Presentation groups never change transfer identities.
struct LibraryPresentationIndex: Sendable {
  struct Metadata {
    let id: String
    let burst: String?
    let representative: Bool
    var key: String { burst.map { "burst:" + $0 } ?? id }
  }
  struct Row: Sendable {
    let key: String
    var rawIndex: Int
  }
  private(set) var rows: [Row] = []
  private(set) var positions: [String: Int] = [:]
  private(set) var cursor = 0

  /// Fill enough display rows, preserving a burst's first position even when its
  /// members cross a page boundary or have noncontiguous edited capture dates.
  @discardableResult mutating func load(sourceCount: Int, targetRows: Int,
    minimumCursor: Int = 0, shouldContinue: () -> Bool = { !Task.isCancelled },
    read: (Int) -> Metadata) -> Bool {
    var changedCover = false
    while cursor < sourceCount && (rows.count < targetRows || cursor < minimumCursor) && shouldContinue() {
      let item = read(cursor)
      if let position = positions[item.key] {
        if item.representative && rows[position].rawIndex != cursor {
          rows[position].rawIndex = cursor
          changedCover = true
        }
      } else {
        positions[item.key] = rows.count
        rows.append(Row(key: item.key, rawIndex: cursor))
      }
      cursor += 1
    }
    return changedCover
  }
}

struct LibrarySource: Sendable {
  let id: String
  let revision: String
}
struct LibraryGroup: Sendable {
  let sources: [LibrarySource]
  let complete: Bool
  var count: Int? { complete ? sources.count : nil }

  func state(_ states: [String: String]) -> String? {
    guard complete, !sources.isEmpty else { return nil }
    let known = sources.compactMap { states[$0.id] }
    // Unfinished members take precedence; incomplete evidence never means saved.
    for state in ["needs_you", "sending", "saving"] {
      if known.contains(state) { return state }
    }
    return known.count == sources.count && known.allSatisfy { $0 == "saved" } ? "saved" : nil
  }
}

extension LibraryPresentationIndex {
  /// Reads every remaining item with one bulk enumeration. Overview mosaics need
  /// the whole library; per-object access faults each asset individually.
  mutating func loadRemaining(_ fetch: PHFetchResult<PHAsset>) {
    let start = cursor, total = fetch.count
    guard start < total else { return }
    var items: [Metadata] = []
    items.reserveCapacity(total - start)
    fetch.enumerateObjects(at: IndexSet(integersIn: start..<total), options: []) { asset, _, stop in
      if Task.isCancelled { stop.pointee = true; return }
      items.append(Metadata(id: asset.localIdentifier, burst: asset.burstIdentifier, representative: asset.representsBurst))
    }
    guard items.count == total - start else { return }
    load(sourceCount: total, targetRows: .max, minimumCursor: total) { items[$0 - start] }
  }
  @discardableResult mutating func load(_ fetch: PHFetchResult<PHAsset>, targetRows: Int,
    minimumCursor: Int = 0) -> Bool {
    load(sourceCount: fetch.count, targetRows: targetRows, minimumCursor: minimumCursor) { index in
      let asset = fetch.object(at: index)
      return Metadata(id: asset.localIdentifier, burst: asset.burstIdentifier,
        representative: asset.representsBurst)
    }
  }
}

/// V5: publication and receipt are different facts; unknown carries no mark.
func libraryTileSymbol(_ state: String?) -> String? {
  switch state {
  case "sending": "arrow.up"
  case "saving": "clock"
  case "needs_you": "exclamationmark.triangle.fill"
  default: nil
  }
}
func libraryTileAccessibilityKey(_ state: String?) -> String {
  switch state {
  case "sending": "state_running"
  case "saving": "state_publication_pending"
  case "saved": "state_published"
  case "needs_you": "state_failed"
  default: ""
  }
}

struct LibrarySourceObservation: Decodable {
  let revision: String?
  let preparing: Bool
  let tile_state: String

  func currentState(for source: LibrarySource) -> String? {
    guard revision == source.revision || (revision == nil && preparing),
      ["sending", "saving", "saved", "needs_you"].contains(tile_state) else { return nil }
    return tile_state
  }
}

/// Presentation-only snapshot; Rust still owns all state decisions and work.
@MainActor final class LibrarySourceStateCache {
  var receiver: String?
  var revision = ""
  var observations: [String: LibrarySourceObservation]?
}

@MainActor func librarySourceStates(_ groups: [String: LibraryGroup], receiver: String?,
  cache: LibrarySourceStateCache, revision: String) async -> [String: String]? {
  guard let receiver else { return [:] }
  guard !Task.isCancelled else { return nil }
  // Fetch once per observed core/preparation revision, not once per scroll window.
  if cache.receiver != receiver || cache.revision != revision || cache.observations == nil {
    guard let data = try? await Bridge.call(["op": "library_source_states", "receiver_id": receiver]),
      let observations = try? JSONDecoder().decode([String: LibrarySourceObservation].self, from: data),
      !Task.isCancelled else { return nil }
    cache.receiver = receiver
    cache.revision = revision
    cache.observations = observations
  }
  guard let observations = cache.observations else { return nil }
  var states: [String: String] = [:]
  for group in groups.values {
    for source in group.sources {
      states[source.id] = observations[source.id]?.currentState(for: source)
    }
  }
  return states
}

/// A lightweight cover index over real capture dates. Transfer and preview
/// identity remain asset/burst tokens; calendar periods never become sources.
struct LibraryCalendarPeriod: Identifiable, Sendable {
  let id: String
  let date: Date?
  let title: String
  var tokens: [String]
  var covers: [Int]
}
struct LibraryCalendarIndex {
  private(set) var years: [LibraryCalendarPeriod] = []
  private(set) var months: [LibraryCalendarPeriod] = []
  private var yearPositions: [String: Int] = [:]
  private var monthPositions: [String: Int] = [:]
  private var sampledDays: [String: Set<Date>] = [:]
  private var bursts = Set<String>()
  var calendar: Calendar
  init(calendar: Calendar = .current) { self.calendar = calendar }
  mutating func append(id: String, burst: String?, date: Date?, rawIndex: Int) {
    if let burst, !bursts.insert(burst).inserted { return }
    let token = burst.map { "burst:" + $0 } ?? id
    let year = date.flatMap { calendar.dateInterval(of: .year, for: $0)?.start }
    let month = date.flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
    let yKey = year.map { String($0.timeIntervalSince1970) } ?? "unknown"
    let mKey = month.map { String($0.timeIntervalSince1970) } ?? "unknown"
    let unknown = NSLocalizedString("design_capture_unknown", comment: "")
    if yearPositions[yKey] == nil {
      yearPositions[yKey] = years.count
      years.append(LibraryCalendarPeriod(id: "year:" + yKey,date: year,
        title: year?.formatted(.dateTime.year()) ?? unknown,tokens: [token],covers: [rawIndex]))
    }
    if monthPositions[mKey] == nil {
      monthPositions[mKey] = months.count
      months.append(LibraryCalendarPeriod(id: "month:" + mKey,date: month,
        title: month?.formatted(.dateTime.year().month(.wide)) ?? unknown,tokens: [],covers: []))
    }
    guard let position = monthPositions[mKey], months[position].covers.count < 6 else { return }
    if let date {
      guard sampledDays[mKey,default: []].insert(calendar.startOfDay(for: date)).inserted else { return }
    } else if !months[position].covers.isEmpty { return }
    months[position].tokens.append(token); months[position].covers.append(rawIndex)
  }
}

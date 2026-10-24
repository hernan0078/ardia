import Foundation

final class CompanionSync {
  static let appScope = "app"
  static let keptPrefixes = ["prof:", "pth:", "dev:", "porder:", "pin:", "pinrow:", "tabs:"]
  static let tabsInterval: TimeInterval = 60
  static let maxSharedTabs = 30
  static let outboxLifetime: TimeInterval = 30 * 86_400
  static let folderWait: TimeInterval = 86_400
  static func keeps(_ key: String) -> Bool { keptPrefixes.contains { key.hasPrefix($0) } }

  let store: SharedStore
  private var cache: [String: [String: [String: Any]]] = [:]
  private let cancelLock = NSLock()
  private var cancelled = false

  func cancel() { cancelLock.withLock { cancelled = true } }
  func resume() { cancelLock.withLock { cancelled = false } }
  private func checkCancelled() throws {
    if cancelLock.withLock({ cancelled }) { throw CancellationError() }
  }

  init(store: SharedStore = .shared) {
    self.store = store
  }

  static func profileScope(_ spaceId: String) -> String { "p:\(spaceId)" }

  var isConnected: Bool { store.loadState() != nil && store.loadKey() != nil }

  static func entropy(fromPhrase text: String) throws -> Data {
    do {
      return try RecoveryPhrase.entropy(from: text)
    } catch RecoveryPhrase.Problem.wordCount(let n) {
      throw CompanionError.phrase(n > RecoveryPhrase.wordCount ? "Too many words. The recovery phrase has 24." : "Recovery phrase must be exactly 24 words (\(n)/24).")
    } catch RecoveryPhrase.Problem.unknownWord(let word) {
      throw CompanionError.phrase("“\(word)” is not a valid recovery phrase word.")
    } catch {
      throw CompanionError.phrase("This recovery phrase is not valid. Please check for typos.")
    }
  }

  func connect(phrase: String, deviceName: String) throws -> DesktopSnapshot {
    let entropy = try Self.entropy(fromPhrase: phrase)
    let keys = SyncKeys(entropy: entropy)
    try store.withFolder { folder in
      let vault = SyncVault(folder: folder, keys: keys)
      guard vault.chainExists() else {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        throw names.contains(where: { Base32.isTag($0) }) ? CompanionError.phraseMismatch : CompanionError.noSyncData
      }
    }
    let name = Self.cleanName(deviceName)
    let saved = try store.withLock { () -> Bool in
      if let existing = store.loadState(), store.loadKey() == entropy { return store.saveState(existing) }
      guard store.saveKey(entropy) else { return false }
      return store.saveState(CompanionState(deviceId: SyncKeys.newFileId(), deviceName: name))
    }
    guard saved else { throw CompanionError.keychain }
    cache = [:]
    return try sync()
  }

  func disconnect(force: Bool = false) throws {
    do {
      try store.withLock {
        try session { vault, state in
          var ops: [String: [[String: Any]]] = [Self.appScope: [op(&state, "dev:\(state.deviceId)", nil), op(&state, "porder:\(state.deviceId)", nil)]]
          if let scope = state.publishedTabsScope { ops[scope, default: []].append(op(&state, "tabs:\(state.deviceId)", nil)) }
          for (scope, list) in ops { try journal(list, to: scope, state: &state) }
          try flushJournal(vault: vault, state: &state)
        }
      }
    } catch {
      if !force { throw error }
    }
    try store.withLock {
      store.saveState(nil)
      store.saveOutbox([])
      store.saveSnapshot(nil)
    }
    store.deleteKey()
    cache = [:]
  }

  static func cleanName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "iPhone" : String(trimmed.prefix(60))
  }

  func rename(_ name: String) {
    _ = try? store.withLock {
      guard var state = store.loadState() else { return }
      state.deviceName = Self.cleanName(name)
      store.saveState(state)
    }
  }

  @discardableResult
  func sync(openTabs: [SharedLink]? = nil, shareTabs: Bool = true, forceTabs: Bool = false) throws -> DesktopSnapshot {
    try store.withLock { try cycle(openTabs: openTabs, shareTabs: shareTabs, forceTabs: forceTabs) }
  }

  func syncIfIdle() throws -> DesktopSnapshot? {
    try store.withLockIfFree { try cycle(openTabs: nil, shareTabs: true, forceTabs: false) }
  }

  private func cycle(openTabs: [SharedLink]?, shareTabs: Bool, forceTabs: Bool) throws -> DesktopSnapshot {
    try session { vault, state in
      try flushJournal(vault: vault, state: &state)
      var snapshot = try readSnapshot(vault: vault, state: &state)
      if state.publishedDeviceName != state.deviceName {
        try append([op(&state, "dev:\(state.deviceId)", ["n": state.deviceName])], to: Self.appScope, vault: vault, state: &state)
        state.publishedDeviceName = state.deviceName
      }
      try flushOutbox(vault: vault, state: &state, snapshot: &snapshot)
      if !shareTabs {
        try retractTabs(vault: vault, state: &state)
      } else if let openTabs {
        try publishTabs(openTabs, force: forceTabs, vault: vault, state: &state, snapshot: snapshot)
      }
      snapshot.updatedAt = Date()
      store.saveSnapshot(snapshot)
      return snapshot
    }
  }

  private func session<T>(_ body: (SyncVault, inout CompanionState) throws -> T) throws -> T {
    guard var state = store.loadState(), let entropy = store.loadKey() else { throw CompanionError.notConnected }
    return try store.withFolder { folder in
      let vault = SyncVault(folder: folder, keys: SyncKeys(entropy: entropy))
      guard vault.chainExists() else { throw CompanionError.phraseMismatch }
      defer { store.saveState(state) }
      return try body(vault, &state)
    }
  }

  private func op(_ state: inout CompanionState, _ key: String, _ value: Any?) -> [String: Any] {
    var clock = HybridClock(device: state.deviceId, last: state.clock)
    let h = clock.tick()
    state.clock = clock.last
    return ["k": key, "h": h, "v": value ?? NSNull()]
  }

  private func append(_ ops: [[String: Any]], to scope: String, vault: SyncVault, state: inout CompanionState) throws {
    try journal(ops, to: scope, state: &state)
    try flushJournal(vault: vault, state: &state)
  }

  private func journal(_ ops: [[String: Any]], to scope: String, state: inout CompanionState, outboxIds: [String] = []) throws {
    guard !ops.isEmpty else { return }
    let seq = max(state.seqs[scope] ?? 0, state.ownSeqs?[scope] ?? 0, state.journal[scope]?.last?.seq ?? 0) + 1
    let file: [String: Any] = ["v": 1, "kind": "log", "device": state.deviceId, "seq": seq, "at": HybridClock.wallNow(), "ops": ops]
    let payload = String(decoding: try JSONSerialization.data(withJSONObject: file, options: [.sortedKeys]), as: UTF8.self)
    let marked = state.journaledOutbox
    state.journal[scope, default: []].append(JournalEntry(seq: seq, payload: payload))
    if !outboxIds.isEmpty { state.journaledOutbox = (marked ?? []) + outboxIds }
    guard store.saveState(state) else {
      state.journal[scope]?.removeLast()
      state.journaledOutbox = marked
      throw CompanionError.stateNotSaved
    }
  }

  private func flushJournal(vault: SyncVault, state: inout CompanionState) throws {
    for scope in state.journal.keys.sorted() {
      while let entry = state.journal[scope]?.first {
        try checkCancelled()
        let id = try vault.write(scope: scope, payload: Data(entry.payload.utf8))
        if let file = try? JSONSerialization.jsonObject(with: Data(entry.payload.utf8)) as? [String: Any] {
          cache[scope, default: [:]][id] = Replica.slim(file, keeping: Self.keeps)
        }
        state.seqs[scope] = entry.seq
        state.journal[scope]?.removeFirst()
        store.saveState(state)
      }
      state.journal[scope] = nil
    }
  }

  private func files(in scope: String, vault: SyncVault) -> (files: [[String: Any]], pending: Int) {
    var known = cache[scope] ?? [:]
    let listing = vault.read(scope: scope, skipping: Set(known.keys))
    for file in listing.files {
      if let json = try? JSONSerialization.jsonObject(with: file.payload) as? [String: Any], json["v"] as? Int == 1 {
        known[file.id] = Replica.slim(json, keeping: Self.keeps)
      }
    }
    let present = Set(listing.present)
    known = known.filter { present.contains($0.key) }
    cache[scope] = known
    return (Array(known.values), listing.pending.count)
  }

  private func replica(_ scope: String, vault: SyncVault, state: inout CompanionState, pending: inout Int) throws -> Replica {
    try checkCancelled()
    let read = files(in: scope, vault: vault)
    pending += read.pending
    var clock = HybridClock(device: state.deviceId, last: state.clock)
    var replica = Replica(keeping: Self.keeps)
    replica.ingest(read.files, clock: &clock)
    state.clock = clock.last
    let own = replica.highestSeq(of: state.deviceId)
    if own > (state.ownSeqs?[scope] ?? 0) { state.ownSeqs = (state.ownSeqs ?? [:]).merging([scope: own]) { max($0, $1) } }
    return replica
  }

  private func readSnapshot(vault: SyncVault, state: inout CompanionState) throws -> DesktopSnapshot {
    var pending = 0
    let app = try replica(Self.appScope, vault: vault, state: &state, pending: &pending)
    var snapshot = DesktopSnapshot()
    var seen: [String: Int64] = app.seen
    var names: [String: String] = [:]
    for (key, value) in app.visible("dev:") {
      names[String(key.dropFirst(4))] = (value as? [String: Any])?["n"] as? String
    }
    for (key, value) in app.visible("prof:") {
      guard let record = value as? [String: Any] else { continue }
      let id = String(key.dropFirst(5))
      var space = DesktopSpace(
        id: id,
        name: record["n"] as? String ?? "Space",
        color: record["c"] as? String ?? "plum",
        icon: record["i"] as? String,
        isDefault: record["d"] as? Bool ?? false,
        accentHex: Self.accent(fromTheme: app.value("pth:\(id)"))
      )
      let scope = Self.profileScope(id)
      let profile = try replica(scope, vault: vault, state: &state, pending: &pending)
      seen.merge(profile.seen) { max($0, $1) }
      Self.fill(&space, from: profile, names: names, me: state.deviceId)
      snapshot.spaces.append(space)
    }
    snapshot.spaces = Self.ordered(snapshot.spaces, by: Self.macOrder(in: app, seen: seen, me: state.deviceId))
    snapshot.devices = names.filter { $0.key != state.deviceId }.map { id, name in
      DesktopDevice(id: id, name: name, lastSeen: seen[id].map { Date(timeIntervalSince1970: Double($0) / 1000) })
    }.sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
    snapshot.waitingForDownloads = pending
    return snapshot
  }

  static func macOrder(in app: Replica, seen: [String: Int64], me: String) -> [String] {
    let orders = app.visible("porder:").compactMap { key, value -> (device: String, order: [String])? in
      let device = String(key.dropFirst(7))
      guard device != me, let order = (value as? [String: Any])?["o"] as? [String] else { return nil }
      return (device, order)
    }
    return orders.max {
      let a = seen[$0.device] ?? 0
      let b = seen[$1.device] ?? 0
      return a == b ? $0.device < $1.device : a < b
    }?.order ?? []
  }

  static func ordered(_ spaces: [DesktopSpace], by order: [String]) -> [DesktopSpace] {
    let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return spaces.sorted { a, b in
      switch (rank[a.id], rank[b.id]) {
      case let (x?, y?): return x < y
      case (_?, nil): return true
      case (nil, _?): return false
      default: return a.isDefault != b.isDefault ? a.isDefault : a.name.localizedStandardCompare(b.name) == .orderedAscending
      }
    }
  }

  static func fill(_ space: inout DesktopSpace, from replica: Replica, names: [String: String], me: String) {
    let rows = Set(replica.visible("pinrow:").filter { ($0.value as? NSNumber)?.intValue == 1 }.map { String($0.key.dropFirst(7)) })
    var folders: [String: DesktopFolder] = [:]
    for (key, value) in replica.visible("pin:g:") {
      guard let v = value as? [String: Any] else { continue }
      let id = String(key.dropFirst(6))
      folders[id] = DesktopFolder(id: id, name: v["n"] as? String ?? "Folder", icon: v["i"] as? String, color: v["c"] as? String, position: v["pos"] as? String ?? "", pins: [])
    }
    var loose: [DesktopPin] = []
    for (key, value) in replica.visible("pin:t:") {
      guard let v = value as? [String: Any] else { continue }
      let id = String(key.dropFirst(6))
      let custom = v["t"] as? String
      let pin = DesktopPin(
        id: id,
        url: v["u"] as? String ?? "",
        title: (custom?.isEmpty == false ? custom : nil) ?? v["ti"] as? String ?? "",
        customIcon: v["i"] as? String,
        folderId: v["g"] as? String,
        position: v["pos"] as? String ?? "",
        isRow: rows.contains(id)
      )
      if let g = pin.folderId, folders[g] != nil {
        folders[g]!.pins.append(pin)
      } else {
        loose.append(pin)
      }
    }
    let byPosition = { (a: DesktopPin, b: DesktopPin) in a.position == b.position ? a.id < b.id : a.position < b.position }
    loose.sort(by: byPosition)
    space.tiles = loose.filter { !$0.isRow }
    space.rows = loose.filter(\.isRow)
    space.folders = folders.values.map { folder in
      var f = folder
      f.pins.sort(by: byPosition)
      return f
    }.sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
    space.deviceTabs = replica.visible("tabs:").compactMap { key, value in
      let device = String(key.dropFirst(5))
      guard device != me, let v = value as? [String: Any] else { return nil }
      let tabs = (v["tabs"] as? [[String: Any]] ?? []).compactMap { t -> SharedLink? in
        guard let u = t["u"] as? String else { return nil }
        return SharedLink(url: u, title: t["t"] as? String ?? "")
      }
      return DesktopDeviceTabs(id: device, name: names[device] ?? v["n"] as? String ?? "Mac", tabs: tabs)
    }.sorted { $0.name < $1.name }
  }

  static func accent(fromTheme raw: Any?) -> String? {
    guard let record = raw as? [String: Any], let theme = record["t"] as? [String: Any],
          let stops = theme["stops"] as? [[String: Any]], let color = stops.first?["color"] as? [String: Any] else { return nil }
    let channels = ["r", "g", "b"].map { (color[$0] as? NSNumber)?.doubleValue ?? 0 }
    let scale = channels.contains { $0 > 1 } ? 1.0 : 255.0
    return "#" + channels.map { String(format: "%02X", Int(max(0, min(255, ($0 * scale).rounded())))) }.joined()
  }

  private func flushOutbox(vault: SyncVault, state: inout CompanionState, snapshot: inout DesktopSnapshot) throws {
    let done = Set(state.journaledOutbox ?? [])
    var outbox = store.loadOutbox()
    if !done.isEmpty {
      outbox.removeAll { done.contains($0.id) }
      store.saveOutbox(outbox)
      state.journaledOutbox = nil
      store.saveState(state)
    }
    guard !outbox.isEmpty else { return }
    let now = Date()
    var left: [OutboxItem] = []
    for (spaceId, items) in Dictionary(grouping: outbox, by: \.spaceId) {
      guard let index = snapshot.spaces.firstIndex(where: { $0.id == spaceId }) else {
        left += items
        continue
      }
      var space = snapshot.spaces[index]
      var ops: [[String: Any]] = []
      var sent: [String] = []
      for item in items {
        switch item {
        case .pin(let pin):
          let folder = pin.folderId.flatMap { id in space.folders.firstIndex { $0.id == id } }
          if pin.folderId != nil, folder == nil, snapshot.waitingForDownloads > 0, now.timeIntervalSince(pin.createdAt) < Self.folderWait {
            left.append(item)
            continue
          }
          let asRow = pin.asRow && folder == nil
          let position = Self.position(in: space, folder: folder, asRow: asRow)
          ops.append(op(&state, "pin:t:\(pin.id)", [
            "g": folder.map { space.folders[$0].id } ?? NSNull(), "u": pin.url, "t": NSNull(), "i": NSNull(), "ti": pin.title, "pos": position,
          ] as [String: Any]))
          if asRow { ops.append(op(&state, "pinrow:\(pin.id)", 1)) }
          let added = DesktopPin(id: pin.id, url: pin.url, title: pin.title, folderId: folder.map { space.folders[$0].id }, position: position, isRow: asRow)
          if let folder {
            space.folders[folder].pins.append(added)
          } else if asRow {
            space.rows.append(added)
          } else {
            space.tiles.append(added)
          }
        case .unpin(let request):
          ops.append(op(&state, "pin:t:\(request.pinId)", nil))
          ops.append(op(&state, "pinrow:\(request.pinId)", nil))
          space.tiles.removeAll { $0.id == request.pinId }
          space.rows.removeAll { $0.id == request.pinId }
          for f in space.folders.indices { space.folders[f].pins.removeAll { $0.id == request.pinId } }
        }
        sent.append(item.id)
      }
      try journal(ops, to: Self.profileScope(spaceId), state: &state, outboxIds: sent)
      snapshot.spaces[index] = space
    }
    store.saveOutbox(left.filter { item in
      item.createdAt.map { now.timeIntervalSince($0) < Self.outboxLifetime } ?? true
    })
    state.journaledOutbox = nil
    store.saveState(state)
    try flushJournal(vault: vault, state: &state)
  }

  static func position(in space: DesktopSpace, folder: Int?, asRow: Bool) -> String {
    if let folder { return FractionalPosition.after(space.folders[folder].pins.map(\.position)) }
    let valid = { (p: String) in !p.isEmpty && !p.hasSuffix("0") }
    let all = (space.tiles + space.rows).map(\.position)
    if asRow { return FractionalPosition.after(all) }
    let lastTile = space.tiles.map(\.position).filter(valid).max() ?? ""
    guard let firstRow = space.rows.map(\.position).filter(valid).min() else { return FractionalPosition.after(all) }
    return lastTile < firstRow ? FractionalPosition.between(lastTile, firstRow) : FractionalPosition.after(all)
  }

  private func publishTabs(_ tabs: [SharedLink], force: Bool, vault: SyncVault, state: inout CompanionState, snapshot: DesktopSnapshot) throws {
    guard let target = snapshot.defaultSpace.map({ Self.profileScope($0.id) }) else { return }
    let list = Array(tabs.filter { SharedLink.isWeb($0.url) }.prefix(Self.maxSharedTabs))
    let due = force || (state.publishedTabsAt.map { Date().timeIntervalSince($0) > Self.tabsInterval } ?? true)
    guard due, list != state.publishedTabs || target != state.publishedTabsScope else { return }
    if let old = state.publishedTabsScope, old != target {
      try append([op(&state, "tabs:\(state.deviceId)", nil)], to: old, vault: vault, state: &state)
    }
    let value: [String: Any] = ["n": state.deviceName, "tabs": list.map { ["u": $0.url, "t": $0.title] }]
    try append([op(&state, "tabs:\(state.deviceId)", value)], to: target, vault: vault, state: &state)
    state.publishedTabs = list
    state.publishedTabsScope = target
    state.publishedTabsAt = Date()
  }

  private func retractTabs(vault: SyncVault, state: inout CompanionState) throws {
    guard let scope = state.publishedTabsScope else { return }
    try append([op(&state, "tabs:\(state.deviceId)", nil)], to: scope, vault: vault, state: &state)
    state.publishedTabs = nil
    state.publishedTabsScope = nil
    state.publishedTabsAt = nil
  }
}

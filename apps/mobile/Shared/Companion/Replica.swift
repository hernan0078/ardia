import Foundation

struct SyncRecord {
  var h: String
  var v: Any?
  var origin: (device: String, seq: Int)
}

struct Replica {
  var records: [String: SyncRecord] = [:]
  var vv: [String: Int] = [:]
  var extra: [String: Set<Int>] = [:]
  var seen: [String: Int64] = [:]
  let keeps: (String) -> Bool

  init(keeping keeps: @escaping (String) -> Bool) {
    self.keeps = keeps
  }

  func covered(_ vv: [String: Int], _ device: String, _ seq: Int) -> Bool { (vv[device] ?? 0) >= seq }

  func isApplied(_ device: String, _ seq: Int) -> Bool {
    covered(vv, device, seq) || (extra[device]?.contains(seq) ?? false)
  }

  mutating func markApplied(_ device: String, _ seq: Int) {
    if covered(vv, device, seq) { return }
    var pending = extra[device] ?? []
    pending.insert(seq)
    var top = vv[device] ?? 0
    while pending.remove(top + 1) != nil { top += 1 }
    vv[device] = top
    extra[device] = pending.isEmpty ? nil : pending
  }

  mutating func see(_ device: String, _ at: Int64) {
    if let known = seen[device], known >= at { return }
    seen[device] = at
  }

  @discardableResult
  mutating func merge(_ key: String, _ record: SyncRecord, clock: inout HybridClock) -> Bool {
    clock.observe(record.h)
    guard keeps(key) else { return false }
    if let current = records[key], current.h >= record.h { return false }
    records[key] = record
    return true
  }

  mutating func ingest(_ files: [[String: Any]], clock: inout HybridClock) {
    for file in files { if let newest = file["maxh"] as? String { clock.observe(newest) } }
    let snapshots = files.filter { $0["kind"] as? String == "snapshot" }
    let logs = files.filter { $0["kind"] as? String == "log" }
    for file in snapshots { ingestSnapshot(file, clock: &clock) }
    for file in logs { ingestLog(file, clock: &clock) }
  }

  mutating func ingestLog(_ file: [String: Any], clock: inout HybridClock) {
    guard let device = file["device"] as? String, let seq = Self.int(file["seq"]) else { return }
    see(device, Self.int64(file["at"]) ?? 0)
    if isApplied(device, seq) { return }
    for op in file["ops"] as? [[String: Any]] ?? [] {
      guard let key = op["k"] as? String, let h = op["h"] as? String else { continue }
      merge(key, SyncRecord(h: h, v: Self.value(op["v"]), origin: (device, seq)), clock: &clock)
    }
    markApplied(device, seq)
  }

  mutating func ingestSnapshot(_ file: [String: Any], clock: inout HybridClock) {
    for (device, at) in file["seen"] as? [String: Any] ?? [:] { see(device, Self.int64(at) ?? 0) }
    if let device = file["device"] as? String { see(device, Self.int64(file["at"]) ?? 0) }
    let fileRecords = file["records"] as? [String: [String: Any]] ?? [:]
    let fileVV = (file["vv"] as? [String: Any] ?? [:]).compactMapValues(Self.int)
    for (key, raw) in fileRecords {
      guard let h = raw["h"] as? String, let o = raw["o"] as? [Any], o.count == 2,
            let device = o[0] as? String, let seq = Self.int(o[1]) else { continue }
      if records[key] == nil, isApplied(device, seq) {
        clock.observe(h)
        continue
      }
      merge(key, SyncRecord(h: h, v: Self.value(raw["v"]), origin: (device, seq)), clock: &clock)
    }
    for (key, record) in records where fileRecords[key] == nil && covered(fileVV, record.origin.device, record.origin.seq) {
      records[key] = nil
    }
    for (device, seq) in fileVV where seq > (vv[device] ?? 0) {
      vv[device] = seq
      var later = (extra[device] ?? []).filter { $0 > seq }
      var top = seq
      while later.remove(top + 1) != nil { top += 1 }
      vv[device] = top
      extra[device] = later.isEmpty ? nil : later
    }
  }

  func visible(_ prefix: String) -> [(key: String, value: Any)] {
    records.compactMap { key, record in
      guard key.hasPrefix(prefix), let v = record.v else { return nil }
      return (key, v)
    }
  }

  func value(_ key: String) -> Any? { records[key]?.v }

  func highestSeq(of device: String) -> Int {
    max(vv[device] ?? 0, extra[device]?.max() ?? 0)
  }

  static func slim(_ file: [String: Any], keeping keeps: (String) -> Bool) -> [String: Any] {
    var out = file
    var newest = ""
    if let ops = file["ops"] as? [[String: Any]] {
      for op in ops { if let h = op["h"] as? String, h > newest { newest = h } }
      out["ops"] = ops.filter { ($0["k"] as? String).map(keeps) ?? false }
    }
    if let records = file["records"] as? [String: [String: Any]] {
      for record in records.values { if let h = record["h"] as? String, h > newest { newest = h } }
      out["records"] = records.filter { keeps($0.key) }
    }
    if !newest.isEmpty { out["maxh"] = newest }
    return out
  }

  static func value(_ raw: Any?) -> Any? {
    guard let raw, !(raw is NSNull) else { return nil }
    return raw
  }

  static func int(_ raw: Any?) -> Int? {
    if let n = raw as? NSNumber { return n.intValue }
    return nil
  }

  static func int64(_ raw: Any?) -> Int64? {
    if let n = raw as? NSNumber { return n.int64Value }
    return nil
  }
}

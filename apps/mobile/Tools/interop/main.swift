import Foundation

let args = CommandLine.arguments
func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}
guard args.count >= 4 else { fail("usage: interop seed|phone-pin|dump <folder> <phrase-file> [scope]") }
let command = args[1]
let folder = URL(fileURLWithPath: args[2], isDirectory: true)
let phrase = (try? String(contentsOfFile: args[3], encoding: .utf8)) ?? ""

func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }

switch command {
case "new-phrase":
  let words = RecoveryPhrase.words(for: RecoveryPhrase.generateEntropy())
  try! words.joined(separator: " ").write(toFile: args[3], atomically: true, encoding: .utf8)
case "seed":
  let keys = SyncKeys(entropy: try! RecoveryPhrase.entropy(from: phrase))
  let vault = SyncVault(folder: folder, keys: keys)
  try! vault.createChain()
  let mac = "macdeviceaaaaaaaaaaaaaaaaa"
  var counter = 0
  func h() -> String {
    counter += 1
    return HybridClock.format(wall: HybridClock.wallNow() - 60_000, counter: counter, device: mac)
  }
  let now = HybridClock.wallNow()
  try! vault.write(scope: "app", payload: json(["v": 1, "kind": "log", "device": mac, "seq": 1, "at": now, "ops": [
    ["k": "prof:personalsync", "h": h(), "v": ["n": "Personal", "c": "plum", "i": NSNull(), "d": true]],
    ["k": "prof:worksync", "h": h(), "v": ["n": "Work", "c": "blue", "i": "symbol:briefcase.fill"]],
    ["k": "dev:\(mac)", "h": h(), "v": ["n": "Hernan’s MacBook Pro"]],
    ["k": "porder:\(mac)", "h": h(), "v": ["o": ["worksync", "personalsync"]]],
  ]]))
  try! vault.write(scope: "p:worksync", payload: json(["v": 1, "kind": "snapshot", "device": mac, "at": now, "vv": [mac: 1], "seen": [mac: now], "records": [
    "pin:t:tab-1": ["h": h(), "o": [mac, 1], "v": ["g": NSNull(), "u": "https://github.com", "t": NSNull(), "i": NSNull(), "ti": "GitHub", "pos": "V"]],
    "pin:t:tab-2": ["h": h(), "o": [mac, 1], "v": ["g": NSNull(), "u": "https://linear.app", "t": "Linear", "i": NSNull(), "ti": "Linear – Inbox", "pos": "k"]],
    "pinrow:tab-2": ["h": h(), "o": [mac, 1], "v": 1],
    "pin:g:grp-1": ["h": h(), "o": [mac, 1], "v": ["n": "Tools", "i": NSNull(), "c": "blue", "pos": "V"]],
    "pin:t:tab-3": ["h": h(), "o": [mac, 1], "v": ["g": "grp-1", "u": "https://figma.com", "t": NSNull(), "i": NSNull(), "ti": "Figma", "pos": "V"]],
    "h:https://example.com/": ["h": h(), "o": [mac, 1], "v": ["t": "Example", "n": 1, "vt": [now]]],
  ]]))
  try! vault.write(scope: "p:worksync", payload: json(["v": 1, "kind": "log", "device": mac, "seq": 2, "at": now, "ops": [
    ["k": "tabs:\(mac)", "h": h(), "v": ["n": "Hernan’s MacBook Pro", "tabs": [["u": "https://news.ycombinator.com", "t": "Hacker News"]]]],
  ]]))
  try! vault.write(scope: "p:personalsync", payload: json(["v": 1, "kind": "log", "device": mac, "seq": 1, "at": now, "ops": [
    ["k": "pin:t:tab-9", "h": h(), "v": ["g": NSNull(), "u": "https://www.youtube.com", "t": NSNull(), "i": NSNull(), "ti": "YouTube", "pos": "V"]],
  ]]))
  print("seeded \(vault.chainURL.path)")
case "phone-pin":
  SharedStore.shared.folderPathOverride = folder.path
  let sync = CompanionSync()
  do {
    let first = try sync.connect(phrase: phrase, deviceName: "Hernan’s iPhone")
    guard first.spaces.map(\.name) == ["Work", "Personal"] else { fail("spaces aren't in the Mac's order: \(first.spaces.map(\.name))") }
    print("spaces:", first.spaces.map { "\($0.name)[\($0.pinCount) pins, tabs from \($0.deviceTabs.map { $0.name })]" })
    let work = first.spaces.first { $0.name == "Work" }!
    SharedStore.shared.enqueue(.pin(PinRequest(id: "tab-mphonepin000001", url: "https://x.com/ardia/status/1", title: "A post on X", spaceId: work.id, asRow: true, createdAt: Date())))
    SharedStore.shared.enqueue(.pin(PinRequest(id: "tab-mphonepin000003", url: "https://ardia.dev", title: "Ardia", spaceId: work.id, asRow: false, createdAt: Date())))
    SharedStore.shared.enqueue(.pin(PinRequest(id: "tab-mphonepin000002", url: "https://developer.apple.com", title: "Apple Developer", spaceId: work.id, folderId: "grp-1", asRow: false, createdAt: Date())))
    let after = try sync.sync(openTabs: [SharedLink(url: "https://ardia.dev", title: "Ardia")], forceTabs: true)
    let w = after.space(work.id)!
    print("work rows:", w.rows.map { "\($0.title)@\($0.position)" }, "tiles:", w.tiles.map { "\($0.title)@\($0.position)" }, "folder:", w.folders.first!.pins.map { "\($0.title)@\($0.position)" })
    var rolledBack = SharedStore.shared.loadState()!
    rolledBack.seqs = [:]
    rolledBack.ownSeqs = nil
    SharedStore.shared.saveState(rolledBack)
    SharedStore.shared.enqueue(.pin(PinRequest(id: "tab-mphonepin000004", url: "https://example.org/after-restore", title: "After a restore", spaceId: work.id, asRow: true, createdAt: Date())))
    let fresh = try CompanionSync().sync()
    print("re-read rows:", fresh.space(work.id)!.rows.map(\.title), "devices:", fresh.devices.map(\.name))
  } catch {
    fail("phone-pin failed: \(error)")
  }
case "dump":
  let keys = SyncKeys(entropy: try! RecoveryPhrase.entropy(from: phrase))
  let listing = SyncVault(folder: folder, keys: keys).read(scope: args[4], skipping: [])
  let out: [String: Any] = [
    "files": listing.files.map { ["id": $0.id, "payload": String(decoding: $0.payload, as: UTF8.self)] },
    "pending": listing.pending, "damaged": [] as [Any], "present": listing.present,
  ]
  FileHandle.standardOutput.write(json(out))
default:
  fail("unknown command")
}

import Foundation
import Security

enum AppGroup {
  static var identifier: String {
    Bundle.main.object(forInfoDictionaryKey: "ArdiaAppGroup") as? String ?? "group.dev.ardia.mobile"
  }

  static var container: URL {
    if let dir = ProcessInfo.processInfo.environment["ARDIA_COMPANION_DIR"] {
      return URL(fileURLWithPath: dir, isDirectory: true)
    }
    let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shared", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

struct CompanionState: Codable {
  var deviceId: String
  var deviceName: String
  var clock: String?
  var seqs: [String: Int] = [:]
  var journal: [String: [JournalEntry]] = [:]
  var publishedDeviceName: String?
  var publishedTabs: [SharedLink]?
  var publishedTabsScope: String?
  var publishedTabsAt: Date?
  var ownSeqs: [String: Int]?
  var journaledOutbox: [String]?
}

struct JournalEntry: Codable {
  var seq: Int
  var payload: String
}

final class SharedStore {
  static let shared = SharedStore()

  private let root = AppGroup.container
  private var stateURL: URL { root.appendingPathComponent("companion-state.json") }
  private var outboxURL: URL { root.appendingPathComponent("outbox.json") }
  private var snapshotURL: URL { root.appendingPathComponent("desktop-snapshot.json") }
  private var lockURL: URL { root.appendingPathComponent("sync.lock") }
  private var fallbackKeyURL: URL { root.appendingPathComponent(".sync-key") }

  func withLock<T>(_ body: () throws -> T) throws -> T {
    let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw CompanionError.lockUnavailable }
    defer { close(fd) }
    var locked = flock(fd, LOCK_EX)
    while locked != 0, errno == EINTR { locked = flock(fd, LOCK_EX) }
    guard locked == 0 else { throw CompanionError.lockUnavailable }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }

  func withLockIfFree<T>(_ body: () throws -> T) rethrows -> T? {
    let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return nil }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }

  func loadState() -> CompanionState? { read(CompanionState.self, from: stateURL) }
  @discardableResult
  func saveState(_ state: CompanionState?) -> Bool { write(state, to: stateURL) }

  func loadOutbox() -> [OutboxItem] { read([OutboxItem].self, from: outboxURL) ?? [] }
  @discardableResult
  func saveOutbox(_ items: [OutboxItem]) -> Bool { write(items, to: outboxURL) }

  @discardableResult
  func enqueue(_ item: OutboxItem) -> Bool {
    (try? withLock {
      var items = loadOutbox().filter { $0.id != item.id }
      items.append(item)
      return saveOutbox(items)
    }) ?? false
  }

  func loadSnapshot() -> DesktopSnapshot? { read(DesktopSnapshot.self, from: snapshotURL) }
  func saveSnapshot(_ snapshot: DesktopSnapshot?) { write(snapshot, to: snapshotURL) }

  var folderBookmark: Data? {
    get { AppGroup.defaults.data(forKey: "syncFolderBookmark") }
    set { AppGroup.defaults.set(newValue, forKey: "syncFolderBookmark") }
  }

  var folderPathOverride: String? {
    get { AppGroup.defaults.string(forKey: "syncFolderPath") }
    set { AppGroup.defaults.set(newValue, forKey: "syncFolderPath") }
  }

  var folderDisplayName: String? {
    get { AppGroup.defaults.string(forKey: "syncFolderName") }
    set { AppGroup.defaults.set(newValue, forKey: "syncFolderName") }
  }

  var lastSpaceId: String? {
    get { AppGroup.defaults.string(forKey: "lastPinSpace") }
    set { AppGroup.defaults.set(newValue, forKey: "lastPinSpace") }
  }

  var pinAsRow: Bool {
    get { AppGroup.defaults.object(forKey: "pinAsRow") as? Bool ?? true }
    set { AppGroup.defaults.set(newValue, forKey: "pinAsRow") }
  }

  func rememberFolder(_ url: URL) throws {
    folderBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    folderDisplayName = url.lastPathComponent
    folderPathOverride = nil
  }

  func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
    if let path = folderPathOverride {
      return try body(URL(fileURLWithPath: path, isDirectory: true))
    }
    guard let bookmark = folderBookmark else { throw CompanionError.noFolder }
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      folderBookmark = fresh
    }
    return try body(url)
  }

  private var keyQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "Ardia Sync Key",
      kSecAttrAccount as String: "companion",
      kSecAttrAccessGroup as String: AppGroup.identifier,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func loadKey() -> Data? {
    var q = keyQuery
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data { return data }
    #if targetEnvironment(simulator)
    return try? Data(contentsOf: fallbackKeyURL)
    #else
    return nil
    #endif
  }

  func saveKey(_ entropy: Data) -> Bool {
    SecItemDelete(keyQuery as CFDictionary)
    var add = keyQuery
    add[kSecValueData as String] = entropy
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return true }
    #if targetEnvironment(simulator)
    return (try? entropy.write(to: fallbackKeyURL, options: [.atomic, .completeFileProtection])) != nil
    #else
    return false
    #endif
  }

  func deleteKey() {
    SecItemDelete(keyQuery as CFDictionary)
    try? FileManager.default.removeItem(at: fallbackKeyURL)
  }

  private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder.companion.decode(type, from: data)
  }

  @discardableResult
  private func write<T: Encodable>(_ value: T?, to url: URL) -> Bool {
    guard let value else {
      guard FileManager.default.fileExists(atPath: url.path) else { return true }
      return (try? FileManager.default.removeItem(at: url)) != nil
    }
    guard let data = try? JSONEncoder.companion.encode(value) else { return false }
    return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
  }
}

enum CompanionError: LocalizedError, Equatable {
  case noFolder
  case notConnected
  case noSyncData
  case phraseMismatch
  case phrase(String)
  case keychain
  case unknownSpace
  case stateNotSaved
  case lockUnavailable

  var errorDescription: String? {
    switch self {
    case .noFolder: "Choose the Ardia Sync folder in iCloud Drive."
    case .notConnected: "Connect to Ardia on your Mac first."
    case .noSyncData: "This folder has no Ardia sync data. Pick the “Ardia Sync” folder in iCloud Drive."
    case .phraseMismatch: "This recovery phrase doesn’t match the synced data in this folder."
    case .phrase(let message): message
    case .keychain: "Couldn’t save the sync key to the Keychain."
    case .unknownSpace: "That space isn’t synced from your Mac anymore."
    case .stateNotSaved: "Couldn’t save sync state on this iPhone. Free up some space and try again."
    case .lockUnavailable: "Another part of Ardia is syncing. Try again in a moment."
    }
  }
}

extension JSONEncoder {
  static var companion: JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .millisecondsSince1970
    return e
  }
}

extension JSONDecoder {
  static var companion: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .millisecondsSince1970
    return d
  }
}

import SwiftUI
import UIKit

@MainActor
final class DesktopModel: ObservableObject {
  enum Status: Equatable {
    case notConnected
    case syncing
    case synced(Date)
    case waiting(Int)
    case failed(String)
  }

  @Published private(set) var snapshot: DesktopSnapshot
  @Published private(set) var status: Status
  @Published private(set) var connected: Bool
  @Published var selectedSpaceId: String?
  @Published private(set) var outboxCount = 0

  private let store = SharedStore.shared
  private let queue = DispatchQueue(label: "ardia.companion.sync", qos: .utility)
  private let engine = CompanionSync()
  private var timer: Timer?
  private var running = false
  private var again = false
  private var againForcesTabs = false
  private var inBackground = false
  var tabSharing: () -> (enabled: Bool, tabs: [SharedLink]) = { (true, []) }

  init() {
    let snapshot = SharedStore.shared.loadSnapshot() ?? DesktopSnapshot()
    let isConnected = SharedStore.shared.loadState() != nil && SharedStore.shared.loadKey() != nil
    self.snapshot = snapshot
    connected = isConnected
    status = isConnected ? (snapshot.updatedAt.map(Status.synced) ?? .syncing) : .notConnected
    selectedSpaceId = SharedStore.shared.lastSpaceId ?? snapshot.defaultSpace?.id
    outboxCount = SharedStore.shared.loadOutbox().count
  }

  var deviceName: String { store.loadState()?.deviceName ?? Self.defaultDeviceName }
  var folderName: String { store.folderPathOverride.map { URL(fileURLWithPath: $0).lastPathComponent } ?? store.folderDisplayName ?? "Not chosen" }
  var macName: String { snapshot.devices.first?.name ?? "your Mac" }
  var selectedSpace: DesktopSpace? { snapshot.space(selectedSpaceId) ?? snapshot.defaultSpace }

  static var defaultDeviceName: String {
    let name = UIDevice.current.name
    return name == UIDevice.current.model ? "My \(name)" : name
  }

  func start() {
    inBackground = false
    engine.resume()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    refresh()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func enterBackground() {
    refresh(forceTabs: true)
    inBackground = true
    stop()
  }

  func chooseFolder(_ url: URL) throws {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    try store.rememberFolder(url)
    objectWillChange.send()
  }

  func connect(phrase: String, name: String) async throws {
    status = .syncing
    let engine = engine
    do {
      let result = try await run { try engine.connect(phrase: phrase, deviceName: name) }
      apply(result)
      connected = true
      if selectedSpaceId == nil || result.space(selectedSpaceId) == nil { selectedSpaceId = result.defaultSpace?.id }
    } catch {
      if store.loadState() != nil, store.loadKey() != nil {
        connected = true
        status = .failed(error.localizedDescription)
        return
      }
      status = .notConnected
      throw error
    }
  }

  func disconnect(force: Bool = false) async throws {
    let engine = engine
    try await run { try engine.disconnect(force: force) }
    connected = false
    snapshot = DesktopSnapshot()
    status = .notConnected
    outboxCount = 0
  }

  func rename(_ name: String) {
    let engine = engine
    Task {
      _ = try? await run { engine.rename(name) }
      objectWillChange.send()
      refresh(forceTabs: true)
    }
  }

  func refresh(forceTabs: Bool = false) {
    Task { await refreshNow(forceTabs: forceTabs) }
  }

  func refreshNow(forceTabs: Bool = false) async {
    guard connected, !inBackground else { return }
    if running {
      again = true
      againForcesTabs = againForcesTabs || forceTabs
      return
    }
    running = true
    if case .failed = status { status = .syncing }
    let sharing = tabSharing()
    let engine = engine
    do {
      let result = try await run { try engine.sync(openTabs: sharing.tabs, shareTabs: sharing.enabled, forceTabs: forceTabs) }
      apply(result)
    } catch is CancellationError {
    } catch {
      status = .failed(error.localizedDescription)
    }
    outboxCount = store.loadOutbox().count
    running = false
    if again || snapshot.waitingForDownloads > 0 {
      let soon = again
      let force = againForcesTabs
      again = false
      againForcesTabs = false
      Task {
        try? await Task.sleep(for: .seconds(soon ? 0.2 : 3))
        await refreshNow(forceTabs: force)
      }
    }
  }

  func pin(url: String, title: String, spaceId: String, folderId: String? = nil, asRow: Bool) async -> Bool {
    store.lastSpaceId = spaceId
    return await enqueue(.pin(PinRequest(id: PinRequest.newId(), url: url, title: title, spaceId: spaceId, folderId: folderId, asRow: asRow, createdAt: Date()))).value
  }

  @discardableResult
  private func enqueue(_ item: OutboxItem) -> Task<Bool, Never> {
    let store = store
    return Task {
      let saved = (try? await run { store.enqueue(item) }) ?? false
      if saved { outboxCount += 1 }
      refresh()
      return saved
    }
  }

  func unpin(_ pin: DesktopPin, in spaceId: String) {
    enqueue(.unpin(UnpinRequest(pinId: pin.id, spaceId: spaceId, createdAt: Date())))
    if let index = snapshot.spaces.firstIndex(where: { $0.id == spaceId }) {
      snapshot.spaces[index].tiles.removeAll { $0.id == pin.id }
      snapshot.spaces[index].rows.removeAll { $0.id == pin.id }
      for f in snapshot.spaces[index].folders.indices { snapshot.spaces[index].folders[f].pins.removeAll { $0.id == pin.id } }
    }
  }

  func isPinned(_ url: String?) -> Bool {
    guard let url else { return false }
    return snapshot.spaces.contains { space in
      (space.tiles + space.rows + space.folders.flatMap(\.pins)).contains { $0.url == url }
    }
  }

  private func apply(_ result: DesktopSnapshot) {
    snapshot = result
    status = result.waitingForDownloads > 0 ? .waiting(result.waitingForDownloads) : .synced(result.updatedAt ?? Date())
    if result.space(selectedSpaceId) == nil { selectedSpaceId = result.defaultSpace?.id }
  }

  private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
    let engine = engine
    var task = UIBackgroundTaskIdentifier.invalid
    task = UIApplication.shared.beginBackgroundTask(withName: "Ardia Sync") {
      engine.cancel()
      if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      task = .invalid
    }
    defer {
      if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      task = .invalid
    }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { continuation.resume(with: Result { try work() }) }
    }
  }

  var statusLine: String {
    switch status {
    case .notConnected: "Not connected"
    case .syncing: "Updating…"
    case .synced(let date): Self.relative(date)
    case .waiting(let n): "Waiting for \(n) file\(n == 1 ? "" : "s") to download from iCloud"
    case .failed(let message): message
    }
  }

  static func relative(_ date: Date) -> String {
    let seconds = Date().timeIntervalSince(date)
    if seconds < 60 { return "Updated just now" }
    return "Updated " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
  }
}

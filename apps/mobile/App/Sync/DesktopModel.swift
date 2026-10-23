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
  var openTabs: () -> [SharedLink]? = { nil }

  init() {
    let snapshot = SharedStore.shared.loadSnapshot() ?? DesktopSnapshot()
    let isConnected = SharedStore.shared.loadState() != nil
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
      status = .notConnected
      throw error
    }
  }

  func disconnect() async {
    let engine = engine
    _ = try? await run { engine.disconnect() }
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
    guard connected else { return }
    if running {
      again = true
      return
    }
    running = true
    if case .failed = status { status = .syncing }
    let tabs = openTabs()
    let engine = engine
    Task {
      do {
        let result = try await run { try engine.sync(openTabs: tabs, forceTabs: forceTabs) }
        apply(result)
      } catch {
        status = .failed(error.localizedDescription)
      }
      outboxCount = store.loadOutbox().count
      running = false
      if again || snapshot.waitingForDownloads > 0 {
        let soon = again
        again = false
        Task {
          try? await Task.sleep(for: .seconds(soon ? 0.2 : 3))
          refresh()
        }
      }
    }
  }

  func pin(url: String, title: String, spaceId: String, folderId: String? = nil, asRow: Bool) {
    store.lastSpaceId = spaceId
    enqueue(.pin(PinRequest(id: PinRequest.newId(), url: url, title: title, spaceId: spaceId, folderId: folderId, asRow: asRow, createdAt: Date())))
  }

  private func enqueue(_ item: OutboxItem) {
    let store = store
    outboxCount += 1
    Task {
      _ = try? await run { store.enqueue(item) }
      refresh()
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
    let task = UIApplication.shared.beginBackgroundTask(withName: "Ardia Sync")
    defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
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

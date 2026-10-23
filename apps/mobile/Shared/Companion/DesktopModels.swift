import Foundation

struct DesktopSnapshot: Codable, Equatable {
  var spaces: [DesktopSpace] = []
  var devices: [DesktopDevice] = []
  var updatedAt: Date?
  var waitingForDownloads = 0

  var defaultSpace: DesktopSpace? { spaces.first { $0.isDefault } ?? spaces.first }
  func space(_ id: String?) -> DesktopSpace? { spaces.first { $0.id == id } }
}

struct DesktopDevice: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var lastSeen: Date?
}

struct DesktopSpace: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var color: String
  var icon: String?
  var isDefault: Bool
  var accentHex: String?
  var tiles: [DesktopPin] = []
  var rows: [DesktopPin] = []
  var folders: [DesktopFolder] = []
  var deviceTabs: [DesktopDeviceTabs] = []

  var pinCount: Int { tiles.count + rows.count + folders.reduce(0) { $0 + $1.pins.count } }

  static let swatches: [String: String] = [
    "plum": "#C07A98", "blue": "#4691C3", "purple": "#7873AF", "pink": "#D37B8B", "red": "#C1575C",
    "orange": "#D87249", "yellow": "#E3AC38", "green": "#3EB489", "neutral": "#8E8E93",
  ]

  var swatchHex: String { accentHex ?? Self.swatches[color] ?? "#C07A98" }

  var symbolName: String? {
    guard let icon, icon.hasPrefix("symbol:") else { return nil }
    return String(icon.dropFirst("symbol:".count))
  }

  var emoji: String? {
    guard let icon, !icon.isEmpty, !icon.hasPrefix("symbol:") else { return nil }
    return icon
  }

  var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

struct DesktopPin: Codable, Equatable, Identifiable, Hashable {
  var id: String
  var url: String
  var title: String
  var customIcon: String?
  var folderId: String?
  var position: String
  var isRow: Bool

  var host: String { URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url }
  var displayTitle: String { title.isEmpty ? host : title }
}

struct DesktopFolder: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var icon: String?
  var color: String?
  var position: String
  var pins: [DesktopPin]
}

struct DesktopDeviceTabs: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var tabs: [SharedLink]
}

struct SharedLink: Codable, Equatable, Hashable {
  var url: String
  var title: String
}

enum OutboxItem: Codable, Equatable, Identifiable {
  case pin(PinRequest)
  case unpin(UnpinRequest)

  var id: String {
    switch self {
    case .pin(let p): "pin:\(p.id)"
    case .unpin(let u): "unpin:\(u.pinId)"
    }
  }

  var spaceId: String {
    switch self {
    case .pin(let p): p.spaceId
    case .unpin(let u): u.spaceId
    }
  }

  var createdAt: Date? {
    switch self {
    case .pin(let p): p.createdAt
    case .unpin(let u): u.createdAt
    }
  }
}

struct PinRequest: Codable, Equatable {
  var id: String
  var url: String
  var title: String
  var spaceId: String
  var folderId: String?
  var asRow: Bool
  var createdAt: Date

  static func newId() -> String { "tab-m" + SyncKeys.newFileId().prefix(16) }
}

struct UnpinRequest: Codable, Equatable {
  var pinId: String
  var spaceId: String
  var createdAt: Date?
}

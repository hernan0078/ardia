import SwiftUI
import UIKit

extension Color {
  init(hex: String) {
    self.init(uiColor: UIColor(hex: hex))
  }
}

extension UIColor {
  convenience init(hex: String) {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
    self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }

  var isLight: Bool {
    var white: CGFloat = 0
    var alpha: CGFloat = 0
    let rgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0]
    if rgb.count >= 3 {
      white = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]
    } else {
      getWhite(&white, alpha: &alpha)
    }
    return white > 0.6
  }
}

enum Palette {
  static let canvas = Color(red: 0.11, green: 0.11, blue: 0.13)
  static let sheet = Color(red: 0.17, green: 0.17, blue: 0.19)
  static let card = Color.white.opacity(0.09)
  static let cardStrong = Color.white.opacity(0.14)
  static let hairline = Color.white.opacity(0.08)
  static let secondaryText = Color.white.opacity(0.55)

  static func spaceGradient(_ hex: String) -> LinearGradient {
    let base = Color(hex: hex)
    return LinearGradient(colors: [base.opacity(0.55), Color(red: 0.16, green: 0.16, blue: 0.22), Color(red: 0.12, green: 0.12, blue: 0.16)], startPoint: .topLeading, endPoint: .bottom)
  }
}

struct IconBadge: View {
  let symbol: String
  let color: Color
  var size: CGFloat = 32

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
  }
}

struct SpaceBadge: View {
  let space: DesktopSpace
  var size: CGFloat = 28
  var selected = false

  var body: some View {
    ZStack {
      if let symbol = space.symbolName {
        Image(systemName: symbol).font(.system(size: size * 0.55, weight: .semibold))
      } else if let emoji = space.emoji {
        Text(emoji).font(.system(size: size * 0.62))
      } else {
        Text(space.initial).font(.system(size: size * 0.5, weight: .bold, design: .rounded))
      }
    }
    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
    .frame(width: size + 10, height: size + 10)
    .background(selected ? Color(hex: space.swatchHex).opacity(0.85) : Color.clear, in: Circle())
    .contentShape(Circle())
  }
}

@MainActor
final class FaviconCache {
  static let shared = FaviconCache()
  private var memory: [String: UIImage] = [:]
  private var inFlight: [String: Task<UIImage?, Never>] = [:]
  private let directory: URL = {
    let url = AppGroup.container.appendingPathComponent("Favicons", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  func cached(_ host: String) -> UIImage? { memory[host] }

  func fromDisk(_ host: String) async -> UIImage? {
    if let image = memory[host] { return image }
    let file = directory.appendingPathComponent(host)
    let image = await Task.detached(priority: .utility) { () -> UIImage? in
      guard let data = try? Data(contentsOf: file) else { return nil }
      return UIImage(data: data)?.preparingForDisplay()
    }.value
    if let image { memory[host] = image }
    return image
  }

  func store(_ data: Data, for host: String) {
    guard let image = UIImage(data: data), image.size.width >= 8 else { return }
    memory[host] = image
    try? data.write(to: directory.appendingPathComponent(host))
  }

  func image(for host: String, hint: URL? = nil) async -> UIImage? {
    if let image = cached(host) { return image }
    if let task = inFlight[host] { return await task.value }
    if let image = await fromDisk(host) { return image }
    let task = Task<UIImage?, Never> {
      var candidates = [hint].compactMap { $0 }
      candidates += ["apple-touch-icon.png", "favicon.ico"].compactMap { URL(string: "https://\(host)/\($0)") }
      for url in candidates {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data: data) != nil else { continue }
        store(data, for: host)
        return UIImage(data: data)
      }
      return nil
    }
    inFlight[host] = task
    let image = await task.value
    inFlight[host] = nil
    return image
  }
}

struct FaviconView: View {
  let url: String
  var size: CGFloat = 22
  var emoji: String?
  @State private var image: UIImage?

  private var host: String { URL(string: url)?.host() ?? url }

  var body: some View {
    Group {
      if let emoji, emoji.hasPrefix("symbol:") {
        Image(systemName: String(emoji.dropFirst("symbol:".count)))
          .font(.system(size: size * 0.7, weight: .semibold))
          .foregroundStyle(.white)
      } else if let emoji, !emoji.isEmpty {
        Text(emoji).font(.system(size: size * 0.8))
      } else if let image {
        Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      } else {
        Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
          .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .frame(width: size, height: size)
          .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      }
    }
    .frame(width: size, height: size)
    .task(id: host) {
      image = FaviconCache.shared.cached(host)
      guard image == nil else { return }
      let found = await FaviconCache.shared.image(for: host)
      if !Task.isCancelled { image = found }
    }
  }
}

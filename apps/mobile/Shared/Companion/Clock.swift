import Foundation

struct HybridClock {
  static let wallDigits = 9
  static let counterDigits = 4

  let device: String
  private(set) var wall: Int64 = 0
  private(set) var counter: Int = 0
  private let now: () -> Int64

  init(device: String, last: String? = nil, now: @escaping () -> Int64 = HybridClock.wallNow) {
    self.device = device
    self.now = now
    if let last { observe(last) }
  }

  static func wallNow() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

  static func format(wall: Int64, counter: Int, device: String) -> String {
    let w = String(max(0, wall), radix: 36)
    let c = String(counter, radix: 36)
    return String(repeating: "0", count: max(0, wallDigits - w.count)) + w + "."
      + String(repeating: "0", count: max(0, counterDigits - c.count)) + c + "." + device
  }

  mutating func tick() -> String {
    let t = now()
    if t > wall {
      wall = t
      counter = 0
    } else {
      counter += 1
    }
    return Self.format(wall: wall, counter: counter, device: device)
  }

  mutating func observe(_ h: String) {
    let parts = h.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count >= 2, let w = Int64(parts[0], radix: 36), let c = Int(parts[1], radix: 36) else { return }
    if w > wall || (w == wall && c > counter) {
      wall = w
      counter = c
    }
  }

  var last: String { Self.format(wall: wall, counter: counter, device: device) }
}

enum FractionalPosition {
  static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
  static var base: Int { digits.count }

  static func digit(_ c: Character?) -> Int {
    guard let c else { return 0 }
    return digits.firstIndex(of: c) ?? 0
  }

  static func between(_ a: String, _ b: String?) -> String {
    let a = Array(a)
    let b = b.map(Array.init)
    if let b {
      var n = 0
      while (n < a.count ? a[n] : "0") == (n < b.count ? b[n] : nil) { n += 1 }
      if n > 0 { return String(b.prefix(n)) + between(String(a.dropFirst(n)), String(b.dropFirst(n))) }
    }
    let da = digit(a.first)
    let db = b.map { digit($0.first) } ?? base
    if db - da > 1 { return String(digits[Int((Double(da + db) / 2).rounded())]) }
    if let b, b.count > 1 { return String(b.prefix(1)) }
    return String(digits[da]) + between(String(a.dropFirst()), nil)
  }

  static func after(_ positions: [String]) -> String {
    between(positions.filter { !$0.isEmpty && !$0.hasSuffix("0") }.max() ?? "", nil)
  }
}

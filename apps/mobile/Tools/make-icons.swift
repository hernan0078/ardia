import AppKit
import CoreImage

struct Variant {
  let id: String
  let name: String
  let plate: (NSColor, NSColor)?
  let mono: Bool
  let tint: String?
}

let cream = (NSColor(srgbRed: 0.973, green: 0.957, blue: 0.902, alpha: 1), NSColor(srgbRed: 0.965, green: 0.945, blue: 0.885, alpha: 1))
let variants = [
  Variant(id: "default", name: "Default", plate: nil, mono: false, tint: nil),
  Variant(id: "midnight", name: "Midnight", plate: (NSColor(srgbRed: 0.20, green: 0.19, blue: 0.22, alpha: 1), NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)), mono: false, tint: "neutral"),
  Variant(id: "daylight", name: "Daylight", plate: (NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), NSColor(srgbRed: 0.90, green: 0.90, blue: 0.91, alpha: 1)), mono: false, tint: "neutral"),
  Variant(id: "plum", name: "Plum", plate: (NSColor(srgbRed: 0.83, green: 0.56, blue: 0.68, alpha: 1), NSColor(srgbRed: 0.52, green: 0.28, blue: 0.40, alpha: 1)), mono: false, tint: "plum"),
  Variant(id: "ocean", name: "Ocean", plate: (NSColor(srgbRed: 0.45, green: 0.70, blue: 0.93, alpha: 1), NSColor(srgbRed: 0.16, green: 0.36, blue: 0.70, alpha: 1)), mono: false, tint: "blue"),
  Variant(id: "mono", name: "Mono", plate: nil, mono: true, tint: nil),
  Variant(id: "noir", name: "Noir", plate: (NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1), NSColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 1)), mono: true, tint: nil),
]

let args = CommandLine.arguments
let marks = URL(fileURLWithPath: args[1])
let catalog = URL(fileURLWithPath: args[2])

func mark(_ tint: String?) -> NSImage {
  let name = tint.map { "AppIconMark-\($0).imageset" } ?? "AppIconMark.imageset"
  return NSImage(contentsOf: marks.appendingPathComponent(name).appendingPathComponent("mark.png"))!
}

func monochrome(_ image: NSImage) -> NSImage {
  let input = CIImage(data: image.tiffRepresentation!)!
  let filter = CIFilter(name: "CIPhotoEffectNoir")!
  filter.setValue(input, forKey: kCIInputImageKey)
  let rep = NSCIImageRep(ciImage: filter.outputImage!)
  let out = NSImage(size: rep.size)
  out.addRepresentation(rep)
  return out
}

func render(_ v: Variant, pixels: Int) -> Data {
  let cg = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
  let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
  var plate = v.plate ?? cream
  if v.mono && v.plate == nil {
    plate = (NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1), NSColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1))
  }
  NSGradient(starting: plate.0, ending: plate.1)!.draw(in: rect, angle: -90)
  let source = mark(v.plate == nil ? nil : v.tint)
  let art = v.mono ? monochrome(source) : source
  let inset = CGFloat(pixels) * 0.12
  art.draw(in: rect.insetBy(dx: inset, dy: inset).offsetBy(dx: 0, dy: -CGFloat(pixels) * 0.01))
  NSGraphicsContext.restoreGraphicsState()
  return NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
}

let fm = FileManager.default
for v in variants {
  let iconName = v.id == "default" ? "AppIcon" : "AppIcon-\(v.id)"
  let iconSet = catalog.appendingPathComponent("\(iconName).appiconset")
  try? fm.removeItem(at: iconSet)
  try! fm.createDirectory(at: iconSet, withIntermediateDirectories: true)
  try! render(v, pixels: 1024).write(to: iconSet.appendingPathComponent("icon-1024.png"))
  try! #"{ "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ], "info" : { "author" : "xcode", "version" : 1 } }"#.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
  let preview = catalog.appendingPathComponent("IconPreview-\(v.id).imageset")
  try? fm.removeItem(at: preview)
  try! fm.createDirectory(at: preview, withIntermediateDirectories: true)
  try! render(v, pixels: 240).write(to: preview.appendingPathComponent("preview.png"))
  try! #"{ "images" : [ { "filename" : "preview.png", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }"#.write(to: preview.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
  print(v.id)
}

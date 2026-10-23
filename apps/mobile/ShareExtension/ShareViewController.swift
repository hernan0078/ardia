import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let model = ShareModel()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    model.finish = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
    model.cancel = { [weak self] in
      self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
    let host = UIHostingController(rootView: ShareRootView(model: model).preferredColorScheme(.dark))
    host.view.backgroundColor = UIColor(Palette.sheet)
    addChild(host)
    host.view.frame = view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(host.view)
    host.didMove(toParent: self)
    Task { await model.load(from: extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
  }
}

@MainActor
final class ShareModel: ObservableObject {
  enum Phase: Equatable {
    case loading
    case notConnected
    case ready
    case noLink
    case sending
    case done(String)
    case queued(String)
  }

  @Published var phase: Phase = .loading
  @Published var link = SharedLink(url: "", title: "")
  @Published var snapshot = SharedStore.shared.loadSnapshot() ?? DesktopSnapshot()
  var finish: () -> Void = {}
  var cancel: () -> Void = {}
  private let store = SharedStore.shared

  func load(from items: [NSExtensionItem]) async {
    guard store.loadState() != nil, store.loadKey() != nil else {
      phase = .notConnected
      return
    }
    let found = await LinkExtractor.link(from: items)
    guard let found else {
      phase = .noLink
      return
    }
    link = found
    phase = snapshot.spaces.isEmpty ? .loading : .ready
    if link.title.isEmpty || link.title == link.url {
      if let title = await LinkExtractor.pageTitle(link.url) { link.title = title }
    }
    if snapshot.spaces.isEmpty {
      if let fresh = await refreshSnapshot() { snapshot = fresh }
      phase = .ready
    }
  }

  private func refreshSnapshot() async -> DesktopSnapshot? {
    await Task.detached { (try? CompanionSync().syncIfIdle()) ?? nil }.value
  }

  func pin(spaceId: String, folderId: String?, asRow: Bool) {
    let spaceName = snapshot.space(spaceId)?.name ?? "your Mac"
    let macName = snapshot.devices.first?.name ?? "your Mac"
    store.lastSpaceId = spaceId
    store.pinAsRow = asRow
    let request = PinRequest(id: PinRequest.newId(), url: link.url, title: link.title, spaceId: spaceId, folderId: folderId, asRow: asRow, createdAt: Date())
    let store = store
    phase = .sending
    Task {
      let sent = await Task.detached { () -> Bool in
        store.enqueue(.pin(request))
        return (try? CompanionSync(store: store).syncIfIdle()) != nil
      }.value
      let stillQueued = store.loadOutbox().contains { $0.id == OutboxItem.pin(request).id }
      phase = sent && !stillQueued ? .done("Pinned to \(spaceName) on \(macName)") : .queued("Saved. It goes to \(spaceName) the next time you open Ardia.")
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      try? await Task.sleep(for: .seconds(1.1))
      finish()
    }
  }
}

struct ShareRootView: View {
  @ObservedObject var model: ShareModel

  var body: some View {
    switch model.phase {
    case .loading:
      VStack(spacing: 14) {
        ProgressView().tint(.white)
        Text("Loading your spaces…").foregroundStyle(Palette.secondaryText)
        Button("Cancel", action: model.cancel).padding(.top, 10)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.sheet)
    case .notConnected:
      message(symbol: "laptopcomputer.and.iphone", title: "Connect Ardia first", detail: "Open Ardia on this iPhone and connect it to Ardia on your Mac. Then you can pin from any app.")
    case .noLink:
      message(symbol: "link.badge.plus", title: "No link to pin", detail: "Share a web page or a post with a link in it.")
    case .ready:
      PinComposer(link: model.link, snapshot: model.snapshot, initialSpaceId: SharedStore.shared.lastSpaceId, asRow: SharedStore.shared.pinAsRow) { space, folder, row in
        model.pin(spaceId: space, folderId: folder, asRow: row)
      } cancel: {
        model.cancel()
      }
    case .sending:
      VStack(spacing: 14) {
        ProgressView().tint(.white)
        Text("Pinning…").foregroundStyle(.white)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.sheet)
    case .done(let text), .queued(let text):
      VStack(spacing: 14) {
        Image(systemName: model.phase == .done(text) ? "pin.circle.fill" : "clock.badge.checkmark.fill")
          .font(.system(size: 56))
          .symbolRenderingMode(.hierarchical)
        Text(text).font(.headline).multilineTextAlignment(.center).padding(.horizontal, 30)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.sheet)
    }
  }

  private func message(symbol: String, title: String, detail: String) -> some View {
    VStack(spacing: 14) {
      Image(systemName: symbol).font(.system(size: 46, weight: .light))
      Text(title).font(.title3.weight(.semibold))
      Text(detail).multilineTextAlignment(.center).foregroundStyle(Palette.secondaryText).padding(.horizontal, 30)
      Button("Close", action: model.cancel).font(.headline).padding(.top, 8)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.sheet)
  }
}

enum LinkExtractor {
  static func link(from items: [NSExtensionItem]) async -> SharedLink? {
    var text = ""
    for item in items {
      let title = item.attributedContentText?.string ?? item.attributedTitle?.string ?? ""
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
           url.scheme?.hasPrefix("http") == true {
          return SharedLink(url: url.absoluteString, title: cleanTitle(title, url: url))
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let string = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
          text += " " + string
        }
      }
      text += " " + title
    }
    guard let url = firstURL(in: text) else { return nil }
    let remainder = text.replacingOccurrences(of: url.absoluteString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    return SharedLink(url: url.absoluteString, title: cleanTitle(remainder, url: url))
  }

  static func firstURL(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    return matches.compactMap(\.url).first { $0.scheme?.hasPrefix("http") == true }
  }

  static func cleanTitle(_ raw: String, url: URL) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t != url.absoluteString else { return "" }
    return String(t.prefix(140))
  }

  static func pageTitle(_ urlString: String) async -> String? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 4)
    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
    let html = String(decoding: data.prefix(300_000), as: UTF8.self)
    let patterns = [
      "<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']",
      "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']",
      "<title[^>]*>([^<]+)</title>",
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: 1), in: html) else { continue }
      let title = decodeEntities(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
      if !title.isEmpty { return String(title.prefix(140)) }
    }
    return nil
  }

  static func decodeEntities(_ s: String) -> String {
    var out = s
    for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
      out = out.replacingOccurrences(of: entity, with: char)
    }
    return out
  }
}

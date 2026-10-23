import SwiftUI
import WebKit

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
  case google, duckDuckGo, bing, brave, kagi, ecosia

  var id: String { rawValue }

  var name: String {
    switch self {
    case .google: "Google"
    case .duckDuckGo: "DuckDuckGo"
    case .bing: "Bing"
    case .brave: "Brave Search"
    case .kagi: "Kagi"
    case .ecosia: "Ecosia"
    }
  }

  func searchURL(_ query: String) -> URL? {
    let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? query
    let base = switch self {
    case .google: "https://www.google.com/search?q="
    case .duckDuckGo: "https://duckduckgo.com/?q="
    case .bing: "https://www.bing.com/search?q="
    case .brave: "https://search.brave.com/search?q="
    case .kagi: "https://kagi.com/search?q="
    case .ecosia: "https://www.ecosia.org/search?q="
    }
    return URL(string: base + q)
  }

  func suggestionsURL(_ query: String) -> URL? {
    let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? query
    switch self {
    case .google: return URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&q=\(q)")
    case .bing: return URL(string: "https://api.bing.com/osjson.aspx?query=\(q)")
    default: return URL(string: "https://duckduckgo.com/ac/?type=list&q=\(q)")
    }
  }
}

enum ArchiveAfter: Int, CaseIterable, Codable, Identifiable {
  case never = 0, twelveHours = 12, oneDay = 24, sevenDays = 168, thirtyDays = 720

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .never: "Never"
    case .twelveHours: "After 12 hours"
    case .oneDay: "After 1 day"
    case .sevenDays: "After 7 days"
    case .thirtyDays: "After 30 days"
    }
  }
}

struct BrowserSettings: Codable, Equatable {
  var searchEngine: SearchEngine = .google
  var searchSuggestions = true
  var autoOpenKeyboard = true
  var archiveAfter: ArchiveAfter = .oneDay
  var blockAds = true
  var blockTrackers = true
  var blockCookieBanners = true
  var collapseBottomBar = true
  var swipeToNavigate = true
  var shareTabsWithMac = true
  var textZoom: Double = 1
  var allowedSites: [String] = []
}

struct SavedTab: Codable {
  var id: String
  var url: String?
  var title: String
  var lastActive: Date
  var interactionState: Data?
}

struct VisitedPage: Codable, Identifiable, Hashable {
  var url: String
  var title: String
  var visitedAt: Date
  var count: Int
  var id: String { url }
}

struct ArchivedTab: Codable, Identifiable, Hashable {
  var id: String
  var url: String
  var title: String
  var archivedAt: Date
}

struct SavedSession: Codable {
  var tabs: [SavedTab]
  var activeId: String?
  var archive: [ArchivedTab]
  var history: [VisitedPage]
  var settings: BrowserSettings
}

@MainActor
final class BrowserModel: ObservableObject {
  @Published private(set) var tabs: [BrowserTab] = []
  @Published var activeTabId: String?
  @Published var archive: [ArchivedTab] = []
  @Published var history: [VisitedPage] = []
  @Published var settings = BrowserSettings() {
    didSet {
      if settings.blockAds != oldValue.blockAds || settings.blockTrackers != oldValue.blockTrackers || settings.blockCookieBanners != oldValue.blockCookieBanners || settings.allowedSites != oldValue.allowedSites {
        Task { await applyContentRules() }
      }
      if settings.swipeToNavigate != oldValue.swipeToNavigate {
        for tab in tabs { tab.webView.allowsBackForwardNavigationGestures = settings.swipeToNavigate }
      }
      if settings.textZoom != oldValue.textZoom {
        for tab in tabs { tab.webView.pageZoom = settings.textZoom }
      }
      scheduleSave()
    }
  }

  let configuration: WKWebViewConfiguration
  private var saveTask: Task<Void, Never>?
  private var ruleList: WKContentRuleList?
  private let sessionURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("session.json")

  init() {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = .audio
    configuration.defaultWebpagePreferences.preferredContentMode = .mobile
    self.configuration = configuration
    restore()
    archiveInactiveTabs()
    Task { await applyContentRules() }
  }

  var activeTab: BrowserTab? { tabs.first { $0.id == activeTabId } }

  func tab(_ id: String?) -> BrowserTab? { tabs.first { $0.id == id } }

  func resolve(_ input: String) -> URL? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https", "about", "file"].contains(scheme), url.host() != nil || scheme == "about" {
      return url
    }
    let looksLikeHost = !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost")) && !text.hasSuffix(".")
    if looksLikeHost, let url = URL(string: "https://" + text), let host = url.host(), host.contains(".") || host == "localhost" {
      if let tld = host.split(separator: ".").last, tld.allSatisfy(\.isLetter) || host.allSatisfy({ $0.isNumber || $0 == "." }) || host == "localhost" {
        return url
      }
    }
    return settings.searchEngine.searchURL(text)
  }

  @discardableResult
  func open(_ input: String, inNewTab: Bool) -> BrowserTab? {
    guard let url = resolve(input) else { return nil }
    if !inNewTab, let tab = activeTab {
      tab.load(url)
      tab.lastActive = Date()
      scheduleSave()
      return tab
    }
    return openInNewTab(url)
  }

  @discardableResult
  func openInNewTab(_ url: URL, activate: Bool = true) -> BrowserTab {
    let tab = makeTab(url: url)
    tab.ensureLoaded()
    tabs.append(tab)
    if activate { select(tab.id) }
    scheduleSave()
    return tab
  }

  func openOrSwitch(to urlString: String) {
    if let existing = tabs.first(where: { $0.urlString == urlString }) {
      select(existing.id)
    } else if let url = URL(string: urlString) {
      openInNewTab(url)
    }
  }

  private func makeTab(url: URL?, id: String = UUID().uuidString, title: String = "", lastActive: Date = Date(), state: Data? = nil) -> BrowserTab {
    let tab = BrowserTab(id: id, url: url, title: title, lastActive: lastActive, interactionState: state, configuration: configuration)
    tab.browser = self
    tab.webView.allowsBackForwardNavigationGestures = settings.swipeToNavigate
    tab.webView.pageZoom = settings.textZoom
    if let ruleList { tab.webView.configuration.userContentController.add(ruleList) }
    return tab
  }

  func select(_ id: String?) {
    activeTab?.captureSnapshot()
    activeTabId = id
    activeTab?.ensureLoaded()
    activeTab?.lastActive = Date()
    scheduleSave()
  }

  func close(_ id: String) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    let tab = tabs[index]
    if let url = tab.url?.absoluteString, url.hasPrefix("http") {
      archive.insert(ArchivedTab(id: tab.id, url: url, title: tab.displayTitle, archivedAt: Date()), at: 0)
      archive = Array(archive.prefix(200))
    }
    tab.webView.stopLoading()
    tabs.remove(at: index)
    if activeTabId == id { activeTabId = nil }
    scheduleSave()
  }

  func closeAll() {
    for tab in tabs { close(tab.id) }
  }

  func reopen(_ archived: ArchivedTab) {
    archive.removeAll { $0.id == archived.id }
    if let url = URL(string: archived.url) { openInNewTab(url) }
  }

  func archiveInactiveTabs() {
    guard settings.archiveAfter != .never else { return }
    let cutoff = Date().addingTimeInterval(-Double(settings.archiveAfter.rawValue) * 3600)
    for tab in tabs where tab.lastActive < cutoff && tab.id != activeTabId { close(tab.id) }
  }

  func recordVisit(url: URL, title: String) {
    guard let scheme = url.scheme, scheme.hasPrefix("http") else { return }
    let key = url.absoluteString
    if let index = history.firstIndex(where: { $0.url == key }) {
      var page = history.remove(at: index)
      page.visitedAt = Date()
      page.count += 1
      if !title.isEmpty { page.title = title }
      history.insert(page, at: 0)
    } else {
      history.insert(VisitedPage(url: key, title: title, visitedAt: Date(), count: 1), at: 0)
    }
    if history.count > 1000 { history.removeLast(history.count - 1000) }
  }

  func clearBrowsingData() async {
    history = []
    archive = []
    let store = WKWebsiteDataStore.default()
    await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    scheduleSave()
  }

  var openLinks: [SharedLink] {
    tabs.sorted { $0.lastActive > $1.lastActive }.compactMap { tab in
      guard let url = tab.url?.absoluteString, url.hasPrefix("http") else { return nil }
      return SharedLink(url: url, title: tab.displayTitle)
    }
  }

  func isAllowed(_ host: String) -> Bool { settings.allowedSites.contains(host) }

  func setBlocking(_ on: Bool, for host: String) {
    if on {
      settings.allowedSites.removeAll { $0 == host }
    } else if !settings.allowedSites.contains(host) {
      settings.allowedSites.append(host)
    }
  }

  private func applyContentRules() async {
    let json = ContentRules.json(ads: settings.blockAds, trackers: settings.blockTrackers, cookieBanners: settings.blockCookieBanners, allowed: settings.allowedSites)
    let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ardia-rules", encodedContentRuleList: json)
    let controller = configuration.userContentController
    controller.removeAllContentRuleLists()
    if let list { controller.add(list) }
    for tab in tabs {
      tab.webView.configuration.userContentController.removeAllContentRuleLists()
      if let list { tab.webView.configuration.userContentController.add(list) }
    }
    ruleList = list
  }

  func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      self?.save()
    }
  }

  func save() {
    let session = SavedSession(
      tabs: tabs.map { SavedTab(id: $0.id, url: $0.url?.absoluteString, title: $0.title, lastActive: $0.lastActive, interactionState: $0.savedInteractionState) },
      activeId: activeTabId,
      archive: archive,
      history: history,
      settings: settings
    )
    guard let data = try? JSONEncoder.companion.encode(session) else { return }
    try? FileManager.default.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: sessionURL, options: [.atomic, .completeFileProtection])
  }

  private func restore() {
    guard let data = try? Data(contentsOf: sessionURL), let session = try? JSONDecoder.companion.decode(SavedSession.self, from: data) else { return }
    settings = session.settings
    archive = session.archive
    history = session.history
    tabs = session.tabs.map { saved in
      makeTab(url: saved.url.flatMap(URL.init(string:)), id: saved.id, title: saved.title, lastActive: saved.lastActive, state: saved.interactionState)
    }
    activeTabId = session.activeId.flatMap { id in tabs.contains { $0.id == id } ? id : nil }
    activeTab?.ensureLoaded()
  }
}

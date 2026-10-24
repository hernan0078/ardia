import LocalAuthentication
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

enum LaunchAction: String, Equatable {
  case search, voice, privateSearch = "private"
}

enum OpenAppLinks: String, CaseIterable, Codable, Identifiable {
  case app, ardia

  var id: String { rawValue }
  var label: String { self == .app ? "Native App" : "Ardia" }
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
  var openAppLinks: OpenAppLinks = .app
  var lockPrivateTabs = false

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = BrowserSettings()
    searchEngine = (try? c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine)) ?? d.searchEngine
    searchSuggestions = (try? c.decodeIfPresent(Bool.self, forKey: .searchSuggestions)) ?? d.searchSuggestions
    autoOpenKeyboard = (try? c.decodeIfPresent(Bool.self, forKey: .autoOpenKeyboard)) ?? d.autoOpenKeyboard
    archiveAfter = (try? c.decodeIfPresent(ArchiveAfter.self, forKey: .archiveAfter)) ?? d.archiveAfter
    blockAds = (try? c.decodeIfPresent(Bool.self, forKey: .blockAds)) ?? d.blockAds
    blockTrackers = (try? c.decodeIfPresent(Bool.self, forKey: .blockTrackers)) ?? d.blockTrackers
    blockCookieBanners = (try? c.decodeIfPresent(Bool.self, forKey: .blockCookieBanners)) ?? d.blockCookieBanners
    collapseBottomBar = (try? c.decodeIfPresent(Bool.self, forKey: .collapseBottomBar)) ?? d.collapseBottomBar
    swipeToNavigate = (try? c.decodeIfPresent(Bool.self, forKey: .swipeToNavigate)) ?? d.swipeToNavigate
    shareTabsWithMac = (try? c.decodeIfPresent(Bool.self, forKey: .shareTabsWithMac)) ?? d.shareTabsWithMac
    textZoom = (try? c.decodeIfPresent(Double.self, forKey: .textZoom)) ?? d.textZoom
    allowedSites = (try? c.decodeIfPresent([String].self, forKey: .allowedSites)) ?? d.allowedSites
    openAppLinks = (try? c.decodeIfPresent(OpenAppLinks.self, forKey: .openAppLinks)) ?? d.openAppLinks
    lockPrivateTabs = (try? c.decodeIfPresent(Bool.self, forKey: .lockPrivateTabs)) ?? d.lockPrivateTabs
  }
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
  @Published var launchAction: LaunchAction?
  @Published var privateMode = false
  @Published var privateLocked = false
  @Published var archive: [ArchivedTab] = []
  @Published var history: [VisitedPage] = []
  @Published var settings = BrowserSettings() {
    didSet {
      if settings.blockAds != oldValue.blockAds || settings.blockTrackers != oldValue.blockTrackers || settings.blockCookieBanners != oldValue.blockCookieBanners || settings.allowedSites != oldValue.allowedSites {
        Task { await applyContentRules() }
        applyUserScripts()
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
  private var privateConfiguration: WKWebViewConfiguration?
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
    applyUserScripts()
    Task { await applyContentRules() }
  }

  var activeTab: BrowserTab? { tabs.first { $0.id == activeTabId } }
  var visibleTabs: [BrowserTab] { tabs.filter { $0.isPrivate == privateMode } }
  var privateTabs: [BrowserTab] { tabs.filter(\.isPrivate) }

  private var controllers: [WKUserContentController] {
    [configuration.userContentController] + (privateConfiguration.map { [$0.userContentController] } ?? [])
  }

  private func privateConfig() -> WKWebViewConfiguration {
    if let privateConfiguration { return privateConfiguration }
    let config = WKWebViewConfiguration()
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = .audio
    config.defaultWebpagePreferences.preferredContentMode = .mobile
    config.websiteDataStore = .nonPersistent()
    if let ruleList { config.userContentController.add(ruleList) }
    privateConfiguration = config
    applyUserScripts()
    return config
  }

  func setPrivateMode(_ on: Bool) {
    guard on != privateMode else { return }
    activeTab?.captureSnapshot()
    privateMode = on
    activeTabId = visibleTabs.max { $0.lastActive < $1.lastActive }?.id
    activeTab?.ensureLoaded()
  }

  func lockPrivateTabsIfNeeded() {
    if settings.lockPrivateTabs, !privateTabs.isEmpty { privateLocked = true }
  }

  func unlockPrivateTabs() async -> Bool {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      privateLocked = false
      return true
    }
    let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your private tabs")) ?? false
    if ok { privateLocked = false }
    return ok
  }

  func closeAllPrivateTabs() {
    for tab in privateTabs { close(tab.id) }
  }

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
  func openInNewTab(_ url: URL, activate: Bool = true, isPrivate: Bool? = nil) -> BrowserTab {
    let isPrivate = isPrivate ?? privateMode
    if isPrivate != privateMode { setPrivateMode(isPrivate) }
    let tab = makeTab(url: url, isPrivate: isPrivate)
    tab.ensureLoaded()
    tabs.append(tab)
    if activate { select(tab.id) }
    scheduleSave()
    return tab
  }

  func openOrSwitch(to urlString: String) {
    if let existing = visibleTabs.first(where: { $0.urlString == urlString }) {
      select(existing.id)
    } else if let url = URL(string: urlString) {
      openInNewTab(url)
    }
  }

  private func makeTab(url: URL?, id: String = UUID().uuidString, title: String = "", lastActive: Date = Date(), state: Data? = nil, isPrivate: Bool = false) -> BrowserTab {
    let tab = BrowserTab(id: id, url: url, title: title, lastActive: lastActive, interactionState: state, configuration: isPrivate ? privateConfig() : configuration, isPrivate: isPrivate)
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
    if !tab.isPrivate, let url = tab.url, SharedLink.isWeb(url) {
      archive.insert(ArchivedTab(id: tab.id, url: url.absoluteString, title: tab.displayTitle, archivedAt: Date()), at: 0)
      archive = Array(archive.prefix(200))
    }
    tab.webView.stopLoading()
    tabs.remove(at: index)
    if activeTabId == id {
      let siblings = visibleTabs
      let next = siblings.last { tabs.firstIndex(of: $0)! < index } ?? siblings.first
      activeTabId = next?.id
      next?.ensureLoaded()
    }
    if tab.isPrivate, privateTabs.isEmpty {
      privateConfiguration = nil
      privateLocked = false
    }
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
    for tab in tabs where !tab.isPrivate && tab.lastActive < cutoff && tab.id != activeTabId { close(tab.id) }
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
    tabs.filter { !$0.isPrivate }.sorted { $0.lastActive > $1.lastActive }.compactMap { tab in
      guard let url = tab.url, SharedLink.isWeb(url) else { return nil }
      return SharedLink(url: url.absoluteString, title: tab.displayTitle)
    }
  }

  func isAllowed(_ host: String) -> Bool { settings.allowedSites.contains(host) }
  var blocksAnything: Bool { settings.blockAds || settings.blockTrackers || settings.blockCookieBanners }

  func removeArchived(at offsets: IndexSet) {
    archive.remove(atOffsets: offsets)
    scheduleSave()
  }

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
    for controller in controllers {
      controller.removeAllContentRuleLists()
      if let list { controller.add(list) }
    }
    for tab in tabs {
      tab.webView.configuration.userContentController.removeAllContentRuleLists()
      if let list { tab.webView.configuration.userContentController.add(list) }
    }
    ruleList = list
  }

  private func applyUserScripts() {
    var scripts: [WKUserScript] = []
    if settings.blockCookieBanners {
      scripts.append(WKUserScript(source: ContentRules.declineCookiePrompts(allowed: settings.allowedSites), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }
    if settings.blockAds {
      scripts.append(WKUserScript(source: ContentRules.hideEmptyAdBars(allowed: settings.allowedSites), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    for controller in controllers {
      controller.removeAllUserScripts()
      scripts.forEach(controller.addUserScript)
    }
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
      tabs: tabs.filter { !$0.isPrivate }.map { SavedTab(id: $0.id, url: $0.url?.absoluteString, title: $0.title, lastActive: $0.lastActive, interactionState: $0.savedInteractionState) },
      activeId: activeTab?.isPrivate == true ? nil : activeTabId,
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

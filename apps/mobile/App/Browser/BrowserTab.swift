import Combine
import SwiftUI
import WebKit

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
  let id: String
  let isPrivate: Bool
  let webView: WKWebView
  @Published var title: String
  @Published var url: URL?
  @Published var canGoBack = false
  @Published var canGoForward = false
  @Published var progress: Double = 0
  @Published var isLoading = false
  @Published var themeColor: UIColor?
  @Published var snapshot: UIImage?
  @Published var scrollingDown = false
  var lastActive: Date
  var desktopMode = false
  private var observations: [NSKeyValueObservation] = []
  private var pendingState: Data?
  private var loaded = false
  private var lastOffset: CGFloat = 0
  weak var browser: BrowserModel?

  init(id: String = UUID().uuidString, url: URL?, title: String = "", lastActive: Date = Date(), interactionState: Data? = nil, configuration: WKWebViewConfiguration, isPrivate: Bool = false) {
    self.id = id
    self.isPrivate = isPrivate
    self.url = url
    self.title = title
    self.lastActive = lastActive
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    webView.allowsBackForwardNavigationGestures = true
    webView.isFindInteractionEnabled = true
    #if DEBUG
    webView.isInspectable = true
    #endif
    webView.scrollView.contentInsetAdjustmentBehavior = .automatic
    webView.backgroundColor = UIColor(Palette.canvas)
    webView.isOpaque = false
    webView.navigationDelegate = self
    webView.uiDelegate = self
    if #available(iOS 26.0, *) {
      webView.scrollView.bottomEdgeEffect.isHidden = true
      webView.scrollView.rightEdgeEffect.isHidden = true
      webView.scrollView.leftEdgeEffect.isHidden = true
    }
    observe()
    pendingState = interactionState
  }

  func ensureLoaded() {
    guard !loaded else { return }
    loaded = true
    if let pendingState {
      webView.interactionState = pendingState
      self.pendingState = nil
    } else if let url {
      webView.load(URLRequest(url: url))
    }
  }

  var savedInteractionState: Data? { loaded ? webView.interactionState as? Data : pendingState }

  private func observe() {
    observations = [
      webView.observe(\.title) { [weak self] web, _ in Task { @MainActor in if let t = web.title, !t.isEmpty { self?.title = t } } },
      webView.observe(\.url) { [weak self] web, _ in Task { @MainActor in if let u = web.url { self?.url = u } } },
      webView.observe(\.canGoBack) { [weak self] web, _ in Task { @MainActor in self?.canGoBack = web.canGoBack } },
      webView.observe(\.canGoForward) { [weak self] web, _ in Task { @MainActor in self?.canGoForward = web.canGoForward } },
      webView.observe(\.estimatedProgress) { [weak self] web, _ in Task { @MainActor in self?.progress = web.estimatedProgress } },
      webView.observe(\.isLoading) { [weak self] web, _ in Task { @MainActor in self?.isLoading = web.isLoading } },
      webView.observe(\.themeColor) { [weak self] web, _ in Task { @MainActor in self?.updateThemeColor() } },
      webView.observe(\.underPageBackgroundColor) { [weak self] web, _ in Task { @MainActor in self?.updateThemeColor() } },
      webView.scrollView.observe(\.contentOffset) { [weak self] scroll, _ in Task { @MainActor in self?.scrolled(scroll) } },
    ]
  }

  private func updateThemeColor() {
    themeColor = webView.themeColor ?? webView.underPageBackgroundColor
  }

  private func scrolled(_ scroll: UIScrollView) {
    let y = scroll.contentOffset.y
    guard scroll.isTracking || scroll.isDecelerating else {
      lastOffset = y
      return
    }
    let delta = y - lastOffset
    lastOffset = y
    if y <= 10 {
      if scrollingDown { scrollingDown = false }
    } else if delta > 6, !scrollingDown {
      scrollingDown = true
    } else if delta < -10, scrollingDown {
      scrollingDown = false
    }
  }

  var host: String { url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "" }
  var displayTitle: String { title.isEmpty ? (host.isEmpty ? "New Tab" : host) : title }
  var urlString: String { url?.absoluteString ?? "" }

  func load(_ url: URL) {
    loaded = true
    pendingState = nil
    self.url = url
    webView.load(URLRequest(url: url))
  }

  func captureSnapshot() {
    guard webView.window != nil, webView.bounds.width > 0 else { return }
    let config = WKSnapshotConfiguration()
    config.snapshotWidth = 390
    webView.takeSnapshot(with: config) { [weak self] image, _ in
      if let image { self?.snapshot = image }
    }
  }

  func setDesktopMode(_ on: Bool) {
    desktopMode = on
    webView.customUserAgent = on ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15" : nil
    webView.reload()
  }

  private func captureFavicon() {
    guard let host = webView.url?.host() else { return }
    let script = """
    (() => { const l = [...document.querySelectorAll('link[rel~="icon"],link[rel="apple-touch-icon"]')];
      const best = l.sort((a, b) => (parseInt((b.sizes && b.sizes.value) || '0') - parseInt((a.sizes && a.sizes.value) || '0')))[0];
      return best ? best.href : null; })()
    """
    webView.evaluateJavaScript(script) { result, _ in
      guard let href = result as? String, let url = URL(string: href) else { return }
      Task { @MainActor in
        guard FaviconCache.shared.cached(host) == nil else { return }
        _ = await FaviconCache.shared.image(for: host, hint: url)
      }
    }
  }
}

extension BrowserTab: WKNavigationDelegate, WKUIDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    captureFavicon()
    if !isPrivate, let url = webView.url { browser?.recordVisit(url: url, title: webView.title ?? "") }
    browser?.scheduleSave()
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
    guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
    if ["http", "https"].contains(scheme), navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame ?? true,
       browser?.settings.openAppLinks == .app, url.host() != webView.url?.host(),
       await UIApplication.shared.open(url, options: [.universalLinksOnly: true]) {
      return .cancel
    }
    if ["http", "https", "about", "data", "blob", "file"].contains(scheme) { return .allow }
    if navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame ?? true {
      await UIApplication.shared.open(url)
    }
    return .cancel
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    if webView.url != nil {
      webView.reload()
    } else if let url {
      webView.load(URLRequest(url: url))
    }
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let url = navigationAction.request.url { browser?.openInNewTab(url, isPrivate: isPrivate) }
    return nil
  }
}

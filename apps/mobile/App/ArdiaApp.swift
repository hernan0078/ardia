import SwiftUI

@main
struct ArdiaApp: App {
  @StateObject private var browser = BrowserModel()
  @StateObject private var desktop = DesktopModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(browser)
        .environmentObject(desktop)
        .onOpenURL { url in handle(url) }
        .task { await debugConnectIfAsked() }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        let browser = browser
        desktop.tabSharing = { [weak browser] in
          guard let browser else { return (true, []) }
          return (browser.settings.shareTabsWithMac, browser.openLinks)
        }
        browser.archiveInactiveTabs()
        desktop.start()
      case .background:
        browser.lockPrivateTabsIfNeeded()
        browser.save()
        desktop.enterBackground()
      default:
        break
      }
    }
  }

  private func handle(_ url: URL) {
    guard url.scheme == "ardia-mobile" else {
      if SharedLink.isWeb(url) { browser.openInNewTab(url) }
      return
    }
    let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
    if url.host() == "open", let target, let page = URL(string: target), SharedLink.isWeb(page) {
      browser.openInNewTab(page, isPrivate: false)
    } else if let action = url.host().flatMap(LaunchAction.init(rawValue:)) {
      browser.launchAction = action
    }
  }

  private func debugConnectIfAsked() async {
    #if DEBUG
    let defaults = UserDefaults.standard
    guard let path = defaults.string(forKey: "ArdiaSyncFolderPath"), let phrase = defaults.string(forKey: "ArdiaSyncPhrase") else { return }
    SharedStore.shared.folderPathOverride = path
    if !desktop.connected { try? await desktop.connect(phrase: phrase, name: "Simulator iPhone") }
    if let space = defaults.string(forKey: "ArdiaSelectSpace") { desktop.selectedSpaceId = desktop.snapshot.spaces.first { $0.name == space }?.id }
    #endif
  }
}

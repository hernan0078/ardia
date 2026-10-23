import SwiftUI

struct PageMenuView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var showDisplay = false

  var body: some View {
    if let tab = browser.activeTab {
      Content(tab: tab, showDisplay: $showDisplay)
    } else {
      Text("No page open").foregroundStyle(Palette.secondaryText).padding(40)
    }
  }

  struct Content: View {
    @ObservedObject var tab: BrowserTab
    @Binding var showDisplay: Bool
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var desktop: DesktopModel
    @EnvironmentObject private var ui: UIStateModel
    @State private var copied = false

    var body: some View {
      ScrollView {
        VStack(spacing: 14) {
          urlPill
          HStack(spacing: 12) {
            tile("Find on Page", symbol: "doc.text.magnifyingglass") {
              ui.sheet = nil
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                tab.webView.findInteraction?.presentFindNavigator(showingReplace: false)
              }
            }
            tile(tab.desktopMode ? "Mobile Site" : "Desktop Site", symbol: tab.desktopMode ? "iphone" : "desktopcomputer") {
              tab.setDesktopMode(!tab.desktopMode)
              ui.sheet = nil
            }
            tile(desktop.isPinned(tab.urlString) ? "Pinned" : "Pin", symbol: desktop.isPinned(tab.urlString) ? "pin.fill" : "pin") {
              ui.sheet = desktop.connected ? .pin(SharedLink(url: tab.urlString, title: tab.displayTitle)) : .connect
            }
            tile("Share", symbol: "square.and.arrow.up") {
              if let url = tab.url { ui.sheet = .share(url) }
            }
          }
          if showDisplay {
            displayOptions
          } else {
            menuRow("Display Options", symbol: "textformat.size", chevron: true) {
              withAnimation(.spring(response: 0.3)) { showDisplay = true }
            }
          }
          menuRow("Site Settings", symbol: "gearshape") { ui.sheet = .siteSettings }
          menuRow("Close Tab", symbol: "xmark.square") {
            browser.close(tab.id)
            ui.sheet = nil
          }
          blockerRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
      }
      .scrollBounceBehavior(.basedOnSize)
      .foregroundStyle(.white)
    }

    private var urlPill: some View {
      HStack(spacing: 6) {
        pillButton("chevron.left", enabled: tab.canGoBack) { tab.webView.goBack() }
        pillButton("chevron.right", enabled: tab.canGoForward) { tab.webView.goForward() }
        Button {
          ui.sheet = nil
          ui.startSearch(newTab: false, text: tab.urlString)
        } label: {
          Text(tab.host.isEmpty ? "Search" : tab.host)
            .font(.system(size: 19, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        pillButton(copied ? "checkmark" : "link", enabled: tab.url != nil) {
          UIPasteboard.general.url = tab.url
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          withAnimation { copied = true }
        }
        pillButton("arrow.clockwise", enabled: true) {
          tab.webView.reload()
          ui.sheet = nil
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 62)
      .background(Color.white.opacity(0.1), in: Capsule())
      .overlay(Capsule().stroke(Color.white.opacity(0.1)))
    }

    private func pillButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).frame(width: 42, height: 42)
      }
      .disabled(!enabled)
      .opacity(enabled ? 1 : 0.35)
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        VStack(spacing: 10) {
          Image(systemName: symbol)
            .font(.system(size: 27, weight: .regular))
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
          Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      .buttonStyle(PressStyle())
    }

    private func menuRow(_ title: String, symbol: String, chevron: Bool = false, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        HStack(spacing: 16) {
          Image(systemName: symbol).font(.system(size: 21)).frame(width: 28)
          Text(title).font(.system(size: 19))
          Spacer()
          if chevron { Image(systemName: "chevron.right").foregroundStyle(Palette.secondaryText) }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      }
      .buttonStyle(PressStyle())
    }

    private var displayOptions: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: "textformat.size").font(.system(size: 21)).frame(width: 28)
          Text("Text Size").font(.system(size: 19))
          Spacer()
          Text("\(Int(browser.settings.textZoom * 100))%").foregroundStyle(Palette.secondaryText).monospacedDigit()
        }
        HStack(spacing: 12) {
          Button { browser.settings.textZoom = max(0.5, browser.settings.textZoom - 0.1) } label: { Image(systemName: "textformat.size.smaller").frame(width: 44, height: 36) }
          Slider(value: $browser.settings.textZoom, in: 0.5...2, step: 0.1).tint(.white)
          Button { browser.settings.textZoom = min(2, browser.settings.textZoom + 0.1) } label: { Image(systemName: "textformat.size.larger").frame(width: 44, height: 36) }
        }
      }
      .padding(18)
      .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var blockerRow: some View {
      let host = tab.host
      let allowed = browser.isAllowed(host)
      return Button {
        browser.setBlocking(allowed, for: host)
        tab.webView.reload()
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(allowed ? "Blocking is off for \(host)" : "Ardia blocks ads and trackers here").font(.system(size: 18, weight: .medium))
          Text(allowed ? "Tap to turn blocking back on" : "Problems? Tap to allow this site").font(.system(size: 16)).foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      }
      .buttonStyle(PressStyle())
      .disabled(host.isEmpty)
    }
  }
}

struct SiteSettingsView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    let host = browser.activeTab?.host ?? ""
    NavigationStack {
      List {
        if !host.isEmpty {
          Section("\(host.uppercased()) settings") {
            ToggleRow(title: "Block Ads", symbol: "hand.raised.fill", color: .red, isOn: siteBinding(\.blockAds, host))
            ToggleRow(title: "Block Cookie Banners", symbol: "birthday.cake.fill", color: .orange, isOn: siteBinding(\.blockCookieBanners, host))
            ToggleRow(title: "Block Trackers", symbol: "eyeglasses", color: .yellow, isOn: siteBinding(\.blockTrackers, host))
          }
        }
        Section {
          ToggleRow(title: "Collapse Bottom Bar", symbol: "iphone.gen3", color: .purple, isOn: $browser.settings.collapseBottomBar)
          ToggleRow(title: "Swipe to Navigate", symbol: "hand.draw.fill", color: .green, isOn: $browser.settings.swipeToNavigate)
        }
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Site Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            browser.activeTab?.webView.reload()
            ui.sheet = nil
          }
          .fontWeight(.semibold)
        }
      }
    }
  }

  private func siteBinding(_ key: WritableKeyPath<BrowserSettings, Bool>, _ host: String) -> Binding<Bool> {
    Binding {
      browser.settings[keyPath: key] && !browser.isAllowed(host)
    } set: { on in
      if on {
        browser.settings[keyPath: key] = true
        browser.setBlocking(true, for: host)
      } else {
        browser.setBlocking(false, for: host)
      }
    }
  }
}

struct ToggleRow: View {
  let title: String
  let symbol: String
  let color: Color
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 14) {
        IconBadge(symbol: symbol, color: color, size: 32)
        Text(title)
      }
    }
    .tint(.green)
    .listRowBackground(Color.white.opacity(0.08))
  }
}

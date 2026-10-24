import SwiftUI

enum HingeState: Equatable {
  case none, closed, partiallyOpen, fullyOpen
}

enum FoldPosture: Equatable {
  case compact
  case open
  case book
  case laptop

  static let wideWidth: CGFloat = 600

  static func of(size: CGSize, hinge: HingeState) -> FoldPosture {
    let landscape = size.width > size.height
    if hinge == .partiallyOpen, max(size.width, size.height) >= wideWidth {
      return landscape ? .laptop : .book
    }
    return size.width >= wideWidth ? .open : .compact
  }
}

struct HingeObserver: ViewModifier {
  @Binding var state: HingeState

  func body(content: Content) -> some View {
    if #available(iOS 27.1, *) {
      content.onHingeChange { _, new in
        state = Self.state(new.hinge?.status)
      }
    } else {
      content
    }
  }

  @available(iOS 27.1, *)
  static func state(_ status: DeviceHinge.Status?) -> HingeState {
    switch status {
    case .some(.closed): .closed
    case .some(.partiallyOpen): .partiallyOpen
    case .some(.fullyOpen): .fullyOpen
    default: .none
    }
  }
}

struct WideBrowserView: View {
  let sidebarWidth: CGFloat
  let hingeAligned: Bool
  var rail: CGFloat = 0
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @AppStorage("sidebarHidden") private var sidebarHidden = false

  var body: some View {
    HStack(spacing: 0) {
      if !sidebarHidden {
        BrowserSidebar(sidebarHidden: $sidebarHidden)
          .frame(width: sidebarWidth)
          .environment(\.colorScheme, .dark)
          .transition(.move(edge: .leading))
        if hingeAligned {
          Color.black.frame(width: 1).ignoresSafeArea()
        }
      }
      ZStack {
        if let tab = browser.activeTab, !(tab.isPrivate && browser.privateLocked) {
          WideContent(tab: tab, rail: rail, sidebarHidden: $sidebarHidden)
        } else if browser.privateMode, browser.privateLocked {
          PrivateLockView().environment(\.colorScheme, .dark)
        } else {
          WideEmptyState().environment(\.colorScheme, .dark)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

struct WideContent: View {
  @ObservedObject var tab: BrowserTab
  var rail: CGFloat = 0
  @Binding var sidebarHidden: Bool
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    ZStack(alignment: .trailing) {
      VStack(spacing: 0) {
        WideToolbar(tab: tab, compact: rail > 0, sidebarHidden: $sidebarHidden)
          .background(Palette.canvas.ignoresSafeArea(edges: rail > 0 ? [.top, .trailing] : .top))
          .environment(\.colorScheme, .dark)
        ZStack(alignment: .top) {
          WebViewHost(tab: tab).ignoresSafeArea(edges: rail > 0 ? [.bottom, .trailing] : .bottom)
          if tab.isLoading && tab.progress < 1 {
            ProgressView(value: tab.progress).progressViewStyle(.linear).tint(.white.opacity(0.85)).frame(height: 2)
          }
        }
      }
      if rail > 0 {
        WideRail(tab: tab, width: rail, sidebarHidden: $sidebarHidden)
          .environment(\.colorScheme, .dark)
          .frame(maxHeight: .infinity)
          .offset(x: rail)
          .ignoresSafeArea(edges: [.top, .bottom])
      }
    }
  }
}

struct WideToolbar: View {
  @ObservedObject var tab: BrowserTab
  var compact = false
  var sidebarHidden: Binding<Bool>?
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    HStack(spacing: 6) {
      if let sidebarHidden, sidebarHidden.wrappedValue {
        toolButton("sidebar.left", "Show Sidebar", enabled: true) {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { sidebarHidden.wrappedValue = false }
        }
      }
      toolButton("chevron.left", "Back", enabled: tab.canGoBack) { tab.webView.goBack() }
      toolButton("chevron.right", "Forward", enabled: tab.canGoForward) { tab.webView.goForward() }
      toolButton(tab.isLoading ? "xmark" : "arrow.clockwise", tab.isLoading ? "Stop" : "Reload", enabled: true) {
        if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() }
      }
      Button { ui.startSearch(newTab: false, text: tab.urlString) } label: {
        HStack(spacing: 6) {
          if tab.isPrivate { Image(systemName: "eyes").font(.system(size: 12)) }
          if tab.url?.scheme == "https" { Image(systemName: "lock.fill").font(.system(size: 11)) }
          Text(tab.host.isEmpty ? "Search or enter address" : tab.host).lineLimit(1)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(Color.white.opacity(0.1), in: Capsule())
      }
      .accessibilityLabel("Address")
      if !compact {
        toolButton(desktop.isPinned(tab.urlString) ? "pin.fill" : "pin", "Pin to Mac", enabled: SharedLink.isWeb(tab.url)) {
          guard let url = tab.url else { return }
          ui.sheet = desktop.connected ? .pin(SharedLink(url: url.absoluteString, title: tab.displayTitle)) : .connect
        }
        toolButton("square.and.arrow.up", "Share", enabled: tab.url != nil) { if let url = tab.url { ui.sheet = .share(url) } }
      }
      toolButton("ellipsis", "Page Menu", enabled: true) { ui.sheet = .pageMenu }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  private func toolButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 38, height: 38)
    }
    .foregroundStyle(.white)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.35)
    .accessibilityLabel(label)
  }
}

struct WideEmptyState: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(spacing: 18) {
      Spacer()
      FidgetLogo(size: 84)
      Button { ui.startSearch(newTab: true) } label: {
        HStack {
          Image(systemName: "magnifyingglass")
          Text(browser.privateMode ? "Search privately" : "Search or enter address")
          Spacer()
        }
        .font(.system(size: 19))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 22)
        .frame(maxWidth: 520)
        .frame(height: 58)
        .background(Color.white.opacity(0.1), in: Capsule())
      }
      Spacer()
      Spacer()
    }
    .padding(30)
  }
}

struct BrowserSidebar: View {
  @Binding var sidebarHidden: Bool
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var openFolders: Set<String> = []

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          if !browser.privateMode, let space = desktop.selectedSpace {
            pins(space)
          }
          Button { ui.startSearch(newTab: true) } label: {
            row(icon: AnyView(Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 24)), title: "New Tab", selected: false, subtle: true)
          }
          ForEach(browser.visibleTabs.reversed()) { tab in
            SidebarTabRow(tab: tab, selected: tab.id == browser.activeTabId) {
              browser.select(tab.id)
            } close: {
              withAnimation(.snappy) { browser.close(tab.id) }
            }
          }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 20)
      }
      footer
    }
    .foregroundStyle(.white)
    .background {
      if browser.privateMode {
        LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.26), Color(red: 0.06, green: 0.05, blue: 0.09)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
      } else {
        Palette.spaceGradient(desktop.selectedSpace?.swatchHex ?? "#5B4B8A").overlay(Color.black.opacity(0.3)).ignoresSafeArea()
      }
    }
  }

  private var header: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        FidgetLogo(size: 32)
        Text(browser.privateMode ? "Private" : (desktop.selectedSpace?.name ?? "Ardia"))
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .lineLimit(1)
        Spacer()
        Button { ui.sheet = .settings } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
          .accessibilityLabel("Settings")
        Button {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { sidebarHidden = true }
        } label: { Image(systemName: "sidebar.left").font(.system(size: 17)) }
          .padding(.leading, 6)
          .accessibilityLabel("Hide Sidebar")
      }
      Button { ui.startSearch(newTab: true) } label: {
        HStack {
          Image(systemName: "magnifyingglass")
          Text("Search").lineLimit(1)
          Spacer()
        }
        .font(.system(size: 16))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 10)
  }

  @ViewBuilder
  private func pins(_ space: DesktopSpace) -> some View {
    if !space.tiles.isEmpty {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
        ForEach(space.tiles) { pin in
          Button { browser.openOrSwitch(to: pin.url) } label: {
            FaviconView(url: pin.url, size: 22, emoji: pin.customIcon)
              .frame(maxWidth: .infinity)
              .frame(height: 44)
              .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .accessibilityLabel(pin.displayTitle)
        }
      }
      .padding(.bottom, 8)
    }
    ForEach(space.rows) { pin in
      Button { browser.openOrSwitch(to: pin.url) } label: {
        row(icon: AnyView(FaviconView(url: pin.url, size: 20, emoji: pin.customIcon)), title: pin.displayTitle, selected: browser.activeTab?.urlString == pin.url)
      }
    }
    ForEach(space.folders) { folder in
      Button {
        withAnimation(.snappy) {
          if openFolders.contains(folder.id) { openFolders.remove(folder.id) } else { openFolders.insert(folder.id) }
        }
      } label: {
        row(icon: AnyView(Image(systemName: openFolders.contains(folder.id) ? "folder.fill" : "folder").font(.system(size: 17)).frame(width: 24)), title: folder.name, selected: false)
      }
      if openFolders.contains(folder.id) {
        ForEach(folder.pins) { pin in
          Button { browser.openOrSwitch(to: pin.url) } label: {
            row(icon: AnyView(FaviconView(url: pin.url, size: 20, emoji: pin.customIcon)), title: pin.displayTitle, selected: browser.activeTab?.urlString == pin.url)
          }
          .padding(.leading, 22)
        }
      }
    }
    if space.pinCount > 0 {
      Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 8).padding(.horizontal, 6)
    }
  }

  private func row(icon: AnyView, title: String, selected: Bool, subtle: Bool = false) -> some View {
    HStack(spacing: 12) {
      icon
      Text(title).font(.system(size: 16)).lineLimit(1)
      Spacer(minLength: 0)
    }
    .foregroundStyle(subtle ? .white.opacity(0.6) : .white)
    .padding(.horizontal, 10)
    .frame(height: 40)
    .background(selected ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .contentShape(Rectangle())
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Button { browser.setPrivateMode(!browser.privateMode) } label: {
        Image(systemName: "eyes")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(browser.privateMode ? Color.purple : .white.opacity(0.7))
          .frame(width: 34, height: 34)
          .background(browser.privateMode ? Color.white : .clear, in: Circle())
      }
      .accessibilityLabel("Private Browsing")
      if !browser.privateMode {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 2) {
            ForEach(desktop.snapshot.spaces) { space in
              Button { withAnimation(.snappy) { desktop.selectedSpaceId = space.id } } label: {
                SpaceBadge(space: space, size: 16, selected: space.id == desktop.selectedSpace?.id)
              }
              .accessibilityLabel(space.name)
            }
          }
        }
        Button { ui.sheet = desktop.connected ? .spaces : .connect } label: {
          Image(systemName: "laptopcomputer").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityLabel("Your Mac’s Spaces")
      } else {
        Spacer()
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 52)
  }
}

struct SidebarTabRow: View {
  @ObservedObject var tab: BrowserTab
  let selected: Bool
  let open: () -> Void
  let close: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      FaviconView(url: tab.urlString, size: 20)
      Text(tab.displayTitle).font(.system(size: 16)).lineLimit(1)
      Spacer(minLength: 0)
      if selected {
        Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.6)) }
          .accessibilityLabel("Close Tab")
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 40)
    .background(selected ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .contentShape(Rectangle())
    .onTapGesture(perform: open)
    .contextMenu {
      Button(role: .destructive, action: close) { Label("Close Tab", systemImage: "xmark") }
    }
  }
}

struct LaptopBrowserView: View {
  let split: CGFloat
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if let tab = browser.activeTab, !(tab.isPrivate && browser.privateLocked) {
          WebViewHost(tab: tab).ignoresSafeArea(edges: .horizontal)
        } else {
          WideEmptyState().environment(\.colorScheme, .dark)
        }
      }
      .frame(height: split)
      .clipped()
      LaptopDeck()
        .environment(\.colorScheme, .dark)
        .frame(maxHeight: .infinity)
    }
  }
}

struct LaptopDeck: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(spacing: 12) {
      if let tab = browser.activeTab {
        WideToolbar(tab: tab)
      } else {
        Button { ui.startSearch(newTab: true) } label: {
          Label("Search or enter address", systemImage: "magnifyingglass")
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(Color.white.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 10)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(browser.visibleTabs) { tab in
            LaptopTabChip(tab: tab, selected: tab.id == browser.activeTabId) { browser.select(tab.id) }
          }
          Button { ui.startSearch(newTab: true) } label: {
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
              .frame(width: 52, height: 52).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .accessibilityLabel("New Tab")
        }
        .padding(.horizontal, 14)
      }
      if !browser.privateMode, let space = desktop.selectedSpace, !(space.tiles + space.rows).isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(space.tiles + space.rows) { pin in
              Button { browser.openOrSwitch(to: pin.url) } label: {
                HStack(spacing: 8) {
                  FaviconView(url: pin.url, size: 18, emoji: pin.customIcon)
                  Text(pin.displayTitle).font(.footnote).lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.white.opacity(0.08), in: Capsule())
              }
            }
          }
          .padding(.horizontal, 14)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 10)
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .background(
      LinearGradient(colors: [Color(red: 0.14, green: 0.13, blue: 0.18), Color(red: 0.09, green: 0.09, blue: 0.11)], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    )
  }
}

struct LaptopTabChip: View {
  @ObservedObject var tab: BrowserTab
  let selected: Bool
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: 8) {
        FaviconView(url: tab.urlString, size: 20)
        Text(tab.displayTitle).font(.subheadline).lineLimit(1).frame(maxWidth: 150, alignment: .leading)
      }
      .padding(.horizontal, 12)
      .frame(height: 52)
      .background(selected ? Color.white.opacity(0.2) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

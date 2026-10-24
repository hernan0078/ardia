import SwiftUI
import WebKit

enum RootSheet: Identifiable {
  case pageMenu, siteSettings, settings, spaces, connect
  case pin(SharedLink)
  case share(URL)
  case reader(ReaderArticle)

  var id: String {
    switch self {
    case .pageMenu: "page"
    case .siteSettings: "site"
    case .settings: "settings"
    case .spaces: "spaces"
    case .connect: "connect"
    case .pin(let link): "pin:\(link.url)"
    case .share(let url): "share:\(url)"
    case .reader(let article): "reader:\(article.id)"
    }
  }
}

@MainActor
final class UIStateModel: ObservableObject {
  @Published var searching = false
  @Published var searchInNewTab = true
  @Published var searchText = ""
  @Published var switcher = false
  @Published var sheet: RootSheet?
  @Published var toast: String?
  @Published var barExpanded = false
  @Published var voiceRequested = false
  private var toastTask: Task<Void, Never>?

  func showToast(_ text: String) {
    toast = text
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(for: .seconds(2.2))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.25)) { toast = nil }
    }
  }

  func startSearch(newTab: Bool, text: String = "", voice: Bool = false) {
    searchInNewTab = newTab
    searchText = text
    voiceRequested = voice
    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { searching = true }
  }
}

struct RootView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @StateObject private var ui = UIStateModel()
  @State private var hinge = HingeState.none

  var body: some View {
    GeometryReader { geo in
      let posture = FoldPosture.of(size: geo.size, hinge: hinge)
      ZStack(alignment: posture == .compact ? .bottom : .top) {
        backdrop.ignoresSafeArea()
        switch posture {
        case .compact:
          compactBody(rail: Rail.width(geo.safeAreaInsets))
        case .open:
          WideBrowserView(sidebarWidth: min(340, geo.size.width * 0.36), hingeAligned: false, rail: Rail.width(geo.safeAreaInsets))
        case .book:
          WideBrowserView(sidebarWidth: geo.size.width / 2, hingeAligned: true, rail: Rail.width(geo.safeAreaInsets))
        case .laptop:
          LaptopBrowserView(split: geo.size.height / 2)
        }
        if ui.searching {
          SearchPanel(floating: posture != .compact)
            .environment(\.colorScheme, .dark)
            .frame(maxHeight: posture == .laptop ? geo.size.height / 2 : .infinity, alignment: .top)
            .frame(maxHeight: .infinity, alignment: posture == .laptop ? .bottom : .top)
            .transition(.move(edge: posture == .compact ? .bottom : .top).combined(with: .opacity))
            .zIndex(2)
        }
        if let toast = ui.toast {
          Label(toast, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Palette.hairline))
            .environment(\.colorScheme, .dark)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, posture == .compact ? 110 : 30)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(3)
        }
      }
      .animation(.spring(response: 0.4, dampingFraction: 0.9), value: posture)
      .onChange(of: posture) { _, new in
        if new != .compact { ui.switcher = false }
      }
    }
    .modifier(HingeObserver(state: $hinge))
    .environmentObject(ui)
    .preferredColorScheme(lightStatusBar ? .light : .dark)
    .animation(.spring(response: 0.38, dampingFraction: 0.88), value: ui.switcher)
    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: browser.activeTabId)
    .sheet(item: $ui.sheet) { sheet in
      sheetContent(sheet)
        .environmentObject(browser)
        .environmentObject(desktop)
        .environmentObject(ui)
        .preferredColorScheme(.dark)
    }
    .onAppear {
      if browser.launchAction != nil {
        run(browser.launchAction)
      } else if browser.activeTab == nil, browser.settings.autoOpenKeyboard {
        ui.startSearch(newTab: true)
      }
    }
    .onChange(of: browser.launchAction) { _, action in run(action) }
  }

  @ViewBuilder
  private func compactBody(rail: CGFloat) -> some View {
      if let tab = browser.activeTab, !ui.switcher, !(tab.isPrivate && browser.privateLocked) {
        BrowsingView(tab: tab, rail: rail)
          .transition(.opacity)
      } else if browser.privateMode, browser.privateLocked {
        PrivateLockView()
          .environment(\.colorScheme, .dark)
          .transition(.opacity)
      } else if ui.switcher {
        TabSwitcherView()
          .environment(\.colorScheme, .dark)
          .transition(.opacity.combined(with: .scale(scale: 1.04)))
      } else if browser.privateMode {
        PrivateHomeView()
          .environment(\.colorScheme, .dark)
          .transition(.opacity)
      } else {
        SpaceHomeView()
          .environment(\.colorScheme, .dark)
          .transition(.opacity)
      }
  }

  private func run(_ action: LaunchAction?) {
    guard let action else { return }
    browser.launchAction = nil
    ui.sheet = nil
    ui.switcher = false
    browser.setPrivateMode(action == .privateSearch)
    ui.searching = false
    DispatchQueue.main.async { ui.startSearch(newTab: true, voice: action == .voice) }
  }

  private var lightStatusBar: Bool {
    guard !ui.switcher, !ui.searching, let color = browser.activeTab?.themeColor else { return false }
    return color.isLight
  }

  @ViewBuilder
  private var backdrop: some View {
    if browser.privateMode {
      LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.26), Color(red: 0.06, green: 0.05, blue: 0.09)], startPoint: .top, endPoint: .bottom)
    } else {
      Palette.spaceGradient(desktop.selectedSpace?.swatchHex ?? "#5B4B8A")
        .overlay(Color.black.opacity(0.25))
    }
  }

  @ViewBuilder
  private func sheetContent(_ sheet: RootSheet) -> some View {
    switch sheet {
    case .pageMenu:
      PageMenuView()
        .presentationDetents([.height(560), .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(40)
    case .siteSettings:
      SiteSettingsView()
        .presentationDetents([.height(640), .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(40)
    case .settings:
      SettingsView()
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(40)
    case .spaces:
      DesktopSpacesView()
        .presentationBackground(.clear)
        .presentationCornerRadius(40)
    case .connect:
      ConnectView()
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(40)
    case .pin(let link):
      PinComposer(link: link, snapshot: desktop.snapshot, initialSpaceId: desktop.selectedSpaceId, asRow: SharedStore.shared.pinAsRow) { spaceId, folderId, asRow in
        SharedStore.shared.pinAsRow = asRow
        let name = desktop.snapshot.space(spaceId)?.name ?? "your Mac"
        ui.sheet = nil
        Task {
          let saved = await desktop.pin(url: link.url, title: link.title, spaceId: spaceId, folderId: folderId, asRow: asRow)
          ui.showToast(saved ? "Pinned to \(name) on \(desktop.macName)" : "Couldn’t save the pin. Try again.")
        }
      } cancel: {
        ui.sheet = nil
      }
      .presentationDetents([.height(600), .large])
      .presentationBackground(Palette.sheet)
      .presentationCornerRadius(40)
    case .share(let url):
      ActivityView(items: [url])
        .presentationDetents([.medium, .large])
    case .reader(let article):
      ReaderView(article: article) {
        ui.sheet = nil
      } openLink: { url in
        ui.sheet = nil
        browser.openInNewTab(url)
      }
    }
  }
}

struct BrowsingView: View {
  @ObservedObject var tab: BrowserTab
  var rail: CGFloat = 0
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel
  @AppStorage("pageUnderRail") private var pageUnderRail = true

  private var collapsed: Bool { browser.settings.collapseBottomBar && tab.scrollingDown && !ui.barExpanded }
  private var topColor: Color { tab.themeColor.map(Color.init(uiColor:)) ?? Palette.canvas }

  var body: some View {
    if rail > 0 {
      railBody
    } else {
      barBody
    }
  }

  private var railBody: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        topColor.frame(height: 0).background(topColor.ignoresSafeArea(edges: .top))
        WebViewHost(tab: tab)
          .ignoresSafeArea(edges: pageUnderRail ? [.bottom, .trailing] : [.bottom])
      }
      if !pageUnderRail {
        HStack(spacing: 0) {
          Spacer()
          Palette.canvas.frame(width: rail)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
      }
      if tab.isLoading && tab.progress < 1 {
        VStack {
          ProgressView(value: tab.progress).progressViewStyle(.linear).tint(.white.opacity(0.85)).frame(height: 2)
          Spacer()
        }
      }
      AddressPill(tab: tab, collapsed: collapsed)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, collapsed ? 0 : 12)
        .padding(.bottom, 6)
        .transition(.opacity)
      HStack(spacing: 0) {
        Spacer()
        CoverRail(tab: tab, width: rail, extendsPage: $pageUnderRail)
          .environment(\.colorScheme, .dark)
      }
      .ignoresSafeArea(edges: [.trailing, .top, .bottom])
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.9), value: collapsed)
    .onChange(of: tab.scrollingDown) { _, down in if down { ui.barExpanded = false } }
  }

  private var barBody: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        topColor.frame(height: 0).background(topColor.ignoresSafeArea(edges: .top))
        WebViewHost(tab: tab)
          .ignoresSafeArea(edges: .bottom)
      }
      if tab.isLoading && tab.progress < 1 {
        VStack {
          ProgressView(value: tab.progress)
            .progressViewStyle(.linear)
            .tint(.white.opacity(0.85))
            .frame(height: 2)
          Spacer()
        }
      }
      if collapsed {
        Button {
          withAnimation(.spring(response: 0.3)) { ui.barExpanded = true }
        } label: {
          HStack(spacing: 6) {
            if tab.isPrivate { Image(systemName: "eyes").font(.system(size: 11)) }
            if tab.url?.scheme == "https" { Image(systemName: "lock.fill").font(.system(size: 10)) }
            Text(tab.host).font(.footnote.weight(.medium))
          }
          .foregroundStyle(.white.opacity(0.9))
          .padding(.horizontal, 14)
          .padding(.vertical, 7)
          .background(.ultraThinMaterial, in: Capsule())
        }
        .environment(\.colorScheme, .dark)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      } else {
        BrowsingBar(tab: tab)
          .environment(\.colorScheme, .dark)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.9), value: collapsed)
    .onChange(of: tab.scrollingDown) { _, down in if down { ui.barExpanded = false } }
  }
}

struct BrowsingBar: View {
  @ObservedObject var tab: BrowserTab
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    HStack {
      TabStackButton {
        tab.captureSnapshot()
        ui.switcher = true
      }
      Spacer()
      PlusButton { ui.startSearch(newTab: true) } longPress: { ui.startSearch(newTab: false, text: tab.urlString) }
      Spacer()
      CircleButton(symbol: "chevron.up") { ui.sheet = .pageMenu }
    }
    .padding(.horizontal, 26)
    .padding(.top, 14)
    .padding(.bottom, 2)
    .background(alignment: .bottom) {
      LinearGradient(colors: tab.isPrivate ? [.clear, Color(red: 0.12, green: 0.08, blue: 0.2).opacity(0.7), Color(red: 0.07, green: 0.05, blue: 0.12).opacity(0.95)] : [.clear, Color(red: 0.36, green: 0.30, blue: 0.48).opacity(0.55), Color(red: 0.30, green: 0.25, blue: 0.42).opacity(0.9)], startPoint: .top, endPoint: .bottom)
        .background(.ultraThinMaterial.opacity(0.6))
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
        .ignoresSafeArea(edges: .bottom)
        .frame(height: 140)
        .allowsHitTesting(false)
    }
    .gesture(DragGesture(minimumDistance: 20).onEnded { value in
      if value.translation.height < -40 { ui.sheet = .pageMenu }
    })
  }
}

struct PlusButton: View {
  let action: () -> Void
  var longPress: (() -> Void)?
  @GestureState private var pressed = false

  private var gesture: some Gesture {
    LongPressGesture(minimumDuration: 0.45)
      .updating($pressed) { value, state, _ in state = value }
      .exclusively(before: TapGesture())
      .onEnded(handle)
  }

  private func handle(_ result: ExclusiveGesture<GestureStateGesture<LongPressGesture, Bool>, TapGesture>.Value) {
    switch result {
    case .first: (longPress ?? action)()
    case .second: action()
    }
  }

  private var capsule: some View {
    Image(systemName: "plus")
      .font(.system(size: 24, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: 92, height: 48)
      .background(Color.white.opacity(0.16), in: Capsule())
      .overlay(Capsule().stroke(Color.white.opacity(0.12)))
  }

  var body: some View {
    capsule
      .scaleEffect(pressed ? 0.92 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
      .contentShape(Capsule())
      .gesture(gesture)
      .accessibilityElement()
      .accessibilityLabel("New Tab")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { action() }
      .accessibilityAction(named: "Edit Address") { (longPress ?? action)() }
  }
}

struct CircleButton: View {
  let symbol: String
  var size: CGFloat = 48
  var label: String = ""
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.4, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.14), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.1)))
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(label.isEmpty ? Self.defaultLabel(symbol) : label)
  }

  static func defaultLabel(_ symbol: String) -> String {
    switch symbol {
    case "chevron.up": "Page Menu"
    case "laptopcomputer": "Your Mac’s Spaces"
    case "gearshape": "Settings"
    case "eyes": "Private Browsing"
    default: symbol
    }
  }
}

struct TabStackButton: View {
  @EnvironmentObject private var browser: BrowserModel
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        let recent = Array(browser.visibleTabs.sorted { $0.lastActive > $1.lastActive }.prefix(3).reversed())
        ForEach(Array(recent.enumerated()), id: \.element.id) { index, tab in
          TabThumb(tab: tab)
            .rotationEffect(.degrees(Double(index - recent.count + 1) * 9))
            .offset(x: CGFloat(index - recent.count + 1) * 3)
        }
        if recent.isEmpty {
          RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.6), lineWidth: 2).frame(width: 30, height: 40)
        }
      }
      .frame(width: 56, height: 56)
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel("Show Tabs (\(browser.visibleTabs.count))")
  }
}

struct TabThumb: View {
  @ObservedObject var tab: BrowserTab

  var body: some View {
    Group {
      if let snapshot = tab.snapshot {
        Image(uiImage: snapshot).resizable().scaledToFill()
      } else {
        ZStack {
          Color.white.opacity(0.9)
          FaviconView(url: tab.urlString, size: 16)
        }
      }
    }
    .frame(width: 32, height: 44)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.85), lineWidth: 1.5))
    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
  }
}

struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

struct WebViewHost: UIViewRepresentable {
  @ObservedObject var tab: BrowserTab

  func makeUIView(context: Context) -> UIView {
    let container = UIView()
    container.backgroundColor = .clear
    attach(tab.webView, to: container)
    return container
  }

  func updateUIView(_ container: UIView, context: Context) {
    if tab.webView.superview !== container {
      container.subviews.forEach { $0.removeFromSuperview() }
      attach(tab.webView, to: container)
    }
  }

  private func attach(_ webView: WKWebView, to container: UIView) {
    webView.removeFromSuperview()
    webView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: container.topAnchor),
      webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
  }
}

struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PrivateHomeView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(spacing: 18) {
      HStack {
        Label("Private", systemImage: "eyes").font(.system(size: 26, weight: .bold, design: .rounded))
        Spacer()
        Button("Exit") { browser.setPrivateMode(false) }
          .font(.headline)
          .padding(.horizontal, 16)
          .frame(height: 38)
          .background(Color.white.opacity(0.14), in: Capsule())
      }
      VStack(alignment: .leading, spacing: 10) {
        Label("Pages you open here stay out of your history and your Mac's synced tabs.", systemImage: "clock.badge.xmark")
        Label("Cookies and site data last only until you close your last private tab.", systemImage: "trash")
        Label(browser.settings.lockPrivateTabs ? "Your private tabs lock when you leave Ardia." : "Lock private tabs with Face ID in Settings.", systemImage: "faceid")
      }
      .font(.subheadline)
      .foregroundStyle(.white.opacity(0.75))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
      .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      Spacer()
      if !ui.searching {
        HStack {
          CircleButton(symbol: "eyes", size: 48) { browser.setPrivateMode(false) }
          Spacer()
          PlusButton { ui.startSearch(newTab: true) }
          Spacer()
          TabStackButton { ui.switcher = true }
            .opacity(browser.visibleTabs.isEmpty ? 0 : 1)
        }
        .padding(.horizontal, 6)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 12)
    .foregroundStyle(.white)
  }
}

struct PrivateLockView: View {
  @EnvironmentObject private var browser: BrowserModel
  @State private var failed = false

  var body: some View {
    VStack(spacing: 18) {
      Spacer()
      Image(systemName: "lock.fill").font(.system(size: 44, weight: .semibold))
      Text("Private tabs are locked").font(.title3.weight(.semibold))
      Button {
        Task { failed = !(await browser.unlockPrivateTabs()) }
      } label: {
        Label("Unlock", systemImage: "faceid")
          .font(.headline)
          .padding(.horizontal, 26)
          .frame(height: 50)
          .background(Color.white.opacity(0.18), in: Capsule())
      }
      if failed { Text("Couldn’t unlock. Try again.").font(.footnote).foregroundStyle(.orange) }
      Button("Back to Tabs") { browser.setPrivateMode(false) }
        .foregroundStyle(.white.opacity(0.7))
      Spacer()
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .task { failed = !(await browser.unlockPrivateTabs()) }
  }
}

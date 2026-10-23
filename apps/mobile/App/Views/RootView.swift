import SwiftUI
import WebKit

enum RootSheet: Identifiable {
  case pageMenu, siteSettings, settings, spaces, connect
  case pin(SharedLink)
  case share(URL)

  var id: String {
    switch self {
    case .pageMenu: "page"
    case .siteSettings: "site"
    case .settings: "settings"
    case .spaces: "spaces"
    case .connect: "connect"
    case .pin(let link): "pin:\(link.url)"
    case .share(let url): "share:\(url)"
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

  func startSearch(newTab: Bool, text: String = "") {
    searchInNewTab = newTab
    searchText = text
    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { searching = true }
  }
}

struct RootView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @StateObject private var ui = UIStateModel()

  var body: some View {
    ZStack(alignment: .bottom) {
      backdrop.ignoresSafeArea()
      if let tab = browser.activeTab, !ui.switcher {
        BrowsingView(tab: tab)
          .transition(.opacity)
      } else if ui.switcher {
        TabSwitcherView()
          .environment(\.colorScheme, .dark)
          .transition(.opacity.combined(with: .scale(scale: 1.04)))
      } else {
        SpaceHomeView()
          .environment(\.colorScheme, .dark)
          .transition(.opacity)
      }
      if ui.searching {
        SearchPanel()
          .environment(\.colorScheme, .dark)
          .transition(.move(edge: .bottom).combined(with: .opacity))
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
          .padding(.bottom, 110)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(3)
      }
    }
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
      if browser.activeTab == nil, browser.settings.autoOpenKeyboard { ui.startSearch(newTab: true) }
    }
  }

  private var lightStatusBar: Bool {
    guard !ui.switcher, !ui.searching, let color = browser.activeTab?.themeColor else { return false }
    return color.isLight
  }

  private var backdrop: some View {
    Palette.spaceGradient(desktop.selectedSpace?.swatchHex ?? "#5B4B8A")
      .overlay(Color.black.opacity(0.25))
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
        desktop.pin(url: link.url, title: link.title, spaceId: spaceId, folderId: folderId, asRow: asRow)
        let name = desktop.snapshot.space(spaceId)?.name ?? "your Mac"
        ui.sheet = nil
        ui.showToast("Pinned to \(name) on \(desktop.macName)")
      } cancel: {
        ui.sheet = nil
      }
      .presentationDetents([.height(600), .large])
      .presentationBackground(Palette.sheet)
      .presentationCornerRadius(40)
    case .share(let url):
      ActivityView(items: [url])
        .presentationDetents([.medium, .large])
    }
  }
}

struct BrowsingView: View {
  @ObservedObject var tab: BrowserTab
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel

  private var collapsed: Bool { browser.settings.collapseBottomBar && tab.scrollingDown && !ui.barExpanded }
  private var topColor: Color { tab.themeColor.map(Color.init(uiColor:)) ?? Palette.canvas }

  var body: some View {
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
      PlusButton { ui.startSearch(newTab: true) }
        .simultaneousGesture(LongPressGesture().onEnded { _ in ui.startSearch(newTab: false, text: tab.urlString) })
      Spacer()
      CircleButton(symbol: "chevron.up") { ui.sheet = .pageMenu }
    }
    .padding(.horizontal, 26)
    .padding(.top, 14)
    .padding(.bottom, 2)
    .background(alignment: .bottom) {
      LinearGradient(colors: [.clear, Color(red: 0.36, green: 0.30, blue: 0.48).opacity(0.55), Color(red: 0.30, green: 0.25, blue: 0.42).opacity(0.9)], startPoint: .top, endPoint: .bottom)
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

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 92, height: 48)
        .background(Color.white.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel("New Tab")
  }
}

struct CircleButton: View {
  let symbol: String
  var size: CGFloat = 48
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
  }
}

struct TabStackButton: View {
  @EnvironmentObject private var browser: BrowserModel
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        let recent = Array(browser.tabs.sorted { $0.lastActive > $1.lastActive }.prefix(3).reversed())
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
    .accessibilityLabel("Show Tabs (\(browser.tabs.count))")
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

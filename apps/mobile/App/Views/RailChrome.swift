import SwiftUI

enum Rail {
  static let minimumWidth: CGFloat = 44
  static let statusClearance: CGFloat = 168

  static func width(_ insets: EdgeInsets) -> CGFloat {
    insets.trailing >= minimumWidth ? insets.trailing : 0
  }
}

struct GlassCircle: ViewModifier {
  var size: CGFloat

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .frame(width: size, height: size)
        .glassEffect(.regular.interactive(), in: Circle())
    } else {
      content
        .frame(width: size, height: size)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.12)))
    }
  }
}

struct GlassCapsule: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.interactive(), in: Capsule())
    } else {
      content
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
    }
  }
}

struct RailButton: View {
  let symbol: String
  let label: String
  var size: CGFloat = 44
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.4, weight: .semibold))
        .foregroundStyle(.primary)
        .modifier(GlassCircle(size: size))
    }
    .buttonStyle(PressStyle())
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
    .accessibilityLabel(label)
  }
}

struct CoverRail: View {
  @ObservedObject var tab: BrowserTab
  let width: CGFloat
  @Binding var extendsPage: Bool
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(spacing: 14) {
      Color.clear.frame(height: Rail.statusClearance)
      RailButton(symbol: "chevron.left", label: "Back", enabled: tab.canGoBack) { tab.webView.goBack() }
      RailButton(symbol: "laptopcomputer", label: "Your Mac’s Spaces") { ui.sheet = desktop.connected ? .spaces : .connect }
      Spacer(minLength: 12)
      RailButton(symbol: extendsPage ? "arrow.right.and.line.vertical.and.arrow.left" : "arrow.left.and.right", label: extendsPage ? "Keep Page Out of the Side" : "Stretch Page Under the Side", size: 36) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { extendsPage.toggle() }
      }
      RailButton(symbol: "plus", label: "New Tab") { ui.startSearch(newTab: true) }
      Button {
        tab.captureSnapshot()
        ui.switcher = true
      } label: {
        Image(systemName: "square.on.square")
          .font(.system(size: 17, weight: .semibold))
          .modifier(GlassCircle(size: 44))
          .overlay(alignment: .topTrailing) {
            Text("\(browser.visibleTabs.count)")
              .font(.system(size: 10, weight: .bold))
              .padding(.horizontal, 4)
              .frame(minWidth: 17, minHeight: 17)
              .background(Color.white, in: Capsule())
              .foregroundStyle(.black)
              .offset(x: 3, y: -3)
          }
      }
      .buttonStyle(PressStyle())
      .accessibilityLabel("Show Tabs (\(browser.visibleTabs.count))")
    }
    .frame(width: width)
    .padding(.bottom, 18)
  }
}

struct AddressPill: View {
  @ObservedObject var tab: BrowserTab
  let collapsed: Bool
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    Group {
      if collapsed {
        Button {
          withAnimation(.spring(response: 0.3)) { ui.barExpanded = true }
        } label: {
          host
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .modifier(GlassCapsule())
        }
        .buttonStyle(.plain)
      } else {
        HStack(spacing: 4) {
          Button { ui.sheet = .pageMenu } label: {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 17, weight: .semibold)).frame(width: 42, height: 46)
          }
          .accessibilityLabel("Page Menu")
          Button { ui.startSearch(newTab: false, text: tab.urlString) } label: {
            host.font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity).frame(height: 46)
          }
          .accessibilityLabel("Address")
          Button {
            if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() }
          } label: {
            Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise").font(.system(size: 16, weight: .semibold)).frame(width: 42, height: 46)
          }
          .accessibilityLabel(tab.isLoading ? "Stop" : "Reload")
        }
        .padding(.horizontal, 4)
        .modifier(GlassCapsule())
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
          if value.translation.height < -30 { ui.sheet = .pageMenu }
        })
      }
    }
    .foregroundStyle(.primary)
  }

  private var host: some View {
    HStack(spacing: 5) {
      if tab.isPrivate { Image(systemName: "eyes").font(.system(size: 11)) }
      if tab.url?.scheme == "https" { Image(systemName: "lock.fill").font(.system(size: 10)) }
      Text(tab.host.isEmpty ? "Search" : tab.host).lineLimit(1)
    }
  }
}

struct WideRail: View {
  @ObservedObject var tab: BrowserTab
  let width: CGFloat
  @Binding var sidebarHidden: Bool
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(spacing: 14) {
      Color.clear.frame(height: Rail.statusClearance)
      RailButton(symbol: desktop.isPinned(tab.urlString) ? "pin.fill" : "pin", label: "Pin to Mac", enabled: SharedLink.isWeb(tab.url)) {
        guard let url = tab.url else { return }
        ui.sheet = desktop.connected ? .pin(SharedLink(url: url.absoluteString, title: tab.displayTitle)) : .connect
      }
      RailButton(symbol: "square.and.arrow.up", label: "Share", enabled: tab.url != nil) { if let url = tab.url { ui.sheet = .share(url) } }
      Spacer(minLength: 12)
      RailButton(symbol: "sidebar.left", label: sidebarHidden ? "Show Sidebar" : "Hide Sidebar") {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { sidebarHidden.toggle() }
      }
      RailButton(symbol: "plus", label: "New Tab") { ui.startSearch(newTab: true) }
    }
    .frame(width: width)
    .padding(.bottom, 18)
  }
}

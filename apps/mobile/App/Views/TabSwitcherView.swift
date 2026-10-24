import SwiftUI

struct TabSwitcherView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var focusedId: String?

  private var ordered: [BrowserTab] { browser.visibleTabs }

  var body: some View {
    GeometryReader { geo in
      let cardWidth = geo.size.width * 0.62
      let cardHeight = min(geo.size.height * 0.68, cardWidth * 2.05)
      VStack(spacing: 14) {
        modePicker
        Spacer(minLength: 12)
        header
        if ordered.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "square.on.square.dashed").font(.system(size: 40)).foregroundStyle(.white.opacity(0.4))
            Text("No open tabs").font(.headline).foregroundStyle(.white.opacity(0.6))
          }
          .frame(height: cardHeight)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
              ForEach(ordered) { tab in
                TabCard(tab: tab, width: cardWidth, height: cardHeight) {
                  open(tab)
                } close: {
                  withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { browser.close(tab.id) }
                }
                .id(tab.id)
                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                  content
                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
                    .opacity(phase.isIdentity ? 1 : 0.7)
                }
              }
            }
            .scrollTargetLayout()
          }
          .contentMargins(.horizontal, (geo.size.width - cardWidth) / 2, for: .scrollContent)
          .scrollTargetBehavior(.viewAligned)
          .scrollPosition(id: $focusedId)
          .frame(height: cardHeight + 20)
        }
        Spacer(minLength: 10)
        HStack {
          if browser.privateMode {
            Menu {
              Button(role: .destructive) { browser.closeAllPrivateTabs() } label: { Label("Close All Private Tabs", systemImage: "xmark") }
            } label: {
              Image(systemName: "eyes").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 50, height: 50).background(Color.white.opacity(0.14), in: Circle())
            }
          } else {
            CircleButton(symbol: "laptopcomputer", size: 50, label: "Your Mac’s Spaces") { ui.sheet = .spaces }
          }
          Spacer()
          PlusButton { ui.startSearch(newTab: true) }
          Spacer()
          CircleButton(symbol: "gearshape", size: 50, label: "Settings") { ui.sheet = .settings }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 4)
      }
    }
    .onAppear { focusedId = browser.activeTabId ?? browser.visibleTabs.last?.id }
    .onChange(of: browser.privateMode) { _, _ in focusedId = browser.activeTabId ?? browser.visibleTabs.last?.id }
  }

  private var modePicker: some View {
    HStack(spacing: 4) {
      modeButton("Tabs", count: browser.tabs.count - browser.privateTabs.count, on: !browser.privateMode) { browser.setPrivateMode(false) }
      modeButton("Private", count: browser.privateTabs.count, on: browser.privateMode) { browser.setPrivateMode(true) }
    }
    .padding(4)
    .background(Color.white.opacity(0.08), in: Capsule())
    .padding(.top, 8)
  }

  private func modeButton(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
    Button {
      withAnimation(.spring(response: 0.3)) { action() }
    } label: {
      HStack(spacing: 6) {
        if title == "Private" { Image(systemName: "eyes") }
        Text(count > 0 ? "\(title) \(count)" : title)
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(on ? Color.black : .white.opacity(0.8))
      .padding(.horizontal, 16)
      .frame(height: 34)
      .background(on ? Color.white : .clear, in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private var header: some View {
    let tab = browser.tab(focusedId)
    return HStack(spacing: 10) {
      if let tab {
        FocusedTabTitle(tab: tab)
      } else {
        Text("\(ordered.count) Tabs").font(.system(size: 19, weight: .medium))
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 40)
    .frame(height: 30)
    .animation(.easeOut(duration: 0.15), value: focusedId)
  }

  private func open(_ tab: BrowserTab) {
    browser.select(tab.id)
    ui.switcher = false
  }
}

struct TabCard: View {
  @ObservedObject var tab: BrowserTab
  let width: CGFloat
  let height: CGFloat
  let open: () -> Void
  let close: () -> Void
  @State private var drag: CGFloat = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        FaviconView(url: tab.urlString, size: 26)
        Text(tab.host.isEmpty ? tab.displayTitle : tab.host.capitalized(with: nil))
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        Spacer()
        Menu {
          Button(role: .destructive, action: close) { Label("Close Tab", systemImage: "xmark") }
          if let url = tab.url { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
          Button { UIPasteboard.general.url = tab.url } label: { Label("Copy Link", systemImage: "link") }
        } label: {
          Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 28, height: 28)
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(height: 50)
      .background(Color(red: 0.13, green: 0.13, blue: 0.15))
      ZStack {
        Color(white: 0.96)
        if let snapshot = tab.snapshot {
          Image(uiImage: snapshot).resizable().scaledToFill().frame(width: width, alignment: .top)
        } else {
          FaviconView(url: tab.urlString, size: 48)
        }
      }
      .frame(width: width, height: height - 50, alignment: .top)
      .clipped()
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    .offset(y: drag)
    .opacity(1 - Double(min(1, abs(min(drag, 0)) / 400)))
    .onTapGesture(perform: open)
    .simultaneousGesture(
      DragGesture(minimumDistance: 14)
        .onChanged { value in
          if abs(value.translation.height) > abs(value.translation.width) { drag = min(0, value.translation.height) }
        }
        .onEnded { value in
          if value.translation.height < -140 || value.predictedEndTranslation.height < -320 {
            withAnimation(.easeIn(duration: 0.18)) { drag = -900 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: close)
          } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
          }
        }
    )
  }
}

struct FocusedTabTitle: View {
  @ObservedObject var tab: BrowserTab

  var body: some View {
    FaviconView(url: tab.urlString, size: 26)
    Text(tab.displayTitle).font(.system(size: 19, weight: .medium)).lineLimit(1)
  }
}

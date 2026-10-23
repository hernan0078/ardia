import SwiftUI

struct DesktopSpacesView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var openFolders: Set<String> = []

  var body: some View {
    ZStack {
      Palette.spaceGradient(desktop.selectedSpace?.swatchHex ?? "#5B4B8A").ignoresSafeArea()
      Color(red: 0.16, green: 0.16, blue: 0.22).opacity(0.55).ignoresSafeArea()
      VStack(spacing: 0) {
        header
        if !desktop.connected {
          notConnected
        } else if let space = desktop.selectedSpace {
          ScrollView {
            content(space)
              .padding(.horizontal, 20)
              .padding(.bottom, 30)
          }
          .refreshable { desktop.refresh() }
        } else {
          Spacer()
          Text(desktop.statusLine).foregroundStyle(Palette.secondaryText).padding()
          Spacer()
        }
        spaceBar
      }
    }
    .foregroundStyle(.white)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(desktop.selectedSpace?.name.uppercased() ?? "YOUR MAC")
          .font(.system(size: 30, weight: .heavy, design: .rounded))
          .lineLimit(1)
        if desktop.connected {
          Text("\(desktop.macName) · \(desktop.statusLine)").font(.footnote).foregroundStyle(Palette.secondaryText).lineLimit(1)
        }
      }
      Spacer()
      Button { ui.sheet = nil } label: {
        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.75))
          .frame(width: 34, height: 34).background(Color.white.opacity(0.18), in: Circle())
      }
    }
    .padding(.horizontal, 26)
    .padding(.top, 30)
    .padding(.bottom, 14)
  }

  @ViewBuilder
  private func content(_ space: DesktopSpace) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if !space.tiles.isEmpty {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
          ForEach(space.tiles) { pin in
            Button { open(pin) } label: {
              FaviconView(url: pin.url, size: 28, emoji: pin.customIcon)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .contextMenu { pinMenu(pin, space: space) }
          }
        }
        .padding(.bottom, 10)
      }
      Button {
        browser.select(nil)
        ui.switcher = false
        ui.sheet = nil
      } label: {
        rowLabel(icon: AnyView(Image(systemName: "house").font(.system(size: 20)).frame(width: 30)), title: "Home")
      }
      ForEach(space.rows) { pin in
        pinRow(pin, space: space)
      }
      ForEach(space.folders) { folder in
        Button {
          withAnimation(.spring(response: 0.3)) {
            if openFolders.contains(folder.id) { openFolders.remove(folder.id) } else { openFolders.insert(folder.id) }
          }
        } label: {
          rowLabel(icon: AnyView(Image(systemName: openFolders.contains(folder.id) ? "folder.fill" : "folder").font(.system(size: 22)).frame(width: 30)), title: folder.name, trailing: "\(folder.pins.count)")
        }
        if openFolders.contains(folder.id) {
          ForEach(folder.pins) { pin in
            pinRow(pin, space: space).padding(.leading, 30)
          }
        }
      }
      if let tab = browser.activeTab, tab.url != nil {
        Button {
          ui.sheet = .pin(SharedLink(url: tab.urlString, title: tab.displayTitle))
        } label: {
          rowLabel(icon: AnyView(Image(systemName: "plus").font(.system(size: 20, weight: .medium)).frame(width: 30)), title: "Pin Current Page", subtle: true)
        }
      }
      ForEach(space.deviceTabs) { device in
        Text("OPEN ON \(device.name.uppercased())")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Palette.secondaryText)
          .padding(.top, 22)
          .padding(.bottom, 4)
        if device.tabs.isEmpty {
          Text("No open tabs").font(.subheadline).foregroundStyle(Palette.secondaryText)
        }
        ForEach(device.tabs, id: \.self) { link in
          Button { openLink(link.url) } label: {
            rowLabel(icon: AnyView(FaviconView(url: link.url, size: 26)), title: link.title.isEmpty ? link.url : link.title)
          }
          .contextMenu {
            Button { ui.sheet = .pin(link) } label: { Label("Pin to a Space", systemImage: "pin") }
            Button { UIPasteboard.general.string = link.url } label: { Label("Copy Link", systemImage: "link") }
          }
        }
      }
      if space.pinCount == 0 && space.deviceTabs.isEmpty {
        Text("Nothing pinned in \(space.name) yet.").font(.subheadline).foregroundStyle(Palette.secondaryText).padding(.top, 12)
      }
    }
  }

  private func pinRow(_ pin: DesktopPin, space: DesktopSpace) -> some View {
    Button { open(pin) } label: {
      rowLabel(icon: AnyView(FaviconView(url: pin.url, size: 26, emoji: pin.customIcon)), title: pin.displayTitle)
    }
    .contextMenu { pinMenu(pin, space: space) }
  }

  @ViewBuilder
  private func pinMenu(_ pin: DesktopPin, space: DesktopSpace) -> some View {
    Button { open(pin) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
    Button { UIPasteboard.general.string = pin.url } label: { Label("Copy Link", systemImage: "link") }
    if let url = URL(string: pin.url) { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
    Button(role: .destructive) { desktop.unpin(pin, in: space.id) } label: { Label("Unpin from Mac", systemImage: "pin.slash") }
  }

  private func rowLabel(icon: AnyView, title: String, trailing: String? = nil, subtle: Bool = false) -> some View {
    HStack(spacing: 16) {
      icon
      Text(title).font(.system(size: 20)).lineLimit(1)
      Spacer()
      if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Palette.secondaryText) }
    }
    .foregroundStyle(subtle ? Color.white.opacity(0.6) : .white)
    .padding(.vertical, 14)
    .contentShape(Rectangle())
  }

  private var notConnected: some View {
    VStack(spacing: 18) {
      Spacer()
      Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 54, weight: .light))
      Text("Bring your Mac’s spaces here").font(.title3.weight(.semibold))
      Text("Connect to Ardia on your Mac to browse your spaces and pinned tabs, and pin pages from your phone straight into a space.")
        .multilineTextAlignment(.center)
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 36)
      Button { ui.sheet = .connect } label: {
        Text("Connect to Mac").font(.headline).padding(.horizontal, 26).frame(height: 50).background(Color.white.opacity(0.2), in: Capsule())
      }
      Spacer()
    }
  }

  private var spaceBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(desktop.snapshot.spaces) { space in
          Button {
            withAnimation(.spring(response: 0.3)) { desktop.selectedSpaceId = space.id }
            SharedStore.shared.lastSpaceId = space.id
          } label: {
            SpaceBadge(space: space, size: 24, selected: space.id == desktop.selectedSpace?.id)
          }
          .accessibilityLabel(space.name)
        }
      }
      .padding(.horizontal, 24)
      .frame(minWidth: UIScreen.main.bounds.width, alignment: .leading)
    }
    .frame(height: 74)
    .background(Color.black.opacity(0.18))
    .opacity(desktop.snapshot.spaces.count > 1 ? 1 : 0)
  }

  private func open(_ pin: DesktopPin) { openLink(pin.url) }

  private func openLink(_ url: String) {
    browser.openOrSwitch(to: url)
    ui.searching = false
    ui.switcher = false
    ui.sheet = nil
  }
}

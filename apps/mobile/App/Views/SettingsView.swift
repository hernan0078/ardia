import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var confirmClear = false
  @State private var exportURL: URL?

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 12) {
            NavigationLink { HistoryView() } label: { capsuleLabel("History", symbol: "clock") }
            NavigationLink { ArchiveView() } label: { capsuleLabel("Archive", symbol: "archivebox") }
          }
          .buttonStyle(.plain)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        Section {
          NavigationLink { SyncSettingsView() } label: {
            row("Ardia on Your Mac", symbol: "laptopcomputer.and.iphone", color: .indigo, value: desktop.connected ? "On" : "Off")
          }
          NavigationLink { ShareHelpView() } label: {
            row("Pin from Other Apps", symbol: "square.and.arrow.up.fill", color: .blue)
          }
        } footer: {
          Text(desktop.connected ? "Syncing with \(desktop.macName) through your iCloud Drive, end-to-end encrypted." : "Connect to see your Mac’s spaces and pin pages into them.")
        }
        Section {
          NavigationLink { GlobalSiteSettingsView() } label: { row("Global Site Settings", symbol: "globe", color: .black) }
        }
        Section {
          Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
            row("Set Ardia as Default Browser", symbol: "safari.fill", color: .purple, chevron: true)
          }
          NavigationLink { AppIconPickerView() } label: {
            row("Change App Icon", symbol: "app.badge.fill", color: .blue, value: AppIconChoice.current.name)
          }
        }
        Section {
          Picker(selection: $browser.settings.searchEngine) {
            ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
          } label: { row("Search Engine", symbol: "magnifyingglass", color: .blue) }
          ToggleRow(title: "Search Suggestions", symbol: "text.magnifyingglass", color: .teal, isOn: $browser.settings.searchSuggestions)
        }
        Section {
          ToggleRow(title: "Auto-Open Keyboard", symbol: "keyboard.fill", color: .yellow, isOn: $browser.settings.autoOpenKeyboard)
          Picker(selection: $browser.settings.archiveAfter) {
            ForEach(ArchiveAfter.allCases) { Text($0.label).tag($0) }
          } label: { row("Archive Inactive Tabs", symbol: "archivebox.fill", color: .purple) }
          ToggleRow(title: "Show My Tabs on Mac", symbol: "macbook.and.iphone", color: .indigo, isOn: $browser.settings.shareTabsWithMac)
          Button { confirmClear = true } label: { row("Clear Browsing Data…", symbol: "eraser.fill", color: .red) }
          Button {
            exportURL = exportTabs()
          } label: {
            HStack(spacing: 14) {
              IconBadge(symbol: "square.and.arrow.up", color: .blue)
              VStack(alignment: .leading, spacing: 2) {
                Text("Export Data")
                Text("Share your open tab URLs").font(.caption).foregroundStyle(Palette.secondaryText)
              }
            }
          }
        }
        .listRowBackground(Color.white.opacity(0.08))
      }
      .scrollContentBackground(.hidden)
      .foregroundStyle(.white)
      .tint(.white)
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { ui.sheet = nil }.fontWeight(.semibold) }
      }
      .confirmationDialog("Clear browsing data?", isPresented: $confirmClear, titleVisibility: .visible) {
        Button("Clear History, Cookies and Site Data", role: .destructive) { Task { await browser.clearBrowsingData() } }
      } message: {
        Text("Open tabs stay open. You'll be signed out of websites.")
      }
      .sheet(item: $exportURL) { url in ActivityView(items: [url]).presentationDetents([.medium]) }
    }
  }

  private func capsuleLabel(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 18, weight: .medium))
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(Color.white.opacity(0.1), in: Capsule())
  }

  private func row(_ title: String, symbol: String, color: Color, value: String? = nil, chevron: Bool = false) -> some View {
    HStack(spacing: 14) {
      IconBadge(symbol: symbol, color: color)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(color == .black ? 0.2 : 0)))
      Text(title).foregroundStyle(.white)
      Spacer()
      if let value { Text(value).foregroundStyle(Palette.secondaryText) }
      if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondaryText) }
    }
  }

  private func exportTabs() -> URL? {
    let text = browser.openLinks.map { "\($0.title)\n\($0.url)" }.joined(separator: "\n\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ardia Tabs.txt")
    return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
  }
}

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}

struct GlobalSiteSettingsView: View {
  @EnvironmentObject private var browser: BrowserModel

  var body: some View {
    List {
      Section {
        ToggleRow(title: "Block Ads", symbol: "hand.raised.fill", color: .red, isOn: $browser.settings.blockAds)
        ToggleRow(title: "Block Cookie Banners", symbol: "birthday.cake.fill", color: .orange, isOn: $browser.settings.blockCookieBanners)
        ToggleRow(title: "Block Trackers", symbol: "eyeglasses", color: .yellow, isOn: $browser.settings.blockTrackers)
      }
      Section {
        ToggleRow(title: "Collapse Bottom Bar", symbol: "iphone.gen3", color: .purple, isOn: $browser.settings.collapseBottomBar)
        ToggleRow(title: "Swipe to Navigate", symbol: "hand.draw.fill", color: .green, isOn: $browser.settings.swipeToNavigate)
      }
      if !browser.settings.allowedSites.isEmpty {
        Section("Blocking turned off on") {
          ForEach(browser.settings.allowedSites, id: \.self) { Text($0) }
            .onDelete { browser.settings.allowedSites.remove(atOffsets: $0) }
            .listRowBackground(Color.white.opacity(0.08))
        }
      }
    }
    .scrollContentBackground(.hidden)
    .navigationTitle("Global Site Settings")
  }
}

struct HistoryView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var query = ""

  var body: some View {
    List {
      ForEach(browser.history.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query) }) { page in
        Button {
          browser.openOrSwitch(to: page.url)
          ui.sheet = nil
          ui.switcher = false
        } label: {
          HStack(spacing: 12) {
            FaviconView(url: page.url, size: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(page.title.isEmpty ? page.url : page.title).lineLimit(1)
              Text(page.visitedAt, style: .relative).font(.caption).foregroundStyle(Palette.secondaryText)
            }
          }
        }
        .listRowBackground(Color.white.opacity(0.08))
      }
    }
    .searchable(text: $query)
    .scrollContentBackground(.hidden)
    .navigationTitle("History")
  }
}

struct ArchiveView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    List {
      if browser.archive.isEmpty {
        Text("Closed and archived tabs show up here.").foregroundStyle(Palette.secondaryText).listRowBackground(Color.clear)
      }
      ForEach(browser.archive) { tab in
        Button {
          browser.reopen(tab)
          ui.sheet = nil
          ui.switcher = false
        } label: {
          HStack(spacing: 12) {
            FaviconView(url: tab.url, size: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(tab.title).lineLimit(1)
              Text(tab.archivedAt, style: .relative).font(.caption).foregroundStyle(Palette.secondaryText)
            }
          }
        }
        .listRowBackground(Color.white.opacity(0.08))
      }
      .onDelete { browser.archive.remove(atOffsets: $0) }
    }
    .scrollContentBackground(.hidden)
    .navigationTitle("Archive")
  }
}

struct ShareHelpView: View {
  var body: some View {
    List {
      Section {
        step(1, "In any app (X, Safari, Mail…), tap the Share button on a link or post.")
        step(2, "Choose “Pin to Ardia”. If it isn’t in the row of apps, scroll to the end, tap More, and add it to Favorites.")
        step(3, "Pick a space (and a folder if you like) and tap Pin. It appears in that space’s pinned tabs on your Mac.")
      } footer: {
        Text("Pins wait on your phone if iCloud Drive can’t be reached right away, and go out the next time you open Ardia.")
      }
      .listRowBackground(Color.white.opacity(0.08))
    }
    .scrollContentBackground(.hidden)
    .navigationTitle("Pin from Other Apps")
  }

  private func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(n)").font(.headline).frame(width: 28, height: 28).background(Color.blue, in: Circle())
      Text(text)
    }
    .padding(.vertical, 4)
  }
}

struct AppIconChoice: Identifiable, Equatable {
  let id: String
  let name: String

  static let all = [
    AppIconChoice(id: "default", name: "Default"),
    AppIconChoice(id: "midnight", name: "Midnight"),
    AppIconChoice(id: "daylight", name: "Daylight"),
    AppIconChoice(id: "plum", name: "Plum"),
    AppIconChoice(id: "ocean", name: "Ocean"),
    AppIconChoice(id: "mono", name: "Mono"),
    AppIconChoice(id: "noir", name: "Noir"),
  ]

  var alternateName: String? { id == "default" ? nil : "AppIcon-\(id)" }

  static var current: AppIconChoice {
    let name = UIApplication.shared.alternateIconName
    return all.first { $0.alternateName == name } ?? all[0]
  }
}

struct AppIconPickerView: View {
  @State private var current = AppIconChoice.current
  @State private var error: String?

  var body: some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 22) {
        ForEach(AppIconChoice.all) { choice in
          Button { choose(choice) } label: {
            VStack(spacing: 8) {
              Image("IconPreview-\(choice.id)")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color.white.opacity(0.12)))
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(choice == current ? Color.white : .clear, lineWidth: 2.5))
              Text(choice.name).font(.subheadline.weight(choice == current ? .semibold : .regular))
            }
          }
          .buttonStyle(PressStyle())
        }
      }
      .padding(22)
      if let error {
        Text(error).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 22)
      }
      Text("The same icons as Ardia on your Mac. iOS shows a short confirmation when the icon changes.")
        .font(.footnote)
        .foregroundStyle(Palette.secondaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
    }
    .foregroundStyle(.white)
    .navigationTitle("App Icon")
  }

  private func choose(_ choice: AppIconChoice) {
    guard choice != current, UIApplication.shared.supportsAlternateIcons else { return }
    UIApplication.shared.setAlternateIconName(choice.alternateName) { failure in
      Task { @MainActor in
        if let failure {
          error = failure.localizedDescription
        } else {
          error = nil
          current = choice
        }
      }
    }
  }
}

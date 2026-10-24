import SwiftUI

struct Suggestion: Identifiable, Hashable {
  enum Kind: Hashable { case search, url, history, openTab(String), pin(String) }
  let kind: Kind
  let title: String
  let url: String
  var id: String { "\(kind)-\(url)-\(title)" }
}

struct SearchPanel: View {
  var floating = false
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @FocusState private var focused: Bool
  @State private var remote: [String] = []
  @State private var fetch: Task<Void, Never>?
  @StateObject private var voice = VoiceSearch()

  var body: some View {
    ZStack(alignment: floating ? .top : .bottom) {
      Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { dismiss() }
      VStack(spacing: 6) {
        if !floating {
          Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 8)
        }
        field
        if voice.state == .listening {
          ListeningView(voice: voice)
        } else {
          if case .denied(let message) = voice.state {
            Label(message, systemImage: "mic.slash").font(.footnote).foregroundStyle(.orange).padding(.top, 6)
          }
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(suggestions) { suggestion in
                row(suggestion)
              }
            }
            .padding(.bottom, 8)
          }
          .scrollDismissesKeyboard(.never)
          .frame(maxHeight: 330)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, floating ? 10 : 0)
      .background {
        if floating {
          RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black.opacity(0.32)))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        } else {
          UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous).fill(Color.black.opacity(0.28)))
            .ignoresSafeArea(edges: .bottom)
        }
      }
      .frame(maxWidth: floating ? 580 : .infinity)
      .padding(.top, floating ? 24 : 0)
      .padding(.horizontal, floating ? 20 : 0)
      .gesture(DragGesture().onEnded { value in if floating ? value.translation.height < -60 : value.translation.height > 80 { dismiss() } })
    }
    .onAppear {
      if ui.voiceRequested {
        ui.voiceRequested = false
        listen()
      } else {
        focused = true
      }
    }
    .onDisappear { voice.stop(submit: false) }
    .onChange(of: ui.searchText) { _, text in loadRemote(text) }
  }

  private var field: some View {
    HStack(spacing: 12) {
      TextField("Search or enter address", text: $ui.searchText)
        .focused($focused)
        .font(.system(size: 22, weight: .regular))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.webSearch)
        .submitLabel(.go)
        .onSubmit { go(ui.searchText) }
      if !ui.searchText.isEmpty {
        Button { ui.searchText = "" } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
        }
      }
      if ui.searchText.isEmpty {
        Button(action: listen) {
          Image(systemName: "mic").font(.system(size: 21)).foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityLabel("Search by Voice")
      }
      Button {
        browser.setPrivateMode(!browser.privateMode)
        ui.searchInNewTab = true
      } label: {
        Image(systemName: "eyes")
          .font(.system(size: 20, weight: browser.privateMode ? .bold : .regular))
          .foregroundStyle(browser.privateMode ? Color.purple : .white.opacity(0.75))
          .frame(width: 34, height: 34)
          .background(browser.privateMode ? Color.white.opacity(0.9) : .clear, in: Circle())
      }
      .accessibilityLabel(browser.privateMode ? "Private Browsing On" : "Private Browsing")
    }
    .padding(.horizontal, 22)
    .frame(height: 64)
    .background(Color.white.opacity(0.12), in: Capsule())
    .overlay(Capsule().stroke(Color.white.opacity(0.1)))
    .padding(.top, 4)
  }

  @ViewBuilder
  private func row(_ s: Suggestion) -> some View {
    Button { pick(s) } label: {
      HStack(spacing: 14) {
        switch s.kind {
        case .search: Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium)).frame(width: 26)
        case .url: Image(systemName: "globe").font(.system(size: 20)).frame(width: 26)
        default: FaviconView(url: s.url, size: 26)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(s.title).font(.system(size: 19)).lineLimit(1)
          if case .search = s.kind {} else if s.title != s.url {
            Text(URL(string: s.url)?.host() ?? s.url).font(.footnote).foregroundStyle(Palette.secondaryText).lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        switch s.kind {
        case .openTab: chip("Switch to Tab")
        case .pin(let space): chip(space)
        default: EmptyView()
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func chip(_ text: String) -> some View {
    Text(text)
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.1), in: Capsule())
      .overlay(Capsule().stroke(Color.white.opacity(0.14)))
  }

  private var suggestions: [Suggestion] {
    let q = ui.searchText.trimmingCharacters(in: .whitespaces).lowercased()
    let history = browser.privateMode ? [] : browser.history
    let pins = desktop.snapshot.spaces.flatMap { space in
      (space.tiles + space.rows + space.folders.flatMap(\.pins)).map { (space.name, $0) }
    }
    if q.isEmpty {
      var out: [Suggestion] = history.prefix(4).map { Suggestion(kind: .history, title: $0.title.isEmpty ? $0.url : $0.title, url: $0.url) }
      if let space = desktop.selectedSpace {
        out += (space.tiles + space.rows).prefix(4).map { Suggestion(kind: .pin(space.name), title: $0.displayTitle, url: $0.url) }
      }
      return out
    }
    var out: [Suggestion] = []
    if let url = browser.resolve(ui.searchText.trimmingCharacters(in: .whitespacesAndNewlines)), !url.absoluteString.contains("?q="), url.host() != nil {
      out.append(Suggestion(kind: .url, title: ui.searchText, url: url.absoluteString))
    }
    out.append(Suggestion(kind: .search, title: ui.searchText, url: ui.searchText))
    let matches = { (title: String, url: String) in title.lowercased().contains(q) || url.lowercased().contains(q) }
    out += browser.visibleTabs.filter { matches($0.displayTitle, $0.urlString) }.prefix(2).map { Suggestion(kind: .openTab($0.id), title: $0.displayTitle, url: $0.urlString) }
    out += pins.filter { matches($0.1.displayTitle, $0.1.url) }.prefix(3).map { Suggestion(kind: .pin($0.0), title: $0.1.displayTitle, url: $0.1.url) }
    out += history.filter { matches($0.title, $0.url) }.prefix(3).map { Suggestion(kind: .history, title: $0.title.isEmpty ? $0.url : $0.title, url: $0.url) }
    out += remote.filter { $0.lowercased() != q }.prefix(4).map { Suggestion(kind: .search, title: $0, url: $0) }
    var seen = Set<String>()
    return out.filter { seen.insert("\($0.kind == .search ? "s" : "u")|\($0.kind == .search ? $0.title.lowercased() : $0.url)").inserted }
  }

  private func listen() {
    focused = false
    voice.reset()
    Task {
      await voice.start { text in
        ui.searchText = text
        go(text)
      }
    }
  }

  private func loadRemote(_ text: String) {
    fetch?.cancel()
    remote = []
    let query = text.trimmingCharacters(in: .whitespaces)
    guard browser.settings.searchSuggestions, !browser.privateMode, query.count >= 2, !query.contains("://"), browser.resolve(query)?.host() == browser.settings.searchEngine.searchURL(query)?.host(),
          let url = browser.settings.searchEngine.suggestionsURL(query) else {
      remote = []
      return
    }
    fetch = Task {
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled, let (data, _) = try? await URLSession.shared.data(from: url) else { return }
      let json = try? JSONSerialization.jsonObject(with: data)
      let list: [String] = {
        if let values = json as? [Any], let suggestions = values.dropFirst().first as? [String] { return suggestions }
        return (json as? [[String: Any]])?.compactMap { $0["phrase"] as? String } ?? []
      }()
      if !Task.isCancelled { remote = list }
    }
  }

  private func pick(_ s: Suggestion) {
    switch s.kind {
    case .openTab(let id):
      browser.select(id)
      close()
    case .search:
      go(s.title)
    default:
      go(s.url)
    }
  }

  private func go(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    browser.open(text, inNewTab: ui.searchInNewTab || browser.activeTab == nil)
    close()
  }

  private func close() {
    focused = false
    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
      ui.searching = false
      ui.switcher = false
    }
  }

  private func dismiss() {
    close()
  }
}

struct SpaceHomeView: View {
  @EnvironmentObject private var browser: BrowserModel
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        FidgetLogo(size: 42)
        Text(desktop.selectedSpace?.name ?? "Ardia").font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1)
        Spacer()
        CircleButton(symbol: "gearshape", size: 40) { ui.sheet = .settings }
      }
      if let space = desktop.selectedSpace, !space.tiles.isEmpty || !space.rows.isEmpty {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
          ForEach(Array((space.tiles + space.rows).prefix(8))) { pin in
            Button { browser.openOrSwitch(to: pin.url) } label: {
              VStack(spacing: 6) {
                FaviconView(url: pin.url, size: 30, emoji: pin.customIcon)
                  .frame(maxWidth: .infinity)
                  .frame(height: 62)
                  .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(pin.displayTitle).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.75))
              }
            }
            .buttonStyle(PressStyle())
          }
        }
      } else if !desktop.connected {
        Button { ui.sheet = .connect } label: {
          HStack(spacing: 14) {
            IconBadge(symbol: "laptopcomputer.and.iphone", color: .indigo, size: 40)
            VStack(alignment: .leading, spacing: 3) {
              Text("Connect to Ardia on your Mac").font(.headline)
              Text("See your spaces and pinned tabs here, and pin pages to your Mac from anywhere.").font(.subheadline).foregroundStyle(Palette.secondaryText)
            }
            Spacer(minLength: 0)
          }
          .padding(16)
          .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(.white)
      }
      Spacer()
      if !ui.searching {
        HStack {
          CircleButton(symbol: "laptopcomputer", size: 48) { ui.sheet = .spaces }
          Spacer()
          PlusButton { ui.startSearch(newTab: true) }
          Spacer()
          TabStackButton { ui.switcher = true }
            .opacity(browser.visibleTabs.isEmpty ? 0 : 1)
            .allowsHitTesting(!browser.visibleTabs.isEmpty)
        }
        .padding(.horizontal, 6)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 12)
    .foregroundStyle(.white)
  }
}

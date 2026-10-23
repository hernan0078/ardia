import SwiftUI

struct PinComposer: View {
  let link: SharedLink
  let snapshot: DesktopSnapshot
  let pin: (_ spaceId: String, _ folderId: String?, _ asRow: Bool) -> Void
  let cancel: () -> Void
  @State private var spaceId: String?
  @State private var folderId: String?
  @State private var asRow: Bool

  init(link: SharedLink, snapshot: DesktopSnapshot, initialSpaceId: String?, asRow: Bool, pin: @escaping (String, String?, Bool) -> Void, cancel: @escaping () -> Void) {
    self.link = link
    self.snapshot = snapshot
    self.pin = pin
    self.cancel = cancel
    _spaceId = State(initialValue: snapshot.space(initialSpaceId)?.id ?? snapshot.defaultSpace?.id)
    _asRow = State(initialValue: asRow)
  }

  private var space: DesktopSpace? { snapshot.space(spaceId) }
  private var macName: String { snapshot.devices.first?.name ?? "your Mac" }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel", action: cancel).foregroundStyle(.white.opacity(0.8))
        Spacer()
        Text("Pin to Mac").font(.headline)
        Spacer()
        Button("Cancel", action: cancel).hidden()
      }
      .padding(.horizontal, 22)
      .padding(.top, 22)
      .padding(.bottom, 16)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          preview
          if snapshot.spaces.isEmpty {
            Text("No spaces have synced from your Mac yet. Turn on Pinned Tabs and Groups in Ardia › Settings › Sync on your Mac.")
              .font(.subheadline)
              .foregroundStyle(Palette.secondaryText)
          } else {
            section("Space") {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                  ForEach(snapshot.spaces) { s in
                    Button {
                      withAnimation(.snappy) {
                        spaceId = s.id
                        folderId = nil
                      }
                    } label: {
                      HStack(spacing: 6) {
                        SpaceBadge(space: s, size: 18, selected: s.id == spaceId)
                        Text(s.name).font(.subheadline.weight(.semibold)).padding(.trailing, 10)
                      }
                      .padding(2)
                      .background(s.id == spaceId ? Color(hex: s.swatchHex).opacity(0.35) : Color.white.opacity(0.08), in: Capsule())
                      .overlay(Capsule().stroke(s.id == spaceId ? Color(hex: s.swatchHex) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                  }
                }
                .padding(.vertical, 2)
              }
            }
            if let space, !space.folders.isEmpty {
              section("Folder") {
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 8) {
                    chip("None", symbol: "pin", selected: folderId == nil) { folderId = nil }
                    ForEach(space.folders) { f in
                      chip(f.name, symbol: "folder", selected: folderId == f.id) { folderId = f.id }
                    }
                  }
                }
              }
            }
            if folderId == nil {
              section("Show as") {
                Picker("Show as", selection: $asRow) {
                  Text("Pinned Row").tag(true)
                  Text("Tile").tag(false)
                }
                .pickerStyle(.segmented)
              }
            }
          }
        }
        .padding(.horizontal, 22)
      }
      Button {
        if let spaceId { pin(spaceId, folderId, asRow) }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "pin.fill")
          Text(space.map { "Pin to \($0.name)" } ?? "Pin")
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Color(hex: space?.swatchHex ?? "#7873AF"), in: Capsule())
      }
      .disabled(space == nil)
      .opacity(space == nil ? 0.5 : 1)
      .padding(.horizontal, 22)
      .padding(.vertical, 14)
      Text("It shows up in this space’s pinned tabs on \(macName) the next time Ardia syncs.")
        .font(.footnote)
        .foregroundStyle(Palette.secondaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.bottom, 16)
    }
    .foregroundStyle(.white)
    .background(Palette.sheet.ignoresSafeArea())
  }

  private var preview: some View {
    HStack(spacing: 14) {
      FaviconView(url: link.url, size: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text(link.title.isEmpty ? (URL(string: link.url)?.host() ?? link.url) : link.title).font(.headline).lineLimit(2)
        Text(link.url).font(.footnote).foregroundStyle(Palette.secondaryText).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title.uppercased()).font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondaryText)
      content()
    }
  }

  private func chip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: { withAnimation(.snappy, action) }) {
      Label(title, systemImage: symbol)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(selected ? Color.white.opacity(0.25) : Color.white.opacity(0.08), in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

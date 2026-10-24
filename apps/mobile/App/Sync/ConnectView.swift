import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct ConnectView: View {
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var phrase = ""
  @State private var name = DesktopModel.defaultDeviceName
  @State private var pickingFolder = false
  @State private var scanning = false
  @State private var folderChosen = SharedStore.shared.folderBookmark != nil || SharedStore.shared.folderPathOverride != nil
  @State private var error: String?
  @State private var busy = false

  private var wordCount: Int { RecoveryPhrase.tokens(in: phrase).count }
  private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 40, weight: .light))
            Text("Connect to Ardia on your Mac").font(.title2.weight(.bold))
            Text("Your phone joins Ardia Sync like another Mac: end-to-end encrypted, through your own iCloud Drive, with no account.")
              .foregroundStyle(Palette.secondaryText)
          }
          step(1, "On your Mac", "Open Ardia › Settings › Sync. Turn on Sync if it’s off, then choose Connect Another Device…")
          step(2, "Scan or enter the recovery phrase", nil)
          VStack(alignment: .leading, spacing: 10) {
            if canScan {
              Button { scanning = true } label: {
                Label("Scan the QR Code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity).frame(height: 48)
                  .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
            }
            TextField("Enter your 24-word recovery phrase", text: $phrase, axis: .vertical)
              .lineLimit(3...6)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .padding(14)
              .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
              Spacer()
              Text(wordCount > 24 ? "too many words" : "\(wordCount)/24 words").font(.caption).foregroundStyle(wordCount == 24 ? .green : Palette.secondaryText)
            }
          }
          .padding(.leading, 42)
          step(3, "Choose the sync folder", "Pick the “Ardia Sync” folder in iCloud Drive (or the folder your Mac syncs to).")
          Button { pickingFolder = true } label: {
            HStack {
              Image(systemName: folderChosen ? "checkmark.circle.fill" : "folder")
                .foregroundStyle(folderChosen ? .green : .white)
              Text(folderChosen ? desktop.folderName : "Choose Folder…")
              Spacer()
              if folderChosen { Text("Change").foregroundStyle(Palette.secondaryText) }
            }
            .padding(14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
          .padding(.leading, 42)
          step(4, "Name this iPhone", "Your Mac lists it under Devices and in “Your iPhone Tabs”.")
          TextField("Name", text: $name)
            .padding(14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.leading, 42)
          if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.subheadline)
          }
          Button(action: connect) {
            HStack {
              if busy { ProgressView().tint(.black) }
              Text(busy ? "Connecting…" : "Connect")
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white, in: Capsule())
          }
          .disabled(busy || wordCount != 24 || !folderChosen)
          .opacity(wordCount == 24 && folderChosen ? 1 : 0.4)
        }
        .padding(24)
      }
      .foregroundStyle(.white)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { ui.sheet = nil } }
      }
      .sheet(isPresented: $pickingFolder) {
        FolderPicker { url in
          do {
            try desktop.chooseFolder(url)
            folderChosen = true
            error = nil
          } catch {
            self.error = error.localizedDescription
          }
        }
        .ignoresSafeArea()
      }
      .fullScreenCover(isPresented: $scanning) {
        QRScanner { text in
          phrase = RecoveryPhrase.tokens(in: text).joined(separator: " ")
          scanning = false
        } cancel: {
          scanning = false
        }
        .ignoresSafeArea()
      }
    }
  }

  private func step(_ n: Int, _ title: String, _ detail: String?) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(n)").font(.subheadline.weight(.bold)).frame(width: 28, height: 28).background(Color.white.opacity(0.18), in: Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        if let detail { Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryText) }
      }
    }
  }

  private func connect() {
    busy = true
    error = nil
    Task {
      do {
        try await desktop.connect(phrase: phrase, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? DesktopModel.defaultDeviceName : name)
        phrase = ""
        ui.sheet = nil
        ui.showToast("Connected to \(desktop.macName)")
      } catch {
        self.error = error.localizedDescription
      }
      busy = false
    }
  }
}

struct SyncSettingsView: View {
  @EnvironmentObject private var desktop: DesktopModel
  @EnvironmentObject private var ui: UIStateModel
  @State private var name = ""
  @State private var confirmDisconnect = false
  @State private var disconnectError: String?

  var body: some View {
    List {
      if desktop.connected {
        Section {
          HStack {
            Text("Status")
            Spacer()
            Text(desktop.statusLine).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.trailing)
          }
          Button("Sync Now") { desktop.refresh(forceTabs: true) }
          if desktop.outboxCount > 0 {
            Text("\(desktop.outboxCount) pin\(desktop.outboxCount == 1 ? "" : "s") waiting to sync").foregroundStyle(.orange)
          }
        }
        Section("This iPhone") {
          TextField("Name", text: $name).onSubmit(saveName)
          HStack {
            Text("Sync Folder")
            Spacer()
            Text(desktop.folderName).foregroundStyle(Palette.secondaryText)
          }
        }
        Section("Devices") {
          if desktop.snapshot.devices.isEmpty { Text("No other devices yet").foregroundStyle(Palette.secondaryText) }
          ForEach(desktop.snapshot.devices) { device in
            HStack {
              Image(systemName: "laptopcomputer")
              Text(device.name)
              Spacer()
              if let seen = device.lastSeen { Text(seen, style: .relative).font(.caption).foregroundStyle(Palette.secondaryText) }
            }
          }
        }
        Section("Spaces") {
          ForEach(desktop.snapshot.spaces) { space in
            HStack(spacing: 12) {
              SpaceBadge(space: space, size: 18, selected: true)
              Text(space.name)
              Spacer()
              Text("\(space.pinCount) pinned").foregroundStyle(Palette.secondaryText)
            }
          }
        }
        Section {
          Button("Stop Syncing This iPhone", role: .destructive) { confirmDisconnect = true }
        } footer: {
          Text("Your Mac keeps everything. This iPhone forgets the key and stops showing your spaces.")
        }
      } else {
        Section {
          Button("Connect to Mac…") { ui.sheet = .connect }
        } footer: {
          Text("Ardia keeps your data in your own iCloud Drive, sealed with your recovery phrase.")
        }
      }
    }
    .listRowBackground(Color.white.opacity(0.08))
    .scrollContentBackground(.hidden)
    .refreshable { await desktop.refreshNow(forceTabs: true) }
    .navigationTitle("Ardia on Your Mac")
    .onAppear {
      name = desktop.deviceName
      desktop.refresh()
    }
    .onDisappear(perform: saveName)
    .confirmationDialog("Stop syncing this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
      Button("Stop Syncing", role: .destructive) { stop(force: false) }
    }
    .alert("Couldn’t reach the sync folder", isPresented: Binding(get: { disconnectError != nil }, set: { if !$0 { disconnectError = nil } })) {
      Button("Forget Anyway", role: .destructive) { stop(force: true) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("\(disconnectError ?? "") Your Mac will keep listing this iPhone until you remove it there.")
    }
  }

  private func saveName() {
    guard desktop.connected else { return }
    let clean = CompanionSync.cleanName(name)
    name = clean
    if clean != desktop.deviceName { desktop.rename(clean) }
  }

  private func stop(force: Bool) {
    Task {
      do {
        try await desktop.disconnect(force: force)
      } catch {
        disconnectError = error.localizedDescription
      }
    }
  }
}

struct FolderPicker: UIViewControllerRepresentable {
  let picked: (URL) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.allowsMultipleSelection = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let picked: (URL) -> Void
    init(picked: @escaping (URL) -> Void) { self.picked = picked }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      if let url = urls.first { picked(url) }
    }
  }
}

struct QRScanner: UIViewControllerRepresentable {
  let found: (String) -> Void
  let cancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(found: found) }

  func makeUIViewController(context: Context) -> UINavigationController {
    let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
    scanner.delegate = context.coordinator
    scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in cancel() })
    scanner.navigationItem.title = "Scan the QR code on your Mac"
    try? scanner.startScanning()
    return UINavigationController(rootViewController: scanner)
  }

  func updateUIViewController(_ controller: UINavigationController, context: Context) {}

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let found: (String) -> Void
    private var done = false
    init(found: @escaping (String) -> Void) { self.found = found }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
      for item in addedItems {
        guard !done, case .barcode(let code) = item, let text = code.payloadStringValue, RecoveryPhrase.tokens(in: text).count == 24 else { continue }
        done = true
        dataScanner.stopScanning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        found(text)
      }
    }
  }
}

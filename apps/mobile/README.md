# Ardia for iPhone

An Arc-style mobile browser that works with Ardia on the Mac.
Browse on your phone, see your Mac's spaces and pinned tabs, and pin pages (from Ardia or from any
app's share sheet) into a chosen space on your Mac.

## How it talks to the Mac

There's no server. The phone joins **Ardia Sync** as one more device:

- Ardia on the Mac writes end-to-end encrypted files to a folder in iCloud Drive (`Ardia Sync`).
- The phone opens that folder (picked once with the Files picker) and unlocks it with the same
  24-word recovery phrase (scan the QR in Ardia › Settings › Sync › Connect Another Device).
- Spaces are Ardia profiles (`prof:` records). Pins are `pin:t:` / `pin:g:` / `pinrow:` records in
  each profile's scope. The phone reads them and writes new pins as its own log files. Ardia on the
  Mac picks them up on its next sync cycle (every 15 s) and adds them to that space's pinned tabs.
- The phone also publishes its device name (`dev:`) and its open tabs (`tabs:`), so the Mac shows
  "Your iPhone Tabs" in its overflow menu.

The crypto and file format are the Mac's own: the project compiles `packages/sync/ios/Core`
(`SyncCrypto`, `SyncVault`, `RecoveryPhrase`, `Wordlist`, `LegacyName`) into both targets.
`Shared/Companion` is the phone's side of the merge: a replica that keeps only the keys it shows
(`prof:`, `pth:`, `dev:`, `pin:`, `pinrow:`, `tabs:`; never passwords or history), plus a writer
that journals each batch before writing it, numbers its logs without gaps, and never compacts or
deletes anyone's files.

No change to the desktop app is needed.

## Layout

- `App/`: the SwiftUI browser (WKWebView tabs, search panel, page menu, tab switcher, spaces sheet,
  settings, pairing flow, icon picker).
- `ShareExtension/`: "Pin to Ardia" in the iOS share sheet.
- `Shared/`: sync code and UI used by both targets. They share state through the App Group
  `group.com.hernan.ardiamobile` (outbox of pins, cached spaces, sync key in the Keychain).
- `Tools/interop/run.sh`: seeds a fake Mac sync folder, pins from the phone code, then runs the
  desktop's own merge (`packages/sync/src/scope.ts`) over the result and checks the pins, the
  version vectors and that `assignPositions` keeps the phone's positions.
- `Tools/make-icons.swift`: renders the 7 app icons (Default, Midnight, Daylight, Plum, Ocean,
  Mono, Noir) from the desktop's `AppIconMark` artwork, like the Mac app's icon picker.

## Build

Needs Xcode 27.1 or later (the app runs on iOS 18 and later, and uses the iOS 27.1 hinge APIs on foldables) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`); the `.xcodeproj` is generated, not checked in.

Signing comes from `Config/Signing.xcconfig`: no team, bundle ID `dev.ardia.mobile` and App Group
`group.dev.ardia.mobile`. To sign with your own team, put your values in `Config/Signing.local.xcconfig`
(git-ignored), for example:

```
DEVELOPMENT_TEAM = ABCDE12345
ARDIA_BUNDLE_ID = com.example.ardia
ARDIA_APP_GROUP = group.com.example.ardia
```

```bash
cd apps/mobile
xcodegen generate
```

Then open `ArdiaMobile.xcodeproj`, or build from the command line:

```bash
xcodebuild -project ArdiaMobile.xcodeproj -scheme ArdiaMobile -destination 'id=<device udid>' -allowProvisioningUpdates build
```

To install that build on a connected device:

```bash
xcrun devicectl device install app --device <device udid> <derived data>/Build/Products/Debug-iphoneos/Ardia.app
```

From `apps/mobile`, check the sync files against the Mac's merge:

```bash
Tools/interop/run.sh
```

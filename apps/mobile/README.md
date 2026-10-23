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

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`); the
`.xcodeproj` is generated, not checked in.

```bash
cd apps/mobile
xcodegen generate
```

Then open `ArdiaMobile.xcodeproj`, or build and install from the command line:

```bash
xcodebuild -project ArdiaMobile.xcodeproj -scheme ArdiaMobile -destination 'id=<device udid>' -allowProvisioningUpdates build
```

Signing team, bundle ID and App Group are at the top of `project.yml` (`DEVELOPMENT_TEAM`,
`ARDIA_APP_GROUP`, and the two `PRODUCT_BUNDLE_IDENTIFIER`s); change them to your own.

```bash
apps/mobile/Tools/interop/run.sh
```

#!/bin/zsh
set -euo pipefail
here=${0:A:h}
root=${here:h:h}
repo=${root:h:h}
core=$repo/packages/sync/ios/Core
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 5 -O -o "$work/interop" "$core"/{SyncCrypto,SyncVault,RecoveryPhrase,Wordlist,LegacyName}.swift "$root"/Shared/Companion/*.swift "$here/main.swift"
mkdir -p "$work/folder" "$work/companion"
cd "$work"
./interop new-phrase folder phrase.txt
ARDIA_COMPANION_DIR="$work/companion" ./interop seed folder phrase.txt
ARDIA_COMPANION_DIR="$work/companion" ./interop phone-pin folder phrase.txt
for scope in app p:worksync p:personalsync; do ./interop dump folder phrase.txt "$scope" > "dump-$scope.json"; done
cp "$here/check.mts" .
ARDIA_SYNC_SRC="${ARDIA_SYNC_SRC:-$repo/packages/sync/src}" node --no-warnings check.mts | tail -1

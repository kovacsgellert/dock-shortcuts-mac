#!/bin/bash
# Assemble DockShortcuts.app from the SwiftPM release binary.
# Usage: VERSION=0.1.0 OUT=dist ./scripts/package-app.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.0.0-dev)}"
OUT="${OUT:-$ROOT/dist}"
APP="$OUT/DockShortcuts.app"

swift build -c release --product dock-shortcuts --package-path "$ROOT"
BIN="$(swift build -c release --show-bin-path --package-path "$ROOT")/dock-shortcuts"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp "$ROOT/assets/dock-shortcuts.icns" "$ROOT/assets/menubar.png" "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/g" "$ROOT/packaging/Info.plist" > "$APP/Contents/Info.plist"
if [ -n "${SIGNING_P12:-}" ]; then
  # Self-signed certificate (scripts/make-signing-cert.sh): a stable identity,
  # so the Accessibility grant survives updates. Imported into a throwaway
  # keychain to leave the login keychain and search list untouched.
  KC_DIR="$(mktemp -d)"
  KC="$KC_DIR/signing.keychain-db"
  KC_PASS="$(uuidgen)"
  trap 'security delete-keychain "$KC" 2>/dev/null; rm -rf "$KC_DIR"' EXIT
  security create-keychain -p "$KC_PASS" "$KC"
  security set-keychain-settings "$KC" # no auto-lock mid-build
  security unlock-keychain -p "$KC_PASS" "$KC"
  security import "$SIGNING_P12" -k "$KC" -P "${SIGNING_P12_PASSWORD:?SIGNING_P12_PASSWORD not set}" \
    -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
  # Sign by certificate hash: self-signed identities aren't "valid" for lookup by name.
  CERT_SHA1="$(security find-certificate -a -Z "$KC" | awk '/SHA-1 hash:/ { print $3; exit }')"
  codesign --force --deep --keychain "$KC" --sign "$CERT_SHA1" "$APP"
  echo "Signed with self-signed certificate $CERT_SHA1"
else
  # Ad-hoc seal so the bundle is self-consistent. The identity changes every
  # build, so macOS drops the Accessibility grant on update.
  codesign --force --deep --sign - "$APP"
  echo "Signed ad-hoc (set SIGNING_P12 for a stable signature)"
fi
echo "Built $APP ($VERSION)"

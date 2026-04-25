#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Muesli"
BUNDLE_ID="com.local.Muesli"
MIN_SYSTEM_VERSION="14.0"
VERSION="${MUESLI_VERSION:-0.1.0}"
CONFIGURATION="release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/Muesli.icns"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-macOS.zip"
NOTES_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-release-notes.md"

DEV_CERT_DIR="$ROOT_DIR/.dev-certs"
DEV_CODESIGN_NAME="Muesli Code Signing Local"
DEV_CODESIGN_PASSWORD="muesli-local"
DEV_CODESIGN_KEYCHAIN="$HOME/Library/Keychains/muesli-local.keychain-db"

build_number() {
  git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo "1"
}

ensure_local_codesign_identity() {
  if security find-identity -v -p codesigning "$DEV_CODESIGN_KEYCHAIN" 2>/dev/null | grep -q "$DEV_CODESIGN_NAME"; then
    return
  fi

  mkdir -p "$DEV_CERT_DIR"
  cat >"$DEV_CERT_DIR/openssl-codesign.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = $DEV_CODESIGN_NAME

[ codesign_ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

  openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -config "$DEV_CERT_DIR/openssl-codesign.cnf" \
    -keyout "$DEV_CERT_DIR/muesli-codesign.key" \
    -out "$DEV_CERT_DIR/muesli-codesign.crt" >/dev/null 2>&1
  openssl pkcs12 -legacy -export -passout "pass:$DEV_CODESIGN_PASSWORD" \
    -inkey "$DEV_CERT_DIR/muesli-codesign.key" \
    -in "$DEV_CERT_DIR/muesli-codesign.crt" \
    -name "$DEV_CODESIGN_NAME" \
    -out "$DEV_CERT_DIR/muesli-codesign.p12" >/dev/null 2>&1

  rm -f "$DEV_CODESIGN_KEYCHAIN"
  security create-keychain -p "$DEV_CODESIGN_PASSWORD" "$DEV_CODESIGN_KEYCHAIN" >/dev/null
  security unlock-keychain -p "$DEV_CODESIGN_PASSWORD" "$DEV_CODESIGN_KEYCHAIN" >/dev/null
  security import "$DEV_CERT_DIR/muesli-codesign.p12" \
    -k "$DEV_CODESIGN_KEYCHAIN" \
    -P "$DEV_CODESIGN_PASSWORD" \
    -T /usr/bin/codesign >/dev/null
  security add-trusted-cert -r trustRoot -p codeSign \
    -k "$DEV_CODESIGN_KEYCHAIN" \
    "$DEV_CERT_DIR/muesli-codesign.crt" >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$DEV_CODESIGN_PASSWORD" "$DEV_CODESIGN_KEYCHAIN" >/dev/null
}

write_info_plist() {
  local build
  build="$(build_number)"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>Muesli.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$build</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Muesli records microphone audio so it can transcribe speech locally.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

sign_bundle() {
  if [[ -n "${MUESLI_CODESIGN_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --deep --options runtime --sign "$MUESLI_CODESIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
  else
    ensure_local_codesign_identity
    /usr/bin/codesign --force --deep --keychain "$DEV_CODESIGN_KEYCHAIN" --sign "$DEV_CODESIGN_NAME" --timestamp=none "$APP_BUNDLE" >/dev/null
  fi
}

write_release_notes() {
  cat >"$NOTES_PATH" <<EOF
# Muesli $VERSION

Muesli is a native macOS voice-to-text app that records audio, transcribes it
locally with NVIDIA Parakeet through FluidAudio, and can paste finished
dictation into the app you were using.

## Highlights

- Local Parakeet transcription through FluidAudio.
- Parakeet TDT 0.6B v3 and v2 model selection.
- Recording history with transcript editing, copy, delete, benchmark, and export.
- Global dictation hotkey with toggle, push-to-talk, hybrid, and custom shortcut support.
- First-run readiness check for microphone, Accessibility, model, and hotkey state.

## Install

1. Download \`$APP_NAME-$VERSION-macOS.zip\`.
2. Unzip it.
3. Move \`$APP_NAME.app\` to Applications or run it from the unzipped folder.
4. Grant Microphone and Accessibility permissions when prompted.

## Signing

This archive is signed. If \`MUESLI_CODESIGN_IDENTITY\` was not set when it was
built, it uses the project-local development signing identity and is not
notarized.
EOF
}

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c "$CONFIGURATION"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_RESOURCES/Muesli.icns"
fi

write_info_plist
sign_bundle

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ARCHIVE_PATH"
write_release_notes

echo "App: $APP_BUNDLE"
echo "Archive: $ARCHIVE_PATH"
echo "Notes: $NOTES_PATH"

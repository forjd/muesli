#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Muesli"
BUNDLE_ID="com.local.Muesli"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="Muesli_Muesli.bundle"
DEV_CERT_DIR="$ROOT_DIR/.dev-certs"
DEV_CODESIGN_NAME="Muesli Code Signing Local"
DEV_CODESIGN_PASSWORD="muesli-local"
DEV_CODESIGN_KEYCHAIN="$HOME/Library/Keychains/muesli-local.keychain-db"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
BUILD_DIR="$(swift build --show-bin-path)"

mkdir -p "$APP_MACOS"
if [[ ! -f "$APP_BINARY" ]] || ! cmp -s "$BUILD_BINARY" "$APP_BINARY"; then
  cp "$BUILD_BINARY" "$APP_BINARY"
fi
chmod +x "$APP_BINARY"

rm -rf "$APP_BUNDLE/$RESOURCE_BUNDLE_NAME"

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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Muesli records microphone audio so it can transcribe speech locally.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

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

if [[ -n "${MUESLI_CODESIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --deep --sign "$MUESLI_CODESIGN_IDENTITY" --timestamp=none "$APP_BUNDLE" >/dev/null
else
  ensure_local_codesign_identity
  /usr/bin/codesign --force --deep --keychain "$DEV_CODESIGN_KEYCHAIN" --sign "$DEV_CODESIGN_NAME" --timestamp=none "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

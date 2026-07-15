#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${1:-${CONFIGURATION:-debug}}
SIGNING_IDENTITY=${GIF_IT_SIGNING_IDENTITY:-}

case "$CONFIGURATION" in
  debug)
    APP_NAME="Gif It Debug"
    BUNDLE_ID="com.josephcampuzano.gif-it.debug"
    DEFAULT_APP="$HOME/Applications/Gif It Debug.app"
    ;;
  release)
    APP_NAME="Gif It"
    BUNDLE_ID="com.josephcampuzano.gif-it"
    DEFAULT_APP="$HOME/Applications/Gif It.app"
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

APP=${GIF_IT_APP_PATH:-"$DEFAULT_APP"}

has_identity() {
  security find-identity -p codesigning -v 2>/dev/null | grep -F "\"$1\"" >/dev/null 2>&1
}

if [ -z "$SIGNING_IDENTITY" ] && has_identity "Gif It Development"; then
  SIGNING_IDENTITY="Gif It Development"
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | sed -n '1p')
fi

swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --product gif-it
BIN_DIR=$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/gif-it" "$APP/Contents/MacOS/Gif It"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
xcrun swift "$ROOT/scripts/generate-icon.swift" "$APP/Contents/Resources/AppIcon.png"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$APP_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$APP/Contents/Info.plist"
xattr -cr "$APP"

if [ -n "$SIGNING_IDENTITY" ]; then
  codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  echo "Signed with stable identity: $SIGNING_IDENTITY" >&2
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "WARNING: No code-signing identity found; using ad-hoc signing." >&2
  echo "         Screen Recording permission may reset after rebuilding." >&2
  echo "         Run ./scripts/setup-dev-signing.sh for the one-time fix." >&2
fi

echo "Built $CONFIGURATION app:"
echo "$APP"

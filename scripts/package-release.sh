#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:-}
DIST=${GIF_IT_DIST_PATH:-"$ROOT/dist"}

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Usage: $0 <major.minor.patch>" >&2
  exit 2
fi

APP="$DIST/Gif It.app"
ARCHIVE_NAME="Gif-It-$VERSION-macos-arm64.zip"
ARCHIVE="$DIST/$ARCHIVE_NAME"
BUILD_NUMBER=${GIF_IT_BUILD_NUMBER:-1}

rm -rf "$DIST"
mkdir -p "$DIST"

GIF_IT_APP_PATH="$APP" \
GIF_IT_SIGNING_IDENTITY="-" \
GIF_IT_VERSION="$VERSION" \
GIF_IT_BUILD_NUMBER="$BUILD_NUMBER" \
  "$ROOT/scripts/build-release.sh"

BINARY="$APP/Contents/MacOS/Gif It"
ARCHES=$(lipo -archs "$BINARY")
case " $ARCHES " in
  *" arm64 "*) ;;
  *)
    echo "Release binary does not contain arm64: $ARCHES" >&2
    exit 1
    ;;
esac

ACTUAL_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
ACTUAL_BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")
if [ "$ACTUAL_VERSION" != "$VERSION" ] || [ "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]; then
  echo "Bundle version mismatch: expected $VERSION ($BUILD_NUMBER), got $ACTUAL_VERSION ($ACTUAL_BUILD)" >&2
  exit 1
fi

xattr -cr "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if find "$APP" -name '._*' -print -quit | grep -q .; then
  echo "AppleDouble files found in app bundle" >&2
  exit 1
fi

/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$ARCHIVE"
(
  cd "$DIST"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

echo "Packaged release assets:"
echo "$ARCHIVE"
echo "$ARCHIVE.sha256"

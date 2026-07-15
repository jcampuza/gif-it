#!/bin/sh
set -eu

echo "Available code-signing identities:"
security find-identity -p codesigning -v

APP=${GIF_IT_APP_PATH:-"$HOME/Applications/Gif It.app"}
if [ -d "$APP" ]; then
  echo
  echo "Current Gif It signature:"
  codesign -dv --verbose=4 "$APP" 2>&1 \
    | grep -E '^(Identifier|Authority|TeamIdentifier|Signature|CodeDirectory)='
fi

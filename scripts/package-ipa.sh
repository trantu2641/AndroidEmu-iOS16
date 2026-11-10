#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -type d \
    -path "*/Build/Products/Release-iphoneos/AndroidEmu.app" \
    -print -quit)"

if [ -z "$APP" ]; then
    echo "AndroidEmu.app not found."
    exit 1
fi

rm -rf Payload

mkdir -p Payload

cp -R "$APP" Payload/AndroidEmu.app

rm -f AndroidEmu-iOS16.4.ipa

zip -qry \
    AndroidEmu-iOS16.4.ipa \
    Payload

echo
echo "IPA:"
ls -lh AndroidEmu-iOS16.4.ipa

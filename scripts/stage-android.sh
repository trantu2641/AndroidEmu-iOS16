#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP_ANDROID="$ROOT/App/AndroidEmu/Resources/Android"

mkdir -p "$APP_ANDROID"

echo "Staging Android runtime..."

if [ -d "$ROOT/Kernarium/android/aosp-17" ]; then
    echo "AOSP 17 source detected."
else
    echo "ERROR: AOSP 17 source not found."
    exit 1
fi

echo "Android staging directory:"
echo "$APP_ANDROID"

mkdir -p "$APP_ANDROID"

touch "$APP_ANDROID/.gitkeep"

echo
echo "Android image staging will be populated by"
echo "the Kernarium Android image builder."

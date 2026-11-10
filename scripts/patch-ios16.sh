#!/usr/bin/env bash

set -euo pipefail

ROOT="${1:?Kernarium path required}"

echo "Patching Kernarium for iOS 16.4"

find "$ROOT" \
    -type f \
    \( \
        -name "*.pbxproj" \
        -o -name "*.xcconfig" \
        -o -name "CMakeLists.txt" \
        -o -name "*.cmake" \
        -o -name "*.plist" \
    \) \
    -print0 |
while IFS= read -r -d '' file
do
    perl -pi -e \
        's/IPHONEOS_DEPLOYMENT_TARGET\s*=\s*(26|27)(\.[0-9]+)?/IPHONEOS_DEPLOYMENT_TARGET = 16.4/g' \
        "$file" 2>/dev/null || true

    perl -pi -e \
        's/MACOSX_DEPLOYMENT_TARGET\s*=\s*(26|27)(\.[0-9]+)?/MACOSX_DEPLOYMENT_TARGET = 13.0/g' \
        "$file" 2>/dev/null || true
done

echo
echo "Remaining iOS targets:"

grep -R \
    "IPHONEOS_DEPLOYMENT_TARGET" \
    "$ROOT" \
    --include="*.pbxproj" \
    --include="*.xcconfig" \
    2>/dev/null \
    | head -100 || true

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/Kernarium"

echo "=== Configure ==="

cmake \
    --preset kernarium-ios-device-android

echo "=== Build ==="

cmake \
    --build \
    --preset kernarium-ios-device-android \
    --parallel "$(sysctl -n hw.ncpu)"

echo "=== Build complete ==="

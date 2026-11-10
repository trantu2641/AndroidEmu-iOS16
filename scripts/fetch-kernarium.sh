#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

KERNARIUM_DIR="$ROOT/Kernarium"

REPO="https://github.com/imxieyi/Kernarium.git"

COMMIT="2c49df8ccb7b138400548ccc391511c5642eca57"

rm -rf "$KERNARIUM_DIR"

git clone \
    --depth 1 \
    "$REPO" \
    "$KERNARIUM_DIR"

cd "$KERNARIUM_DIR"

git fetch \
    --depth 1 \
    origin "$COMMIT"

git checkout "$COMMIT"

echo
echo "Kernarium:"
git rev-parse HEAD

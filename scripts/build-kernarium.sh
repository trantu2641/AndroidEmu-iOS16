#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

DEPENDENCY_ROOT="$KERNARIUM/external/sources"
DEPENDENCY_BUILD_ROOT="$KERNARIUM/.build/dependency-build"
DEPENDENCY_PREFIX_ROOT="$KERNARIUM/.build/dependencies"

JOBS="${KERNARIUM_JOBS:-3}"

IOS_PREFIX="$DEPENDENCY_PREFIX_ROOT/apple-gpu/ios-device-arm64"
MACOS_PREFIX="$DEPENDENCY_PREFIX_ROOT/apple-gpu/macos-arm64"

echo "========================================"
echo "Checking environment"
echo "========================================"

echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version | head -1)"
echo "iOS SDK     : $(xcrun --sdk iphoneos --show-sdk-path)"
echo "CPU cores   : $(sysctl -n hw.ncpu)"
echo "Kernarium   : $KERNARIUM"

echo
echo "========================================"
echo "Configure Git identity"
echo "========================================"

git config --global user.name "AndroidEmu Builder"
git config --global user.email "androidemu-builder@localhost"

export GIT_AUTHOR_NAME="AndroidEmu Builder"
export GIT_AUTHOR_EMAIL="androidemu-builder@localhost"
export GIT_COMMITTER_NAME="AndroidEmu Builder"
export GIT_COMMITTER_EMAIL="androidemu-builder@localhost"

echo "Git global user : $(git config --global user.name)"
echo "Git global email: $(git config --global user.email)"
echo "Committer       : $GIT_COMMITTER_NAME <$GIT_COMMITTER_EMAIL>"

echo
echo "========================================"
echo "Prepare Kernarium dependencies"
echo "========================================"

echo "Dependency source root:"
echo "$DEPENDENCY_ROOT"

#
# IMPORTANT:
#
# prepare.sh WITHOUT --verify is the command that actually materializes
# the dependency repositories.
#
# build-apple-gpu.sh itself later calls:
#
#   prepare.sh --verify
#
# so this first call MUST NOT use --verify.
#

rm -rf "$DEPENDENCY_ROOT"
mkdir -p "$DEPENDENCY_ROOT"

echo "Clean dependency source tree created."

echo "Running dependencies/prepare.sh..."

(
    cd "$KERNARIUM"

    ./dependencies/prepare.sh \
        --product apple-gpu \
        --root "$DEPENDENCY_ROOT"
)

echo
echo "========================================"
echo "Verify prepared dependency repositories"
echo "========================================"

for repo in \
    utm-webkit \
    utm-libepoxy \
    utm-virglrenderer
do
    if [ ! -d "$DEPENDENCY_ROOT/$repo/.git" ]; then
        echo "ERROR: prepared repository missing: $repo"
        exit 1
    fi

    echo "OK: $repo"
done

echo
echo "========================================"
echo "Clean previous dependency build output"
echo "========================================"

rm -rf "$DEPENDENCY_BUILD_ROOT"

mkdir -p "$DEPENDENCY_BUILD_ROOT"
mkdir -p "$DEPENDENCY_PREFIX_ROOT"

echo
echo "========================================"
echo "Build macOS Apple GPU dependency"
echo "========================================"

(
    cd "$KERNARIUM"

    ./dependencies/build-apple-gpu.sh \
        --platform macos \
        --product apple-gpu \
        --source-root "$DEPENDENCY_ROOT" \
        --prefix "$MACOS_PREFIX" \
        --work-root "$DEPENDENCY_BUILD_ROOT/macos" \
        --jobs "$JOBS"
)

echo
echo "========================================"
echo "Verify macOS Apple GPU dependency"
echo "========================================"

if [ ! -f "$MACOS_PREFIX/lib/libepoxy.a" ]; then
    echo "ERROR: macOS libepoxy.a not found:"
    echo "$MACOS_PREFIX/lib/libepoxy.a"
    exit 1
fi

if [ ! -f "$MACOS_PREFIX/lib/libvirglrenderer.a" ]; then
    echo "ERROR: macOS libvirglrenderer.a not found:"
    echo "$MACOS_PREFIX/lib/libvirglrenderer.a"
    exit 1
fi

echo "macOS libepoxy.a:"
ls -lh "$MACOS_PREFIX/lib/libepoxy.a"

echo "macOS libvirglrenderer.a:"
ls -lh "$MACOS_PREFIX/lib/libvirglrenderer.a"

echo
echo "========================================"
echo "Build iOS 16 Apple GPU dependency"
echo "========================================"

(
    cd "$KERNARIUM"

    ./dependencies/build-apple-gpu.sh \
        --platform ios \
        --product apple-gpu \
        --source-root "$DEPENDENCY_ROOT" \
        --prefix "$IOS_PREFIX" \
        --work-root "$DEPENDENCY_BUILD_ROOT/ios" \
        --jobs "$JOBS"
)

echo
echo "========================================"
echo "Verify iOS Apple GPU dependency"
echo "========================================"

if [ ! -f "$IOS_PREFIX/lib/libepoxy.a" ]; then
    echo "ERROR: iOS libepoxy.a not found:"
    echo "$IOS_PREFIX/lib/libepoxy.a"
    exit 1
fi

if [ ! -f "$IOS_PREFIX/lib/libvirglrenderer.a" ]; then
    echo "ERROR: iOS libvirglrenderer.a not found:"
    echo "$IOS_PREFIX/lib/libvirglrenderer.a"
    exit 1
fi

echo "iOS libepoxy.a:"
ls -lh "$IOS_PREFIX/lib/libepoxy.a"

echo "iOS libvirglrenderer.a:"
ls -lh "$IOS_PREFIX/lib/libvirglrenderer.a"

echo
echo "========================================"
echo "Prepare Kernarium dependency compatibility path"
echo "========================================"

#
# Kernarium's CMake configuration for this historical commit expects
# the host prefix at:
#
#   .build/dependencies/macos-arm64
#
# The Apple GPU builder stores it under:
#
#   .build/dependencies/apple-gpu/macos-arm64
#
# Keep the real prefix intact and expose the expected path as a symlink.
#

EXPECTED_MACOS_PREFIX="$DEPENDENCY_PREFIX_ROOT/macos-arm64"

if [ -L "$EXPECTED_MACOS_PREFIX" ] || [ -e "$EXPECTED_MACOS_PREFIX" ]; then
    rm -rf "$EXPECTED_MACOS_PREFIX"
fi

ln -s "$MACOS_PREFIX" "$EXPECTED_MACOS_PREFIX"

echo "macOS compatibility prefix:"
ls -ld "$EXPECTED_MACOS_PREFIX"

echo
echo "========================================"
echo "Configure Kernarium iOS 16.4"
echo "========================================"

rm -rf "$KERNARIUM/.build/kernarium-ios"

mkdir -p "$KERNARIUM/.build/kernarium-ios"

(
    cd "$KERNARIUM"

    cmake \
        -S . \
        -B .build/kernarium-ios \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 \
        -DCMAKE_BUILD_TYPE=Release
)

echo
echo "========================================"
echo "Build Kernarium"
echo "========================================"

(
    cd "$KERNARIUM"

    cmake \
        --build .build/kernarium-ios \
        --parallel "$JOBS"
)

echo
echo "========================================"
echo "Kernarium build completed"
echo "========================================"

echo
echo "Dependency prefixes:"
echo "  macOS:"
echo "    $MACOS_PREFIX"

echo "  iOS:"
echo "    $IOS_PREFIX"

echo
echo "Kernarium build:"
echo "  $KERNARIUM/.build/kernarium-ios"

echo
echo "SUCCESS"

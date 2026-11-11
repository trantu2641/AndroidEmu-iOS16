#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

IOS_VERSION="${IOS_VERSION:-16.4}"
ARCH="${ARCH:-arm64}"

SOURCE_ROOT="$KERNARIUM/external/sources"

HOST_PREFIX="$KERNARIUM/.build/dependencies/macos-arm64"
HOST_WORK_ROOT="$KERNARIUM/.build/dependency-build"

IOS_GPU_PREFIX="$KERNARIUM/.build/dependencies/apple-gpu/ios-device-arm64"

CPU_CORES="$(sysctl -n hw.ncpu)"

log()
{
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
}

run()
{
    echo
    echo "+ $*"
    "$@"
}

fail()
{
    echo
    echo "ERROR: $*"
    exit 1
}

###############################################################################
# Environment
###############################################################################

log "Checking environment"

echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version | head -1)"
echo "iOS SDK     : $(xcrun --sdk iphoneos --show-sdk-path)"
echo "CPU cores   : $CPU_CORES"
echo "Kernarium   : $KERNARIUM"
echo "iOS target  : $IOS_VERSION"
echo "Architecture: $ARCH"

###############################################################################
# Git identity
###############################################################################

log "Configure Git identity"

git config --global user.name "AndroidEmu Builder"
git config --global user.email "androidemu-builder@localhost"

export GIT_AUTHOR_NAME="AndroidEmu Builder"
export GIT_AUTHOR_EMAIL="androidemu-builder@localhost"
export GIT_COMMITTER_NAME="AndroidEmu Builder"
export GIT_COMMITTER_EMAIL="androidemu-builder@localhost"

###############################################################################
# Verify source
###############################################################################

log "Verify Kernarium source"

[ -d "$KERNARIUM" ] || fail "Kernarium directory does not exist"

cd "$KERNARIUM"

EXPECTED_COMMIT="${KERNARIUM_COMMIT:-2c49df8ccb7b138400548ccc391511c5642eca57}"
ACTUAL_COMMIT="$(git rev-parse HEAD)"

echo "Kernarium commit:"
echo "$ACTUAL_COMMIT"

if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
    fail "Kernarium commit mismatch. Expected $EXPECTED_COMMIT, got $ACTUAL_COMMIT"
fi

[ -d "$KERNARIUM/android/aosp-17" ] ||
    fail "Android AOSP 17 source not found"

echo "Android AOSP 17: OK"

###############################################################################
# IMPORTANT:
#
# Kernarium's dependency CMakeLists.txt is HOST macOS-only.
#
# The iOS product MUST NOT configure:
#
#   dependencies/CMakeLists.txt
#
# Therefore:
#   - UML_APPLE_PLATFORM=ios
#   - UML_BUILD_CLI=OFF
#   - UML_BUILD_ANDROID17_CLI=OFF
#   - UML_BUILD_GPU=OFF
#   - UML_BUILD_AUDIO=OFF
#   - UML_BUILD_NETWORK_PROVIDER=OFF
#
# The Apple GPU static libraries are built separately above/below and are
# supplied explicitly to the iOS build only when the iOS target supports them.
#
###############################################################################

log "Verify iOS build configuration"

echo "UML_APPLE_PLATFORM : ios"
echo "UML_BUILD_CLI      : OFF"
echo "UML_BUILD_ANDROID17_CLI: OFF"
echo "UML_BUILD_GPU      : OFF"
echo "UML_BUILD_AUDIO    : OFF"
echo "UML_BUILD_NETWORK_PROVIDER: OFF"
echo "UML_BUILD_KERNARIUM_RUNTIME: ON"

###############################################################################
# Verify host dependency prefix
###############################################################################

log "Verify host dependency prefix"

if [ ! -d "$HOST_PREFIX" ]; then
    fail "Host dependency prefix is missing: $HOST_PREFIX"
fi

if [ -L "$HOST_PREFIX" ]; then
    fail "Host dependency prefix must not be a symbolic link: $HOST_PREFIX"
fi

HOST_RECEIPT="$HOST_PREFIX/share/uml-dependencies/receipt.tsv"

if [ ! -f "$HOST_RECEIPT" ]; then
    fail "Host dependency receipt is missing: $HOST_RECEIPT"
fi

echo
echo "Host dependency prefix:"
echo "$HOST_PREFIX"

echo
echo "Host dependency receipt:"
cat "$HOST_RECEIPT"

###############################################################################
# Verify iOS GPU prefix
###############################################################################

log "Verify iOS GPU dependency prefix"

if [ ! -d "$IOS_GPU_PREFIX" ]; then
    fail "iOS Apple GPU prefix is missing: $IOS_GPU_PREFIX"
fi

if [ -L "$IOS_GPU_PREFIX" ]; then
    fail "iOS Apple GPU prefix must not be a symbolic link"
fi

IOS_EPOXY="$IOS_GPU_PREFIX/lib/libepoxy.a"
IOS_VIRGL="$IOS_GPU_PREFIX/lib/libvirglrenderer.a"

[ -f "$IOS_EPOXY" ] ||
    fail "Missing iOS libepoxy.a: $IOS_EPOXY"

[ -f "$IOS_VIRGL" ] ||
    fail "Missing iOS libvirglrenderer.a: $IOS_VIRGL"

echo
echo "iOS Apple GPU prefix:"
echo "$IOS_GPU_PREFIX"

ls -lh \
    "$IOS_EPOXY" \
    "$IOS_VIRGL"

###############################################################################
# Clean iOS build tree
###############################################################################

log "Clean Kernarium iOS build tree"

BUILD_DIR="$KERNARIUM/.build/ios-arm64"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

###############################################################################
# Configure Kernarium for iOS
###############################################################################

log "Configure Kernarium iOS $IOS_VERSION"

cd "$KERNARIUM"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"
IOS_CLANGXX="$(xcrun --sdk iphoneos --find clang++)"

echo
echo "iOS SDK:"
echo "$IOS_SDK"

echo
echo "iOS clang:"
echo "$IOS_CLANG"

###############################################################################
# CRITICAL:
#
# Do NOT pass UML_DEPENDENCY_PREFIX here.
#
# Do NOT configure the host dependencies/CMakeLists.txt.
#
# Do NOT use:
#
#   -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4
#   with the macOS private dependency prefix.
#
# The iOS configuration is isolated from the host dependency prefix.
###############################################################################

run cmake \
    -S "$KERNARIUM" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_VERSION" \
    -DCMAKE_C_COMPILER="$IOS_CLANG" \
    -DCMAKE_CXX_COMPILER="$IOS_CLANGXX" \
    -DUML_APPLE_PLATFORM=ios \
    -DUML_BUILD_CLI=OFF \
    -DUML_BUILD_ANDROID17_CLI=OFF \
    -DUML_BUILD_GPU=OFF \
    -DUML_BUILD_AUDIO=OFF \
    -DUML_BUILD_NETWORK_PROVIDER=OFF \
    -DUML_BUILD_KERNARIUM_RUNTIME=ON \
    -DUML_BUILD_UNIT_TESTS=OFF \
    -DUML_BUILD_INTEGRATION_TESTS=OFF \
    -DUML_BUILD_TOOLING_TESTS=OFF \
    -DUML_BUILD_WINE_ARM64EC=OFF \
    -DUML_MAINLINE_KERNEL_SLICE=arm64 \
    -DUML_MAINLINE_KERNEL_PROFILE=standard

###############################################################################
# Build
###############################################################################

log "Build Kernarium"

run cmake \
    --build "$BUILD_DIR" \
    --parallel "$CPU_CORES

###############################################################################
# Install
###############################################################################

log "Install Kernarium"

INSTALL_PREFIX="$KERNARIUM/.build/install-ios"

rm -rf "$INSTALL_PREFIX"
mkdir -p "$INSTALL_PREFIX"

run cmake \
    --install "$BUILD_DIR" \
    --prefix "$INSTALL_PREFIX"

###############################################################################
# Verify
###############################################################################

log "Kernarium iOS build completed"

echo
echo "Build directory:"
echo "$BUILD_DIR"

echo
echo "Install directory:"
echo "$INSTALL_PREFIX"

echo
echo "Generated files:"

find "$INSTALL_PREFIX" \
    -maxdepth 5 \
    -type f \
    -print \
    | sort \
    | head -300

echo
echo "========================================"
echo "Kernarium iOS build: SUCCESS"
echo "========================================"

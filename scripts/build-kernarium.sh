
#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

BUILD_DIR="$KERNARIUM/.build/kernarium-ios16"
GPU_PREFIX="$KERNARIUM/.build/dependencies/apple-gpu/ios-device-arm64"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CC="$(xcrun --sdk iphoneos -f clang)"
IOS_CXX="$(xcrun --sdk iphoneos -f clang++)"

CPU_COUNT="$(sysctl -n hw.ncpu)"

section()
{
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo
}

fail()
{
    echo
    echo "ERROR: $1"
    exit 1
}

section "Checking environment"

if [ ! -d "$KERNARIUM" ]; then
    fail "Kernarium directory not found: $KERNARIUM"
fi

if [ "$(uname -s)" != "Darwin" ]; then
    fail "This build must run on macOS."
fi

if [ "$(uname -m)" != "arm64" ]; then
    fail "Kernarium Apple GPU build requires an arm64 macOS runner."
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "xcodebuild not found."
fi

if ! command -v xcrun >/dev/null 2>&1; then
    fail "xcrun not found."
fi

if ! command -v cmake >/dev/null 2>&1; then
    fail "cmake not found."
fi

echo "macOS      : $(sw_vers -productVersion)"
echo "Xcode      : $(xcodebuild -version | head -1)"
echo "iOS SDK    : $IOS_SDK"
echo "CPU cores  : $CPU_COUNT"
echo "Kernarium  : $KERNARIUM"

section "Configure Git identity"

git config user.name "AndroidEmu Builder"
git config user.email "androidemu-builder@localhost"

echo "Git user : $(git config user.name)"
echo "Git email: $(git config user.email)"

section "Prepare Kernarium dependencies"

cd "$KERNARIUM"

DEPENDENCY_ROOT="$KERNARIUM/external/sources"

echo "Preparing dependency source trees:"
echo "$DEPENDENCY_ROOT"

mkdir -p "$DEPENDENCY_ROOT"

#
# IMPORTANT:
#
# dependencies/build-apple-gpu.sh calls prepare.sh with --verify.
# Therefore the dependency sources MUST be materialized first.
#
"$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$DEPENDENCY_ROOT"

if [ ! -d "$DEPENDENCY_ROOT" ]; then
    fail "Dependency source root was not created."
fi

echo
echo "Prepared dependency sources:"
find "$DEPENDENCY_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -print | sort

section "Build Apple GPU dependency"

GPU_SCRIPT="$KERNARIUM/dependencies/build-apple-gpu.sh"

if [ ! -f "$GPU_SCRIPT" ]; then
    fail "Apple GPU build script not found: $GPU_SCRIPT"
fi

echo "Building:"
echo "  platform : ios"
echo "  product  : apple-gpu"
echo "  jobs     : $CPU_COUNT"
echo "  prefix   : $GPU_PREFIX"

"$GPU_SCRIPT" \
    --platform ios \
    --product apple-gpu \
    --source-root "$DEPENDENCY_ROOT" \
    --prefix "$GPU_PREFIX" \
    --jobs "$CPU_COUNT"

section "Verify Apple GPU dependency"

EPOXY="$GPU_PREFIX/lib/libepoxy.a"
VIRGL="$GPU_PREFIX/lib/libvirglrenderer.a"

if [ ! -f "$EPOXY" ]; then
    fail "Missing libepoxy.a: $EPOXY"
fi

if [ ! -f "$VIRGL" ]; then
    fail "Missing libvirglrenderer.a: $VIRGL"
fi

echo "OK: $EPOXY"
echo "OK: $VIRGL"

section "Configure Kernarium"

rm -rf "$BUILD_DIR"

mkdir -p "$BUILD_DIR"

cmake \
    -S "$KERNARIUM" \
    -B "$BUILD_DIR" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$IOS_CC" \
    -DCMAKE_CXX_COMPILER="$IOS_CXX" \
    -DCMAKE_OBJCXX_COMPILER="$IOS_CXX" \
    -DAPPLE_GPU_PREFIX="$GPU_PREFIX"

section "Build Kernarium"

cmake \
    --build "$BUILD_DIR" \
    --parallel "$CPU_COUNT"

section "Build output"

echo "Build directory:"
echo "$BUILD_DIR"

echo

find "$BUILD_DIR" \
    -type f \
    \( \
        -name "*.a" \
        -o -name "*.dylib" \
        -o -name "*.framework" \
        -o -name "*.bin" \
        -o -name "*.img" \
        -o -name "*.o" \
    \) \
    -print \
    | sort

section "Kernarium build finished"

echo "Kernarium iOS 16.4 build completed."
echo
echo "Build directory:"
echo "$BUILD_DIR"

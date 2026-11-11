#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

BUILD_DIR="$KERNARIUM/.build/kernarium-ios16"

IOS_GPU_PREFIX="$KERNARIUM/.build/dependencies/apple-gpu/ios-device-arm64"
MACOS_GPU_PREFIX="$KERNARIUM/.build/dependencies/apple-gpu/macos-arm64"

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
    fail "Kernarium build requires an arm64 macOS runner."
fi

command -v xcodebuild >/dev/null 2>&1 ||
    fail "xcodebuild not found."

command -v xcrun >/dev/null 2>&1 ||
    fail "xcrun not found."

command -v cmake >/dev/null 2>&1 ||
    fail "cmake not found."

command -v meson >/dev/null 2>&1 ||
    fail "meson not found."

echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version | head -1)"
echo "iOS SDK     : $IOS_SDK"
echo "CPU cores   : $CPU_COUNT"
echo "Kernarium   : $KERNARIUM"

section "Configure Git identity"

git config --global user.name "AndroidEmu Builder"
git config --global user.email "androidemu-builder@localhost"

export GIT_AUTHOR_NAME="AndroidEmu Builder"
export GIT_AUTHOR_EMAIL="androidemu-builder@localhost"
export GIT_COMMITTER_NAME="AndroidEmu Builder"
export GIT_COMMITTER_EMAIL="androidemu-builder@localhost"

echo "Git global user : $(git config --global user.name)"
echo "Git global email: $(git config --global user.email)"
echo "Committer       : $GIT_COMMITTER_NAME <$GIT_COMMITTER_EMAIL>"

section "Prepare Kernarium dependencies"

cd "$KERNARIUM"

DEPENDENCY_ROOT="$KERNARIUM/external/sources"

echo "Dependency source root:"
echo "$DEPENDENCY_ROOT"

# IMPORTANT:
# prepare.sh yêu cầu mỗi dependency là một Git repository hoàn chỉnh.
# Nếu workflow trước đó bị fail giữa chừng, source tree có thể tồn tại
# nhưng không còn ở trạng thái hợp lệ.
#
# Xóa sạch source tree để tránh:
#   "utm-webkit is not a prepared Git repository"
#
rm -rf "$DEPENDENCY_ROOT"

mkdir -p "$DEPENDENCY_ROOT"

echo
echo "Clean dependency source tree created."

echo
echo "Running dependencies/prepare.sh..."

"$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$DEPENDENCY_ROOT" \
    --verify

if [ ! -d "$DEPENDENCY_ROOT" ]; then
    fail "Dependency source root was not created."
fi

echo
echo "Prepared dependency sources:"

find "$DEPENDENCY_ROOT" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -print \
    | sort

# Verify each expected dependency is actually a Git repository.
for repo in \
    "$DEPENDENCY_ROOT/utm-webkit" \
    "$DEPENDENCY_ROOT/utm-libepoxy" \
    "$DEPENDENCY_ROOT/utm-virglrenderer"
do
    if [ ! -d "$repo/.git" ]; then
        fail "Dependency is not a valid Git repository: $repo"
    fi
done

echo
echo "All dependency repositories are valid Git repositories."

section "Clean previous dependency builds"

rm -rf \
    "$KERNARIUM/.build/dependency-build" \
    "$KERNARIUM/.build/dependencies"

mkdir -p "$KERNARIUM/.build/dependencies"

echo "Previous dependency build directories removed."

section "Build host macOS dependency"

GPU_SCRIPT="$KERNARIUM/dependencies/build-apple-gpu.sh"

if [ ! -f "$GPU_SCRIPT" ]; then
    fail "Apple GPU build script not found: $GPU_SCRIPT"
fi

echo "Building host dependency:"
echo "  platform : macos"
echo "  product  : apple-gpu"
echo "  jobs     : $CPU_COUNT"
echo "  prefix   : $MACOS_GPU_PREFIX"

"$GPU_SCRIPT" \
    --platform macos \
    --product apple-gpu \
    --source-root "$DEPENDENCY_ROOT" \
    --prefix "$MACOS_GPU_PREFIX" \
    --jobs "$CPU_COUNT"

if [ ! -d "$MACOS_GPU_PREFIX" ]; then
    fail "macOS dependency prefix was not created: $MACOS_GPU_PREFIX"
fi

section "Verify host macOS dependency"

echo "OK: $MACOS_GPU_PREFIX"

find "$MACOS_GPU_PREFIX" \
    -type f \
    \( -name "*.a" -o -name "*.dylib" \) \
    -print \
    | sort

section "Build iOS Apple GPU dependency"

echo "Building:"
echo "  platform : ios"
echo "  product  : apple-gpu"
echo "  jobs     : $CPU_COUNT"
echo "  prefix   : $IOS_GPU_PREFIX"

"$GPU_SCRIPT" \
    --platform ios \
    --product apple-gpu \
    --source-root "$DEPENDENCY_ROOT" \
    --prefix "$IOS_GPU_PREFIX" \
    --jobs "$CPU_COUNT"

section "Verify iOS Apple GPU dependency"

EPOXY="$IOS_GPU_PREFIX/lib/libepoxy.a"
VIRGL="$IOS_GPU_PREFIX/lib/libvirglrenderer.a"

if [ ! -f "$EPOXY" ]; then
    fail "Missing libepoxy.a: $EPOXY"
fi

if [ ! -f "$VIRGL" ]; then
    fail "Missing libvirglrenderer.a: $VIRGL"
fi

echo "OK: $EPOXY"
echo "OK: $VIRGL"

section "Prepare Kernarium dependency layout"

EXPECTED_MACOS_PREFIX="$KERNARIUM/.build/dependencies/macos-arm64"

if [ ! -d "$EXPECTED_MACOS_PREFIX" ]; then
    echo "Creating Kernarium compatibility path:"
    echo "  $EXPECTED_MACOS_PREFIX"

    mkdir -p "$(dirname "$EXPECTED_MACOS_PREFIX")"

    ln -s \
        "$MACOS_GPU_PREFIX" \
        "$EXPECTED_MACOS_PREFIX"
fi

if [ ! -d "$EXPECTED_MACOS_PREFIX" ]; then
    fail "Kernarium macos-arm64 dependency prefix is missing."
fi

if [ ! -d "$IOS_GPU_PREFIX" ]; then
    fail "Kernarium ios-device-arm64 dependency prefix is missing."
fi

echo
echo "Dependency layout ready:"
echo
echo "  macos-arm64:"
echo "    $EXPECTED_MACOS_PREFIX"
echo
echo "  ios-device-arm64:"
echo "    $IOS_GPU_PREFIX"

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
    -DAPPLE_GPU_PREFIX="$IOS_GPU_PREFIX"

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

echo
echo "Kernarium iOS 16.4 build completed."
echo
echo "Build directory:"
echo "$BUILD_DIR"

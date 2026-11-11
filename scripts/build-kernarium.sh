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

KERNEL_ARTIFACT_ROOT="$KERNARIUM/.build/kernel/artifacts"
KERNEL_ARTIFACT_NAME="android-6.18-arm64-16k-20260906-main-integration-14163bda"
KERNEL_ARTIFACT_DIR="$KERNEL_ARTIFACT_ROOT/$KERNEL_ARTIFACT_NAME"

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

XCODE_VERSION="$(xcodebuild -version 2>/dev/null || true)"
echo "Xcode       : $(printf '%s\n' "$XCODE_VERSION" | sed -n '1p')"

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
# Build tools
###############################################################################

log "Verify build tools"

required_tools=(
    cmake
    ninja
    meson
    pkg-config
    python3
    clang
    autoreconf
    autoconf
    automake
    glibtoolize
    autopoint
    gperf
    git
    curl
    rsync
    shasum
)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "Required build tool is missing: $tool"
    fi
done

###############################################################################
# Python
###############################################################################

log "Verify Python build environment"

VENV="$RUNNER_TEMP/kernarium-venv"

if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
fi

source "$VENV/bin/activate"

python -m pip install --upgrade pip
python -m pip install PyYAML

python --version
python -c 'import yaml; print("PyYAML:", yaml.__version__)'

###############################################################################
# Verify Kernarium
###############################################################################

log "Verify Kernarium source"

[ -d "$KERNARIUM" ] ||
    fail "Kernarium directory does not exist"

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
# Kernel artifact
###############################################################################

log "Verify Android 17 kernel artifact"

mkdir -p "$KERNEL_ARTIFACT_ROOT"

echo "Required artifact:"
echo "$KERNEL_ARTIFACT_DIR"

if [ ! -d "$KERNEL_ARTIFACT_DIR" ]; then
    fail 
        "Android 17 kernel artifact is missing.

Expected:
$KERNEL_ARTIFACT_DIR

The artifact must be the real accepted Kernarium Android 17
ACK 6.18 arm64 16 KiB artifact.

Do NOT create an empty directory or copy a random vmlinux."
fi

[ -d "$KERNEL_ARTIFACT_DIR" ] ||
    fail "Kernel artifact root is not a directory"

[ -f "$KERNEL_ARTIFACT_DIR/kernel-artifact.json" ] ||
    fail "Missing kernel-artifact.json"

[ -f "$KERNEL_ARTIFACT_DIR/kernel/vmlinux" ] ||
    fail "Missing kernel/vmlinux"

[ -f "$KERNEL_ARTIFACT_DIR/kernel/config" ] ||
    fail "Missing kernel/config"

[ -f "$KERNEL_ARTIFACT_DIR/kernel/kernel.release" ] ||
    fail "Missing kernel/kernel.release"

[ -f "$KERNEL_ARTIFACT_DIR/kernel/modules.builtin" ] ||
    fail "Missing kernel/modules.builtin"

[ -f "$KERNEL_ARTIFACT_DIR/kernel/modules.builtin.modinfo" ] ||
    fail "Missing kernel/modules.builtin.modinfo"

echo
echo "Kernel artifact files:"
find "$KERNEL_ARTIFACT_DIR" -maxdepth 3 -type f -print | sort

echo
echo "Kernel artifact metadata:"
cat "$KERNEL_ARTIFACT_DIR/kernel-artifact.json"

###############################################################################
# Dependency source root
###############################################################################

log "Prepare dependency source root"

mkdir -p "$SOURCE_ROOT"
mkdir -p "$KERNARIUM/.build/dependency-cache"
mkdir -p "$KERNARIUM/.build/dependency-cache/git"
mkdir -p "$KERNARIUM/.build/dependency-cache/archives"

###############################################################################
# Prepare macOS dependency sources
###############################################################################

log "Prepare standard macOS dependencies"

MACOS_PREPARE_LOG="$KERNARIUM/.build/macos-prepare.log"

set +e

"$KERNARIUM/dependencies/prepare.sh" 
    --product macos 
    --root "$SOURCE_ROOT" 
    >"$MACOS_PREPARE_LOG" 2>&1

MACOS_PREPARE_STATUS=$?

set -e

cat "$MACOS_PREPARE_LOG"

###############################################################################
# Verify macOS dependency repositories
###############################################################################

if [ "$MACOS_PREPARE_STATUS" -ne 0 ]; then
    fail "macOS dependency preparation failed"
fi

log "Verify prepared macOS dependency repositories"

macos_repos=(
    zlib
    pcre2
    libffi
    gnulib
    libiconv
    proxy-libintl
    glib
    gvdb
    libslirp
    libvncserver
)

for repo in "${macos_repos[@]}"; do
    [ -d "$SOURCE_ROOT/$repo/.git" ] ||
        fail "macOS dependency source is missing: $repo"

    echo "OK: $repo"
done

run "$KERNARIUM/dependencies/prepare.sh" 
    --product macos 
    --root "$SOURCE_ROOT" 
    --verify

###############################################################################
# Build host dependency prefix
###############################################################################

log "Build Kernarium host dependency prefix"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

echo "Host deployment target: $MACOSX_DEPLOYMENT_TARGET"

run env 
    MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" 
    UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT" 
    UML_DEPENDENCY_PREFIX="$HOST_PREFIX" 
    UML_DEPENDENCY_BUILD_ROOT="$HOST_WORK_ROOT" 
    UML_DEPENDENCY_JOBS="$CPU_CORES" 
    "$KERNARIUM/dependencies/build.sh" 
    --source-root "$SOURCE_ROOT" 
    --prefix "$HOST_PREFIX" 
    --work-root "$HOST_WORK_ROOT" 
    --jobs "$CPU_CORES"

###############################################################################
# Verify host dependency prefix
###############################################################################

log "Verify host dependency prefix"

HOST_RECEIPT="$HOST_PREFIX/share/uml-dependencies/receipt.tsv"

[ -f "$HOST_RECEIPT" ] ||
    fail "Host dependency receipt is missing: $HOST_RECEIPT"

echo "Host dependency prefix:"
echo "$HOST_PREFIX"

echo
echo "Host dependency receipt:"
cat "$HOST_RECEIPT"

###############################################################################
# Prepare Apple GPU sources
###############################################################################

log "Prepare Apple GPU dependency sources"

run "$KERNARIUM/dependencies/prepare.sh" 
    --product apple-gpu 
    --root "$SOURCE_ROOT"

gpu_repos=(
    utm-webkit
    utm-libepoxy
    utm-virglrenderer
)

for repo in "${gpu_repos[@]}"; do
    [ -d "$SOURCE_ROOT/$repo/.git" ] ||
        fail "Apple GPU dependency source is missing: $repo"

    echo "OK: $repo"
done

###############################################################################
# Build Apple GPU dependencies
###############################################################################

log "Build Apple GPU dependencies for iOS"

run "$KERNARIUM/dependencies/build-apple-gpu.sh" 
    --platform ios

###############################################################################
# Verify iOS GPU prefix
###############################################################################

log "Verify iOS GPU dependency prefix"

[ -d "$IOS_GPU_PREFIX" ] ||
    fail "iOS Apple GPU prefix was not created: $IOS_GPU_PREFIX"

IOS_EPOXY="$IOS_GPU_PREFIX/lib/libepoxy.a"
IOS_VIRGL="$IOS_GPU_PREFIX/lib/libvirglrenderer.a"

[ -f "$IOS_EPOXY" ] ||
    fail "Missing iOS libepoxy.a: $IOS_EPOXY"

[ -f "$IOS_VIRGL" ] ||
    fail "Missing iOS libvirglrenderer.a: $IOS_VIRGL"

ls -lh 
    "$IOS_EPOXY" 
    "$IOS_VIRGL"

###############################################################################
# Configure Kernarium
###############################################################################

log "Configure Kernarium iOS build"

BUILD_DIR="$KERNARIUM/.build/ios-arm64"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$KERNARIUM"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"
IOS_CLANGXX="$(xcrun --sdk iphoneos --find clang++)"

echo
echo "iOS SDK:"
echo "$IOS_SDK"

echo
echo "iOS deployment target:"
echo "$IOS_VERSION"

echo
echo "Kernel artifact:"
echo "$KERNEL_ARTIFACT_DIR"

###############################################################################
# Configure iOS
###############################################################################

run cmake 
    -S "$KERNARIUM" 
    -B "$BUILD_DIR" 
    -G Ninja 
    -DCMAKE_BUILD_TYPE=Release 
    -DCMAKE_SYSTEM_NAME=iOS 
    -DCMAKE_OSX_SYSROOT="$IOS_SDK" 
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" 
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_VERSION" 
    -DCMAKE_C_COMPILER="$IOS_CLANG" 
    -DCMAKE_CXX_COMPILER="$IOS_CLANGXX" 
    -DUML_APPLE_PLATFORM=ios 
    -DUML_KERNEL_PRODUCT=android-17 
    -DUML_KERNEL_ARTIFACT_DIR="$KERNEL_ARTIFACT_DIR" 
    -DUML_GUEST_16K_PAGES=ON 
    -DUML_BUILD_CLI=OFF 
    -DUML_BUILD_ANDROID17_CLI=OFF 
    -DUML_BUILD_GPU=OFF 
    -DUML_BUILD_AUDIO=OFF 
    -DUML_BUILD_NETWORK_PROVIDER=OFF 
    -DUML_BUILD_KERNARIUM_RUNTIME=ON 
    -DUML_BUILD_UNIT_TESTS=OFF 
    -DUML_BUILD_INTEGRATION_TESTS=OFF 
    -DUML_BUILD_TOOLING_TESTS=OFF

###############################################################################
# Build
###############################################################################

log "Build Kernarium"

run cmake 
    --build "$BUILD_DIR" 
    --parallel "$CPU_CORES"

###############################################################################
# Install
###############################################################################

log "Install Kernarium"

INSTALL_PREFIX="$KERNARIUM/.build/install-ios"

rm -rf "$INSTALL_PREFIX"

run cmake 
    --install "$BUILD_DIR" 
    --prefix "$INSTALL_PREFIX"

###############################################################################
# Final verification
###############################################################################

log "Kernarium build completed"

echo
echo "Build directory:"
echo "$BUILD_DIR"

echo
echo "Install directory:"
echo "$INSTALL_PREFIX"

find "$INSTALL_PREFIX" 
    -maxdepth 5 
    -type f 
    -print 
    | sort

echo
echo "========================================"
echo "Kernarium build: SUCCESS"
echo "========================================"

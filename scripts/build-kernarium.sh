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

# ==========================================================
# Environment
# ==========================================================

log "Checking environment"

echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version | head -1)"
echo "iOS SDK     : $(xcrun --sdk iphoneos --show-sdk-path)"
echo "CPU cores   : $CPU_CORES"
echo "Kernarium   : $KERNARIUM"
echo "iOS target  : $IOS_VERSION"
echo "Architecture: $ARCH"

# ==========================================================
# Git identity
# ==========================================================

log "Configure Git identity"

git config --global user.name "AndroidEmu Builder"
git config --global user.email "androidemu-builder@localhost"

echo "Git global user : $(git config --global user.name)"
echo "Git global email: $(git config --global user.email)"

export GIT_AUTHOR_NAME="AndroidEmu Builder"
export GIT_AUTHOR_EMAIL="androidemu-builder@localhost"
export GIT_COMMITTER_NAME="AndroidEmu Builder"
export GIT_COMMITTER_EMAIL="androidemu-builder@localhost"

echo "Committer       : ${GIT_COMMITTER_NAME} <${GIT_COMMITTER_EMAIL}>"

# ==========================================================
# Verify required tools
# ==========================================================

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
)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "Required build tool is missing: $tool"
    fi
done

echo
echo "cmake      : $(cmake --version | head -1)"
echo "ninja      : $(ninja --version)"
echo "meson      : $(meson --version)"
echo "pkg-config : $(pkg-config --version)"
echo "python3    : $(python3 --version)"
echo "clang      : $(clang --version | head -1)"
echo "autoreconf : $(autoreconf --version | head -1)"
echo "autoconf   : $(autoconf --version | head -1)"
echo "automake   : $(automake --version | head -1)"
echo "libtool    : $(glibtoolize --version | head -1)"
echo "autopoint  : $(autopoint --version | head -1)"
echo "gperf      : $(gperf --version | head -1)"

# ==========================================================
# Python environment
# ==========================================================

log "Verify Python build environment"

VENV="$RUNNER_TEMP/kernarium-venv"

if [ ! -d "$VENV" ]; then
    echo
    echo "Creating Python virtual environment:"
    echo "$VENV"

    python3 -m venv "$VENV"
fi

source "$VENV/bin/activate"

python -m pip install --upgrade pip
python -m pip install PyYAML

echo
echo "Python:"
python --version

echo "PyYAML:"
python -c 'import yaml; print(yaml.__version__)'

# ==========================================================
# Verify Kernarium
# ==========================================================

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

if [ -d "$KERNARIUM/android/aosp-17" ]; then
    echo
    echo "Android AOSP 17:"
    echo "  OK"
else
    fail "Android AOSP 17 source not found"
fi

# ==========================================================
# Prepare dependency sources
# ==========================================================

log "Prepare Kernarium dependency sources"

mkdir -p "$SOURCE_ROOT"

echo "Dependency source root:"
echo "$SOURCE_ROOT"

# ----------------------------------------------------------
# IMPORTANT:
#
# Kernarium has separate dependency products.
#
# macos     = host/runtime dependencies
# apple-gpu = Apple GPU dependencies
#
# build.sh internally verifies product=macos, therefore
# macos MUST be prepared before calling build.sh.
# ----------------------------------------------------------

echo
echo "Preparing macOS host dependency repositories..."

run "$KERNARIUM/dependencies/prepare.sh" \
    --product macos \
    --root "$SOURCE_ROOT"

echo
echo "Preparing Apple GPU dependency repositories..."

run "$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$SOURCE_ROOT"

# ==========================================================
# Verify prepared repositories
# ==========================================================

log "Verify prepared dependency repositories"

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

gpu_repos=(
    utm-webkit
    utm-libepoxy
    utm-virglrenderer
)

for repo in "${macos_repos[@]}"; do
    if [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "macOS dependency repository is missing: $repo"
    fi

    echo "OK: $repo"
done

for repo in "${gpu_repos[@]}"; do
    if [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "Apple GPU dependency repository is missing: $repo"
    fi

    echo "OK: $repo"
done

# ==========================================================
# Build host dependency prefix
# ==========================================================

log "Build Kernarium host dependency prefix"

run "$KERNARIUM/dependencies/build.sh" \
    --source-root "$SOURCE_ROOT" \
    --prefix "$HOST_PREFIX" \
    --work-root "$HOST_WORK_ROOT" \
    --jobs "$CPU_CORES"

# ==========================================================
# Verify host dependency receipt
# ==========================================================

log "Verify host dependency prefix"

HOST_RECEIPT="$HOST_PREFIX/share/uml-dependencies/receipt.tsv"

if [ ! -f "$HOST_RECEIPT" ]; then
    fail "Host dependency receipt is missing: $HOST_RECEIPT"
fi

if [ ! -d "$HOST_PREFIX/lib" ]; then
    fail "Host dependency lib directory is missing"
fi

echo "Host dependency prefix:"
echo "$HOST_PREFIX"

echo
echo "Host dependency receipt:"
cat "$HOST_RECEIPT"

# ==========================================================
# Build Apple GPU dependencies
# ==========================================================

log "Build Apple GPU dependencies for iOS"

run "$KERNARIUM/dependencies/build-apple-gpu.sh" \
    --platform ios

# ==========================================================
# Verify iOS GPU prefix
# ==========================================================

log "Verify iOS GPU dependency prefix"

if [ ! -d "$IOS_GPU_PREFIX" ]; then
    fail "iOS Apple GPU prefix was not created: $IOS_GPU_PREFIX"
fi

IOS_EPOXY="$IOS_GPU_PREFIX/lib/libepoxy.a"
IOS_VIRGL="$IOS_GPU_PREFIX/lib/libvirglrenderer.a"

if [ !f "$IOS_EPOXY" ]; then
    fail "Missing iOS libepoxy.a: $IOS_EPOXY"
fi

if [ ! -f "$IOS_VIRGL" ]; then
    fail "Missing iOS libvirglrenderer.a: $IOS_VIRGL"
fi

echo
echo "iOS Apple GPU prefix:"
echo "$IOS_GPU_PREFIX"

echo
echo "GPU libraries:"
ls -lh \
    "$IOS_EPOXY" \
    "$IOS_VIRGL"

# ==========================================================
# Configure Kernarium
# ==========================================================

log "Configure Kernarium CMake build"

BUILD_DIR="$KERNARIUM/.build/ios-arm64"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$KERNARIUM"

run cmake \
    -S "$KERNARIUM" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_VERSION" \
    -DCMAKE_C_COMPILER="$(xcrun --find clang)" \
    -DCMAKE_CXX_COMPILER="$(xcrun --find clang++)"

# ==========================================================
# Build Kernarium
# ==========================================================

log "Build Kernarium"

run cmake \
    --build "$BUILD_DIR" \
    --parallel "$CPU_CORES"

# ==========================================================
# Install / stage
# ==========================================================

log "Install Kernarium"

INSTALL_PREFIX="$KERNARIUM/.build/install-ios"

rm -rf "$INSTALL_PREFIX"

run cmake \
    --install "$BUILD_DIR" \
    --prefix "$INSTALL_PREFIX"

# ==========================================================
# Final verification
# ==========================================================

log "Kernarium build completed"

echo
echo "Build directory:"
echo "$BUILD_DIR"

echo
echo "Install directory:"
echo "$INSTALL_PREFIX"

echo
echo "Generated files:"
find "$INSTALL_PREFIX" \
    -maxdepth 4 \
    -type f \
    -print \
    | sort \
    | head -200

echo
echo "========================================"
echo "Kernarium build: SUCCESS"
echo "========================================"

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

IOS_VERSION="${IOS_VERSION:-16.4}"
CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 3)"

BUILD_DIR="$KERNARIUM/.build"
SOURCE_ROOT="$KERNARIUM/external/sources"

HOST_PREFIX="$BUILD_DIR/dependencies/macos-arm64"
IOS_GPU_PREFIX="$BUILD_DIR/dependencies/apple-gpu/ios-device-arm64"

HOST_WORK_ROOT="$BUILD_DIR/dependency-build"
CMAKE_BUILD_DIR="$BUILD_DIR/kernarium-ios16"
INSTALL_DIR="$BUILD_DIR/install-ios"

section()
{
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
}

fail()
{
    echo
    echo "ERROR: $*" >&2
    exit 1
}

require_file()
{
    local path="$1"

    if [ ! -f "$path" ]; then
        fail "Required file does not exist:
$path"
    fi
}

require_dir()
{
    local path="$1"

    if [ ! -d "$path" ]; then
        fail "Required directory does not exist:
$path"
    fi
}

run()
{
    echo
    echo "+ $*"
    "$@"
}

# ============================================================
# ENVIRONMENT
# ============================================================

section "Checking environment"

echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version | head -1)"
echo "iOS SDK     : $(xcrun --sdk iphoneos --show-sdk-path)"
echo "CPU cores   : $CPU_CORES"
echo "Kernarium   : $KERNARIUM"
echo "iOS target  : $IOS_VERSION"
echo "Architecture: arm64"

require_dir "$KERNARIUM"
require_file "$KERNARIUM/CMakeLists.txt"

# ============================================================
# GIT IDENTITY
# ============================================================

section "Configure Git identity"

git config --global user.name "AndroidEmu Builder"
git config --global user.email "androidemu-builder@localhost"

export GIT_AUTHOR_NAME="AndroidEmu Builder"
export GIT_AUTHOR_EMAIL="androidemu-builder@localhost"
export GIT_COMMITTER_NAME="AndroidEmu Builder"
export GIT_COMMITTER_EMAIL="androidemu-builder@localhost"

echo "Git global user : $(git config --global user.name)"
echo "Git global email: $(git config --global user.email)"
echo "Committer       : ${GIT_COMMITTER_NAME} <${GIT_COMMITTER_EMAIL}>"

# ============================================================
# BUILD TOOLS
# ============================================================

section "Verify build tools"

for tool in cmake ninja meson pkg-config python3 git xcodebuild xcrun; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "required build tool is unavailable: $tool"
    fi
done

echo
echo "cmake      : $(cmake --version | head -1)"
echo "ninja      : $(ninja --version)"
echo "meson      : $(meson --version)"
echo "pkg-config : $(pkg-config --version)"
echo "python3    : $(python3 --version)"
echo "clang      : $(clang --version | head -1)"

# ============================================================
# PYTHON / PYYAML
# ============================================================

section "Verify Python build environment"

if python3 -c "import yaml" >/dev/null 2>&1; then

    echo "PyYAML available:"
    python3 -c \
        'import yaml; print("  PyYAML:", yaml.__version__)'

else

    VENV_DIR="${RUNNER_TEMP:-$BUILD_DIR}/kernarium-venv"

    echo
    echo "Creating Python virtual environment:"
    echo "$VENV_DIR"

    python3 -m venv "$VENV_DIR"

    "$VENV_DIR/bin/python" \
        -m pip install --upgrade pip

    "$VENV_DIR/bin/python" \
        -m pip install PyYAML

    export PATH="$VENV_DIR/bin:$PATH"
fi

echo
echo "Python:"
python3 --version

echo "PyYAML:"
python3 -c \
    'import yaml; print(yaml.__version__)'

# ============================================================
# VERIFY KERNARIUM
# ============================================================

section "Verify Kernarium source"

cd "$KERNARIUM"

echo "Kernarium commit:"
git rev-parse HEAD

if [ -d "$KERNARIUM/android/aosp-17" ]; then
    echo
    echo "Android AOSP 17:"
    echo "  OK"
else
    fail "android/aosp-17 source tree is missing"
fi

# ============================================================
# PREPARE DEPENDENCY SOURCE TREES
#
# IMPORTANT:
#
# DO NOT:
#
#   rm -rf external/sources/utm-webkit
#
# followed by:
#
#   prepare.sh --verify
#
# because --verify is verification-only.
#
# First call prepare.sh WITHOUT --verify.
# It will fetch/materialize the pinned Git repositories.
#
# After that, dependencies/build.sh can safely use --verify.
# ============================================================

section "Prepare Kernarium dependency sources"

mkdir -p "$SOURCE_ROOT"

echo "Dependency source root:"
echo "$SOURCE_ROOT"

echo
echo "Running dependencies/prepare.sh..."

export UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT"
export UML_DEPENDENCY_PRODUCT="apple-gpu"

run \
    "$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$SOURCE_ROOT"

# ============================================================
# VERIFY PREPARED APPLE GPU SOURCES
# ============================================================

section "Verify prepared dependency repositories"

for repo in \
    utm-webkit \
    utm-libepoxy \
    utm-virglrenderer
do

    if [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "Prepared Git repository is missing:
$SOURCE_ROOT/$repo"
    fi

    echo "OK: $repo"
done

# ============================================================
# SHOW PREPARED SOURCE REVISIONS
# ============================================================

section "Show dependency source revisions"

for repo in \
    utm-webkit \
    utm-libepoxy \
    utm-virglrenderer
do

    echo
    echo "$repo:"
    git -C "$SOURCE_ROOT/$repo" rev-parse HEAD
done

# ============================================================
# BUILD HOST DEPENDENCIES
#
# Kernarium's own dependencies/build.sh performs:
#
#   prepare.sh --product macos --verify
#
# and then builds:
#
#   .build/dependencies/macos-arm64/
#
# including:
#
#   share/uml-dependencies/receipt.tsv
#
# We MUST NOT fake this prefix by copying GPU libraries.
# ============================================================

section "Build Kernarium host dependency prefix"

mkdir -p "$BUILD_DIR"

export UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT"
export UML_DEPENDENCY_JOBS="$CPU_CORES"
export MACOSX_DEPLOYMENT_TARGET="14.0"

run \
    "$KERNARIUM/dependencies/build.sh" \
    --source-root "$SOURCE_ROOT" \
    --prefix "$HOST_PREFIX" \
    --work-root "$HOST_WORK_ROOT" \
    --jobs "$CPU_CORES"

# ============================================================
# VERIFY HOST PREFIX
# ============================================================

section "Verify Kernarium host dependency prefix"

require_dir "$HOST_PREFIX"

require_file \
    "$HOST_PREFIX/share/uml-dependencies/receipt.tsv"

require_file \
    "$HOST_PREFIX/lib/libepoxy.a"

require_file \
    "$HOST_PREFIX/lib/libvirglrenderer.a"

echo
echo "Host dependency receipt:"
cat "$HOST_PREFIX/share/uml-dependencies/receipt.tsv"

echo
echo "Host libepoxy:"
ls -lh "$HOST_PREFIX/lib/libepoxy.a"

echo
echo "Host libvirglrenderer:"
ls -lh "$HOST_PREFIX/lib/libvirglrenderer.a"

# ============================================================
# BUILD iOS APPLE GPU DEPENDENCIES
# ============================================================

section "Build iOS Apple GPU dependency"

export UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT"

run \
    "$KERNARIUM/dependencies/build-apple-gpu.sh" \
    --platform ios

# ============================================================
# VERIFY iOS GPU PREFIX
# ============================================================

section "Verify iOS Apple GPU dependency"

require_dir "$IOS_GPU_PREFIX"

require_file \
    "$IOS_GPU_PREFIX/lib/libepoxy.a"

require_file \
    "$IOS_GPU_PREFIX/lib/libvirglrenderer.a"

echo
echo "iOS libepoxy.a:"
ls -lh \
    "$IOS_GPU_PREFIX/lib/libepoxy.a"

echo
echo "iOS libvirglrenderer.a:"
ls -lh \
    "$IOS_GPU_PREFIX/lib/libvirglrenderer.a"

# ============================================================
# CLEAN CMAKE BUILD
# ============================================================

section "Prepare Kernarium CMake build"

rm -rf "$CMAKE_BUILD_DIR"
mkdir -p "$CMAKE_BUILD_DIR"

# ============================================================
# CMAKE CONFIGURATION
# ============================================================

section "Configure Kernarium iOS $IOS_VERSION"

cd "$KERNARIUM"

export CMAKE_PREFIX_PATH="$HOST_PREFIX"
export PKG_CONFIG_PATH="$HOST_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$HOST_PREFIX/lib/pkgconfig"

echo
echo "Host dependency prefix:"
echo "$HOST_PREFIX"

echo
echo "iOS GPU dependency prefix:"
echo "$IOS_GPU_PREFIX"

echo
echo "CMake build directory:"
echo "$CMAKE_BUILD_DIR"

cmake \
    -S "$KERNARIUM" \
    -B "$CMAKE_BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_VERSION" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DUML_DEPENDENCY_PREFIX="$HOST_PREFIX" \
    -DUML_APPLE_GPU_DEPENDENCY_PREFIX="$IOS_GPU_PREFIX" \
    -DUML_APPLE_PLATFORM=ios \
    -DUML_BUILD_GPU=ON \
    -DUML_BUILD_AUDIO=ON \
    -DUML_BUILD_NETWORK_PROVIDER=ON \
    -DUML_BUILD_UNIT_TESTS=OFF \
    -DUML_BUILD_INTEGRATION_TESTS=OFF \
    -DUML_BUILD_TOOLING_TESTS=OFF

# ============================================================
# BUILD
# ============================================================

section "Build Kernarium iOS $IOS_VERSION"

cmake \
    --build "$CMAKE_BUILD_DIR" \
    --parallel "$CPU_CORES"

# ============================================================
# INSTALL
# ============================================================

section "Install Kernarium iOS build"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

cmake \
    --install "$CMAKE_BUILD_DIR"

# ============================================================
# LOCATE OUTPUTS
# ============================================================

section "Locate Kernarium outputs"

echo
echo "Build directory:"
du -sh "$CMAKE_BUILD_DIR" || true

echo
echo "Generated files:"

find "$CMAKE_BUILD_DIR" \
    -type f \
    \( \
        -perm -111 \
        -o -name "*.a" \
        -o -name "*.dylib" \
        -o -name "*.framework" \
    \) \
    -print \
    | head -200

echo
echo "Installed files:"

if [ -d "$INSTALL_DIR" ]; then

    find "$INSTALL_DIR" \
        -type f \
        -print \
        | head -200

else

    echo "Install directory was not generated."

fi

# ============================================================
# VERIFY CMAKE
# ============================================================

section "Verify Kernarium build"

require_file \
    "$CMAKE_BUILD_DIR/CMakeCache.txt"

echo
echo "CMake configuration: OK"

# ============================================================
# EXPORT BUILD ENVIRONMENT
# ============================================================

cat > "$BUILD_DIR/kernarium-build-env.sh" <<EOF
export KERNARIUM_ROOT="$KERNARIUM"
export KERNARIUM_BUILD_DIR="$CMAKE_BUILD_DIR"
export KERNARIUM_INSTALL_DIR="$INSTALL_DIR"
export KERNARIUM_HOST_PREFIX="$HOST_PREFIX"
export KERNARIUM_IOS_GPU_PREFIX="$IOS_GPU_PREFIX"
export KERNARIUM_IOS_VERSION="$IOS_VERSION"
export KERNARIUM_IOS_ARCH="arm64"
EOF

echo
echo "Build environment:"
cat "$BUILD_DIR/kernarium-build-env.sh"

# ============================================================
# DONE
# ============================================================

section "Kernarium iOS build completed"

echo
echo "Kernarium build:"
echo "$CMAKE_BUILD_DIR"

echo
echo "Host dependency prefix:"
echo "$HOST_PREFIX"

echo
echo "iOS GPU dependency prefix:"
echo "$IOS_GPU_PREFIX"

echo
echo "Install directory:"
echo "$INSTALL_DIR"

echo
echo "SUCCESS"

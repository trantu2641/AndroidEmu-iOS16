#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

IOS_VERSION="${IOS_VERSION:-16.4}"
IOS_PLATFORM="ios"
IOS_ARCH="arm64"

BUILD_DIR="$KERNARIUM/.build"
CMAKE_BUILD_DIR="$BUILD_DIR/kernarium-ios16"
MACOS_PREFIX="$BUILD_DIR/dependencies/macos-arm64"
IOS_GPU_PREFIX="$BUILD_DIR/dependencies/apple-gpu/ios-device-arm64"

CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 3)"

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
    local file="$1"

    if [ ! -f "$file" ]; then
        fail "Required file does not exist:
$file"
    fi
}

require_dir()
{
    local dir="$1"

    if [ ! -d "$dir" ]; then
        fail "Required directory does not exist:
$dir"
    fi
}

run()
{
    echo
    echo "+ $*"
    "$@"
}

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

section "Checking environment"

echo
echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version | head -1)"
echo "iOS SDK     : $(xcrun --sdk iphoneos --show-sdk-path)"
echo "CPU cores   : $CPU_CORES"
echo "Kernarium   : $KERNARIUM"
echo "iOS target  : $IOS_VERSION"
echo "Architecture: $IOS_ARCH"

require_dir "$KERNARIUM"
require_file "$KERNARIUM/CMakeLists.txt"

# ------------------------------------------------------------
# Git identity
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Toolchain
# ------------------------------------------------------------

section "Verify build tools"

command -v cmake >/dev/null 2>&1 ||
    fail "cmake is unavailable"

command -v ninja >/dev/null 2>&1 ||
    fail "ninja is unavailable"

command -v meson >/dev/null 2>&1 ||
    fail "meson is unavailable"

command -v pkg-config >/dev/null 2>&1 ||
    fail "pkg-config is unavailable"

command -v python3 >/dev/null 2>&1 ||
    fail "python3 is unavailable"

command -v xcodebuild >/dev/null 2>&1 ||
    fail "xcodebuild is unavailable"

command -v xcrun >/dev/null 2>&1 ||
    fail "xcrun is unavailable"

echo
echo "cmake      : $(cmake --version | head -1)"
echo "ninja      : $(ninja --version)"
echo "meson      : $(meson --version)"
echo "pkg-config : $(pkg-config --version)"
echo "python3    : $(python3 --version)"
echo "clang      : $(clang --version | head -1)"

# ------------------------------------------------------------
# Python / PyYAML
# ------------------------------------------------------------

section "Verify Python build environment"

PYTHON_BIN="$(command -v python3)"

if "$PYTHON_BIN" -c "import yaml" >/dev/null 2>&1; then

    echo "PyYAML available:"
    "$PYTHON_BIN" -c \
        'import yaml; print("  PyYAML:", yaml.__version__)'

else

    echo "System Python does not contain PyYAML."

    if [ -x "${RUNNER_TEMP:-/tmp}/kernarium-venv/bin/python" ]; then

        PYTHON_BIN="${RUNNER_TEMP}/kernarium-venv/bin/python"

    else

        VENV_DIR="${RUNNER_TEMP:-$ROOT/.build}/kernarium-venv"

        echo
        echo "Creating Python virtual environment:"
        echo "$VENV_DIR"

        python3 -m venv "$VENV_DIR"

        "$VENV_DIR/bin/python" \
            -m pip install --upgrade pip

        "$VENV_DIR/bin/python" \
            -m pip install PyYAML

        PYTHON_BIN="$VENV_DIR/bin/python"
    fi

fi

export PATH="$(dirname "$PYTHON_BIN"):$PATH"

echo
echo "Python:"
python3 --version

echo "PyYAML:"
python3 -c \
    'import yaml; print(yaml.__version__)'

# ------------------------------------------------------------
# Verify Kernarium source
# ------------------------------------------------------------

section "Verify Kernarium source"

cd "$KERNARIUM"

echo "Kernarium commit:"
git rev-parse HEAD

echo
echo "Android AOSP 17:"
if [ -d "$KERNARIUM/android/aosp-17" ]; then
    echo "  OK"
else
    fail "Kernarium android/aosp-17 directory is missing"
fi

# ------------------------------------------------------------
# Prepare dependency source trees
# ------------------------------------------------------------

section "Prepare Kernarium dependency sources"

SOURCE_ROOT="$KERNARIUM/external/sources"

mkdir -p "$SOURCE_ROOT"

echo "Dependency source root:"
echo "$SOURCE_ROOT"

# Do not leave half-created Git repositories behind.
rm -rf \
    "$SOURCE_ROOT/utm-webkit" \
    "$SOURCE_ROOT/utm-libepoxy" \
    "$SOURCE_ROOT/utm-virglrenderer"

echo
echo "Running dependencies/prepare.sh..."

export UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT"

run \
    "$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$SOURCE_ROOT" \
    --verify

# ------------------------------------------------------------
# Verify prepared sources
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Clean only generated build output
# ------------------------------------------------------------

section "Clean previous Kernarium build output"

rm -rf \
    "$BUILD_DIR/dependency-build" \
    "$BUILD_DIR/kernarium-ios16"

# ------------------------------------------------------------
# Build HOST dependencies
#
# IMPORTANT:
# Do NOT fake macos-arm64 by copying the Apple GPU prefix.
#
# Kernarium's dependencies/build.sh creates:
#
#   .build/dependencies/macos-arm64/
#       include/
#       lib/
#       share/
#           uml-dependencies/
#               receipt.tsv
#
# CMake VerifyDependencies.cmake requires that receipt.
# ------------------------------------------------------------

section "Build Kernarium host dependency prefix"

export UML_DEPENDENCY_JOBS="$CPU_CORES"
export MACOSX_DEPLOYMENT_TARGET="14.0"

run \
    "$KERNARIUM/dependencies/build.sh" \
    --source-root "$SOURCE_ROOT" \
    --prefix "$MACOS_PREFIX" \
    --work-root "$BUILD_DIR/dependency-build" \
    --jobs "$CPU_CORES"

# ------------------------------------------------------------
# Verify HOST dependency prefix
# ------------------------------------------------------------

section "Verify Kernarium host dependency prefix"

require_dir "$MACOS_PREFIX"

require_file \
    "$MACOS_PREFIX/share/uml-dependencies/receipt.tsv"

require_file \
    "$MACOS_PREFIX/lib/libepoxy.a"

require_file \
    "$MACOS_PREFIX/lib/libvirglrenderer.a"

echo
echo "Host dependency receipt:"
cat "$MACOS_PREFIX/share/uml-dependencies/receipt.tsv"

echo
echo "Host libepoxy:"
ls -lh "$MACOS_PREFIX/lib/libepoxy.a"

echo
echo "Host libvirglrenderer:"
ls -lh "$MACOS_PREFIX/lib/libvirglrenderer.a"

# ------------------------------------------------------------
# Build iOS Apple GPU dependencies
# ------------------------------------------------------------

section "Build iOS Apple GPU dependency"

export UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT"

run \
    "$KERNARIUM/dependencies/build-apple-gpu.sh" \
    --platform "$IOS_PLATFORM"

# ------------------------------------------------------------
# Verify iOS Apple GPU prefix
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Important:
# Kernarium's iOS CMake configuration still expects the private
# dependency prefix at:
#
#   .build/dependencies/macos-arm64
#
# BUT that prefix must remain the REAL host prefix.
#
# The iOS Apple GPU libraries are supplied separately through:
#
#   UML_APPLE_GPU_DEPENDENCY_PREFIX
#
# if supported by the CMake dependency module.
# ------------------------------------------------------------

section "Prepare iOS GPU dependency configuration"

if [ -f "$KERNARIUM/dependencies/cmake/AppleGpuDependencies.cmake" ]; then

    echo "Apple GPU CMake module:"
    echo "$KERNARIUM/dependencies/cmake/AppleGpuDependencies.cmake"

else

    fail "AppleGpuDependencies.cmake is missing"

fi

# ------------------------------------------------------------
# Configure Kernarium
# ------------------------------------------------------------

section "Configure Kernarium iOS $IOS_VERSION"

rm -rf "$CMAKE_BUILD_DIR"

mkdir -p "$CMAKE_BUILD_DIR"

cd "$KERNARIUM"

export CMAKE_PREFIX_PATH="$MACOS_PREFIX"
export PKG_CONFIG_PATH="$MACOS_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$MACOS_PREFIX/lib/pkgconfig"

cmake \
    -S "$KERNARIUM" \
    -B "$CMAKE_BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_VERSION" \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install-ios" \
    -DUML_APPLE_PLATFORM=ios \
    -DUML_BUILD_CLI=OFF \
    -DUML_BUILD_ANDROID17_CLI=OFF \
    -DUML_BUILD_KERNEL_RUNNER=OFF \
    -DUML_BUILD_UNIT_TESTS=OFF \
    -DUML_BUILD_INTEGRATION_TESTS=OFF \
    -DUML_BUILD_TOOLING_TESTS=OFF \
    -DUML_BUILD_GPU=ON \
    -DUML_BUILD_AUDIO=ON \
    -DUML_BUILD_NETWORK_PROVIDER=ON \
    -DUML_BUILD_KERNARIUM_RUNTIME=ON \
    -DUML_GUEST_16K_PAGES=ON \
    -DUML_MAINLINE_KERNEL_SLICE=arm64 \
    -DUML_MAINLINE_KERNEL_PROFILE=standard \
    -DUML_BUILD_WINE_ARM64EC=OFF \
    -DUML_DEPENDENCY_PREFIX="$MACOS_PREFIX"

# ------------------------------------------------------------
# Build Kernarium
# ------------------------------------------------------------

section "Build Kernarium iOS $IOS_VERSION"

cmake \
    --build "$CMAKE_BUILD_DIR" \
    --parallel "$CPU_CORES"

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

section "Install Kernarium iOS build"

rm -rf "$BUILD_DIR/install-ios"

cmake \
    --install "$CMAKE_BUILD_DIR"

# ------------------------------------------------------------
# Locate generated binaries
# ------------------------------------------------------------

section "Locate Kernarium outputs"

echo
echo "Executable files:"

find "$CMAKE_BUILD_DIR" \
    -type f \
    \( -perm -111 -o -name "*.a" -o -name "*.dylib" \) \
    -print \
    | head -200

echo
echo "Installed files:"

if [ -d "$BUILD_DIR/install-ios" ]; then

    find "$BUILD_DIR/install-ios" \
        -type f \
        -print \
        | head -200

else

    echo "No install directory generated."

fi

# ------------------------------------------------------------
# Verify build tree
# ------------------------------------------------------------

section "Verify Kernarium build"

if [ -f "$CMAKE_BUILD_DIR/CMakeCache.txt" ]; then
    echo "CMake configuration: OK"
else
    fail "CMakeCache.txt was not generated"
fi

if [ -f "$CMAKE_BUILD_DIR/codemodel-v2.json" ] || \
   find "$CMAKE_BUILD_DIR/.cmake/api/v1/reply" \
       -type f \
       -name "codemodel-v2*.json" \
       -print -quit \
       | grep -q .
then
    echo "CMake File API: OK"
fi

# ------------------------------------------------------------
# Export useful paths for later scripts
# ------------------------------------------------------------

cat > "$BUILD_DIR/kernarium-build-env.sh" <<EOF
export KERNARIUM_ROOT="$KERNARIUM"
export KERNARIUM_BUILD_DIR="$CMAKE_BUILD_DIR"
export KERNARIUM_INSTALL_DIR="$BUILD_DIR/install-ios"
export KERNARIUM_HOST_PREFIX="$MACOS_PREFIX"
export KERNARIUM_IOS_GPU_PREFIX="$IOS_GPU_PREFIX"
export KERNARIUM_IOS_ARCH="$IOS_ARCH"
export KERNARIUM_IOS_VERSION="$IOS_VERSION"
EOF

echo
echo "Build environment:"
cat "$BUILD_DIR/kernarium-build-env.sh"

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

section "Kernarium iOS build completed"

echo
echo "Kernarium build directory:"
echo "$CMAKE_BUILD_DIR"

echo
echo "Host dependency prefix:"
echo "$MACOS_PREFIX"

echo
echo "iOS GPU dependency prefix:"
echo "$IOS_GPU_PREFIX"

echo
echo "Install directory:"
echo "$BUILD_DIR/install-ios"

echo
echo "SUCCESS"

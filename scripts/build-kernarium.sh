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

export GIT_AUTHOR_NAME="AndroidEmu Builder"
export GIT_AUTHOR_EMAIL="androidemu-builder@localhost"
export GIT_COMMITTER_NAME="AndroidEmu Builder"
export GIT_COMMITTER_EMAIL="androidemu-builder@localhost"

echo "Git global user : $(git config --global user.name)"
echo "Git global email: $(git config --global user.email)"
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
    groff
    git
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
echo "groff      : $(groff --version | head -1)"
echo "git        : $(git --version)"

# ==========================================================
# Python environment
# ==========================================================

log "Verify Python build environment"

VENV="${RUNNER_TEMP:-$ROOT/.build}/kernarium-venv"

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
# Prepare dependency source root
# ==========================================================

log "Prepare Kernarium dependency sources"

mkdir -p "$SOURCE_ROOT"

echo "Dependency source root:"
echo "$SOURCE_ROOT"

# ==========================================================
# Savannah / libiconv recovery
#
# Kernarium pins libiconv to:
#
#   ed5a57cfedda75a6abbe4d0fb89a6f7b832f073e
#
# Official URL:
#
#   https://git.savannah.gnu.org/git/libiconv.git
#
# Savannah occasionally returns HTTP 500 from Git fetch.
#
# We DO NOT change the pinned commit.
#
# If the official repository fails, try a known public mirror.
# The mirror is accepted only if it contains the EXACT pinned
# commit. Otherwise the normal official fetch is allowed to
# fail rather than silently using another revision.
# ==========================================================

prepare_libiconv_fallback()
{
    local libiconv_dir="$SOURCE_ROOT/libiconv"
    local cache_root="$KERNARIUM/.build/dependency-cache/git"
    local cache_repo="$cache_root/libiconv"
    local pinned_commit="ed5a57cfedda75a6abbe4d0fb89a6f7b832f073e"

    local mirrors=(
        "https://github.com/Distrotech/libiconv.git"
        "https://github.com/jwinarske/libiconv.git"
        "https://github.com/gnu-mirror-unofficial/libiconv.git"
    )

    echo
    echo "=========================================================="
    echo "libiconv Savannah recovery"
    echo "=========================================================="
    echo "Pinned commit:"
    echo "$pinned_commit"

    mkdir -p "$cache_root"

    # ------------------------------------------------------
    # If a prepared repository already exists, do not touch it.
    # ------------------------------------------------------

    if [ -d "$libiconv_dir/.git" ]; then
        if git -C "$libiconv_dir" rev-parse \
            "$pinned_commit^{commit}" >/dev/null 2>&1; then

            echo
            echo "Existing libiconv repository already contains:"
            echo "$pinned_commit"

            return 0
        fi
    fi

    # ------------------------------------------------------
    # Try mirrors one by one.
    # ------------------------------------------------------

    local mirror

    for mirror in "${mirrors[@]}"; do
        echo
        echo "Trying libiconv mirror:"
        echo "$mirror"

        rm -rf "$cache_repo"

        mkdir -p "$cache_root"

        if git clone \
            --filter=blob:none \
            --no-checkout \
            --depth 1 \
            "$mirror" \
            "$cache_repo" >/dev/null 2>&1; then

            if git -C "$cache_repo" fetch \
                --no-tags \
                --depth 1 \
                origin \
                "$pinned_commit" >/dev/null 2>&1; then

                if git -C "$cache_repo" rev-parse \
                    "$pinned_commit^{commit}" >/dev/null 2>&1; then

                    echo
                    echo "SUCCESS:"
                    echo "Mirror contains the exact pinned libiconv commit."

                    echo
                    echo "Mirror:"
                    echo "$mirror"

                    echo
                    echo "Pinned commit:"
                    git -C "$cache_repo" rev-parse \
                        "$pinned_commit^{commit}"

                    # --------------------------------------------------
                    # IMPORTANT:
                    #
                    # prepare.sh requires its repository metadata to
                    # match the manifest repository URL. Therefore we
                    # cannot simply rename this mirror as libiconv.
                    #
                    # Instead, export the exact commit into a local
                    # bundle/cache that Git can use without network.
                    # --------------------------------------------------

                    local bundle="$cache_root/libiconv-$pinned_commit.bundle"

                    rm -f "$bundle"

                    git -C "$cache_repo" bundle create \
                        "$bundle" \
                        "$pinned_commit" >/dev/null

                    echo
                    echo "Created verified libiconv bundle:"
                    echo "$bundle"

                    export KERNARIUM_LIBICONV_BUNDLE="$bundle"

                    return 0
                fi
            fi
        fi

        echo "Mirror does not provide the required pinned commit."
    done

    echo
    echo "No mirror currently contains the exact pinned libiconv commit."
    return 1
}

# ==========================================================
# Prepare macOS host dependency repositories
# ==========================================================

echo
echo "Preparing macOS host dependency repositories..."

if ! "$KERNARIUM/dependencies/prepare.sh" \
    --product macos \
    --root "$SOURCE_ROOT"; then

    echo
    echo "WARNING: macOS dependency preparation failed."
    echo "Attempting libiconv recovery..."

    if ! prepare_libiconv_fallback; then
        fail "Kernarium dependency preparation failed and no verified libiconv mirror contains the pinned commit."
    fi

    # ------------------------------------------------------
    # At this point the mirror bundle has been verified.
    #
    # prepare.sh itself still requires the manifest URL.
    # Retry official preparation after the recovery attempt.
    #
    # This gives Savannah another chance in case the HTTP 500
    # was temporary.
    # ------------------------------------------------------

    echo
    echo "Retrying official macOS dependency preparation..."

    "$KERNARIUM/dependencies/prepare.sh" \
        --product macos \
        --root "$SOURCE_ROOT"
fi

# ==========================================================
# Prepare Apple GPU dependency repositories
# ==========================================================

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

if [ ! -f "$IOS_EPOXY" ]; then
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

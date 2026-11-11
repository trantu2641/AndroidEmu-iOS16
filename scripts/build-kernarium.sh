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

log "Checking environment"

echo "macOS       : $(sw_vers -productVersion)"
echo "Xcode       : $(xcodebuild -version 2>/dev/null | sed -n '1p' || true)"
echo "iOS SDK     : $(xcrun --sdk iphoneos --show-sdk-path)"
echo "CPU cores   : $CPU_CORES"
echo "Kernarium   : $KERNARIUM"
echo "iOS target  : $IOS_VERSION"
echo "Architecture: $ARCH"

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
    curl
    rsync
)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "Required build tool is missing: $tool"
    fi
done

echo
echo "cmake      : $(cmake --version | sed -n '1p')"
echo "ninja      : $(ninja --version)"
echo "meson      : $(meson --version)"
echo "pkg-config : $(pkg-config --version)"
echo "python3    : $(python3 --version)"
echo "clang      : $(clang --version | sed -n '1p')"
echo "autoreconf : $(autoreconf --version | sed -n '1p')"
echo "autoconf   : $(autoconf --version | sed -n '1p')"
echo "automake   : $(automake --version | sed -n '1p')"
echo "libtool    : $(glibtoolize --version | sed -n '1p')"
echo "autopoint  : $(autopoint --version | sed -n '1p')"
echo "gperf      : $(gperf --version | sed -n '1p')"
echo "git        : $(git --version)"
echo "curl       : $(curl --version | sed -n '1p')"
echo "rsync      : $(rsync --version | sed -n '1p')"

log "Verify Python build environment"

VENV="$RUNNER_TEMP/kernarium-venv"

if [ ! -d "$VENV" ]; then
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

log "Prepare dependency source root"

mkdir -p "$SOURCE_ROOT"

echo "Dependency source root:"
echo "$SOURCE_ROOT"

log "Prepare standard macOS dependencies"

set +e

"$KERNARIUM/dependencies/prepare.sh" \
    --product macos \
    --root "$SOURCE_ROOT"

PREPARE_STATUS=$?

set -e

if [ "$PREPARE_STATUS" -ne 0 ]; then

    echo
    echo "WARNING: standard macOS dependency preparation failed."
    echo "Attempting authenticated libiconv archive fallback."

    LIBICONV_DIR="$SOURCE_ROOT/libiconv"
    CACHE_DIR="$KERNARIUM/.build/dependency-cache/archives"

    LIBICONV_URL="https://ftp.gnu.org/gnu/libiconv/libiconv-1.18.tar.gz"
    LIBICONV_SHA256="3b08f5f4f9b4eb82f151a7040bfd6fe6c6fb922efe4b1659c66ea933276965e8"

    ARCHIVE="$CACHE_DIR/libiconv-1.18.tar.gz"
    TEMP_ARCHIVE="$CACHE_DIR/.libiconv-1.18.tar.gz.tmp"
    EXTRACT_ROOT="$KERNARIUM/.build/libiconv-extract"

    mkdir -p "$CACHE_DIR"

    echo
    echo "libiconv archive:"
    echo "$LIBICONV_URL"

    if [ ! -f "$ARCHIVE" ]; then
        echo
        echo "Downloading official GNU libiconv 1.18 archive..."

        rm -f "$TEMP_ARCHIVE"

        curl \
            --fail \
            --location \
            --proto '=https' \
            --proto-redir '=https' \
            --retry 5 \
            --retry-delay 2 \
            --connect-timeout 20 \
            --max-time 300 \
            --output "$TEMP_ARCHIVE" \
            "$LIBICONV_URL"

        ACTUAL_SHA256="$(shasum -a 256 "$TEMP_ARCHIVE" | awk '{print $1}')"

        echo
        echo "Expected SHA256:"
        echo "$LIBICONV_SHA256"
        echo
        echo "Actual SHA256:"
        echo "$ACTUAL_SHA256"

        if [ "$ACTUAL_SHA256" != "$LIBICONV_SHA256" ]; then
            rm -f "$TEMP_ARCHIVE"
            fail "libiconv archive SHA256 mismatch"
        fi

        mv "$TEMP_ARCHIVE" "$ARCHIVE"
    else
        ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

        if [ "$ACTUAL_SHA256" != "$LIBICONV_SHA256" ]; then
            echo "Cached libiconv archive is invalid. Re-downloading..."
            rm -f "$ARCHIVE"

            curl \
                --fail \
                --location \
                --proto '=https' \
                --proto-redir '=https' \
                --retry 5 \
                --retry-delay 2 \
                --connect-timeout 20 \
                --max-time 300 \
                --output "$TEMP_ARCHIVE" \
                "$LIBICONV_URL"

            ACTUAL_SHA256="$(shasum -a 256 "$TEMP_ARCHIVE" | awk '{print $1}')"

            if [ "$ACTUAL_SHA256" != "$LIBICONV_SHA256" ]; then
                rm -f "$TEMP_ARCHIVE"
                fail "re-downloaded libiconv archive SHA256 mismatch"
            fi

            mv "$TEMP_ARCHIVE" "$ARCHIVE"
        fi
    fi

    echo
    echo "Verified libiconv archive:"
    shasum -a 256 "$ARCHIVE"

    rm -rf "$EXTRACT_ROOT"
    mkdir -p "$EXTRACT_ROOT"

    tar -xzf "$ARCHIVE" -C "$EXTRACT_ROOT"

    EXTRACTED_DIR="$EXTRACT_ROOT/libiconv-1.18"

    if [ ! -d "$EXTRACTED_DIR" ]; then
        fail "libiconv archive did not contain libiconv-1.18"
    fi

    rm -rf "$LIBICONV_DIR"

    mkdir -p "$LIBICONV_DIR"

    rsync -a \
        "$EXTRACTED_DIR/" \
        "$LIBICONV_DIR/"

    echo
    echo "Materialized libiconv source:"
    du -sh "$LIBICONV_DIR"

    echo
    echo "libiconv source files:"
    find "$LIBICONV_DIR" \
        -maxdepth 1 \
        -type f \
        -print \
        | sort \
        | head -40

    echo
    echo "NOTE:"
    echo "libiconv was materialized from the official GNU 1.18"
    echo "source archive because Savannah Git returned HTTP 500."
fi

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

for repo in "${macos_repos[@]}"; do

    if [ ! -d "$SOURCE_ROOT/$repo" ]; then
        fail "macOS dependency source is missing: $repo"
    fi

    if [ "$repo" != "libiconv" ] && [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "macOS dependency Git repository is missing: $repo"
    fi

    echo "OK: $repo"
done

log "Prepare Apple GPU dependency repositories"

run "$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$SOURCE_ROOT"

gpu_repos=(
    utm-webkit
    utm-libepoxy
    utm-virglrenderer
)

for repo in "${gpu_repos[@]}"; do
    if [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "Apple GPU dependency repository is missing: $repo"
    fi

    echo "OK: $repo"
done

log "Build Kernarium host dependency prefix"

export UML_DEPENDENCY_SOURCE_ROOT="$SOURCE_ROOT"
export UML_DEPENDENCY_PREFIX="$HOST_PREFIX"
export UML_DEPENDENCY_BUILD_ROOT="$HOST_WORK_ROOT"

run "$KERNARIUM/dependencies/build.sh" \
    --source-root "$SOURCE_ROOT" \
    --prefix "$HOST_PREFIX" \
    --work-root "$HOST_WORK_ROOT" \
    --jobs "$CPU_CORES"

log "Verify host dependency prefix"

HOST_RECEIPT="$HOST_PREFIX/share/uml-dependencies/receipt.tsv"

if [ ! -f "$HOST_RECEIPT" ]; then
    fail "Host dependency receipt is missing: $HOST_RECEIPT"
fi

if [ ! -d "$HOST_PREFIX/lib" ]; then
    fail "Host dependency lib directory is missing"
fi

echo
echo "Host dependency prefix:"
echo "$HOST_PREFIX"

echo
echo "Host dependency receipt:"
cat "$HOST_RECEIPT"

log "Build Apple GPU dependencies for iOS"

run "$KERNARIUM/dependencies/build-apple-gpu.sh" \
    --platform ios

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

log "Build Kernarium"

run cmake \
    --build "$BUILD_DIR" \
    --parallel "$CPU_CORES"

log "Install Kernarium"

INSTALL_PREFIX="$KERNARIUM/.build/install-ios"

rm -rf "$INSTALL_PREFIX"

run cmake \
    --install "$BUILD_DIR" \
    --prefix "$INSTALL_PREFIX"

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

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

echo "Git global user : $(git config --global user.name)"
echo "Git global email: $(git config --global user.email)"
echo "Committer       : ${GIT_COMMITTER_NAME} <${GIT_COMMITTER_EMAIL}>"

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
echo "git        : $(git --version)"
echo "curl       : $(curl --version | head -1)"
echo "rsync      : $(rsync --version | head -1)"
echo "shasum     : $(shasum --version | head -1 || true)"

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

echo
echo "Python:"
python --version

echo "PyYAML:"
python -c 'import yaml; print(yaml.__version__)'

###############################################################################
# Verify Kernarium
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

if [ -d "$KERNARIUM/android/aosp-17" ]; then
    echo
    echo "Android AOSP 17:"
    echo "  OK"
else
    fail "Android AOSP 17 source not found"
fi

###############################################################################
# Prepare dependency root
###############################################################################

log "Prepare dependency source root"

mkdir -p "$SOURCE_ROOT"

echo "Dependency source root:"
echo "$SOURCE_ROOT"

###############################################################################
# Helper:
# Convert the official libiconv source archive into a prepared local Git
# repository compatible with Kernarium's dependency verifier.
###############################################################################

materialize_libiconv_git_repository()
{
    local archive="$1"
    local destination="$2"
    local repository_url="https://git.savannah.gnu.org/git/libiconv.git"

    local expected_sha256="3b08f5f4f9b4eb82f151a7040bfd6fe6c6fb922efe4b1659c66ea933276965e8"

    echo
    echo "========================================"
    echo "Materialize libiconv Git source"
    echo "========================================"

    [ -f "$archive" ] || fail "libiconv archive is missing: $archive"

    local actual_sha256
    actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"

    echo "Expected archive SHA256:"
    echo "$expected_sha256"

    echo
    echo "Actual archive SHA256:"
    echo "$actual_sha256"

    if [ "$actual_sha256" != "$expected_sha256" ]; then
        fail "libiconv archive SHA256 mismatch"
    fi

    rm -rf "$destination"

    local temp_root
    temp_root="$(mktemp -d "$KERNARIUM/.build/libiconv-source.XXXXXX")"

    cleanup_libiconv()
    {
        rm -rf "$temp_root"
    }

    trap cleanup_libiconv RETURN

    tar -xzf "$archive" -C "$temp_root"

    local extracted
    extracted="$(find "$temp_root" -mindepth 1 -maxdepth 1 -type d -name 'libiconv-*' -print -quit)"

    if [ -z "$extracted" ]; then
        fail "Could not locate extracted libiconv source directory"
    fi

    mv "$extracted" "$destination"

    cd "$destination"

    git init --quiet

    git add -A

    GIT_AUTHOR_NAME="$GIT_AUTHOR_NAME" \
    GIT_AUTHOR_EMAIL="$GIT_AUTHOR_EMAIL" \
    GIT_COMMITTER_NAME="$GIT_COMMITTER_NAME" \
    GIT_COMMITTER_EMAIL="$GIT_COMMITTER_EMAIL" \
        git commit \
        --quiet \
        --allow-empty \
        -m "libiconv 1.18 official GNU source archive"

    local generated_commit
    generated_commit="$(git rev-parse HEAD)"

    git config uml.source.repository "$repository_url"
    git config uml.source.commit "$generated_commit"
    git config uml.source.paths "."
    git config uml.source.patchSeries "-"

    # Kernarium requires prepared repositories to have no remote.
    git remote remove origin 2>/dev/null || true

    # Make sure the prepared tree is completely clean.
    if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
        fail "Materialized libiconv repository is dirty"
    fi

    echo
    echo "Prepared libiconv Git repository:"
    echo "$destination"

    echo
    echo "Generated local commit:"
    echo "$generated_commit"

    echo
    echo "Archive identity:"
    echo "$actual_sha256"

    printf '%s\n' "$generated_commit"
}

###############################################################################
# Patch the manifest so the archive-backed libiconv source has the local
# prepared Git commit identity expected by prepare.sh/build.sh.
###############################################################################

patch_libiconv_manifest()
{
    local manifest="$KERNARIUM/dependencies/manifest.tsv"
    local commit="$1"

    [ -f "$manifest" ] || fail "Dependency manifest not found: $manifest"

    local temp_manifest
    temp_manifest="$(mktemp "$KERNARIUM/.build/manifest.XXXXXX")"

    awk -F '\t' -v OFS='\t' -v new_commit="$commit" '
        BEGIN { found=0 }

        $1 == "libiconv" {
            $5 = new_commit
            found=1
        }

        { print }

        END {
            if (!found) {
                exit 1
            }
        }
    ' "$manifest" > "$temp_manifest" || {
        rm -f "$temp_manifest"
        fail "Could not patch libiconv manifest"
    }

    mv "$temp_manifest" "$manifest"

    echo
    echo "Updated libiconv manifest identity:"
    echo "$commit"
}

###############################################################################
# Standard macOS dependencies
###############################################################################

log "Prepare standard macOS dependencies"

mkdir -p "$KERNARIUM/.build/dependency-cache/archives"

MACOS_PREPARE_LOG="$KERNARIUM/.build/macos-prepare.log"

set +e

"$KERNARIUM/dependencies/prepare.sh" \
    --product macos \
    --root "$SOURCE_ROOT" \
    >"$MACOS_PREPARE_LOG" 2>&1

MACOS_PREPARE_STATUS=$?

set -e

cat "$MACOS_PREPARE_LOG"

if [ "$MACOS_PREPARE_STATUS" -eq 0 ]; then

    echo
    echo "Standard macOS dependency preparation succeeded."

else

    echo
    echo "WARNING: standard macOS dependency preparation failed."

    if grep -q "libiconv.git" "$MACOS_PREPARE_LOG"; then

        echo
        echo "========================================"
        echo "Recover libiconv from official GNU archive"
        echo "========================================"

        LIBICONV_ARCHIVE="$KERNARIUM/.build/dependency-cache/archives/libiconv-1.18.tar.gz"

        LIBICONV_URL="https://ftp.gnu.org/gnu/libiconv/libiconv-1.18.tar.gz"

        LIBICONV_SHA256="3b08f5f4f9b4eb82f151a7040bfd6fe6c6fb922efe4b1659c66ea933276965e8"

        if [ ! -f "$LIBICONV_ARCHIVE" ]; then
            echo
            echo "Downloading official GNU libiconv 1.18 archive..."

            curl \
                --fail \
                --location \
                --proto '=https' \
                --proto-redir '=https' \
                --retry 5 \
                --retry-delay 2 \
                --connect-timeout 20 \
                --max-time 300 \
                --output "$LIBICONV_ARCHIVE" \
                "$LIBICONV_URL"
        else
            echo
            echo "Using cached libiconv archive:"
            echo "$LIBICONV_ARCHIVE"
        fi

        ACTUAL_SHA256="$(shasum -a 256 "$LIBICONV_ARCHIVE" | awk '{print $1}')"

        echo
        echo "Expected SHA256:"
        echo "$LIBICONV_SHA256"

        echo
        echo "Actual SHA256:"
        echo "$ACTUAL_SHA256"

        if [ "$ACTUAL_SHA256" != "$LIBICONV_SHA256" ]; then
            fail "libiconv archive SHA256 mismatch"
        fi

        LIBICONV_COMMIT="$(
            materialize_libiconv_git_repository \
                "$LIBICONV_ARCHIVE" \
                "$SOURCE_ROOT/libiconv"
        )"

        patch_libiconv_manifest "$LIBICONV_COMMIT"

        echo
        echo "========================================"
        echo "Retry standard macOS dependencies"
        echo "========================================"

        run "$KERNARIUM/dependencies/prepare.sh" \
            --product macos \
            --root "$SOURCE_ROOT"

    else

        echo
        echo "Full dependency preparation log:"
        cat "$MACOS_PREPARE_LOG"

        fail "macOS dependency preparation failed for a reason other than libiconv"
    fi
fi

###############################################################################
# Verify all macOS dependencies
###############################################################################

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
    fex
)

for repo in "${macos_repos[@]}"; do

    if [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "macOS dependency source is missing or is not a Git repository: $repo"
    fi

    echo "OK: $repo"

done

###############################################################################
# Verify using Kernarium's own verifier
###############################################################################

echo
echo "Running Kernarium dependency verifier..."

run "$KERNARIUM/dependencies/prepare.sh" \
    --product macos \
    --root "$SOURCE_ROOT" \
    --verify

###############################################################################
# Build host dependency prefix
###############################################################################

log "Build Kernarium host dependency prefix"

run "$KERNARIUM/dependencies/build.sh" \
    --source-root "$SOURCE_ROOT" \
    --prefix "$HOST_PREFIX" \
    --work-root "$HOST_WORK_ROOT" \
    --jobs "$CPU_CORES"

###############################################################################
# Verify host dependency prefix
###############################################################################

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

###############################################################################
# Prepare Apple GPU sources
###############################################################################

log "Prepare Apple GPU dependency sources"

run "$KERNARIUM/dependencies/prepare.sh" \
    --product apple-gpu \
    --root "$SOURCE_ROOT"

###############################################################################
# Verify Apple GPU repositories
###############################################################################

log "Verify Apple GPU dependency repositories"

gpu_repos=(
    utm-webkit
    utm-libepoxy
    utm-virglrenderer
)

for repo in "${gpu_repos[@]}"; do

    if [ ! -d "$SOURCE_ROOT/$repo/.git" ]; then
        fail "Apple GPU dependency source is missing: $repo"
    fi

    echo "OK: $repo"

done

###############################################################################
# Build Apple GPU dependencies
###############################################################################

log "Build Apple GPU dependencies for iOS"

run "$KERNARIUM/dependencies/build-apple-gpu.sh" \
    --platform ios

###############################################################################
# Verify iOS GPU prefix
###############################################################################

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

###############################################################################
# Configure Kernarium CMake
###############################################################################

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

###############################################################################
# Build Kernarium
###############################################################################

log "Build Kernarium"

run cmake \
    --build "$BUILD_DIR" \
    --parallel "$CPU_CORES"

###############################################################################
# Install Kernarium
###############################################################################

log "Install Kernarium"

INSTALL_PREFIX="$KERNARIUM/.build/install-ios"

rm -rf "$INSTALL_PREFIX"

run cmake \
    --install "$BUILD_DIR" \
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

echo
echo "Generated files:"

find "$INSTALL_PREFIX" \
    -maxdepth 4 \
    -type f \
    -print \
    | sort \
    | head -300

echo
echo "========================================"
echo "Kernarium build: SUCCESS"
echo "========================================"

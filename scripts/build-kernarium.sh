```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNARIUM="$ROOT/Kernarium"

echo
echo "========================================"
echo " AndroidEmu iOS 16.4"
echo " Build Kernarium"
echo "========================================"
echo

cd "$KERNARIUM"

# --------------------------------------------------
# 1. Check architecture
# --------------------------------------------------

echo "==> Checking host..."

ARCH="$(uname -m)"
echo "Host architecture: $ARCH"

if [ "$ARCH" != "arm64" ]; then
    echo
    echo "ERROR: Kernarium Apple GPU build requires an arm64 macOS runner."
    echo "Current architecture: $ARCH"
    exit 1
fi

# --------------------------------------------------
# 2. Check Xcode
# --------------------------------------------------

echo
echo "==> Checking Xcode..."

xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcrun --sdk iphoneos --show-sdk-path

# --------------------------------------------------
# 3. Build Apple GPU dependencies
# --------------------------------------------------

echo
echo "========================================"
echo "==> Building Apple GPU dependency"
echo "========================================"
echo

GPU_SCRIPT="$KERNARIUM/dependencies/build-apple-gpu.sh"

if [ ! -f "$GPU_SCRIPT" ]; then
    echo "ERROR: Apple GPU dependency script not found:"
    echo "$GPU_SCRIPT"
    exit 1
fi

chmod +x "$GPU_SCRIPT"

"$GPU_SCRIPT" \
    --platform ios \
    --jobs "$(sysctl -n hw.ncpu)"

# --------------------------------------------------
# 4. Verify libepoxy
# --------------------------------------------------

GPU_PREFIX="$KERNARIUM/.build/dependencies/apple-gpu/ios-device-arm64"

echo
echo "==> Verifying Apple GPU dependency..."

if [ ! -f "$GPU_PREFIX/lib/libepoxy.a" ]; then
    echo
    echo "ERROR: libepoxy.a was not produced."
    echo
    echo "Expected:"
    echo "$GPU_PREFIX/lib/libepoxy.a"
    echo
    exit 1
fi

if [ ! -f "$GPU_PREFIX/lib/libvirglrenderer.a" ]; then
    echo
    echo "ERROR: libvirglrenderer.a was not produced."
    echo
    exit 1
fi

if [ ! -d "$GPU_PREFIX/include" ]; then
    echo
    echo "ERROR: Apple GPU include directory is missing."
    echo
    exit 1
fi

echo
echo "Apple GPU dependency OK:"
echo "  $GPU_PREFIX"
echo

ls -lh \
    "$GPU_PREFIX/lib/libepoxy.a" \
    "$GPU_PREFIX/lib/libvirglrenderer.a"

# --------------------------------------------------
# 5. Show actual CMake configuration
# --------------------------------------------------

echo
echo "========================================"
echo "==> Detecting CMake configuration"
echo "========================================"
echo

if [ -f "$KERNARIUM/CMakePresets.json" ]; then

    echo "CMakePresets.json found."

    echo
    echo "Available presets:"
    cmake --list-presets 2>&1 || true

elif [ -f "$KERNARIUM/CMakeLists.txt" ]; then

    echo "No CMakePresets.json."
    echo "Using direct CMake configuration."

else

    echo
    echo "ERROR: Kernarium CMakeLists.txt not found."
    exit 1

fi

# --------------------------------------------------
# 6. Configure
# --------------------------------------------------

echo
echo "========================================"
echo "==> Configure Kernarium"
echo "========================================"
echo

BUILD_DIR="$KERNARIUM/.build/androidemu-ios16"

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
    -DCMAKE_C_COMPILER="$(xcrun --sdk iphoneos --find clang)" \
    -DCMAKE_CXX_COMPILER="$(xcrun --sdk iphoneos --find clang++)" \
    -DCMAKE_OBJCXX_COMPILER="$(xcrun --sdk iphoneos --find clang++)"

# --------------------------------------------------
# 7. Build
# --------------------------------------------------

echo
echo "========================================"
echo "==> Build Kernarium"
echo "========================================"
echo

cmake \
    --build "$BUILD_DIR" \
    --parallel "$(sysctl -n hw.ncpu)"

echo
echo "========================================"
echo " Kernarium build completed"
echo "========================================"
echo
echo "Build directory:"
echo "$BUILD_DIR"
```

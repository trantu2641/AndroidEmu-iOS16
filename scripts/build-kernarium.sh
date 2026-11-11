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

# ==================================================
# 1. Git identity
# ==================================================

echo "==> Configuring Git identity..."

git config user.name "AndroidEmu Builder"
git config user.email "androidemu-builder@localhost"

echo "Git user:"
git config user.name
git config user.email

# ==================================================
# 2. Host check
# ==================================================

echo
echo "==> Checking host..."

ARCH="$(uname -m)"

echo "Architecture: $ARCH"

if [ "$ARCH" != "arm64" ]; then
    echo
    echo "ERROR: Apple GPU dependency build requires arm64 macOS."
    exit 1
fi

# ==================================================
# 3. Xcode
# ==================================================

echo
echo "==> Checking Xcode..."

xcodebuild -version

echo
echo "iOS SDK:"
xcrun --sdk iphoneos --show-sdk-version

echo
echo "iOS SDK path:"
xcrun --sdk iphoneos --show-sdk-path

# ==================================================
# 4. Apple GPU dependency
# ==================================================

echo
echo "========================================"
echo "==> Building Apple GPU dependency"
echo "========================================"
echo

GPU_SCRIPT="$KERNARIUM/dependencies/build-apple-gpu.sh"

if [ ! -f "$GPU_SCRIPT" ]; then
    echo
    echo "ERROR:"
    echo "Apple GPU dependency script not found:"
    echo "$GPU_SCRIPT"
    exit 1
fi

chmod +x "$GPU_SCRIPT"

"$GPU_SCRIPT" \
    --platform ios \
    --jobs "$(sysctl -n hw.ncpu)"

# ==================================================
# 5. Verify GPU dependency
# ==================================================

echo
echo "========================================"
echo "==> Verifying Apple GPU dependency"
echo "========================================"
echo

GPU_PREFIX="$KERNARIUM/.build/dependencies/apple-gpu/ios-device-arm64"

EPOXY="$GPU_PREFIX/lib/libepoxy.a"
VIRGL="$GPU_PREFIX/lib/libvirglrenderer.a"

if [ ! -f "$EPOXY" ]; then
    echo
    echo "ERROR: libepoxy.a was not produced."
    echo
    echo "Expected:"
    echo "$EPOXY"
    exit 1
fi

if [ ! -f "$VIRGL" ]; then
    echo
    echo "ERROR: libvirglrenderer.a was not produced."
    echo
    echo "Expected:"
    echo "$VIRGL"
    exit 1
fi

if [ ! -d "$GPU_PREFIX/include" ]; then
    echo
    echo "ERROR: GPU include directory was not produced."
    exit 1
fi

echo "Apple GPU dependency OK."
echo
echo "libepoxy:"
ls -lh "$EPOXY"

echo
echo "libvirglrenderer:"
ls -lh "$VIRGL"

# ==================================================
# 6. Detect CMake
# ==================================================

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

else

    echo "No CMakePresets.json found."
    echo "Using direct CMake configuration."

fi

# ==================================================
# 7. Configure
# ==================================================

echo
echo "========================================"
echo "==> Configuring Kernarium"
echo "========================================"
echo

BUILD_DIR="$KERNARIUM/.build/androidemu-ios16"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

IOS_CC="$(xcrun --sdk iphoneos --find clang)"
IOS_CXX="$(xcrun --sdk iphoneos --find clang++)"

echo "C compiler:"
echo "$IOS_CC"

echo
echo "C++ compiler:"
echo "$IOS_CXX"

echo
echo "Build directory:"
echo "$BUILD_DIR"

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
    -DCMAKE_OBJCXX_COMPILER="$IOS_CXX"

# ==================================================
# 8. Build
# ==================================================

echo
echo "========================================"
echo "==> Building Kernarium"
echo "========================================"
echo

cmake \
    --build "$BUILD_DIR" \
    --parallel "$(sysctl -n hw.ncpu)"

# ==================================================
# 9. Result
# ==================================================

echo
echo "========================================"
echo " Kernarium build completed"
echo "========================================"
echo

echo "Build directory:"
echo "$BUILD_DIR"

echo
echo "Produced files:"

find "$BUILD_DIR" \
    -type f \
    \( \
        -name "*.a" \
        -o -name "*.dylib" \
        -o -name "*.framework" \
        -o -name "*.bin" \
        -o -name "*.img" \
    \) \
    -print \
    2>/dev/null || true

echo
echo "========================================"
echo " DONE"
echo "========================================"
```

#!/bin/zsh

# build.sh — Build loopdown for one or more architectures.
#
# Usage:
#   ./build.sh              # universal (arm64 + x86_64, default)
#   ./build.sh universal    # universal (arm64 + x86_64)
#   ./build.sh arm64        # Apple Silicon only
#   ./build.sh x86_64       # Intel only
#
# Output locations:
#   ../dist/swift/universal/loopdown
#   ../dist/swift/arm64/loopdown
#   ../dist/swift/x86_64/loopdown

set -euo pipefail

ARCH="${1:-universal}"
PROJECT="loopdown.xcodeproj"
SCHEME="loopdown"
CONFIG="Release"
BUILD_ROOT="/tmp/loopdown-build"
DIST_ROOT="../dist/swift"
BINARY="loopdown"

# ── Shared xcodebuild flags ────────────────────────────────────────────────────
XCODE_FLAGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    INFOPLIST_FILE="./Sources/Generated/Info.plist"
    CODE_SIGN_IDENTITY=""
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
)

# ── Build helper ───────────────────────────────────────────────────────────────
build_arch() {
    local arch="$1"
    echo "==> Building $arch..."
    xcodebuild \
        "${XCODE_FLAGS[@]}" \
        -arch "$arch" \
        -derivedDataPath "$BUILD_ROOT/$arch" \
        BUILD_DIR="$BUILD_ROOT/$arch" \
        clean build
}

# ── Adhoc Signing helper ───────────────────────────────────────────────────────
adhoc_sign_binary() {
    local path="$1"
    echo "==> Signing (ad-hoc)..."
    /usr/bin/codesign --sign - --force --preserve-metadata=entitlements "$path"
}

# ── Main ───────────────────────────────────────────────────────────────────────
case "$ARCH" in
    universal)
        build_arch arm64
        build_arch x86_64
        mkdir -p "$DIST_ROOT/universal"
        echo "==> Creating universal binary..."
        lipo -create \
            "$BUILD_ROOT/arm64/$CONFIG/$BINARY" \
            "$BUILD_ROOT/x86_64/$CONFIG/$BINARY" \
            -output "$DIST_ROOT/universal/$BINARY"
        adhoc_sign_binary "$DIST_ROOT/universal/$BINARY"
        echo "==> Verifying..."
        lipo -info "$DIST_ROOT/universal/$BINARY"
        echo "==> Done: $DIST_ROOT/universal/$BINARY"
        ;;
    arm64|x86_64)
        build_arch "$ARCH"
        mkdir -p "$DIST_ROOT/$ARCH"
        cp "$BUILD_ROOT/$ARCH/$CONFIG/$BINARY" "$DIST_ROOT/$ARCH/$BINARY"
        adhoc_sign_binary "$DIST_ROOT/$ARCH/$BINARY"
        echo "==> Verifying..."
        lipo -info "$DIST_ROOT/$ARCH/$BINARY"
        echo "==> Done: $DIST_ROOT/$ARCH/$BINARY"
        ;;
    *)
        echo "error: unknown architecture '$ARCH'" >&2
        echo "usage: $0 [universal|arm64|x86_64]" >&2
        exit 1
        ;;
esac

echo "==> Cleaning up..."
/bin/rm -rf "$BUILD_ROOT"

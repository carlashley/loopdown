#!/bin/zsh

# Build for Apple Silicon
xcodebuild \
    -project loopdown.xcodeproj \
    -scheme loopdown \
    -configuration Release \
    -arch arm64 \
    -derivedDataPath /tmp/loopdown-build/arm64 \
    BUILD_DIR=/tmp/loopdown-build/arm64 \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build

# Build for Intel
xcodebuild \
    -project loopdown.xcodeproj \
    -scheme loopdown \
    -configuration Release \
    -arch x86_64 \
    -derivedDataPath /tmp/loopdown-build/x86_64 \
    BUILD_DIR=/tmp/loopdown-build/x86_64 \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build

# Create output directory and combine
mkdir -p ../dist/swift
lipo -create \
    /tmp/loopdown-build/arm64/Release/loopdown \
    /tmp/loopdown-build/x86_64/Release/loopdown \
    -output ../dist/swift/loopdown

# Verify
lipo -info ../dist/swift/loopdown

# remove tmp
/bin/rm -rf /tmp/loopdown-build 2>/dev/null

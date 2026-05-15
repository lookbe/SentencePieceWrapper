#!/bin/bash
set -e

# --- Configuration ---
WRAPPER_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$WRAPPER_DIR/build_xcframework"
OUTPUT_XCFRAMEWORK="$WRAPPER_DIR/SentencePieceWrapper.xcframework"

echo "=== Building SentencePieceWrapper XCFramework ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 1. macOS (Universal: x86_64 and arm64)
echo "--- Building macOS Universal ---"
mkdir -p "$BUILD_DIR/mac"
cd "$BUILD_DIR/mac"
cmake ../.. -DCMAKE_SYSTEM_NAME=Darwin \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
            -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# 2. iOS (arm64)
echo "--- Building iOS ---"
mkdir -p "$BUILD_DIR/ios"
cd "$BUILD_DIR/ios"
cmake ../.. -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphoneos \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# 3. iOS Simulator (Universal: x86_64 and arm64)
echo "--- Building iOS Simulator Universal ---"
mkdir -p "$BUILD_DIR/ios_sim"
cd "$BUILD_DIR/ios_sim"
cmake ../.. -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphonesimulator \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
            -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# Create XCFramework
echo "--- Creating XCFramework ---"
cd "$WRAPPER_DIR"
rm -rf "$OUTPUT_XCFRAMEWORK"

xcodebuild -create-xcframework \
    -library "$BUILD_DIR/mac/libSentencePieceWrapper.dylib" \
    -library "$BUILD_DIR/ios/libSentencePieceWrapper.dylib" \
    -library "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib" \
    -output "$OUTPUT_XCFRAMEWORK"

echo "=== Done ==="
echo "Created $OUTPUT_XCFRAMEWORK"

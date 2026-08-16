#!/bin/bash
set -e

# --- Configuration ---
WRAPPER_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$WRAPPER_DIR/build_xcframework"
OUTPUT_XCFRAMEWORK="$WRAPPER_DIR/SentencePieceWrapper.xcframework"

echo "=== Building SentencePieceWrapper XCFramework ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# -g keeps DWARF debug info alongside -O3/-DNDEBUG so dsymutil below has
# something real to extract, instead of producing an empty dSYM that only
# satisfies the UUID check without any actual symbolication value.
RELEASE_WITH_DEBUG="-O3 -DNDEBUG -g"

# 1. macOS (Universal: x86_64 and arm64)
echo "--- Building macOS Universal ---"
mkdir -p "$BUILD_DIR/mac"
cd "$BUILD_DIR/mac"
cmake ../.. -DCMAKE_SYSTEM_NAME=Darwin \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_FLAGS_RELEASE="$RELEASE_WITH_DEBUG" \
            -DCMAKE_C_FLAGS_RELEASE="$RELEASE_WITH_DEBUG"
cmake --build . --config Release

# 2. iOS (arm64)
echo "--- Building iOS ---"
mkdir -p "$BUILD_DIR/ios"
cd "$BUILD_DIR/ios"
cmake ../.. -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphoneos \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_FLAGS_RELEASE="$RELEASE_WITH_DEBUG" \
            -DCMAKE_C_FLAGS_RELEASE="$RELEASE_WITH_DEBUG"
cmake --build . --config Release

# 3. iOS Simulator (Universal: x86_64 and arm64)
echo "--- Building iOS Simulator Universal ---"
mkdir -p "$BUILD_DIR/ios_sim"
cd "$BUILD_DIR/ios_sim"
cmake ../.. -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphonesimulator \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_FLAGS_RELEASE="$RELEASE_WITH_DEBUG" \
            -DCMAKE_C_FLAGS_RELEASE="$RELEASE_WITH_DEBUG"
cmake --build . --config Release

# Ensure dylibs have correct @rpath install names
echo "--- Setting RPath IDs ---"
chmod +w "$BUILD_DIR/mac/libSentencePieceWrapper.dylib"
install_name_tool -id "@rpath/libSentencePieceWrapper.dylib" "$BUILD_DIR/mac/libSentencePieceWrapper.dylib"

chmod +w "$BUILD_DIR/ios/libSentencePieceWrapper.dylib"
install_name_tool -id "@rpath/libSentencePieceWrapper.dylib" "$BUILD_DIR/ios/libSentencePieceWrapper.dylib"

chmod +w "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib"
install_name_tool -id "@rpath/libSentencePieceWrapper.dylib" "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib"

# Generate a dSYM per slice so App Store Connect can symbolicate crashes
# touching libSentencePieceWrapper.dylib (previously "Upload Symbols Failed").
echo "--- Generating dSYMs ---"
dsymutil "$BUILD_DIR/mac/libSentencePieceWrapper.dylib" -o "$BUILD_DIR/mac/libSentencePieceWrapper.dylib.dSYM"
dsymutil "$BUILD_DIR/ios/libSentencePieceWrapper.dylib" -o "$BUILD_DIR/ios/libSentencePieceWrapper.dylib.dSYM"
dsymutil "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib" -o "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib.dSYM"

# Create XCFramework
echo "--- Creating XCFramework ---"
cd "$WRAPPER_DIR"
rm -rf "$OUTPUT_XCFRAMEWORK"

xcodebuild -create-xcframework \
    -library "$BUILD_DIR/mac/libSentencePieceWrapper.dylib" -debug-symbols "$BUILD_DIR/mac/libSentencePieceWrapper.dylib.dSYM" \
    -library "$BUILD_DIR/ios/libSentencePieceWrapper.dylib" -debug-symbols "$BUILD_DIR/ios/libSentencePieceWrapper.dylib.dSYM" \
    -library "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib" -debug-symbols "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib.dSYM" \
    -output "$OUTPUT_XCFRAMEWORK"

echo "=== Done ==="
echo "Created $OUTPUT_XCFRAMEWORK"

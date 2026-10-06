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
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
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
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
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
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_FLAGS_RELEASE="$RELEASE_WITH_DEBUG" \
            -DCMAKE_C_FLAGS_RELEASE="$RELEASE_WITH_DEBUG"
cmake --build . --config Release

create_framework() {
    local PLATFORM_DIR="$1"
    local FW_NAME="SentencePieceWrapper"
    local FW_DIR="$PLATFORM_DIR/$FW_NAME.framework"
    local DYLIB="$PLATFORM_DIR/libSentencePieceWrapper.dylib"

    rm -rf "$FW_DIR"

    if [[ "$PLATFORM_DIR" == *"mac"* ]]; then
        # macOS Deep/Versioned Framework Bundle
        local VER_A="$FW_DIR/Versions/A"
        mkdir -p "$VER_A/Resources"
        cp "$DYLIB" "$VER_A/$FW_NAME"
        chmod +w "$VER_A/$FW_NAME"
        install_name_tool -id "@rpath/$FW_NAME.framework/Versions/A/$FW_NAME" "$VER_A/$FW_NAME"
        codesign --remove-signature "$VER_A/$FW_NAME" || true

        cat > "$VER_A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$FW_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>ai.lookbe.$FW_NAME</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$FW_NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
EOF
        # Create standard macOS framework symlinks
        cd "$FW_DIR/Versions" && ln -sf A Current
        cd "$FW_DIR"
        ln -sf Versions/Current/$FW_NAME $FW_NAME
        ln -sf Versions/Current/Resources Resources
        cd - > /dev/null
    else
        # iOS Shallow Framework Bundle
        mkdir -p "$FW_DIR"
        cp "$DYLIB" "$FW_DIR/$FW_NAME"
        chmod +w "$FW_DIR/$FW_NAME"
        install_name_tool -id "@rpath/$FW_NAME.framework/$FW_NAME" "$FW_DIR/$FW_NAME"
        codesign --remove-signature "$FW_DIR/$FW_NAME" || true

        cat > "$FW_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$FW_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>ai.lookbe.$FW_NAME</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$FW_NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>17.0</string>
</dict>
</plist>
EOF
    fi
}


echo "--- Generating dSYMs ---"
dsymutil "$BUILD_DIR/mac/libSentencePieceWrapper.dylib" -o "$BUILD_DIR/mac/SentencePieceWrapper.framework.dSYM"
dsymutil "$BUILD_DIR/ios/libSentencePieceWrapper.dylib" -o "$BUILD_DIR/ios/SentencePieceWrapper.framework.dSYM"
dsymutil "$BUILD_DIR/ios_sim/libSentencePieceWrapper.dylib" -o "$BUILD_DIR/ios_sim/SentencePieceWrapper.framework.dSYM"

create_framework "$BUILD_DIR/mac"
create_framework "$BUILD_DIR/ios"
create_framework "$BUILD_DIR/ios_sim"

echo "--- Creating XCFramework ---"
cd "$WRAPPER_DIR"
rm -rf "$OUTPUT_XCFRAMEWORK"

xcodebuild -create-xcframework \
    -framework "$BUILD_DIR/mac/SentencePieceWrapper.framework" -debug-symbols "$BUILD_DIR/mac/SentencePieceWrapper.framework.dSYM" \
    -framework "$BUILD_DIR/ios/SentencePieceWrapper.framework" -debug-symbols "$BUILD_DIR/ios/SentencePieceWrapper.framework.dSYM" \
    -framework "$BUILD_DIR/ios_sim/SentencePieceWrapper.framework" -debug-symbols "$BUILD_DIR/ios_sim/SentencePieceWrapper.framework.dSYM" \
    -output "$OUTPUT_XCFRAMEWORK"

echo "=== Done ==="
echo "Created $OUTPUT_XCFRAMEWORK"

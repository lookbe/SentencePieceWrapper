#!/bin/bash
set -e

# --- Configuration ---
WRAPPER_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$WRAPPER_DIR/build_mac"

echo "=== Building SentencePieceWrapper ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure and build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

echo "=== Build Complete ==="
echo "The library is available at:"
echo "$BUILD_DIR/libSentencePieceWrapper.dylib"


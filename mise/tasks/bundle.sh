#!/usr/bin/env bash
set -euo pipefail

# Build the Cassiopeia dynamic library
echo "Building Cassiopeia dynamic library..."

# Clean and build for release
swift build -c release --product Cassiopeia

# Create build directory
mkdir -p build

# Find the built dylib and copy it to build/
DYLIB_PATH=$(swift build -c release --product Cassiopeia --show-bin-path)/libCassiopeia.dylib

if [ -f "$DYLIB_PATH" ]; then
    cp "$DYLIB_PATH" build/libCassiopeia.dylib
    echo "✓ Dynamic library created at build/libCassiopeia.dylib"
else
    echo "✗ Failed to find built dylib at $DYLIB_PATH"
    exit 1
fi
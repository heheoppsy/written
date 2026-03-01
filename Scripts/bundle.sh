#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
BUNDLE_DIR="$PROJECT_DIR/.build/Written.app"

# Check toolchain
if ! command -v swift &>/dev/null; then
    echo "Error: swift not found. Install Xcode or Swift toolchain."
    exit 1
fi
if ! xcrun --find swiftc &>/dev/null 2>&1; then
    echo "Error: Xcode command-line tools not configured. Run: xcode-select --install"
    exit 1
fi

echo "Building Written..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy executables
cp "$BUILD_DIR/Written" "$BUNDLE_DIR/Contents/MacOS/Written"
cp "$BUILD_DIR/WrittenCLI" "$BUNDLE_DIR/Contents/MacOS/WrittenCLI"

# Copy Info.plist and icon
cp "$PROJECT_DIR/Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Copy logos for welcome screen
cp "$PROJECT_DIR/written-ico.png" "$BUNDLE_DIR/Contents/Resources/written-ico.png"
cp "$PROJECT_DIR/written-ico-light.png" "$BUNDLE_DIR/Contents/Resources/written-ico-light.png"

# Copy bundled fonts
mkdir -p "$BUNDLE_DIR/Contents/Resources/Fonts"
cp "$PROJECT_DIR/Resources/Fonts/"*.ttf "$BUNDLE_DIR/Contents/Resources/Fonts/"

echo "Written.app created at: $BUNDLE_DIR"
echo ""
echo "To install the CLI tool:"
echo "  cp $BUILD_DIR/WrittenCLI /usr/local/bin/written"
echo ""
echo "To run the app:"
echo "  open $BUNDLE_DIR"

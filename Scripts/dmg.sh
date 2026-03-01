#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(defaults read "$PROJECT_DIR/Resources/Info.plist" CFBundleShortVersionString)
BUNDLE_DIR="$PROJECT_DIR/.build/Written.app"
DMG_NAME="Written-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/.build/$DMG_NAME"
RW_DMG="$PROJECT_DIR/.build/Written-rw.dmg"
VOLUME_NAME="Written"

# Check toolchain
if ! command -v swift &>/dev/null; then
    echo "Error: swift not found. Install Xcode or Swift toolchain."
    exit 1
fi
if ! xcrun --find swiftc &>/dev/null 2>&1; then
    echo "Error: Xcode command-line tools not configured. Run: xcode-select --install"
    exit 1
fi
for tool in codesign hdiutil strip; do
    if ! command -v "$tool" &>/dev/null; then
        echo "Error: $tool not found. Install Xcode command-line tools."
        exit 1
    fi
done

# Build the .app bundle first
echo "==> Building app bundle..."
"$SCRIPT_DIR/bundle.sh"

# Strip debug symbols from binaries
echo "==> Stripping binaries..."
strip "$BUNDLE_DIR/Contents/MacOS/Written"
strip "$BUNDLE_DIR/Contents/MacOS/WrittenCLI"

# Clean extended attributes (resource forks break codesign)
xattr -cr "$BUNDLE_DIR"

# Ad-hoc codesign (prevents "damaged app" on Apple Silicon)
echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "$BUNDLE_DIR"

# Verify no personal paths leaked
if strings "$BUNDLE_DIR/Contents/MacOS/Written" | grep -qi "/Users/"; then
    echo "WARNING: Binary contains /Users/ paths. Aborting."
    exit 1
fi

echo "==> Creating DMG..."
rm -f "$RW_DMG" "$DMG_PATH"

# Calculate size needed (app size + 20MB headroom)
APP_SIZE=$(du -sm "$BUNDLE_DIR" | cut -f1)
DMG_SIZE=$(( APP_SIZE + 20 ))

# Create read-write DMG with APFS
hdiutil create \
    -size "${DMG_SIZE}m" \
    -fs APFS \
    -volname "$VOLUME_NAME" \
    -type SPARSE \
    -ov \
    "$RW_DMG"

# Mount the writable image
MOUNT_DIR=$(hdiutil attach "${RW_DMG}.sparseimage" -readwrite -noverify -noautoopen | grep "/Volumes/" | tail -1 | cut -f3-)
echo "    Mounted at: $MOUNT_DIR"

# Copy app
cp -R "$BUNDLE_DIR" "$MOUNT_DIR/"

# Create a Finder alias to /Applications (renders better than a unix symlink)
osascript -e "
    tell application \"Finder\"
        make new alias file at POSIX file \"$MOUNT_DIR\" to POSIX file \"/Applications\"
    end tell
" >/dev/null 2>&1

# Set volume icon
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"

# Set custom icon flag on the volume root (kHasCustomIcon = bit 10 = 0x0400)
# Byte 8-9 of FinderInfo are finderFlags (big-endian u16). We set bit 0x0400.
python3 -c "
import ctypes, ctypes.util, struct, os
lib = ctypes.CDLL(ctypes.util.find_library('System'))
buf = (ctypes.c_uint8 * 32)()
lib.getxattr('$MOUNT_DIR'.encode(), b'com.apple.FinderInfo', buf, 32, 0, 0)
flags = struct.unpack('>H', bytes(buf[8:10]))[0]
flags |= 0x0400
struct.pack_into('>H', buf, 8, flags)
lib.setxattr('$MOUNT_DIR'.encode(), b'com.apple.FinderInfo', buf, 32, 0, 0)
"

# Set window layout so Finder shows a nice drag-to-install view
osascript -e "
    tell application \"Finder\"
        tell disk \"$VOLUME_NAME\"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 200, 640, 420}
            set arrangement of icon view options of container window to not arranged
            set icon size of icon view options of container window to 80
            set position of item \"Written.app\" of container window to {110, 110}
            set position of item \"Applications\" of container window to {330, 110}
            close
        end tell
    end tell
" 2>/dev/null || echo "    (window layout skipped)"

# Unmount
sync
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "${RW_DMG}.sparseimage" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

# Clean up intermediate
rm -f "${RW_DMG}.sparseimage"

echo ""
echo "==> Done: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE="$PROJECT_DIR/Icon-macOS-512x512@2x.png"
ICONSET="$PROJECT_DIR/Resources/AppIcon.iconset"
ICNS="$PROJECT_DIR/Resources/AppIcon.icns"

if [ ! -f "$SOURCE" ]; then
    echo "Error: $SOURCE not found"
    exit 1
fi

echo "==> Generating iconset from $(basename "$SOURCE")..."

/opt/homebrew/bin/python3.14 -c "
from PIL import Image

src = Image.open('$SOURCE').convert('RGBA')
canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
x = (1024 - src.width) // 2
y = (1024 - src.height) // 2
canvas.paste(src, (x, y), src)
canvas = canvas.crop((0, 0, 1024, 1024))

sizes = [
    ('icon_16x16.png', 16),
    ('icon_16x16@2x.png', 32),
    ('icon_32x32.png', 32),
    ('icon_32x32@2x.png', 64),
    ('icon_128x128.png', 128),
    ('icon_128x128@2x.png', 256),
    ('icon_256x256.png', 256),
    ('icon_256x256@2x.png', 512),
    ('icon_512x512.png', 512),
    ('icon_512x512@2x.png', 1024),
]

for name, px in sizes:
    resized = canvas.resize((px, px), Image.LANCZOS)
    resized.save(f'$ICONSET/{name}')
    print(f'    {name}: {px}x{px}')
"

echo "==> Building .icns..."
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Done: $ICNS"

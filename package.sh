#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MarkdownEditor"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
STAGING_DIR=$(mktemp -d)

echo "==> Creating DMG for $APP_NAME ..."

# Ensure .app exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run build.sh first."
    exit 1
fi

# Copy .app to staging
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"

# Create Applications symlink for drag-and-drop install
ln -s /Applications "$STAGING_DIR/Applications"

# Build DMG
echo "==> Creating temporary disk image ..."
hdiutil create -srcfolder "$STAGING_DIR" \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_PATH" 2>/dev/null

# Clean up
rm -rf "$STAGING_DIR"

echo ""
echo "==== Package complete ===="
echo "DMG: $DMG_PATH"
echo "Size: $(du -sh "$DMG_PATH" | cut -f1)"

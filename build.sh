#!/bin/bash
set -euo pipefail

PROJECT="MarkdownEditor"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SRC_DIR/build"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$PROJECT.app/Contents/MacOS"

echo "==> Compiling..."
swiftc -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -g \
  -o "$BUILD_DIR/$PROJECT" \
  "$SRC_DIR/Sources/$PROJECT/TraceLog.swift" \
  "$SRC_DIR/Sources/$PROJECT/AST.swift" \
  "$SRC_DIR/Sources/$PROJECT/Parser.swift" \
  "$SRC_DIR/Sources/$PROJECT/HTMLRenderer.swift" \
  "$SRC_DIR/Sources/$PROJECT/DocumentController.swift" \
  "$SRC_DIR/Sources/$PROJECT/Views/SplitView.swift" \
  "$SRC_DIR/Sources/$PROJECT/Views/Editor/EditorView.swift" \
  "$SRC_DIR/Sources/$PROJECT/Views/Preview/WebPreviewView.swift" \
  "$SRC_DIR/Sources/$PROJECT/App.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -framework WebKit

echo "==> Creating .app bundle..."
mkdir -p "$BUILD_DIR/$PROJECT.app/Contents/Resources"
cp "$BUILD_DIR/$PROJECT" "$BUILD_DIR/$PROJECT.app/Contents/MacOS/$PROJECT"
cp "$SRC_DIR/$PROJECT.icns" "$BUILD_DIR/$PROJECT.app/Contents/Resources/$PROJECT.icns"

cat > "$BUILD_DIR/$PROJECT.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PROJECT</string>
  <key>CFBundleIdentifier</key>
  <string>com.example.$PROJECT</string>
  <key>CFBundleName</key>
  <string>$PROJECT</string>
  <key>CFBundleIconFile</key>
  <string>$PROJECT</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo ""
echo "✅ Done! App at: $BUILD_DIR/$PROJECT.app"

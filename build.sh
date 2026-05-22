#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MarkdownEditor"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
SWIFTC_FLAGS=(
  -target "arm64-apple-macosx14.0"
  -sdk "$(xcrun --show-sdk-path)"
  -parse-as-library
)

echo "==> Building $APP_NAME.app ..."

# 1. Download mermaid.min.js if missing
MERMAID="$PROJECT_DIR/Resources/mermaid.min.js"
if [ ! -f "$MERMAID" ]; then
  echo "==> Downloading mermaid.min.js ..."
  curl -sL "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js" -o "$MERMAID"
  echo "    Downloaded: $(wc -c < "$MERMAID") bytes"
else
  echo "==> mermaid.min.js already present, skipping download"
fi

# 2. Create .app bundle structure
echo "==> Creating app bundle structure ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Write Info.plist
echo "==> Writing Info.plist ..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<- PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Markdown File</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Default</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
		</dict>
	</array>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.$APP_NAME</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHumanReadableCopyright</key>
	<string></string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# 4. Compile Swift sources
echo "==> Compiling Swift sources ..."
SOURCES=(
  "$PROJECT_DIR/Sources/MarkdownEditorApp.swift"
  "$PROJECT_DIR/Sources/Models/AppState.swift"
  "$PROJECT_DIR/Sources/Models/FileTreeItem.swift"
  "$PROJECT_DIR/Sources/Services/FileService.swift"
  "$PROJECT_DIR/Sources/Services/FolderWatcher.swift"
  "$PROJECT_DIR/Sources/Services/ImageHandler.swift"
  "$PROJECT_DIR/Sources/Services/MarkdownParser.swift"
  "$PROJECT_DIR/Sources/Views/ContentView.swift"
  "$PROJECT_DIR/Sources/Views/Editor/EditorContainerView.swift"
  "$PROJECT_DIR/Sources/Views/Editor/LineNumberRulerView.swift"
  "$PROJECT_DIR/Sources/Views/Editor/MarkdownTextStorage.swift"
  "$PROJECT_DIR/Sources/Views/Editor/MarkdownTextView.swift"
  "$PROJECT_DIR/Sources/Views/Preview/PreviewWebView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/FileRowView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/FolderHeaderView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/SidebarView.swift"
)

swiftc "${SWIFTC_FLAGS[@]}" \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  "${SOURCES[@]}"

# 5. Copy resources
echo "==> Copying resources ..."
cp "$PROJECT_DIR/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$MERMAID" "$APP_BUNDLE/Contents/Resources/mermaid.min.js"

# 6. Ad-hoc code sign
echo "==> Code signing ..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "==== Build complete ===="
echo "App: $APP_BUNDLE"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
open -R "$APP_BUNDLE"

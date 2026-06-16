#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MarkdownEditor"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
APP_TARGET_VERSION="14.0"

# cmark-gfm library (Homebrew). Gracefully degrade if not present. When the
# installed dylib targets a newer macOS than our default, build the app for that
# newer target so Markdown preview keeps the full cmark-gfm renderer without
# linker warnings.
CMARK_PREFIX="$(brew --prefix cmark-gfm 2>/dev/null || echo "")"
CMARK_INCLUDE=""
CMARK_LIB=""
CMARK_LINK=""
if [ -n "$CMARK_PREFIX" ] && [ -f "$CMARK_PREFIX/include/cmark-gfm.h" ]; then
  CMARK_CANDIDATE_DYLIB="$(ls "$CMARK_PREFIX"/lib/libcmark-gfm.*.dylib 2>/dev/null | head -1 || true)"
  CMARK_MINOS=""
  if [ -n "$CMARK_CANDIDATE_DYLIB" ]; then
    CMARK_MINOS="$(otool -l "$CMARK_CANDIDATE_DYLIB" 2>/dev/null | awk '/LC_BUILD_VERSION/{in_build=1} in_build && /minos/{print $2; exit}' || true)"
  fi
  APP_TARGET_MAJOR="${APP_TARGET_VERSION%%.*}"
  CMARK_MINOS_MAJOR="${CMARK_MINOS%%.*}"
  if [ -n "$CMARK_MINOS_MAJOR" ] && [ "$CMARK_MINOS_MAJOR" -gt "$APP_TARGET_MAJOR" ] 2>/dev/null; then
    APP_TARGET_VERSION="$CMARK_MINOS"
    echo "==> cmark-gfm targets macOS $CMARK_MINOS; building app for macOS $APP_TARGET_VERSION"
  else
    echo "==> Using cmark-gfm from $CMARK_PREFIX"
  fi
  CMARK_INCLUDE="$CMARK_PREFIX/include"
  CMARK_LIB="$CMARK_PREFIX/lib"
  CMARK_LINK="-lcmark-gfm -lcmark-gfm-extensions"
else
  echo "==> cmark-gfm not found; falling back to built-in parser"
fi
APP_TARGET="arm64-apple-macosx$APP_TARGET_VERSION"

SWIFTC_FLAGS=(
  -target "$APP_TARGET"
  -sdk "$(xcrun --show-sdk-path)"
  -parse-as-library
  -O
)
[ -n "$CMARK_INCLUDE" ] && SWIFTC_FLAGS+=(-I "$CMARK_INCLUDE" -Xcc -I"$CMARK_INCLUDE")
[ -n "$CMARK_LIB" ] && SWIFTC_FLAGS+=(-L "$CMARK_LIB" -Xlinker -rpath -Xlinker "@executable_path/../Frameworks")
[ -n "$CMARK_LINK" ] && SWIFTC_FLAGS+=($CMARK_LINK)

# Module map for cmark-gfm C interop (only needed when cmark is available)
if [ -n "$CMARK_INCLUDE" ]; then
  MODULE_DIR="$PROJECT_DIR/Sources/CCmarkGfm"
  SWIFTC_FLAGS+=(-I "$MODULE_DIR")
fi

echo "==> Building $APP_NAME.app ..."

# 1. Download mermaid.min.js if missing
MERMAID="$PROJECT_DIR/Resources/mermaid.min.js"
if [ ! -f "$MERMAID" ]; then
  echo "==> Downloading mermaid.min.js ..."
  curl -sL "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js" -o "$MERMAID"
  echo "    Downloaded: $(wc -c < "$MERMAID") bytes"
else
  echo "==> mermaid.min.js already present, skipping download"
fi

# 1b. Download highlight.min.js if missing
HLJS="$PROJECT_DIR/Resources/highlight.min.js"
if [ ! -f "$HLJS" ]; then
  echo "==> Downloading highlight.min.js ..."
  curl -sL "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js" -o "$HLJS" || true
  [ -f "$HLJS" ] && echo "    Downloaded: $(wc -c < "$HLJS") bytes" || echo "    (download failed — preview will skip syntax highlighting)"
else
  echo "==> highlight.min.js already present, skipping download"
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
			<key>CFBundleTypeExtensions</key>
			<array>
				<string>md</string>
				<string>markdown</string>
				<string>mkd</string>
			</array>
			<key>LSItemContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
				<string>public.plain-text</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleTypeName</key>
			<string>HTML File</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>CFBundleTypeExtensions</key>
			<array>
				<string>html</string>
				<string>htm</string>
			</array>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.html</string>
			</array>
		</dict>
	</array>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon.icns</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.$APP_NAME</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.0.5</string>
	<key>CFBundleVersion</key>
	<string>0.0.5</string>
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
  "$PROJECT_DIR/Sources/Models/HeadingItem.swift"
  "$PROJECT_DIR/Sources/Models/LRUCache.swift"
  "$PROJECT_DIR/Sources/Models/SearchState.swift"
  "$PROJECT_DIR/Sources/Models/ViewRefs.swift"
  "$PROJECT_DIR/Sources/Services/FileService.swift"
  "$PROJECT_DIR/Sources/Services/FolderWatcher.swift"
  "$PROJECT_DIR/Sources/Services/HeadingParser.swift"
  "$PROJECT_DIR/Sources/Services/ImageHandler.swift"
  "$PROJECT_DIR/Sources/Services/MarkdownParser.swift"
  "$PROJECT_DIR/Sources/Services/SearchJS.swift"
  "$PROJECT_DIR/Sources/Services/SessionRestoreService.swift"
  "$PROJECT_DIR/Sources/Services/ThemeManager.swift"
  "$PROJECT_DIR/Sources/Views/ContentView.swift"
  "$PROJECT_DIR/Sources/Views/OutlinePanelView.swift"
  "$PROJECT_DIR/Sources/Views/ResizableHSplitView.swift"
  "$PROJECT_DIR/Sources/Views/InlineSearchView.swift"
  "$PROJECT_DIR/Sources/Views/Editor/EditorContainerView.swift"
  "$PROJECT_DIR/Sources/Views/Editor/LineNumberSideView.swift"
  "$PROJECT_DIR/Sources/Views/Editor/MarkdownTextStorage.swift"
  "$PROJECT_DIR/Sources/Views/Editor/MarkdownTextView.swift"
  "$PROJECT_DIR/Sources/Views/Preview/PreviewWebView.swift"
  "$PROJECT_DIR/Sources/Views/Preview/PreviewSearchOverlay.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/DirectoryRowView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/FileRowView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/FolderHeaderView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/SidebarView.swift"
  "$PROJECT_DIR/Sources/Views/Sidebar/RenamePopover.swift"
)

swiftc "${SWIFTC_FLAGS[@]}" \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  "${SOURCES[@]}"

# 5. Copy resources
echo "==> Copying resources ..."
cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/MarkdownEditor.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/Credits.html" "$APP_BUNDLE/Contents/Resources/Credits.html"
cp "$MERMAID" "$APP_BUNDLE/Contents/Resources/mermaid.min.js"
[ -f "$HLJS" ] && cp "$HLJS" "$APP_BUNDLE/Contents/Resources/highlight.min.js" || true

# Copy cmark-gfm dylibs into bundle for portable distribution
if [ -n "$CMARK_LIB" ]; then
  CMAJOR_DYLIB=$(ls "$CMARK_LIB"/libcmark-gfm.*.dylib 2>/dev/null | head -1)
  CME_DYLIB=$(ls "$CMARK_LIB"/libcmark-gfm-extensions.*.dylib 2>/dev/null | head -1)
  CMAJOR_NAME=$(basename "$CMAJOR_DYLIB" 2>/dev/null || echo "")
  CME_NAME=$(basename "$CME_DYLIB" 2>/dev/null || echo "")
  if [ -n "$CMAJOR_NAME" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp "$CMAJOR_DYLIB" "$APP_BUNDLE/Contents/Frameworks/"
    cp "$CME_DYLIB" "$APP_BUNDLE/Contents/Frameworks/"
    install_name_tool -change "@rpath/$CMAJOR_NAME" "@executable_path/../Frameworks/$CMAJOR_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    install_name_tool -change "@rpath/$CME_NAME" "@executable_path/../Frameworks/$CME_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
  fi
fi

# 6. Strip debug symbols (safe for release, keeps code signatures intact)
echo "==> Stripping binary ..."
strip -S "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# 7. Ad-hoc code sign
echo "==> Code signing ..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "==== Build complete ===="
echo "App: $APP_BUNDLE"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
open -R "$APP_BUNDLE"

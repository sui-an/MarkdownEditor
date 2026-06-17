#!/bin/bash
set -e
cd "$(dirname "$0")"
npm run build
npx electron-builder --win
echo "Done: dist/MarkdownEditor-${npm_package_version:-0.0.5}.exe"

#!/bin/bash
# Download mermaid.min.js for Mermaid diagram rendering in the preview
# Run this script to enable Mermaid support

cd "$(dirname "$0")"

MERMAID_URL="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
OUTPUT="Resources/mermaid.min.js"

if [ -f "$OUTPUT" ] && [ "$1" != "--force" ]; then
    echo "mermaid.min.js already exists. Use --force to re-download."
    echo "Size: $(wc -c < "$OUTPUT") bytes"
    exit 0
fi

echo "Downloading mermaid.min.js..."
if command -v curl &> /dev/null; then
    curl -sL "$MERMAID_URL" -o "$OUTPUT"
elif command -v wget &> /dev/null; then
    wget -q "$MERMAID_URL" -O "$OUTPUT"
else
    echo "Error: curl or wget is required."
    exit 1
fi

if [ -f "$OUTPUT" ]; then
    echo "Downloaded successfully: $(wc -c < "$OUTPUT") bytes"
else
    echo "Download failed."
    exit 1
fi

#!/bin/bash
# Generate test markdown files of various sizes for benchmarking.
# Each iteration is ~200 bytes, so:
#   50  iterations ≈   10KB
#  1000 iterations ≈  200KB
#  5000 iterations ≈    1MB
# 50000 iterations ≈   10MB

OUTPUT_DIR="/tmp/markdown-test-files"
mkdir -p "$OUTPUT_DIR"

echo "Generating test files in $OUTPUT_DIR ..."

# 10KB
cat > "$OUTPUT_DIR/small.md" <<- 'EOF'
# Small File
This is a small markdown file for quick testing.
EOF

gen_block() {
  local label="$1" count="$2"
  echo "Generating $label ($count iterations) ..."
  echo "# $label"
  echo ""
  for i in $(seq 1 "$count"); do
    echo "## Section $i"
    echo ""
    echo "Paragraph with **bold** and *italic*."
    echo ""
    echo "- Item A"
    echo "- Item B"
    echo "- Item C"
    echo ""
  done
}

gen_block "200KB File"   1000 > "$OUTPUT_DIR/medium_200KB.md"
gen_block "1MB File"     5000 > "$OUTPUT_DIR/large_1MB.md"
gen_block "10MB File"   50000 > "$OUTPUT_DIR/huge_10MB.md"

echo ""
echo "=== Generated files ==="
ls -lh "$OUTPUT_DIR"/*.md

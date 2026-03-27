#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <tag> <output-dir>" >&2
  exit 1
fi

TAG="$1"
OUTPUT_DIR="$2"
BUILD_DIR=".build/arm64-apple-macosx/release"
STAGE_DIR="${OUTPUT_DIR}/openbird-${TAG}-macos-arm64"
ARCHIVE_BASENAME="openbird-${TAG}-macos-arm64"

mkdir -p "$OUTPUT_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

cp "$BUILD_DIR/OpenbirdApp" "$STAGE_DIR/"
cp "$BUILD_DIR/OpenbirdCollector" "$STAGE_DIR/"
cp README.md "$STAGE_DIR/"

cat > "$STAGE_DIR/RELEASE.txt" <<EOF
Openbird ${TAG}

Included artifacts:
- OpenbirdApp
- OpenbirdCollector

These are unsigned macOS arm64 release binaries built via SwiftPM.
EOF

(
  cd "$OUTPUT_DIR"
  tar -czf "${ARCHIVE_BASENAME}.tar.gz" "${ARCHIVE_BASENAME}"
  shasum -a 256 "${ARCHIVE_BASENAME}.tar.gz" > "${ARCHIVE_BASENAME}.sha256"
)

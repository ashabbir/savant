#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

[[ -d "$DIST_DIR" ]] || { echo "dist not found" >&2; exit 2; }

pushd "$DIST_DIR" >/dev/null
rm -f checksums.txt
for f in *.tar.gz; do
  [[ -f "$f" ]] || continue
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1, FILENAME}' FILENAME="$f" >> checksums.txt
  else
    sha256sum "$f" | awk '{print $1, FILENAME}' FILENAME="$f" >> checksums.txt
  fi
done
popd >/dev/null

echo "[checksum] Wrote $DIST_DIR/checksums.txt"


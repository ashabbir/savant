#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

SALT="${SAVANT_BUILD_SALT:-DEVELOPMENT_ONLY_CHANGE_ME}"
echo "[build] Building Linux amd64 binary via Dockerfile.build (salt length=${#SALT})..."
docker build --build-arg SAVANT_BUILD_SALT="$SALT" -f "$ROOT_DIR/Dockerfile.build" -t savant-builder:latest "$ROOT_DIR" 1>/dev/null
CID=$(docker create savant-builder:latest)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
docker cp "$CID:/dist/savant-linux-amd64" "$DIST_DIR/"
chmod +x "$DIST_DIR/savant-linux-amd64"
echo "[build] Output: $DIST_DIR/savant-linux-amd64"

# Optionally build a local Darwin binary if rubyc is available
if command -v rubyc >/dev/null 2>&1; then
  echo "[build] rubyc found locally, attempting macOS build..."
  pushd "$ROOT_DIR" >/dev/null
  rubyc --output "$DIST_DIR/savant-darwin-$(uname -m)" ./bin/savant || echo "[build] macOS build skipped (rubyc error)"
  popd >/dev/null
fi

echo "[build] Done."

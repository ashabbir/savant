#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION_FILE="$ROOT_DIR/lib/savant/version.rb"

if [[ ! -d "$DIST_DIR" ]]; then
  echo "dist directory not found; run scripts/build/build.sh first" >&2
  exit 2
fi

VERSION=$(ruby -e "load '$VERSION_FILE'; print Savant::VERSION")
echo "[package] Version: $VERSION"

pushd "$DIST_DIR" >/dev/null
for bin in savant-*; do
  [[ -x "$bin" ]] || continue
  osarch="${bin#savant-}"
  tarball="savant-${VERSION}-${osarch}.tar.gz"
  echo "[package] Packaging $bin -> $tarball (contains 'savant')"
  # stage a renamed copy as 'savant' inside the tarball
  rm -f savant
  cp -f "$bin" savant
  tar -czf "$tarball" savant
  rm -f savant
done
popd >/dev/null

echo "[package] Done. Artifacts in $DIST_DIR"

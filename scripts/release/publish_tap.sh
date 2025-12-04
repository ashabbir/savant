#!/usr/bin/env bash
set -euo pipefail

# Publish formula to a Homebrew tap repository.
# Usage:
#   TAP_DIR=/path/to/local/tap \
#   scripts/release/publish_tap.sh packaging/homebrew/savant.rb

FORMULA_SRC=${1:-packaging/homebrew/savant.rb}
TAP_DIR=${TAP_DIR:-}

if [[ -z "$TAP_DIR" ]]; then
  echo "TAP_DIR env var must point to a local clone of your tap (e.g., ~/code/homebrew-tap)" >&2
  exit 2
fi

if [[ ! -f "$FORMULA_SRC" ]]; then
  echo "Formula not found: $FORMULA_SRC" >&2
  exit 2
fi

mkdir -p "$TAP_DIR/Formula"
cp -f "$FORMULA_SRC" "$TAP_DIR/Formula/savant.rb"
pushd "$TAP_DIR" >/dev/null
git add Formula/savant.rb
git commit -m "Update savant formula" || true
git push
popd >/dev/null

echo "[tap] Published formula to $TAP_DIR/Formula/savant.rb"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/memory_bank/assets/reasoning_api"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required (install Node.js)." >&2
  exit 127
fi

mkdir -p "$ASSETS_DIR"

render_one() {
  local in="$1";
  local base="${in%.mmd}";
  echo "Rendering $in -> ${base}.{svg,png}"
  npx --yes @mermaid-js/mermaid-cli -i "$in" -o "${base}.svg" --backgroundColor transparent >/dev/null 2>&1
  npx --yes @mermaid-js/mermaid-cli -i "$in" -o "${base}.png" --backgroundColor white --scale 1 >/dev/null 2>&1
}

for m in "$ASSETS_DIR"/*.mmd; do
  [ -e "$m" ] || continue
  render_one "$m"
done

echo "Done. Assets in $ASSETS_DIR"


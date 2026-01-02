#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VENV=".venv_reasoning"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV" >/dev/null 2>&1 || true
fi
. "$VENV/bin/activate" || true

# Best-effort install
python3 -m pip install -r reasoning/requirements.txt >/dev/null 2>&1 || true

exec python3 scripts/reasoning_queue_reset.py "$@"


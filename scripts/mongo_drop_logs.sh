#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VENV=".venv_reasoning"
if [ ! -d "$VENV" ]; then
  echo "Creating venv at $VENV" >&2
  python3 -m venv "$VENV"
fi

source "$VENV/bin/activate"
python3 -m pip install -r reasoning/requirements.txt >/dev/null 2>&1 || true

exec python3 scripts/mongo_drop_logs.py


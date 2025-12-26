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
python3 -m pip install -r reasoning/requirements.txt

export UVICORN_HOST="${UVICORN_HOST:-127.0.0.1}"
export UVICORN_PORT="${UVICORN_PORT:-9000}"

# Limit reload watching to Python sources and exclude large/churny dirs (like frontend/node_modules)
RELOAD_DIRS=("reasoning" "memory_bank")
RELOAD_EXCLUDES=(
  "frontend/*"
  "frontend/node_modules/*"
  "node_modules/*"
  ".git/*"
  ".savant/*"
  "logs/*"
  "coverage/*"
  "dist/*"
)

ARGS=("--host" "$UVICORN_HOST" "--port" "$UVICORN_PORT" "--reload")
for d in "${RELOAD_DIRS[@]}"; do
  ARGS+=("--reload-dir" "$d")
done
for p in "${RELOAD_EXCLUDES[@]}"; do
  ARGS+=("--reload-exclude" "$p")
done

exec uvicorn reasoning.api:app "${ARGS[@]}"

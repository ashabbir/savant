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

# Enable worker unless explicitly disabled; spawn 4 threads by default
export REASONING_QUEUE_WORKER=${REASONING_QUEUE_WORKER:-1}
export REASONING_QUEUE_WORKERS=${REASONING_QUEUE_WORKERS:-4}
export REASONING_QUEUE_POLL_MS=${REASONING_QUEUE_POLL_MS:-50}

exec python3 -m reasoning.worker

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
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONWARNINGS=${PYTHONWARNINGS:-"ignore:Importing verbose from langchain root module is no longer supported.:UserWarning"}
python3 -m pip install -r reasoning/requirements.txt >/dev/null 2>&1 || true

# Enable worker unless explicitly disabled; spawn 4 threads by default
export REASONING_QUEUE_WORKER=${REASONING_QUEUE_WORKER:-1}
export REASONING_QUEUE_WORKERS=${REASONING_QUEUE_WORKERS:-4}
export REASONING_QUEUE_POLL_MS=${REASONING_QUEUE_POLL_MS:-50}

exec python3 -m reasoning.worker

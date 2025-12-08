#!/usr/bin/env bash
set -euo pipefail

# Provide a localhost default for development if not set
if [[ -z "${DATABASE_URL:-}" ]]; then
  export DATABASE_URL="postgres://context:contextpw@localhost:5432/contextdb"
  echo "DATABASE_URL not set; defaulting to ${DATABASE_URL}" >&2
fi

HUB_BASE="${HUB_BASE:-http://localhost:9999}"

cleanup() {
  trap - INT TERM EXIT
  [[ -n "${RAILS_PID:-}" ]] && kill "${RAILS_PID}" >/dev/null 2>&1 || true
  [[ -n "${VITE_PID:-}" ]] && kill "${VITE_PID}" >/dev/null 2>&1 || true
}

trap cleanup INT TERM EXIT

echo "Starting Rails on 9999..."
(
  cd server
  exec bundle exec rails s -b 0.0.0.0 -p 9999
) &
RAILS_PID=$!

echo "Starting Vite on 5173... (HUB_BASE=${HUB_BASE})"
(
  cd frontend
  exec env VITE_HUB_BASE="${HUB_BASE}" npm run dev -- --host 0.0.0.0
) &
VITE_PID=$!

wait

#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
LAST_PORT_FILE="$RUNTIME_DIR/last-port"

PORT="${PORT:-12345}"
mkdir -p "$RUNTIME_DIR"
rm -f "$LAST_PORT_FILE"

"$SCRIPT_DIR/start-word-match.sh" &
SERVER_PID=$!

cleanup() {
  if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

SELECTED_PORT="$PORT"
for _ in {1..40}; do
  if [[ -f "$LAST_PORT_FILE" ]]; then
    SELECTED_PORT="$(cat "$LAST_PORT_FILE")"
    break
  fi
  sleep 0.25
done

open "http://127.0.0.1:$SELECTED_PORT"

wait "$SERVER_PID"

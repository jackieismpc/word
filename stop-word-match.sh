#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/server.pid"
LAST_PORT_FILE="$RUNTIME_DIR/last-port"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/word-match-unix-common.sh"

PIDS=()

if [[ -f "$PID_FILE" ]]; then
  PID="$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null || true)"
  if word_match_is_word_match_pid "${PID:-}"; then
    PIDS+=("$PID")
  else
    rm -f "$PID_FILE"
  fi
fi

while IFS= read -r FOUND_PID; do
  [[ -n "$FOUND_PID" ]] || continue
  if [[ ! " ${PIDS[*]:-} " =~ [[:space:]]${FOUND_PID}[[:space:]] ]]; then
    PIDS+=("$FOUND_PID")
  fi
done < <(word_match_find_existing_pids)

if (( ${#PIDS[@]} == 0 )); then
  rm -f "$PID_FILE" "$LAST_PORT_FILE"
  echo "没有找到正在运行的单词对对碰服务。"
  exit 0
fi

PORT_VALUE="$(cat "$LAST_PORT_FILE" 2>/dev/null || echo "未知端口")"
echo "正在停止单词对对碰服务..."
echo "PID: ${PIDS[*]}"
echo "端口: $PORT_VALUE"

for PID in "${PIDS[@]}"; do
  kill -TERM "$PID" >/dev/null 2>&1 || true
done

for _ in {1..20}; do
  ALIVE=0
  for PID in "${PIDS[@]}"; do
    if word_match_is_word_match_pid "$PID"; then
      ALIVE=1
      break
    fi
  done

  if (( ALIVE == 0 )); then
    rm -f "$PID_FILE" "$LAST_PORT_FILE"
    echo "服务已停止。"
    exit 0
  fi

  sleep 0.25
done

echo "服务未在预期时间内退出，尝试强制结束..."
for PID in "${PIDS[@]}"; do
  kill -KILL "$PID" >/dev/null 2>&1 || true
done

rm -f "$PID_FILE" "$LAST_PORT_FILE"
echo "服务已强制停止。"

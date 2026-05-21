#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/server.pid"
LAST_PORT_FILE="$RUNTIME_DIR/last-port"

is_word_match_pid() {
  local pid="$1"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    return 1
  fi

  local command cwd state
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  state="$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]' || true)"
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"

  [[ -n "$state" ]] && [[ "$state" != *Z* ]] && [[ -n "$command" ]] && echo "$command" | rg -q 'server\.mjs' && [[ "$cwd" == "$SCRIPT_DIR" ]]
}

port_in_use() {
  local port="$1"
  [[ -n "$port" ]] && [[ "$port" != "未知端口" ]] && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

find_existing_word_match_pid() {
  local pid
  for pid in ${(f)"$(pgrep -f 'server\.mjs' 2>/dev/null || true)"}; do
    if is_word_match_pid "$pid"; then
      echo "$pid"
    fi
  done
}

if [[ ! -f "$PID_FILE" ]]; then
  PIDS=(${(f)"$(find_existing_word_match_pid || true)"})
  if [[ ${#PIDS[@]} -eq 0 ]]; then
    echo "没有找到正在运行的单词对对碰服务。"
    exit 0
  fi
else
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
fi

if [[ -z "${PID:-}" ]]; then
  rm -f "$PID_FILE"
  PID=""
fi

PIDS=()
if is_word_match_pid "${PID:-}"; then
  PIDS+=("$PID")
fi

for found_pid in ${(f)"$(find_existing_word_match_pid || true)"}; do
  if [[ ! " ${PIDS[*]} " =~ " ${found_pid} " ]]; then
    PIDS+=("$found_pid")
  fi
done

if [[ ${#PIDS[@]} -eq 0 ]]; then
  rm -f "$PID_FILE"
  rm -f "$LAST_PORT_FILE"
  echo "服务进程不存在，已清理残留 PID 文件。"
  exit 0
fi

PORT="$(cat "$LAST_PORT_FILE" 2>/dev/null || echo "未知端口")"
echo "正在停止单词对对碰服务..."
echo "PID: ${PIDS[*]}"
echo "端口: $PORT"

for pid in "${PIDS[@]}"; do
  kill -TERM "$pid" >/dev/null 2>&1 || true
done

for _ in {1..20}; do
  alive=0
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      alive=1
      break
    fi
  done
  if [[ "$alive" -eq 0 ]]; then
    if port_in_use "$PORT"; then
      sleep 0.25
      continue
    fi
    rm -f "$PID_FILE"
    rm -f "$LAST_PORT_FILE"
    echo "服务已停止。"
    exit 0
  fi
  sleep 0.25
done

echo "服务未在预期时间内退出，尝试强制结束..."
for pid in "${PIDS[@]}"; do
  kill -KILL "$pid" >/dev/null 2>&1 || true
done
rm -f "$PID_FILE"
rm -f "$LAST_PORT_FILE"
echo "服务已强制停止。"

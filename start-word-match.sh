#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
LAST_PORT_FILE="$RUNTIME_DIR/last-port"
PID_FILE="$RUNTIME_DIR/server.pid"
SERVER_SCRIPT="$SCRIPT_DIR/server.mjs"
STDOUT_LOG="$RUNTIME_DIR/server.stdout.log"
STDERR_LOG="$RUNTIME_DIR/server.stderr.log"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/word-match-unix-common.sh"

mkdir -p "$RUNTIME_DIR"

NODE_BIN="$(word_match_ensure_node)"
REQUESTED_PORT="${PORT:-12345}"
BIND_HOST="${BIND_HOST:-${WORD_MATCH_HOST:-${HOST:-0.0.0.0}}}"

if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID="$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null || true)"
  if word_match_is_word_match_pid "${EXISTING_PID:-}"; then
    EXISTING_PORT="$(cat "$LAST_PORT_FILE" 2>/dev/null || echo "$REQUESTED_PORT")"
    LOCAL_URL="http://127.0.0.1:$EXISTING_PORT"
    echo "单词对对碰已经在运行。"
    echo "PID: $EXISTING_PID"
    echo "访问地址: $LOCAL_URL"
    TAILSCALE_IP="$(word_match_get_tailscale_ipv4 || true)"
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
      echo "Tailscale 地址: http://$TAILSCALE_IP:$EXISTING_PORT"
    fi
    word_match_open_browser "$LOCAL_URL"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

EXISTING_PIDS=()
while IFS= read -r FOUND_PID; do
  [[ -n "$FOUND_PID" ]] || continue
  EXISTING_PIDS+=("$FOUND_PID")
done < <(word_match_find_existing_pids)

if (( ${#EXISTING_PIDS[@]} > 0 )); then
  EXISTING_PID="${EXISTING_PIDS[0]}"
  printf '%s\n' "$EXISTING_PID" > "$PID_FILE"
  EXISTING_PORT="$(cat "$LAST_PORT_FILE" 2>/dev/null || echo "$REQUESTED_PORT")"
  LOCAL_URL="http://127.0.0.1:$EXISTING_PORT"
  echo "单词对对碰已经在运行。"
  echo "PID: $EXISTING_PID"
  echo "访问地址: $LOCAL_URL"
  TAILSCALE_IP="$(word_match_get_tailscale_ipv4 || true)"
  if [[ -n "${TAILSCALE_IP:-}" ]]; then
    echo "Tailscale 地址: http://$TAILSCALE_IP:$EXISTING_PORT"
  fi
  word_match_open_browser "$LOCAL_URL"
  exit 0
fi

SELECTED_PORT="$(word_match_find_available_port "$REQUESTED_PORT" || true)"
if [[ -z "${SELECTED_PORT:-}" ]]; then
  echo "没有找到可用端口。" >&2
  echo "已尝试范围: ${REQUESTED_PORT}-$((REQUESTED_PORT + 49))" >&2
  exit 1
fi

if [[ "$SELECTED_PORT" != "$REQUESTED_PORT" ]]; then
  echo "端口 $REQUESTED_PORT 已被占用，已自动切换到 $SELECTED_PORT。"
fi

printf '%s\n' "$SELECTED_PORT" > "$LAST_PORT_FILE"
rm -f "$STDOUT_LOG" "$STDERR_LOG"

nohup env \
  PORT="$SELECTED_PORT" \
  BIND_HOST="$BIND_HOST" \
  WORD_MATCH_PID_FILE="$PID_FILE" \
  "$NODE_BIN" "$SERVER_SCRIPT" \
  </dev/null >>"$STDOUT_LOG" 2>>"$STDERR_LOG" &
SERVER_PID=$!

LOCAL_URL="http://127.0.0.1:$SELECTED_PORT"
if ! word_match_wait_http_ready "$LOCAL_URL/api/bootstrap"; then
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "服务启动失败。" >&2
    if [[ -f "$STDERR_LOG" ]]; then
      echo "错误日志:" >&2
      tail -n 20 "$STDERR_LOG" >&2
    fi
    exit 1
  fi

  echo "服务已启动，但健康检查超时。你仍然可以尝试手动打开：$LOCAL_URL"
else
  echo "启动单词对对碰本地版..."
  echo "工作目录: $SCRIPT_DIR"
  echo "Node: $NODE_BIN"
  echo "访问地址: $LOCAL_URL"
fi

TAILSCALE_IP="$(word_match_get_tailscale_ipv4 || true)"
if [[ -n "${TAILSCALE_IP:-}" ]]; then
  echo "Tailscale 地址: http://$TAILSCALE_IP:$SELECTED_PORT"
else
  echo "Tailscale 地址: 未检测到，可在安装并登录后自动显示"
fi

echo "日志输出: $STDOUT_LOG"
word_match_open_browser "$LOCAL_URL"

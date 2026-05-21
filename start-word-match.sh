#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
LAST_PORT_FILE="$RUNTIME_DIR/last-port"
PID_FILE="$RUNTIME_DIR/server.pid"

mkdir -p "$RUNTIME_DIR"

find_node() {
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi

  local candidates=(
    "/opt/homebrew/bin/node"
    "/usr/local/bin/node"
    "/Applications/Codex.app/Contents/Resources/node"
    "$HOME/.nvm/versions/node/*/bin/node"
  )

  local candidate
  for candidate in $candidates; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

find_available_port() {
  local requested_port="$1"
  local port="$requested_port"
  local max_tries=50
  local tries=0

  while (( tries < max_tries )); do
    if ! port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done

  return 1
}

get_tailscale_ipv4() {
  if ! command -v tailscale >/dev/null 2>&1; then
    return 0
  fi

  tailscale ip -4 2>/dev/null | head -n 1
}

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

find_existing_word_match_pid() {
  local pid
  for pid in ${(f)"$(pgrep -f 'server\.mjs' 2>/dev/null || true)"}; do
    if is_word_match_pid "$pid"; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

NODE_BIN="$(find_node || true)"

if [[ -z "${NODE_BIN:-}" ]]; then
  echo "未找到可用的 Node.js。"
  echo "请先确认以下任一位置存在 node："
  echo "  1. PATH 里可直接执行 node"
  echo "  2. /opt/homebrew/bin/node"
  echo "  3. /usr/local/bin/node"
  echo "  4. ~/.nvm/versions/node/.../bin/node"
  exit 1
fi

REQUESTED_PORT="${PORT:-12345}"
BIND_HOST="${BIND_HOST:-0.0.0.0}"

if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_word_match_pid "$EXISTING_PID"; then
    EXISTING_PORT="$(cat "$LAST_PORT_FILE" 2>/dev/null || echo "$REQUESTED_PORT")"
    echo "单词对对碰已经在运行。"
    echo "PID: $EXISTING_PID"
    echo "访问地址: http://127.0.0.1:$EXISTING_PORT"
    TAILSCALE_IP="$(get_tailscale_ipv4 || true)"
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
      echo "Tailscale 地址: http://$TAILSCALE_IP:$EXISTING_PORT"
    fi
    exit 0
  fi
  rm -f "$PID_FILE"
fi

EXISTING_PID="$(find_existing_word_match_pid || true)"
if [[ -n "${EXISTING_PID:-}" ]]; then
  echo "$EXISTING_PID" > "$PID_FILE"
  EXISTING_PORT="$(cat "$LAST_PORT_FILE" 2>/dev/null || echo "$REQUESTED_PORT")"
  echo "单词对对碰已经在运行。"
  echo "PID: $EXISTING_PID"
  echo "访问地址: http://127.0.0.1:$EXISTING_PORT"
  TAILSCALE_IP="$(get_tailscale_ipv4 || true)"
  if [[ -n "${TAILSCALE_IP:-}" ]]; then
    echo "Tailscale 地址: http://$TAILSCALE_IP:$EXISTING_PORT"
  fi
  exit 0
fi

PORT="$(find_available_port "$REQUESTED_PORT" || true)"

if [[ -z "${PORT:-}" ]]; then
  echo "没有找到可用端口。"
  echo "已尝试范围: ${REQUESTED_PORT}-$((REQUESTED_PORT + 49))"
  exit 1
fi

if [[ "$PORT" != "$REQUESTED_PORT" ]]; then
  echo "端口 $REQUESTED_PORT 已被占用，已自动切换到 $PORT。"
fi

echo "$PORT" > "$LAST_PORT_FILE"
export WORD_MATCH_PID_FILE="$PID_FILE"
export PORT BIND_HOST

echo "启动单词对对碰本地版..."
echo "工作目录: $SCRIPT_DIR"
echo "Node: $NODE_BIN"
echo "访问地址: http://127.0.0.1:$PORT"

TAILSCALE_IP="$(get_tailscale_ipv4 || true)"
if [[ -n "${TAILSCALE_IP:-}" ]]; then
  echo "Tailscale 地址: http://$TAILSCALE_IP:$PORT"
else
  echo "Tailscale 地址: 未检测到，可在安装并登录后自动显示"
fi

echo ""

exec "$NODE_BIN" server.mjs

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/word-match-unix-common.sh"

mkdir -p "$RUNTIME_DIR"

NODE_BIN="$(word_match_ensure_node)"
NODE_VERSION="$(word_match_node_version "$NODE_BIN")"

echo "已找到可用的 Node.js。"
echo "路径: $NODE_BIN"
echo "版本: $NODE_VERSION"

TAILSCALE_IP="$(word_match_get_tailscale_ipv4 || true)"
if [[ -n "${TAILSCALE_IP:-}" ]]; then
  echo "当前 Tailscale IPv4: $TAILSCALE_IP"
else
  echo "未检测到 Tailscale。"
  echo "如果你只在本机使用，可以忽略。"
  echo "如果要让其他设备访问这台机器，再安装 Tailscale 即可。"
fi

echo
echo "安装完成。"
echo "本项目不依赖 npm、pnpm 或额外 node_modules。"
echo "启动: ./start-word-match.sh"
echo "停止: ./stop-word-match.sh"

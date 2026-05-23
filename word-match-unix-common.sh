#!/usr/bin/env bash
set -euo pipefail

WORD_MATCH_MINIMUM_NODE_MAJOR=18
WORD_MATCH_FALLBACK_NODE_VERSION="v20.12.2"

word_match_portable_node_bin() {
  printf '%s\n' "$RUNTIME_DIR/node/bin/node"
}

word_match_node_major() {
  local node_bin="$1"
  local version

  if ! version="$("$node_bin" -p 'process.versions.node' 2>/dev/null | head -n 1)"; then
    return 1
  fi

  version="${version%%.*}"
  [[ "$version" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$version"
}

word_match_node_version() {
  local node_bin="$1"
  "$node_bin" -p 'process.versions.node' 2>/dev/null | head -n 1
}

word_match_is_compatible_node() {
  local node_bin="$1"
  local major

  [[ -x "$node_bin" ]] || return 1
  major="$(word_match_node_major "$node_bin" || true)"
  [[ -n "${major:-}" ]] && (( major >= WORD_MATCH_MINIMUM_NODE_MAJOR ))
}

word_match_array_contains() {
  local needle="$1"
  shift || true

  while (( $# > 0 )); do
    [[ "$1" == "$needle" ]] && return 0
    shift
  done

  return 1
}

word_match_find_node() {
  local portable_node
  local -a candidates=()
  local candidate

  portable_node="$(word_match_portable_node_bin)"
  if ! word_match_array_contains "$portable_node" "${candidates[@]:-}"; then
    candidates+=("$portable_node")
  fi

  if command -v node >/dev/null 2>&1; then
    candidate="$(command -v node)"
    if ! word_match_array_contains "$candidate" "${candidates[@]:-}"; then
      candidates+=("$candidate")
    fi
  fi

  for candidate in \
    "/opt/homebrew/bin/node" \
    "/usr/local/bin/node" \
    "/Applications/Codex.app/Contents/Resources/node" \
    "$HOME/.nvm/versions/node/current/bin/node" \
    "$HOME/.volta/bin/node"; do
    if ! word_match_array_contains "$candidate" "${candidates[@]:-}"; then
      candidates+=("$candidate")
    fi
  done

  shopt -s nullglob
  for candidate in "$HOME/.nvm/versions/node/"*/bin/node; do
    if ! word_match_array_contains "$candidate" "${candidates[@]:-}"; then
      candidates+=("$candidate")
    fi
  done
  shopt -u nullglob

  for candidate in "${candidates[@]}"; do
    if word_match_is_compatible_node "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

word_match_download() {
  local url="$1"
  local output_path="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output_path"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$output_path"
    return 0
  fi

  echo "未找到 curl 或 wget，无法自动下载 Node.js。" >&2
  return 1
}

word_match_node_archive_name() {
  local os_name arch_name

  os_name="$(uname -s)"
  arch_name="$(uname -m)"

  case "${os_name}:${arch_name}" in
    Darwin:arm64) printf 'node-%s-darwin-arm64.tar.gz\n' "$WORD_MATCH_FALLBACK_NODE_VERSION" ;;
    Darwin:x86_64) printf 'node-%s-darwin-x64.tar.gz\n' "$WORD_MATCH_FALLBACK_NODE_VERSION" ;;
    Linux:x86_64) printf 'node-%s-linux-x64.tar.xz\n' "$WORD_MATCH_FALLBACK_NODE_VERSION" ;;
    Linux:aarch64 | Linux:arm64) printf 'node-%s-linux-arm64.tar.xz\n' "$WORD_MATCH_FALLBACK_NODE_VERSION" ;;
    *)
      echo "暂不支持的系统架构: ${os_name} ${arch_name}" >&2
      return 1
      ;;
  esac
}

word_match_install_portable_node() {
  local archive_name archive_url download_dir archive_path extract_dir expanded_dir node_dir

  archive_name="$(word_match_node_archive_name)"
  archive_url="https://nodejs.org/dist/${WORD_MATCH_FALLBACK_NODE_VERSION}/${archive_name}"
  download_dir="$RUNTIME_DIR/download-node"
  archive_path="$download_dir/$archive_name"
  extract_dir="$download_dir/extract"
  node_dir="$RUNTIME_DIR/node"

  mkdir -p "$RUNTIME_DIR"
  rm -rf "$download_dir"
  mkdir -p "$download_dir"

  echo "正在下载 Node.js ${WORD_MATCH_FALLBACK_NODE_VERSION} ..."
  word_match_download "$archive_url" "$archive_path"

  echo "正在解压 Node.js ..."
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xf "$archive_path" -C "$extract_dir"

  expanded_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "${expanded_dir:-}" ]] || {
    echo "Node.js 解压失败，未找到内容目录。" >&2
    return 1
  }

  rm -rf "$node_dir"
  mkdir -p "$node_dir"
  cp -R "$expanded_dir"/. "$node_dir"/
  rm -rf "$download_dir"

  word_match_is_compatible_node "$(word_match_portable_node_bin)" || {
    echo "Node.js 安装完成，但版本校验失败。" >&2
    return 1
  }
}

word_match_ensure_node() {
  local node_bin

  node_bin="$(word_match_find_node || true)"
  if [[ -n "${node_bin:-}" ]]; then
    printf '%s\n' "$node_bin"
    return 0
  fi

  word_match_install_portable_node
  printf '%s\n' "$(word_match_portable_node_bin)"
}

word_match_wait_http_ready() {
  local url="$1"
  local attempts="${2:-60}"
  local i

  for ((i = 0; i < attempts; i += 1)); do
    if command -v curl >/dev/null 2>&1; then
      if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -T 2 -O /dev/null "$url" >/dev/null 2>&1; then
        return 0
      fi
    fi

    sleep 0.25
  done

  return 1
}

word_match_get_tailscale_ipv4() {
  local tailscale_bin

  if command -v tailscale >/dev/null 2>&1; then
    tailscale_bin="tailscale"
  elif [[ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
    tailscale_bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  else
    return 0
  fi

  "$tailscale_bin" ip -4 2>/dev/null | head -n 1
}

word_match_process_cwd() {
  local pid="$1"

  if [[ -L "/proc/$pid/cwd" ]]; then
    readlink "/proc/$pid/cwd"
    return 0
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1
    return 0
  fi

  return 1
}

word_match_is_word_match_pid() {
  local pid="$1"
  local command_line state cwd

  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1

  command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  state="$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]' || true)"
  cwd="$(word_match_process_cwd "$pid" 2>/dev/null || true)"

  [[ -n "$state" ]] || return 1
  [[ "$state" != *Z* ]] || return 1
  [[ "$command_line" == *"server.mjs"* ]] || return 1
  [[ "$cwd" == "$SCRIPT_DIR" ]]
}

word_match_find_existing_pids() {
  local pid

  while IFS= read -r pid; do
    if word_match_is_word_match_pid "$pid"; then
      printf '%s\n' "$pid"
    fi
  done < <(pgrep -f 'server\.mjs' 2>/dev/null || true)
}

word_match_port_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :$port )" 2>/dev/null | tail -n +2 | grep -q .
    return
  fi

  netstat -an 2>/dev/null | grep -E "[\.:]$port[[:space:]].*LISTEN" >/dev/null 2>&1
}

word_match_find_available_port() {
  local requested_port="$1"
  local max_tries="${2:-50}"
  local port="$requested_port"
  local tries=0

  while (( tries < max_tries )); do
    if ! word_match_port_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi

    port=$((port + 1))
    tries=$((tries + 1))
  done

  return 1
}

word_match_open_browser() {
  local url="$1"

  if [[ "${WORD_MATCH_OPEN_BROWSER:-0}" != "1" ]]; then
    return 0
  fi

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
}

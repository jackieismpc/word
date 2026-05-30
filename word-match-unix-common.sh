#!/usr/bin/env bash
set -euo pipefail

WORD_MATCH_MINIMUM_NODE_MAJOR=18
WORD_MATCH_FALLBACK_NODE_VERSION="v20.12.2"

word_match_portable_node_bin() {
  printf '%s\n' "$RUNTIME_DIR/node/bin/node"
}

word_match_offline_node_dir() {
  printf '%s\n' "$SCRIPT_DIR/offline-assets/node"
}

word_match_run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
command = sys.argv[2:]

try:
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=timeout_seconds,
        check=False,
        text=True,
    )
    sys.stdout.write(result.stdout)
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
PY
    return
  fi

  local output_file pid status elapsed_ticks
  output_file="$(mktemp "${TMPDIR:-/tmp}/word-match-node-check.XXXXXX")"

  "$@" >"$output_file" 2>/dev/null &
  pid=$!
  status=0
  elapsed_ticks=0

  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( elapsed_ticks >= timeout_seconds * 10 )); then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      sleep 0.2
      kill -KILL "$pid" >/dev/null 2>&1 || true
      wait "$pid" 2>/dev/null || true
      rm -f "$output_file"
      return 124
    fi

    sleep 0.1
    elapsed_ticks=$((elapsed_ticks + 1))
  done

  wait "$pid"
  status=$?
  cat "$output_file"
  rm -f "$output_file"
  return "$status"
}

word_match_clear_macos_quarantine() {
  local target_path="$1"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$target_path" 2>/dev/null || true
  fi
}

word_match_node_major() {
  local node_bin="$1"
  local version

  if ! version="$(word_match_run_with_timeout 3 "$node_bin" -p 'process.versions.node' | head -n 1)"; then
    return 1
  fi

  version="${version%%.*}"
  [[ "$version" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$version"
}

word_match_node_version() {
  local node_bin="$1"
  word_match_run_with_timeout 3 "$node_bin" -p 'process.versions.node' | head -n 1
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
  local -a candidates=()
  local candidate

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

word_match_portable_node_installed() {
  local portable_node

  portable_node="$(word_match_portable_node_bin)"
  if word_match_is_compatible_node "$portable_node"; then
    printf '%s\n' "$portable_node"
    return 0
  fi

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

word_match_node_archive_glob() {
  local os_name arch_name

  os_name="$(uname -s)"
  arch_name="$(uname -m)"

  case "${os_name}:${arch_name}" in
    Darwin:arm64) printf 'node-*-darwin-arm64.tar.gz\n' ;;
    Darwin:x86_64) printf 'node-*-darwin-x64.tar.gz\n' ;;
    Linux:x86_64) printf 'node-*-linux-x64.tar.xz\n' ;;
    Linux:aarch64 | Linux:arm64) printf 'node-*-linux-arm64.tar.xz\n' ;;
    *)
      echo "暂不支持的系统架构: ${os_name} ${arch_name}" >&2
      return 1
      ;;
  esac
}

word_match_find_offline_node_archive() {
  local offline_dir exact_archive_path archive_glob matched_archive
  offline_dir="$(word_match_offline_node_dir)"

  [[ -d "$offline_dir" ]] || return 1

  exact_archive_path="$offline_dir/$(word_match_node_archive_name)"
  if [[ -f "$exact_archive_path" ]]; then
    printf '%s\n' "$exact_archive_path"
    return 0
  fi

  archive_glob="$(word_match_node_archive_glob)"
  matched_archive="$(
    find "$offline_dir" -maxdepth 1 -type f -name "$archive_glob" -print 2>/dev/null |
      sort -r |
      head -n 1
  )"

  [[ -n "${matched_archive:-}" ]] || return 1
  printf '%s\n' "$matched_archive"
}

word_match_install_portable_node() {
  local archive_name archive_url download_dir archive_path extract_dir expanded_dir node_dir source_archive

  source_archive="${1:-}"
  archive_name="$(word_match_node_archive_name)"
  archive_url="https://nodejs.org/dist/${WORD_MATCH_FALLBACK_NODE_VERSION}/${archive_name}"
  download_dir="$RUNTIME_DIR/download-node"
  archive_path="$download_dir/$archive_name"
  extract_dir="$download_dir/extract"
  node_dir="$RUNTIME_DIR/node"

  mkdir -p "$RUNTIME_DIR"
  rm -rf "$download_dir"
  mkdir -p "$download_dir"

  if [[ -n "${source_archive:-}" ]]; then
    echo "检测到离线 Node.js 包，正在使用: $source_archive" >&2
    cp "$source_archive" "$archive_path"
  else
    if [[ "${WORD_MATCH_ALLOW_ONLINE_DOWNLOAD:-0}" != "1" ]]; then
      echo "未找到离线 Node.js 包，且当前不允许联网下载。" >&2
      echo "请先把对应平台的 Node.js 官方压缩包放到 $(word_match_offline_node_dir) 。" >&2
      echo "如需显式允许联网下载，请设置 WORD_MATCH_ALLOW_ONLINE_DOWNLOAD=1 后重试。" >&2
      return 1
    fi

    echo "未找到离线 Node.js 包，正在下载 Node.js ${WORD_MATCH_FALLBACK_NODE_VERSION} ..." >&2
    word_match_download "$archive_url" "$archive_path"
  fi

  echo "正在解压 Node.js ..." >&2
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
  word_match_clear_macos_quarantine "$node_dir"
  rm -rf "$download_dir"

  word_match_is_compatible_node "$(word_match_portable_node_bin)" || {
    echo "Node.js 安装完成，但版本校验失败。" >&2
    return 1
  }
}

word_match_ensure_node() {
  local node_bin offline_archive

  node_bin="$(word_match_portable_node_installed || true)"
  if [[ -n "${node_bin:-}" ]]; then
    printf '%s\n' "$node_bin"
    return 0
  fi

  offline_archive="$(word_match_find_offline_node_archive || true)"
  if [[ -n "${offline_archive:-}" ]]; then
    if word_match_install_portable_node "$offline_archive"; then
      printf '%s\n' "$(word_match_portable_node_bin)"
      return 0
    fi

    echo "项目离线 Node.js 校验失败，已回退到其他可用 Node.js。" >&2
    rm -rf "$RUNTIME_DIR/node" "$RUNTIME_DIR/download-node"
  fi

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
  local command_line state cwd server_script

  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1

  command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  state="$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]' || true)"
  cwd="$(word_match_process_cwd "$pid" 2>/dev/null || true)"
  server_script="$SCRIPT_DIR/server.mjs"

  [[ -n "$state" ]] || return 1
  [[ "$state" != *Z* ]] || return 1
  [[ "$command_line" == *"server.mjs"* ]] || return 1
  [[ "$command_line" == *"$server_script"* ]] || return 1

  if [[ -n "${cwd:-}" ]]; then
    [[ "$cwd" == "$SCRIPT_DIR" ]]
    return
  fi

  return 0
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

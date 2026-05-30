#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/offline-assets/node"
NODE_VERSION="${WORD_MATCH_NODE_VERSION:-v20.12.2}"

download_file() {
  local url="$1"
  local output_path="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL "$url" -o "$output_path"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "$output_path" "$url"
    return 0
  fi

  echo "未找到 curl 或 wget，无法下载离线安装包。" >&2
  return 1
}

verify_sha256() {
  local checksums_file="$1"
  local file_name="$2"
  local file_path="$3"
  local expected actual

  expected="$(awk -v name="$file_name" '$2 == name { print $1 }' "$checksums_file" | head -n 1)"
  if [[ -z "${expected:-}" ]]; then
    echo "未在 SHASUMS256.txt 中找到 $file_name，跳过校验。"
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file_path" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file_path" | awk '{print $1}')"
  else
    echo "未找到 shasum 或 sha256sum，跳过校验。"
    return 0
  fi

  if [[ "$expected" != "$actual" ]]; then
    echo "校验失败: $file_name" >&2
    return 1
  fi
}

main() {
  local -a arches=("$@")
  if (( ${#arches[@]} == 0 )); then
    arches=("x64")
  fi

  mkdir -p "$TARGET_DIR"

  local base_url="https://nodejs.org/dist/$NODE_VERSION"
  local checksums_path="$TARGET_DIR/SHASUMS256.txt"

  echo "下载 Node.js 校验文件..."
  download_file "$base_url/SHASUMS256.txt" "$checksums_path"

  local arch file_name file_path
  for arch in "${arches[@]}"; do
    case "$arch" in
      x64|arm64|x86) ;;
      *)
        echo "不支持的架构: $arch。支持: x64 / arm64 / x86" >&2
        return 1
        ;;
    esac

    file_name="node-$NODE_VERSION-win-$arch.zip"
    file_path="$TARGET_DIR/$file_name"

    echo "下载 $file_name ..."
    download_file "$base_url/$file_name" "$file_path"
    verify_sha256 "$checksums_path" "$file_name" "$file_path"
  done

  cat <<EOF

离线包已准备完成，目录如下：
  $TARGET_DIR

把整个项目目录复制到 Windows 后，直接运行：
  install-word-match.cmd

Windows 安装脚本会优先使用 offline-assets/node 里的 zip 包，
只有在离线包不存在时才会尝试联网下载。
EOF
}

main "$@"

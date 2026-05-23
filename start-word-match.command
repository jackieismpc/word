#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
WORD_MATCH_OPEN_BROWSER=1 "$SCRIPT_DIR/start-word-match.sh"

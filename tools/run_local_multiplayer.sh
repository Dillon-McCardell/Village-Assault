#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/village-assault"
GODOT_BIN="${GODOT_BIN:-}"

if [[ -z "$GODOT_BIN" ]]; then
  for candidate in \
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$(command -v godot4 2>/dev/null || true)" \
    "$(command -v godot 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      GODOT_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$GODOT_BIN" ]]; then
  echo "Godot binary not found. Set GODOT_BIN to the executable path." >&2
  exit 1
fi

PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT INT TERM

"$GODOT_BIN" --path "$PROJECT_DIR" --position 40,40 "$@" &
PIDS+=("$!")
"$GODOT_BIN" --path "$PROJECT_DIR" --position 160,100 "$@" &
PIDS+=("$!")

echo "Started two Village Assault windows at the main menu."
echo "Press Ctrl-C to close both windows."
wait "${PIDS[@]}"

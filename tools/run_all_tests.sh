#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/village-assault"
DEFAULT_GODOT_BIN="/Users/dmccard/Downloads/Godot.app/Contents/MacOS/Godot"
HEADLESS=1
GODOT_BIN="${GODOT_BIN:-}"

usage() {
  cat <<'USAGE'
Usage: tools/run_all_tests.sh [--godot-bin /path/to/godot] [--no-headless]

Runs all automated test suites for Village Assault:
- Full GdUnit suite
- Reconnect acceptance harness (`game_reconnect`)
- Reconnect acceptance harness (`lobby_reconnect`)

Options:
  --godot-bin PATH  Path to the Godot executable.
  --no-headless     Run reconnect harness windows visibly.
  -h, --help        Show this help text.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --godot-bin)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --godot-bin" >&2
        exit 1
      fi
      GODOT_BIN="$2"
      shift 2
      ;;
    --no-headless)
      HEADLESS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$GODOT_BIN" ]]; then
  if [[ -x "$DEFAULT_GODOT_BIN" ]]; then
    GODOT_BIN="$DEFAULT_GODOT_BIN"
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  else
    echo "Godot binary not found. Pass --godot-bin or set GODOT_BIN." >&2
    exit 1
  fi
fi

HARNESS_ARGS=()
if [[ "$HEADLESS" -eq 1 ]]; then
  HARNESS_ARGS+=(--headless)
fi

printf '\n==> Running GdUnit suite\n'
(
  cd "$PROJECT_DIR"
  ./addons/gdUnit4/runtest.sh --godot_binary "$GODOT_BIN" --add res://tests/
)

printf '\n==> Running reconnect harness: game_reconnect\n'
(
  cd "$ROOT_DIR"
  python3 tools/run_reconnect_harness.py \
    --godot-bin "$GODOT_BIN" \
    --timeout-sec 30 \
    "${HARNESS_ARGS[@]}"
)

printf '\n==> Running reconnect harness: lobby_reconnect\n'
(
  cd "$ROOT_DIR"
  python3 tools/run_reconnect_harness.py \
    --godot-bin "$GODOT_BIN" \
    --timeout-sec 30 \
    --scenario lobby_reconnect \
    "${HARNESS_ARGS[@]}"
)

printf '\nAll automated test suites passed.\n'

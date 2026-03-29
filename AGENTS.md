# Codex Notes

## Godot CLI

- Preferred Godot binary for this repo: `/Users/dmccard/Downloads/Godot.app/Contents/MacOS/Godot`
- Verified on 2026-03-29 with `--version`: `4.5.1.stable.official.f62fdbde1`
- When running GdUnit from the repo, prefer either:
  - `export GODOT_BIN=/Users/dmccard/Downloads/Godot.app/Contents/MacOS/Godot`
  - `./addons/gdUnit4/runtest.sh --godot_binary /Users/dmccard/Downloads/Godot.app/Contents/MacOS/Godot --add res://tests/...`

## Repository Layout

- Godot project root: `/Users/dmccard/Repos/Village-Assault/village-assault`
- Repo root is not the Godot project root. Commands like GdUnit test runs should usually execute from the `village-assault/` subdirectory.

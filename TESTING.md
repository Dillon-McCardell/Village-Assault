# Testing

Village Assault has two layers of automated testing:

- Property-style unit/integration coverage via [GdUnit4](https://github.com/MikeSchulze/gdUnit4)
- A local multi-process acceptance harness for the client mid-game reconnect flow

## Canonical Test Command

Use this repo-root command as the default verification entry point for full
coverage:

```bash
./tools/run_all_tests.sh
```

It runs every automated suite sequentially:

- full `GdUnit4` coverage under `village-assault/tests/`
- reconnect harness `game_reconnect`
- reconnect harness `lobby_reconnect`

Prefer this command for future Codex verification unless you are intentionally
scoping down to a smaller target while iterating.

## Git Hook Enforcement

This repo's `pre-commit` hook runs the same command before a commit is allowed
to succeed:

```bash
./tools/run_all_tests.sh
```

The repository already points `core.hooksPath` at `.githooks`, so commits made
from this checkout automatically enforce the full test pass before the commit is
created.

## GdUnit4 Tests

The GdUnit4 suites live in `village-assault/tests/`. They run 100 randomized
iterations per property with deterministic seeds.

### From the CLI

The preferred full-suite entry point is:

```bash
./tools/run_all_tests.sh --godot-bin /path/to/godot
```

To run only the GdUnit layer:

```bash
export GODOT_BIN=/path/to/godot
cd village-assault
./addons/gdUnit4/runtest.sh --add res://tests/
```

To run a single test file:

```bash
./addons/gdUnit4/runtest.sh --add res://tests/test_disconnect_handling.gd
```

Or pass the binary path inline:

```bash
./addons/gdUnit4/runtest.sh --godot_binary /path/to/godot --add res://tests/
```

### From the Godot Editor

1. Open the project in Godot 4.
2. Enable the GdUnit4 plugin under **Project → Project Settings → Plugins**.
3. Open the GdUnit4 panel (bottom dock) and run tests from there.

### Test Suites

| File | Covers |
|---|---|
| `test_territory_manager.gd` | Heightmap generation, spawn bounds, base anchors, world sizing, deterministic gold ore generation, ore depth constraints, ore density-window limits, and terrain/resource layer rendering |
| `test_unit_spawning.gd` | Spawn queue FIFO, troop scene mapping, invalid request rejection |
| `test_disconnect_handling.gd` | State preservation, team reservation, restore round-trip, state erasure, pause/unpause |
| `test_passive_income.gd` | Host-authoritative passive income timing, accumulation, scene gating, and inactive-peer exclusion |
| `test_reconnect_routing.gd` | Scene redirect and restored reconnect state after transport recovery |
| `test_game_ui.gd` | Game HUD status text and scene-level UI behavior |
| `test_troop_combat.gd` | Troop stat payloads, spawn-time stat initialization, damage/defense resolution, enemy combat, survivor movement, friendly non-engagement, debug spawn grunt stats |

### Shared Test Helpers

- `res://scripts/testing/terrain_test_harness.gd` provides a reusable terrain
  fixture for world-generation tests:
  - resets multiplayer and world runtime state
  - creates and mounts a `TerritoryManager` with a `WorldTileMap`
  - encodes deterministic gold-tile snapshots for equality assertions
  - asserts ore rule compliance for depth and 10x10 density windows

Use it for any future mining/resource suites so ore-validation logic stays
centralized instead of being copied into each test file.

### Ore Generation Coverage

The ore-generation feature is currently validated at the GdUnit layer rather
than the multi-process reconnect harness. The terrain suite verifies:

- deterministic ore placement for a fixed map seed
- minimum ore depth below each local surface column
- the `max 2 gold tiles in any 10x10 window` rule
- correct separation of terrain tiles vs. resource-layer gold tiles
- valid ore regeneration after world size/seed updates

To run just the ore-related terrain coverage:

```bash
export GODOT_BIN=/path/to/godot
cd village-assault
./addons/gdUnit4/runtest.sh --godot_binary "$GODOT_BIN" --add res://tests/test_territory_manager.gd
```

## Reconnection Acceptance Harness

The repo also includes a local-only multi-process acceptance harness for the
client mid-game reconnect flow. It launches two fresh Godot processes, drives
the normal boot -> lobby -> game path, forces a client disconnect, waits for
reconnect, and verifies the client returns to the same game state.

Run it directly from the repo root when you only need the reconnect acceptance layer:

```bash
python3 tools/run_reconnect_harness.py --godot-bin /path/to/godot
```

Optional flags:

- `--artifacts-dir /tmp/village-assault-harness` to keep event and child log files
- `--timeout-sec 30` to increase per-step timeout
- `--headless` to run child Godot processes without windows

### What It Verifies

- The host and client follow the normal boot -> lobby -> game flow
- A client can disconnect mid-game and reconnect through the real ENet path
- The reconnected client remains in the `game` scene
- Team and money are restored instead of being reassigned
- A troop visible before disconnect is still visible after reconnect

### Artifacts

Each harness run writes artifacts for both child processes, including:

- JSONL event streams
- Child stdout logs
- Child stderr logs

The runner prints the artifact directory on success or failure so the run can
be inspected afterward.

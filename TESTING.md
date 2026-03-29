# Testing

Village Assault has two layers of automated testing:

- Property-style unit/integration coverage via [GdUnit4](https://github.com/MikeSchulze/gdUnit4)
- A local multi-process acceptance harness for the client mid-game reconnect flow

## GdUnit4 Tests

The GdUnit4 suites live in `village-assault/tests/`. They run 100 randomized
iterations per property with deterministic seeds.

### From the CLI

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
| `test_unit_spawning.gd` | Spawn queue FIFO, troop scene mapping, invalid request rejection |
| `test_disconnect_handling.gd` | State preservation, team reservation, restore round-trip, state erasure, pause/unpause |
| `test_troop_combat.gd` | Troop stat payloads, spawn-time stat initialization, damage/defense resolution, enemy combat, survivor movement, friendly non-engagement, debug spawn grunt stats |

## Reconnection Acceptance Harness

The repo also includes a local-only multi-process acceptance harness for the
client mid-game reconnect flow. It launches two fresh Godot processes, drives
the normal boot -> lobby -> game path, forces a client disconnect, waits for
reconnect, and verifies the client returns to the same game state.

Run it from the repo root:

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

# Codex Notes

## Project Orientation

- The repository root contains tooling and Git hooks. The Godot project root is
  `village-assault/`; `res://` paths and direct GdUnit commands resolve from there.
- Run repository launchers such as `tools/run_all_tests.sh`,
  `tools/run_test_session.py`, and `tools/run_local_multiplayer.sh` from the repository
  root.
- Before editing, inspect `git status`. This checkout is often used for iterative
  gameplay validation, so preserve unrelated worktree changes and build on relevant
  changes rather than reverting them.

## Godot CLI

- Preferred Godot binary:
  `/Applications/Godot.app/Contents/MacOS/Godot`
- Verified on 2026-07-16 with `--version`:
  `4.5.1.stable.official.f62fdbde1`
- Set the binary explicitly before using repository tools:

  ```sh
  export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
  ```

- Run a focused GdUnit suite from `village-assault/`:

  ```sh
  ./addons/gdUnit4/runtest.sh \
    --godot_binary "$GODOT_BIN" \
    --add res://tests/test_unit_spawning.gd
  ```

- Do not run Godot-based tests in parallel. GdUnit scenes and multiplayer harnesses can
  contend for local ENet ports and produce misleading failures.

## Runtime and Multiplayer

- The server is authoritative for terrain mutations, tactical orders, worker jobs,
  combat, and resource rewards. Clients should present replicated state rather than
  independently deciding gameplay transitions.
- For multiplayer-spawned troops, prefer scene-owned visual nodes over dynamically
  created runtime children. Both peers then instantiate the same node tree before
  replicated state begins updating.
- Replicated exported-property updates do not always behave like ordinary local setter
  calls. Client-visible presentation derived from replicated values should have a
  lightweight refresh path that reconciles visuals with current state.
- `GameState.local_state_updated` also fires for money and state refreshes. Gate camera
  anchoring and similar one-time setup on initial team assignment or an actual team
  change.
- Code that can run in offline tests must check
  `multiplayer.multiplayer_peer != null` before calling `multiplayer.is_server()`,
  `multiplayer.get_unique_id()`, or `multiplayer.get_peers()`.

## UI and Input

- `CanvasLayer/UI` in `res://scenes/game.tscn` is a full-screen `Control`. Gameplay mouse
  input belongs in `_input()` when it must run before controls consume the event.
- World clicks that coexist with UI need explicit pointer-over-blocking-UI checks. Do
  not rely on `_unhandled_input()` alone.
- Bottom-corner HUD controls should follow `shop_menu.gd` and derive placement from the
  configured viewport dimensions. Control-local viewport sizing can place controls
  off-screen.
- Camera-drag tests must send explicit mouse-button release events so drag state cannot
  leak into later assertions.

## Movement and Footprints

- Grounded movement is tile-based. `TerritoryManager` owns standability, footprint,
  climb/drop, pathfinding, and tile/world conversion rules; troop scripts should call
  its narrow APIs rather than duplicate terrain logic.
- A stand tile is the bottom air tile occupied by a troop, not its support block.
  Convert it with `troop_stand_tile_to_world_position()` and pass the troop width so
  wide units remain centered correctly.
- `TestUnit.set_body_polygon()` derives occupancy width and height by rounding the body
  polygon's bounds up to whole terrain tiles. Changing a troop polygon is therefore a
  gameplay/pathfinding change, not just a visual change.
- Keep every troop's scene-owned `Body` polygon synchronized with the runtime fallback
  polygon in its script. Test both dimensions whenever either definition changes.
- Miners intentionally occupy exactly one 16 x 16 tile. Miner job navigation currently
  uses the one-tile `is_standable_tile()` and `find_miner_path()` contract, while
  tactical Move uses footprint-aware troop pathing. If miners become taller than one
  tile, migrate job navigation to footprint-aware APIs in the same change or Dig and
  Move will disagree about tunnel clearance.
- Tactical Move should compute one path with
  `find_troop_path_to_nearest_reachable()` and retain it while the order is active.
  Avoid reachability searches during command validation or every physics frame. Use an
  indexed queue for breadth-first search rather than `Array.pop_front()`.
- Clear committed and transient path state whenever an order or miner job changes.
  Rebuild only when a new order begins or a terrain mutation invalidates the next path
  tile.
- Paths across climbs and drops must contain each intermediate stand tile. Advance path
  progress after reaching that tile's exact world position; deriving progress only from
  the current grid tile can cause freezing and visual vibration near transitions.
- Retreat ignores enemy acquisition and routes to
  `TerritoryManager.get_base_troop_stand_tile()` for the troop's actual footprint. Do
  not use the camera-oriented base anchor directly as a movement destination.

## Terrain, Fog, and Worker Jobs

- Keep excavation state separate from harvesting state: terrain health, underground
  air, ore health, ore reveal state, and overlays have distinct lifecycles.
- Add TileMap gameplay layers with explicit TileMap and layer z-index/modulate settings.
  Defaults can place terrain over troops or selection overlays.
- Fog transition work runs at a bounded interval and updates the existing mask texture
  in place. Avoid rebuilding the complete fog image/texture every rendered frame;
  troop movement can otherwise cause severe frame-rate drops.
- Model long-running worker behavior with separate assigned-job and runtime-state
  payloads. Runtime branches such as Dig becoming Harvest must be explicit
  authority-side state transitions.
- Gameplay choices that may be evaluated on multiple peers need deterministic
  tie-breakers. Prefer shortest path, then stable tile-coordinate ordering.

## Testing and Visual QA

- Git hooks are enabled through `core.hooksPath=.githooks`. A failed commit can come
  from either the pre-commit test run or the commit-message hook.
- Final verification from the repository root is:

  ```sh
  GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
    ./tools/run_all_tests.sh
  ```

  This runs the complete GdUnit suite, game and lobby reconnect harnesses, and the
  two-peer grouped-mining acceptance scenario in sequence.
- Use `./tools/run_test_session.py <scenario.json>` for deterministic map-dependent
  visual or multiplayer QA. Pass `--players 2` for host/client windows or
  `--headless --exit-after-ready` for setup smoke tests. Scenario documentation lives
  in `village-assault/test_sessions/README.md`.
- Use `./tools/run_local_multiplayer.sh` when manual validation should start two
  independent windows at the main menu and exercise the complete Host/Join flow.
- Scene tests for mouse behavior must call the same path as the live game. If runtime
  handling is in `_input()`, driving `_unhandled_input()` in a test can hide routing
  bugs.
- New terrain or movement rules need a direct `TerritoryManager` test plus a scene or
  runtime test. The direct test locks down grid semantics; the scene test verifies body
  footprints, spawning, input, and multiplayer-facing initialization together.
- For clearance regressions, build an enclosed tunnel with explicit air, support, and
  ceiling tiles. Assert both the computed occupancy size and the final tactical order
  position.
- The in-game debug console is useful for temporary instrumentation. Log order
  acceptance, blocked-by-UI events, screen/world/tile conversions, path goals, and
  selection changes while reproducing input or movement failures.

## Godot File Hygiene

- Opening the editor can rewrite `project.godot`. Keep such changes only when they are
  required by the feature; discard incidental editor churn after reviewing the diff.
- Godot `.uid` files preserve script/resource identity. Commit newly generated UID
  files that correspond to tracked resources, even when the editor produced them
  separately from the gameplay change.

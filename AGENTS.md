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

## Multiplayer and Runtime Gotchas

- For multiplayer-spawned troops, prefer scene-owned visual nodes over dynamically created runtime children when possible. Existing scene children replicate more predictably across host/client because both peers instantiate the same node tree before replicated state starts updating.
- Do not assume replicated exported-property updates will always behave like ordinary local setter calls in gameplay code. For client-visible visuals derived from replicated values, it is safer to include a lightweight runtime refresh path that re-syncs presentation from current state.
- `GameState.local_state_updated` is not just a "team assigned" signal. It also fires on local money/state refreshes, so game-camera anchoring or other one-time view setup should be gated to initial team assignment or actual team changes instead of every emission.
- Any code path that may run in offline tests should guard `multiplayer.is_server()`, `multiplayer.get_unique_id()`, and `multiplayer.get_peers()` behind `multiplayer.multiplayer_peer != null`. Otherwise Godot emits noisy peer warnings and some scene tests become brittle.

## UI and Input Gotchas

- The `CanvasLayer/UI` node in `res://scenes/game.tscn` is a full-screen `Control`. Mouse interactions that should work during gameplay often need to be handled in `_input()` rather than `_unhandled_input()`, because UI controls can consume events before `_unhandled_input()` sees them.
- If world clicks should coexist with UI, keep explicit "pointer over blocking UI" checks in game-scene input code instead of relying on `_unhandled_input()` alone.
- For bottom-corner HUD controls in the game scene, prefer the same layout strategy used by `shop_menu.gd`: compute positions from `ProjectSettings` viewport width/height. Using control-local viewport sizing can make buttons appear off-screen or not appear at all.
- When changing camera drag behavior, update both runtime input code and any tests that simulate drags. Tests need explicit mouse-button release events or the camera can remain in a drag state across later assertions.

## World and Terrain Conventions

- `TerritoryManager` is the authoritative home for tile-grid queries and tile-state mutations. New gameplay that depends on terrain, visibility, ore, pathability, or tile destruction should prefer adding narrow helper APIs there instead of duplicating tile logic in troop scripts or UI code.
- Keep terrain excavation state separate from resource-harvesting state. Normal terrain health, underground-air replacement, ore health, ore reveal state, and overlay rendering are easier to reason about and test when they are modeled as distinct systems instead of one overloaded "tile damage" path.
- Grounded troop movement should operate in tile-space first and derive world positions from standable tiles. Free world-space interpolation is easy to add but often causes floating, invalid climbs, and host/client divergence once terrain changes at runtime.
- When adding new TileMap layers for gameplay rendering, explicitly set both the TileMap `z_index` and each layer z-index/modulate in code. Default layer ordering is easy to break when adding overlays or underground visuals and can cause terrain to render over troops.

## Job and State Modeling

- For long-running worker behavior, prefer explicit job/state payloads over inferring behavior from a single tile list. Separate "assigned job" from "runtime state" so UI, replication, and AI transitions stay understandable.
- If a worker action can branch at runtime, such as digging that may convert into harvesting, encode the branch as an explicit state transition on the authority rather than implicit client-side heuristics.
- When a unit has both committed orders and transient path progress, clear and rebuild path progress whenever the committed order changes. Reusing stale path state after reassignment causes subtle bugs that are hard to notice until multiplayer testing.
- Prefer deterministic tie-breakers for gameplay decisions that can happen on different peers, such as selecting among multiple reachable targets. Shortest path, then stable coordinate ordering, is a good default.

## Testing Notes

- This repo enforces tests at commit time through `.githooks/pre-commit`, and `core.hooksPath` already points at `.githooks` in this checkout. If a commit fails unexpectedly, check both the pre-commit test run and the `commit-msg` hook.
- Do not run Godot-based test commands in parallel. GdUnit scene tests and reconnect harness runs can contend for local ENet ports and produce misleading failures.
- Prefer `./tools/run_all_tests.sh` for final verification. It runs the full GdUnit suite plus both reconnect harness scenarios in the correct sequence.
- Scene tests for real mouse behavior should call the same input path the live game uses. If gameplay input is handled in `_input()`, tests should drive `_input()` too; directly calling `_unhandled_input()` can hide routing bugs.
- The in-game debug console is useful for temporary instrumentation while debugging input and coordinate conversion issues. Logging blocked-by-UI events, screen/world/tile conversions, and selection state transitions is high-signal in this project.
- When adding new gameplay rules to terrain or worker AI, add at least one direct `TerritoryManager`-level test and one scene/runtime test. The direct test should lock down grid/pathing rules; the scene test should verify the rule still holds once UI, spawning, and multiplayer-facing initialization are involved.

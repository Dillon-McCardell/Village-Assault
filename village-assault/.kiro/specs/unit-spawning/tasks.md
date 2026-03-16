# Implementation Plan: Unit Spawning

## Overview

Wire the shop purchase flow to unit instantiation: create four troop scripts/scenes, add
the spawn queue processor and `spawn_unit` RPC to `game.gd`, and hook `shop_menu.gd` into
`GameState.enqueue_spawn`. All spawn authority lives on the server; clients only receive
and execute the RPC.

## Tasks

- [x] 1. Create troop scripts
  - [x] 1.1 Create `scripts/troops/troop_grunt.gd`
    - Extend `test_unit.gd`
    - Override polygon to `PackedVector2Array(-8,-8, 8,-8, 8,8, -8,8)` (16×16)
    - Set `unit_height = 16.0`
    - Set base color `Color(0.2, 0.75, 0.2, 1)` (green) on the `Body` Polygon2D in `_ready`
    - _Requirements: 7.1_

  - [x] 1.2 Create `scripts/troops/troop_ranger.gd`
    - Extend `test_unit.gd`
    - Override polygon to `PackedVector2Array(-8,-16, 8,-16, 8,16, -8,16)` (16×32)
    - Set `unit_height = 32.0`
    - Set base color `Color(0.2, 0.4, 0.9, 1)` (blue) on `Body` in `_ready`
    - _Requirements: 7.2_

  - [x] 1.3 Create `scripts/troops/troop_brute.gd`
    - Extend `test_unit.gd`
    - Override polygon to `PackedVector2Array(-16,-16, 16,-16, 16,16, -16,16)` (32×32)
    - Set `unit_height = 32.0`
    - Set base color `Color(0.55, 0.35, 0.15, 1)` (brown) on `Body` in `_ready`
    - _Requirements: 7.3_

  - [x] 1.4 Create `scripts/troops/troop_scout.gd`
    - Extend `test_unit.gd`
    - Override polygon to `PackedVector2Array(-8,-8, 8,-8, 8,8, -8,8)` (16×16)
    - Set `unit_height = 16.0`
    - Set base color `Color(0.95, 0.85, 0.1, 1)` (yellow) on `Body` in `_ready`
    - _Requirements: 7.4_

- [x] 2. Create troop scenes
  - [x] 2.1 Create `scenes/troops/troop_grunt.tscn`
    - Duplicate `test_unit.tscn` structure; attach `troop_grunt.gd` as the root script
    - _Requirements: 4.1, 4.2, 7.1_

  - [x] 2.2 Create `scenes/troops/troop_ranger.tscn`
    - Duplicate `test_unit.tscn` structure; attach `troop_ranger.gd` as the root script
    - _Requirements: 4.1, 4.2, 7.2_

  - [x] 2.3 Create `scenes/troops/troop_brute.tscn`
    - Duplicate `test_unit.tscn` structure; attach `troop_brute.gd` as the root script
    - _Requirements: 4.1, 4.2, 7.3_

  - [x] 2.4 Create `scenes/troops/troop_scout.tscn`
    - Duplicate `test_unit.tscn` structure; attach `troop_scout.gd` as the root script
    - _Requirements: 4.1, 4.2, 7.4_

- [x] 3. Add spawn system to `game.gd`
  - [x] 3.1 Add `_troop_scenes` dictionary and `TROOP_CATEGORY` constant
    - Declare `const TROOP_CATEGORY: String = "Troops"`
    - Declare `var _troop_scenes: Dictionary` with four `preload(...)` entries pointing to the four `.tscn` files created in task 2
    - _Requirements: 4.1, 4.2, 4.3_

  - [x] 3.2 Write property test for item-to-scene mapping (Property 6)
    - **Property 6: Item-to-scene mapping is total over troop IDs**
    - Iterate all four troop IDs; assert `_troop_scenes.get(id) != null`
    - Iterate a set of non-troop IDs; assert `_troop_scenes.get(id) == null`
    - **Validates: Requirements 4.1, 4.2, 5.2**

  - [x] 3.3 Implement `_process_spawn_queue()` in `game.gd`
    - Guard with `if not multiplayer.is_server(): return`
    - Call `GameState.dequeue_spawn()`; return early if result is empty dict
    - Validate `request.team != GameState.Team.NONE`; discard silently if invalid
    - Call `TerritoryManager.get_next_spawn_position_for_team(request.team)`
    - Validate position with `TerritoryManager.is_world_pos_in_team_territory(pos, request.team)`; discard silently if invalid
    - Look up scene via `_troop_scenes.get(request.item_id)`; discard silently if null
    - Call `spawn_unit.rpc(pos, request.team, request.item_id)`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 1.2, 1.3_

  - [x] 3.4 Implement `spawn_unit` RPC in `game.gd`
    - Annotate `@rpc("authority", "reliable", "call_local")`
    - Look up `PackedScene` from `_troop_scenes.get(item_id)`; return if null
    - Instantiate scene, call `set_team(team)`, set `position = pos`
    - Add unit to the `Units` node in the scene tree
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 3.5 Hook `_process_spawn_queue()` into `_physics_process(delta)` in `game.gd`
    - Add or extend `_physics_process` to call `_process_spawn_queue()` each frame
    - _Requirements: 6.2, 6.3, 6.4_

  - [x] 3.6 Write property test for server-only spawn processing (Property 3)
    - **Property 3: Server-only spawn processing**
    - Simulate a non-server context; call `_process_spawn_queue()` with a valid request in the queue; assert no RPC is issued and no unit is added to the scene tree
    - **Validates: Requirements 2.1**

  - [x] 3.7 Write property test for invalid request discarding (Property 4)
    - **Property 4: Invalid requests are silently discarded**
    - Generate requests with `team == NONE` and requests with out-of-territory positions (100+ iterations each); assert no unit is added to the scene tree and no RPC is fired
    - **Validates: Requirements 2.2, 2.3, 2.5**

- [x] 4. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Integrate `shop_menu.gd` with the spawn queue
  - [x] 5.1 Add `enqueue_spawn` call in `_process_purchase_request`
    - After the money deduction block, check `if item.category == "Troops":`
    - Retrieve team via `GameState.get_team_for_peer(peer_id)`
    - Call `GameState.enqueue_spawn({ "peer_id": peer_id, "item_id": item.id, "team": team })`
    - Non-troop categories fall through without calling `enqueue_spawn`
    - _Requirements: 1.1, 5.1, 6.1_

  - [x] 5.2 Write property test for troop purchase enqueuing (Property 1)
    - **Property 1: Troop purchase enqueues a well-formed SpawnRequest**
    - Generate random peer IDs and troop item IDs (100+ iterations); call `_process_purchase_request`; assert `enqueue_spawn` was called exactly once with correct `peer_id`, `item_id`, and `team` keys
    - **Validates: Requirements 1.1**

  - [x] 5.3 Write property test for non-troop purchase exclusion (Property 2)
    - **Property 2: Non-troop purchases never enqueue a SpawnRequest**
    - Generate random non-troop items (Defense, Turrets) across 100+ iterations; assert `enqueue_spawn` is never called
    - **Validates: Requirements 5.1**

- [x] 6. Validate spawn queue FIFO ordering
  - [x] 6.1 Write unit test for `enqueue_spawn` / `dequeue_spawn` round-trip
    - Enqueue a known request dict; dequeue; assert returned dict equals original
    - Enqueue on empty queue; assert `dequeue_spawn` returns `{}`
    - _Requirements: 6.1, 6.2_

  - [x] 6.2 Write property test for FIFO ordering (Property 5)
    - **Property 5: Spawn queue preserves FIFO ordering**
    - Enqueue N random SpawnRequests (N between 1–50, 100+ iterations); dequeue all; assert dequeue order matches insertion order
    - **Validates: Requirements 6.2**

- [x] 7. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- All property tests live in `tests/test_unit_spawning.gd` using GdUnit4
- Each property test runs a minimum of 100 iterations
- Each property test is tagged with `# Feature: unit-spawning, Property <N>: <text>`
- The existing `request_spawn_test_unit` / `spawn_test_unit` debug pair in `game.gd` is left unchanged

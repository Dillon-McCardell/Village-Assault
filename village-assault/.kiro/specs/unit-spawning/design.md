# Design Document: Unit Spawning

## Overview

This feature wires the existing shop purchase flow to actual unit instantiation in the game
world. The path is: player clicks a troop in the shop → `ShopMenu` calls
`GameState.enqueue_spawn()` → `game.gd` drains the queue each physics frame (server-only) →
validates team and territory → broadcasts a `spawn_unit` RPC with `call_local` semantics →
every peer instantiates the correct troop scene at the given position.

The design follows the existing `request_spawn_test_unit` / `spawn_test_unit` RPC pattern
already present in `game.gd` and extends it to support four distinct troop types. No new
autoloads or singletons are introduced; all spawn logic lives in `game.gd`.

---

## Architecture

```
ShopMenu (_process_purchase_request)
    │  category == "Troops"?
    ▼
GameState.enqueue_spawn({ peer_id, item_id, team })
    │
    │  (server physics frame)
    ▼
game.gd  _process_spawn_queue()          ← new, called from _physics_process
    │  dequeue one request per frame
    │  validate team != NONE
    │  validate spawn pos in territory
    ▼
game.gd  spawn_unit.rpc(pos, team, item_id)   ← authority, reliable, call_local
    │
    ▼  (all peers, including server)
game.gd  spawn_unit(pos, team, item_id)
    │  look up PackedScene in _troop_scenes
    │  instantiate → set_team(team) → add to Units node
    ▼
Unit node live in scene tree
```

The queue already exists in `GameState` (`_spawn_queue: Array[Dictionary]`) but is unused.
This feature activates it.

---

## Components and Interfaces

### `game.gd` (modified)

New members:
```gdscript
const TROOP_CATEGORY: String = "Troops"

var _troop_scenes: Dictionary = {
    "troop_grunt":  preload("res://scenes/troops/troop_grunt.tscn"),
    "troop_ranger": preload("res://scenes/troops/troop_ranger.tscn"),
    "troop_brute":  preload("res://scenes/troops/troop_brute.tscn"),
    "troop_scout":  preload("res://scenes/troops/troop_scout.tscn"),
}
```

New / changed methods:

| Method | Visibility | Description |
|---|---|---|
| `_physics_process(delta)` | private | Calls `_process_spawn_queue()` when server |
| `_process_spawn_queue()` | private | Dequeues one request, validates, fires RPC |
| `spawn_unit(pos, team, item_id)` | `@rpc authority reliable call_local` | Instantiates unit on all peers |

The existing `request_spawn_test_unit` / `spawn_test_unit` pair is kept unchanged for the
debug spawn button.

### `shop_menu.gd` (modified)

`_process_purchase_request` gains a single block after the money deduction:

```gdscript
if item.category == "Troops":
    var team := GameState.get_team_for_peer(peer_id)
    GameState.enqueue_spawn({
        "peer_id": peer_id,
        "item_id": item.id,
        "team":    team,
    })
```

Non-troop categories fall through without calling `enqueue_spawn`.

### `GameState` (unchanged)

`enqueue_spawn` / `dequeue_spawn` already exist and already guard against non-server calls.
No changes needed.

### `TerritoryManager` (unchanged)

`get_next_spawn_position_for_team(team)` and `is_world_pos_in_team_territory(pos, team)`
are used as-is.

---

## New Files / Scenes

Four troop scenes under `village-assault/scenes/troops/` and four scripts under
`village-assault/scripts/troops/`.

Each troop script extends `test_unit.gd` (or duplicates its logic) and overrides only the
visual polygon and `unit_height`. The base movement, ground-snapping, enemy detection, and
team-coloring logic is inherited unchanged.

```
village-assault/
  scenes/
    troops/
      troop_grunt.tscn
      troop_ranger.tscn
      troop_brute.tscn
      troop_scout.tscn
  scripts/
    troops/
      troop_grunt.gd
      troop_ranger.gd
      troop_brute.gd
      troop_scout.gd
```

---

## Data Models

### SpawnRequest Dictionary

```gdscript
{
    "peer_id": int,    # multiplayer peer who purchased
    "item_id": String, # e.g. "troop_grunt"
    "team":    int,    # GameState.Team.LEFT or RIGHT
}
```

### Item-to-Scene Mapping

```gdscript
var _troop_scenes: Dictionary = {
    "troop_grunt":  <PackedScene>,
    "troop_ranger": <PackedScene>,
    "troop_brute":  <PackedScene>,
    "troop_scout":  <PackedScene>,
}
```

Lookup: `_troop_scenes.get(item_id)` — returns `null` for unknown IDs, which causes the
request to be silently skipped.

---

## Troop Visual Specifications

All troops use a `Polygon2D` node named `Body`, identical to `test_unit.tscn`. The polygon
is a rectangle centered on the origin. `unit_height` is set to match the pixel height so
ground-snapping positions the unit correctly.

| Troop | Width | Height | `unit_height` | Base color (untinted) |
|---|---|---|---|---|
| Grunt  | 16 px | 16 px | 16.0 | Green  `Color(0.2, 0.75, 0.2, 1)` |
| Ranger | 16 px | 32 px | 32.0 | Blue   `Color(0.2, 0.4, 0.9, 1)` |
| Brute  | 32 px | 32 px | 32.0 | Brown  `Color(0.55, 0.35, 0.15, 1)` |
| Scout  | 16 px | 16 px | 16.0 | Yellow `Color(0.95, 0.85, 0.1, 1)` |

The base color is the "NONE team" fallback. Team coloring (LEFT = blue-ish, RIGHT = red-ish)
is applied by `_update_color()` inherited from `test_unit.gd`, which overwrites the base
color. The base color therefore only appears briefly before `set_team` is called, or in
editor preview.

Rectangle polygon for a W×H unit (centered):
```gdscript
PackedVector2Array(-W/2, -H/2,  W/2, -H/2,  W/2, H/2,  -W/2, H/2)
```

---

## Spawn Flow Sequence

```
Client                      Server (game.gd)            All Peers
  │                               │                          │
  │── _on_item_pressed ──────────►│                          │
  │   _request_purchase.rpc_id(1) │                          │
  │                               │                          │
  │                  _process_purchase_request()             │
  │                  deduct money                            │
  │                  category == "Troops"?                   │
  │                  GameState.enqueue_spawn(request)        │
  │                               │                          │
  │              (next physics frame)                        │
  │                  _process_spawn_queue()                  │
  │                  dequeue one request                     │
  │                  validate team != NONE                   │
  │                  get_next_spawn_position_for_team()      │
  │                  is_world_pos_in_team_territory()?       │
  │                               │                          │
  │                  spawn_unit.rpc(pos, team, item_id) ────►│
  │                               │◄────────────────────────│
  │                               │  (call_local: server     │
  │                               │   also executes)         │
  │                               │                          │
  │                          instantiate scene               │
  │                          set_team(team)                  │
  │                          units_root.add_child(unit)      │
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions
of a system — essentially, a formal statement about what the system should do. Properties
serve as the bridge between human-readable specifications and machine-verifiable correctness
guarantees.*

### Property 1: Troop purchase enqueues a well-formed SpawnRequest

*For any* valid troop item purchase by any peer, `GameState.enqueue_spawn` is called exactly
once with a dictionary containing the keys `peer_id` (matching the buyer), `item_id`
(matching the item), and `team` (matching the peer's assigned team).

**Validates: Requirements 1**

---

### Property 2: Non-troop purchases never enqueue a SpawnRequest

*For any* item whose `category` is not `"Troops"` (Defense, Turret, etc.), completing a
purchase must not result in any call to `GameState.enqueue_spawn`.

**Validates: Requirements 5**

---

### Property 3: Server-only spawn processing

*For any* SpawnRequest in the queue, the spawn RPC is only issued when the processing node
is running as the server (`multiplayer.is_server() == true`). A non-server peer that somehow
calls `_process_spawn_queue` must produce no side effects.

**Validates: Requirements 2**

---

### Property 4: Invalid requests are silently discarded

*For any* SpawnRequest where the team is `NONE`, or where the resolved spawn position is
outside the team's territory, no `spawn_unit` RPC is issued and no unit is added to the
scene tree.

**Validates: Requirements 2**

---

### Property 5: Spawn queue preserves FIFO ordering

*For any* sequence of SpawnRequests enqueued via `GameState.enqueue_spawn`, successive calls
to `GameState.dequeue_spawn` must return them in the same order they were enqueued.

**Validates: Requirements 6**

---

### Property 6: Item-to-scene mapping is total over troop IDs

*For each* of the four troop item IDs (`"troop_grunt"`, `"troop_ranger"`, `"troop_brute"`,
`"troop_scout"`), the `_troop_scenes` dictionary must return a non-null `PackedScene`.
Any item ID not in this set must return `null`.

**Validates: Requirements 4, 5**

---

## Error Handling

| Condition | Handling |
|---|---|
| `team == GameState.Team.NONE` | Skip request silently; no RPC fired |
| Spawn position outside territory | Skip request silently; no RPC fired |
| `item_id` not in `_troop_scenes` | Skip request silently (`dict.get` returns null) |
| Queue empty on dequeue | `dequeue_spawn` returns `{}`; `_process_spawn_queue` checks for empty dict |
| `enqueue_spawn` called on client | `GameState.enqueue_spawn` already guards with `is_server()` check |

No error dialogs or player-facing messages are shown for spawn failures — they are silent
server-side discards, consistent with the existing pattern.

---

## Testing Strategy

### Unit Tests

Focus on specific examples and edge cases:

- `GameState.enqueue_spawn` / `dequeue_spawn` round-trip with a known request dict
- `dequeue_spawn` on an empty queue returns `{}`
- `_process_purchase_request` with a troop item calls `enqueue_spawn` (mock)
- `_process_purchase_request` with a defense item does not call `enqueue_spawn` (mock)
- `_troop_scenes` contains all four troop IDs and no entry returns null

### Property-Based Tests

Use a GDScript property-based testing library (e.g. **GdUnit4** with fuzz helpers, or a
lightweight custom generator). Each property test runs a minimum of **100 iterations**.

Each test is tagged with a comment in the format:
`# Feature: unit-spawning, Property <N>: <property_text>`

| Property | Test description |
|---|---|
| Property 1 | Generate random peer IDs and troop items; verify enqueue_spawn dict keys/values |
| Property 2 | Generate random non-troop items; verify enqueue_spawn is never called |
| Property 3 | Simulate non-server context; verify no RPC or scene instantiation occurs |
| Property 4 | Generate requests with NONE team or out-of-bounds positions; verify no unit added |
| Property 5 | Enqueue N random requests; dequeue all; verify order matches insertion order |
| Property 6 | Iterate all four troop IDs; assert non-null scene; iterate non-troop IDs; assert null |

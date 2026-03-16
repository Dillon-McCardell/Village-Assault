# Requirements Document

## Introduction

This feature connects the shop purchase flow to actual unit spawning in the game world.
When a player buys a troop from the shop, the server validates the purchase, resolves a
spawn position inside the buyer's territory, and replicates the unit instantiation to all
connected clients. The feature covers the full round-trip: purchase → server validation →
spawn RPC → unit instantiation on every peer.

Only items in the **Troops** category (Grunt, Ranger, Brute, Scout) are in scope for
spawning as mobile units. Defense and Turret items are out of scope for this feature.

## Glossary

- **SpawnSystem**: The server-side subsystem responsible for validating purchase requests
  and issuing spawn RPCs. Lives in `game.gd` or a dedicated autoload.
- **ShopMenu**: The existing UI node (`shop_menu.gd`) that handles player purchase input
  and sends purchase requests to the server.
- **GameState**: The existing autoload (`game_state.gd`) that tracks peer teams, money,
  and the spawn queue.
- **TerritoryManager**: The existing node (`territory_manager.gd`) that owns terrain data
  and exposes spawn position queries.
- **Unit**: A mobile game entity instantiated from a scene that corresponds to a purchased
  troop item (Grunt, Ranger, Brute, Scout).
- **SpawnRequest**: A Dictionary passed through `GameState.enqueue_spawn()` containing at
  minimum `peer_id`, `item_id`, and `team`.
- **Peer**: A connected multiplayer participant identified by a unique integer ID.
- **Server**: The authoritative ENet host (peer ID 1) that processes all game logic.
- **Client**: Any non-server peer that receives replicated state via RPC.

---

## Requirements

### Requirement 1: Purchase-Triggered Spawn Request

**User Story:** As a player, I want buying a troop from the shop to spawn that unit in the
game world, so that my purchase has an immediate visible effect.

#### Acceptance Criteria

1. WHEN a player completes a valid troop purchase, THE ShopMenu SHALL call
   `GameState.enqueue_spawn()` with a SpawnRequest containing the purchasing peer's ID,
   the item ID, and the peer's assigned team.
2. THE SpawnSystem SHALL process only SpawnRequests whose `item_id` maps to a known troop
   scene (Grunt, Ranger, Brute, or Scout).
3. IF a SpawnRequest contains an `item_id` that does not map to a known troop scene, THEN
   THE SpawnSystem SHALL discard the request without spawning any unit.

---

### Requirement 2: Server-Side Spawn Validation

**User Story:** As a game developer, I want all spawn decisions to be made on the server,
so that clients cannot cheat by spawning units without paying.

#### Acceptance Criteria

1. THE SpawnSystem SHALL process SpawnRequests only when running on the server
   (`multiplayer.is_server()` is true).
2. WHEN the SpawnSystem processes a SpawnRequest, THE SpawnSystem SHALL verify that the
   requesting peer has an assigned team other than `GameState.Team.NONE` before spawning.
3. IF the requesting peer's team is `GameState.Team.NONE`, THEN THE SpawnSystem SHALL
   discard the SpawnRequest without spawning any unit.
4. THE SpawnSystem SHALL resolve the spawn position by calling
   `TerritoryManager.get_next_spawn_position_for_team(team)` using the team stored in the
   SpawnRequest.
5. WHEN the resolved spawn position is not inside the requesting team's territory according
   to `TerritoryManager.is_world_pos_in_team_territory(pos, team)`, THE SpawnSystem SHALL
   discard the SpawnRequest without spawning any unit.

---

### Requirement 3: Replicated Unit Instantiation

**User Story:** As a player, I want spawned units to appear on all connected clients
simultaneously, so that every player sees the same game state.

#### Acceptance Criteria

1. WHEN the SpawnSystem approves a SpawnRequest, THE SpawnSystem SHALL broadcast a spawn
   RPC to all peers (including the server itself) using `call_local` semantics.
2. THE spawn RPC SHALL carry the resolved spawn position (Vector2), the team (int), and
   the item ID (String) as parameters.
3. WHEN a peer receives the spawn RPC, THE peer SHALL instantiate the correct unit scene
   that corresponds to the item ID and add it to the `Units` node in the scene tree.
4. WHEN a peer receives the spawn RPC, THE peer SHALL set the unit's team by calling
   `set_team(team)` on the instantiated unit before adding it to the scene tree.
5. WHEN a peer receives the spawn RPC, THE peer SHALL set the unit's position to the
   spawn position carried in the RPC before adding it to the scene tree.

---

### Requirement 4: Item-to-Scene Mapping

**User Story:** As a developer, I want a single authoritative mapping from item IDs to
unit scenes, so that the SpawnSystem always instantiates the correct scene for each troop.

#### Acceptance Criteria

1. THE SpawnSystem SHALL maintain a Dictionary that maps each troop item ID string to its
   corresponding `PackedScene`.
2. THE SpawnSystem SHALL include entries for all four troop types: Grunt, Ranger, Brute,
   and Scout.
3. WHEN a new troop type is added to the shop, THE SpawnSystem SHALL require only a single
   entry added to the mapping Dictionary to support spawning that troop.

---

### Requirement 5: Non-Troop Items Are Not Spawned

**User Story:** As a developer, I want Defense and Turret shop items to be silently
ignored by the spawn system, so that purchasing them does not cause errors or unexpected
behaviour.

#### Acceptance Criteria

1. WHEN a player purchases an item whose category is "Defense" or "Turrets", THE ShopMenu
   SHALL NOT enqueue a SpawnRequest for that item.
2. IF a SpawnRequest for a non-troop item reaches THE SpawnSystem, THEN THE SpawnSystem
   SHALL discard it without spawning any unit and without emitting an error.

---

### Requirement 6: Spawn Queue Integration

**User Story:** As a developer, I want spawn requests to flow through the existing
`GameState` spawn queue, so that the architecture remains consistent with the established
pattern.

#### Acceptance Criteria

1. THE ShopMenu SHALL enqueue SpawnRequests via `GameState.enqueue_spawn()` immediately
   after a successful purchase money deduction.
2. THE SpawnSystem SHALL dequeue and process SpawnRequests via `GameState.dequeue_spawn()`
   each frame while the queue is non-empty.
3. WHILE the spawn queue is empty, THE SpawnSystem SHALL perform no spawn processing that
   frame.
4. THE SpawnSystem SHALL process at most one SpawnRequest per physics frame to avoid
   instantiating multiple units in a single frame.

---

### Requirement 7: Troop Visual Differentiation

**User Story:** As a player, I want each troop type to have a distinct size and colour
when spawned, so that I can visually identify troop types at a glance during gameplay.

#### Acceptance Criteria

1. WHEN a Grunt unit is instantiated, THE Unit SHALL have a sprite size of 16×16 px and a
   colour of green.
2. WHEN a Ranger unit is instantiated, THE Unit SHALL have a sprite size of 16×32 px and a
   colour of blue.
3. WHEN a Brute unit is instantiated, THE Unit SHALL have a sprite size of 32×32 px and a
   colour of brown.
4. WHEN a Scout unit is instantiated, THE Unit SHALL have a sprite size of 16×16 px and a
   colour of yellow.

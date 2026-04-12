# Village Assault

<img width="573" height="323" alt="image" src="https://github.com/user-attachments/assets/2ab7527e-8251-4231-9b59-a645a8710ca3" />


A 2-player multiplayer side-on, block-based game built with Godot 4 and GDScript. Players each control one side of a village, purchasing troops, defenses, and turrets to assault the opposing side.

## Prerequisites

- [Godot 4.5+](https://godotengine.org/download) (standard build, no .NET required)

## Getting Started

1. Open Godot 4 and import the project at `./village-assault/` (the folder containing `project.godot`).
2. Run the project — the main scene is the Boot Menu (`res://scenes/boot_menu.tscn`).

## How to Play

1. One player clicks **Host** to start a server.
2. The second player clicks **Join** and enters the host's IP (defaults to `127.0.0.1` for local play).
3. Both players land in the Lobby. The host clicks **Start** when ready.
4. In-game, purchase troops from the shop to attack the opposing side.
5. Troops now use their shop `health`, `damage`, and `defense` stats in combat. When opposing troops meet, they stop, exchange hits, and the survivor resumes marching.

### Disconnect Handling

If the client disconnects mid-game, the host's game pauses and waits indefinitely for the client to reconnect. The client can rejoin from the boot menu and their team/money state is restored, including active troop replication when they return to the game. If the host disconnects, the client sees a notification and auto-reconnects every 5 seconds.

### Pause Menu

Press **ESC** to pause the game for both players. The pausing player sees a menu with Settings (placeholder), Main Menu, and Back. The other player sees "The other player has paused the game." Press ESC again or click Back to unpause.

### Debug Disconnect (F9)

Press **F9** to simulate a network disconnect without closing the window. Press F9 again to reconnect. The host re-hosts on the same port; the client rejoins the last host address. Both sides pause and show an overlay during the disconnect. Useful for testing disconnect/reconnect flows.

### Debug Spawn Button

The in-game **Spawn Test Unit** button spawns a free troop for the local player's team. It uses the grunt troop's runtime combat stats, but does not deduct money.

## Architecture

```
scenes/
  boot_menu.tscn    — Host/Join menu
  lobby.tscn        — Pre-game waiting room
  game.tscn         — Main gameplay
  troops/           — Troop unit scenes
  ui/               — Reusable UI (disconnect overlay, pause menu)

scripts/
  game_state.gd     — Autoload: peer teams, money, spawn queue, disconnect state
  network/
    network_manager.gd — Autoload: ENet connection, reconnection, F9 debug toggle
  debug_console.gd  — Autoload: on-screen debug logging
  boot_menu.gd      — Boot menu scene logic
  lobby.gd          — Lobby scene logic
  game.gd           — Game scene: host-authoritative troop spawning, pause/unpause, disconnect overlays, ESC menu
  camera/           — Camera controller
  shop/             — Shop items (troops, defenses, turrets)
  troops/           — Troop behavior scripts
  ui/               — UI scripts (shop menu, disconnect overlay, pause menu)
  world/            — Territory management

tests/              — GdUnit4 property-based tests
```

Three autoloads are registered in `project.godot`:

| Autoload | Purpose |
|---|---|
| `NetworkManager` | ENet peer creation, host/join, reconnection, F9 debug disconnect |
| `GameState` | Authoritative game state: team assignments, money, spawn queue, inactive peer tracking, scene redirect |
| `DebugConsole` | On-screen debug log overlay (visible below the game viewport) |

## Testing

Testing instructions, GdUnit4 suite coverage, and the reconnection acceptance
harness are documented in [TESTING.md](./TESTING.md).

## Known Limitations

- Troops now use Godot's built-in multiplayer scene replication for spawn, despawn, and reconnect visibility. Non-troop world objects still use their existing local logic.

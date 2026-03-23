# Implementation Plan: Player Disconnect Handling

## Overview

Implement graceful disconnect handling, in-game pause menu, and debug disconnect tooling for Village Assault's 2-player multiplayer game. Changes are scoped to `GameState`, `NetworkManager`, scene scripts (`game.gd`, `lobby.gd`, `boot_menu.gd`), and new UI components (`DisconnectOverlay`, `PauseMenu`). All authoritative state lives on the host; the client displays UI and attempts reconnection.

## Tasks

- [x] 1. Extend GameState with inactive peer tracking
  - [x] 1.1 Add new signals and state variables to `game_state.gd`
  - [x] 1.2 Modify `_on_peer_disconnected` to preserve state instead of erasing
  - [x] 1.3 Modify `_count_team` to include inactive peers
  - [x] 1.4 Add `try_restore_peer(new_peer_id)` and `clear_inactive_peer(peer_id)`
  - [x] 1.5 Modify `_on_peer_connected` to attempt restore before fresh assignment
  - [x] 1.6 Add `current_scene` tracking and `_receive_scene_redirect` RPC
  - [x] 1.7 Add `reset_all()` for session cleanup
  - [x] 1.8 Detect re-host in `_on_host_started` to skip world settings broadcast
  - [x] 1.9 Write property tests for GameState disconnect/reconnect logic

- [x] 2. Extend NetworkManager with reconnection support
  - [x] 2.1 Add reconnect state, signals, and `process_mode = ALWAYS`
  - [x] 2.2 Store last host address/port in `join()`; store host params in `host()`
  - [x] 2.3 Implement `attempt_reconnect()`, `start_auto_reconnect()`, `stop_auto_reconnect()`
  - [x] 2.4 Modify `_on_connected_to_server` and `_on_connection_failed` for reconnect flow
  - [x] 2.5 Implement `simulate_disconnect()` with manual `_on_peer_disconnected` for remote peers
  - [x] 2.6 Add F9 toggle handler (role-aware: re-host vs rejoin)
  - [x] 2.7 Add `local_disconnected` signal
  - [x] 2.8 Skip `_reset_local_state` / `_reset_world_settings` in `_on_join_started` when reconnecting

- [x] 3. Create DisconnectOverlay UI component
  - [x] 3.1 Create `scenes/ui/disconnect_overlay.tscn` and `scripts/ui/disconnect_overlay.gd`
  - [x] 3.2 Implement differentiated messages: `show_client_left`, `show_client_disconnected`, `show_host_left`, `show_host_disconnected`, `show_self_disconnected`
  - [x] 3.3 Set `mouse_filter = IGNORE` on all non-button elements; stop background 160px from bottom

- [x] 4. Create PauseMenu UI component
  - [x] 4.1 Create `scenes/ui/pause_menu.tscn` and `scripts/ui/pause_menu.gd`
  - [x] 4.2 Implement `show_pause_menu()` and `show_remote_paused()` display modes
  - [x] 4.3 Handle ESC key directly in PauseMenu `_unhandled_input` (works while paused)
  - [x] 4.4 Set `mouse_filter = IGNORE` on non-button elements; stop background 160px from bottom

- [x] 5. Integrate disconnect handling into Game scene
  - [x] 5.1 Add DisconnectOverlay and PauseMenu to `game.gd`
  - [x] 5.2 Connect all disconnect/reconnect signals
  - [x] 5.3 Implement pause on disconnect and unpause on reconnect for all cases
  - [x] 5.4 Track `_peer_left_intentionally` via `_notify_leaving` RPC for message differentiation
  - [x] 5.5 Implement ESC pause with server-authoritative `_set_paused` RPC
  - [x] 5.6 Wire Main Menu from pause: send `_notify_leaving`, wait, disconnect
  - [x] 5.7 Clear all overlays on reconnect; reset camera anchor

- [x] 6. Integrate disconnect handling into Lobby scene
  - [x] 6.1 Add DisconnectOverlay to `lobby.gd` and connect signals
  - [x] 6.2 Wire overlay buttons and auto-reconnect

- [x] 7. Update Boot Menu
  - [x] 7.1 Add `class_name BootMenu` with static `return_status_message`
  - [x] 7.2 Call `reset_all()` → `host()` → `set_world_settings()` (correct order)
  - [x] 7.3 Skip lobby redirect when `_is_reconnecting`
  - [x] 7.4 Set `GameState.current_scene = "boot_menu"` in `_ready()`

- [x] 8. Set DebugLayer `process_mode = ALWAYS` in game.tscn

- [x] 9. Write property-based tests
  - [x] 9.1 State preservation on disconnect (Property 1)
  - [x] 9.2 Team reservation during inactive state (Property 2)
  - [x] 9.3 State restoration round-trip (Property 3)
  - [x] 9.4 Fresh state after clearing inactive peer (Property 4)
  - [x] 9.5 State erasure on clear (Property 5)
  - [x] 9.6 Pause/unpause round-trip (Property 6)

- [x] 10. Final verification — All 15 tests pass (6 disconnect + 9 unit spawning)

## Post-Implementation Fixes

The following issues were discovered during manual testing and fixed iteratively:

1. **Client lands in lobby instead of game on reconnect**: Fixed by adding `GameState.current_scene` tracking and `_receive_scene_redirect` RPC. Each scene sets `current_scene` in `_ready()`. On restore, host sends redirect to client.

2. **Countdown timer doesn't tick while paused**: Removed the reconnect window timer entirely. The host now waits indefinitely for the client.

3. **Map regenerates on each reconnect attempt**: Fixed by guarding `_on_join_started` to skip `_reset_local_state`/`_reset_world_settings` when `_is_reconnecting`.

4. **Stale peer on reconnect**: `attempt_reconnect()` now closes and nulls the old peer before creating a new connection.

5. **Host disconnect is unrecoverable but client should auto-reconnect**: Client now starts auto-reconnect on `server_disconnected` so it picks up the host if it comes back.

6. **F9 doesn't pause the local game**: Added `local_disconnected` signal emitted by `simulate_disconnect()`. Game scene listens for it and pauses + shows overlay.

7. **F9 re-host doesn't populate `_inactive_peers`**: `peer.close()` + nulling `multiplayer_peer` races with Godot's disconnect callbacks. Fixed by manually calling `GameState._on_peer_disconnected()` for all remote peers in `simulate_disconnect()` before nulling.

8. **Camera jumps on F9 re-host**: `_on_host_started` was re-sending world settings, causing terrain rebuild. Fixed by detecting re-host (peer 1 already in `_peer_team`) and skipping the broadcast.

9. **Double overlays on Main Menu from pause**: Fixed by hiding pause menu before showing disconnect overlay in all disconnect handlers, and sending `_notify_leaving` RPC before disconnecting.

10. **ESC doesn't unpause**: `_unhandled_input` on game node doesn't fire while paused. Fixed by handling ESC directly in PauseMenu's own `_unhandled_input` (which has `process_mode = ALWAYS`).

11. **Overlays block debug console**: Fixed by setting `mouse_filter = IGNORE` on all non-button overlay elements and stopping the background 160px from the bottom. Set DebugLayer `process_mode = ALWAYS` so it stays interactive while paused.

12. **Stale session data on new game**: Added `GameState.reset_all()` called from boot menu before hosting. Fixed call order: `reset_all()` → `host()` → `set_world_settings()`.

13. **`set_world_settings` error before peer exists**: Fixed by calling `host()` before `set_world_settings()` in boot menu.

## Known Limitations (Fix Later)

1. **Troop state not synced on reconnect**: Spawned units are fire-and-forget RPCs. A reconnecting client won't see troops spawned while disconnected. Requires MultiplayerSpawner or snapshot RPC.

2. **Troop desync after F9 disconnect/reconnect**: Same root cause as above. Both host and client may see different troop positions after a disconnect cycle.

## Notes

- Property tests use GdUnit4 with `RandomNumberGenerator` loops of 100 iterations for broad input coverage
- All authoritative state lives on the host; client only displays UI and retries connection
- Debug logging via `DebugConsole.log_msg` is present in key GameState and game.gd handlers for troubleshooting

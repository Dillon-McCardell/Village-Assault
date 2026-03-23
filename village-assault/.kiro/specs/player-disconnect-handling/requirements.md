# Requirements Document

## Introduction

Village Assault is a 2-player multiplayer game (host + 1 client) built with Godot 4 and ENet. Currently, when a player disconnects, the peer state is immediately erased and no reconnection is possible. This feature adds graceful disconnect handling, in-game disconnect notifications for both players, reconnection support that restores the disconnected player's state (team, money), an in-game pause menu, and a debug disconnect tool for testing.

## Glossary

- **Host**: The player running the ENet server (peer ID 1) via NetworkManager
- **Client**: The player connected to the Host via ENet (peer ID assigned by Godot multiplayer)
- **NetworkManager**: Autoload singleton responsible for creating and managing the ENetMultiplayerPeer connection
- **GameState**: Autoload singleton that tracks peer teams, money, and spawn queues
- **DisconnectOverlay**: An in-game UI overlay displayed to inform a player about a disconnect event
- **PauseMenu**: An in-game UI overlay displayed when a player presses ESC to pause
- **Peer_State**: The collection of data associated with a connected player, including team assignment and money
- **Game_Scene**: The main gameplay scene where units are spawned and territory is managed
- **Lobby_Scene**: The pre-game scene where players wait before the Host starts the game
- **Boot_Menu**: The initial menu scene where players choose to host or join a game

## Requirements

### Requirement 1: Preserve Peer State on Disconnect

**User Story:** As a player, I want my game state to be preserved when I disconnect, so that I can resume where I left off if I reconnect.

#### Acceptance Criteria

1. WHEN a Client disconnects, THE GameState SHALL retain the disconnected Client's Peer_State (team assignment and money) instead of erasing the Peer_State.
2. WHEN a Client disconnects, THE GameState SHALL mark the disconnected Client's Peer_State as inactive rather than removing the Peer_State.
3. WHILE a disconnected Client's Peer_State is marked inactive, THE GameState SHALL prevent new players from being assigned to the disconnected Client's team.

### Requirement 2: Disconnect Notification for Host

**User Story:** As the host, I want to be notified when the client disconnects, so that I know the game is interrupted and can wait for the client to reconnect.

#### Acceptance Criteria

1. WHEN the Client disconnects during the Game_Scene, THE Game_Scene SHALL display a DisconnectOverlay to the Host.
2. WHEN the Client disconnects during the Lobby_Scene, THE Lobby_Scene SHALL display a DisconnectOverlay to the Host.
3. THE DisconnectOverlay SHALL differentiate between intentional departure ("The Client has left the game") and network disconnection ("The Client disconnected").
4. THE DisconnectOverlay SHALL include a "Main Menu" button to return to the Boot_Menu.

### Requirement 3: Disconnect Notification for Client

**User Story:** As a client, I want to be notified when I lose connection to the host, so that I understand why the game is interrupted.

#### Acceptance Criteria

1. WHEN the Host becomes unreachable, THE Game_Scene SHALL display a DisconnectOverlay to the Client.
2. WHEN the Host becomes unreachable during the Lobby_Scene, THE Lobby_Scene SHALL display a DisconnectOverlay to the Client.
3. THE DisconnectOverlay SHALL differentiate between intentional departure ("The Host has left the game") and network disconnection ("The Host disconnected").
4. THE Client SHALL automatically attempt reconnection every 5 seconds when the Host disconnects.
5. THE DisconnectOverlay SHALL include a "Main Menu" button to return to the Boot_Menu.

### Requirement 4: Client Reconnection

**User Story:** As a client, I want to reconnect to the host after a disconnect, so that I can continue the game without losing my progress.

#### Acceptance Criteria

1. WHEN a Client reconnects to the Host, THE GameState SHALL restore the Client's previous Peer_State including team assignment and money.
2. WHEN a Client reconnects to the Host, THE NetworkManager SHALL re-associate the new peer ID with the previously stored Peer_State.
3. WHEN a Client reconnects successfully, THE Game_Scene SHALL remove all overlays from both the Host and the Client and unpause.
4. THE Host SHALL wait indefinitely for the Client to reconnect (no time limit).
5. WHEN a Client reconnects, THE Host SHALL send a scene redirect RPC to ensure the Client loads the correct scene.

### Requirement 5: Session Reset on New Game

**User Story:** As a host, I want to start a fresh game without stale data from a previous session.

#### Acceptance Criteria

1. WHEN the Host starts a new game from the Boot_Menu, THE GameState SHALL clear all peer data, inactive peers, and spawn queues via `reset_all()`.
2. THE Boot_Menu SHALL call `host()` before `set_world_settings()` to ensure the multiplayer peer exists before broadcasting.

### Requirement 6: Host Disconnect Handling

**User Story:** As a client, I want the game to handle the host disconnecting, so that I can attempt to reconnect or return to the menu.

#### Acceptance Criteria

1. WHEN the Host disconnects, THE Client SHALL remain on the current scene and display a DisconnectOverlay.
2. THE Client SHALL attempt automatic reconnection to the Host's address at a regular interval of 5 seconds.
3. WHEN the Client successfully reconnects to the Host, THE Game_Scene SHALL resume normal gameplay and remove the DisconnectOverlay.
4. THE Client MAY return to the Boot_Menu at any time via the "Main Menu" button.

### Requirement 7: Game Pause on Disconnect

**User Story:** As a player, I want the game to pause when the other player disconnects, so that neither side gains an unfair advantage during the interruption.

#### Acceptance Criteria

1. WHEN a player disconnects during the Game_Scene, THE Game_Scene SHALL pause game logic for both players.
2. WHEN the disconnected player reconnects, THE Game_Scene SHALL resume game logic for both players.
3. WHEN a player presses F9 to simulate a disconnect, THE local Game_Scene SHALL also pause.

### Requirement 8: In-Game Pause Menu

**User Story:** As a player, I want to pause the game via ESC to access settings or return to the main menu.

#### Acceptance Criteria

1. WHEN a player presses ESC during the Game_Scene, THE game SHALL pause for both players via server-authoritative RPC.
2. THE player who pressed ESC SHALL see a PauseMenu with Settings, Main Menu, and Back buttons.
3. THE other player SHALL see a message "The other player has paused the game."
4. WHEN the pausing player presses Back or ESC again, THE game SHALL unpause for both players.
5. WHEN the pausing player presses Main Menu, THE game SHALL notify the other player via RPC, then disconnect and return to Boot_Menu.
6. THE Settings button SHALL be present but non-functional (placeholder for future use).

### Requirement 9: Intentional vs Network Disconnect Differentiation

**User Story:** As a player, I want to know whether the other player left intentionally or lost connection.

#### Acceptance Criteria

1. WHEN a player leaves via Main Menu, THE remaining player SHALL see "The [Host/Client] has left the game."
2. WHEN a player disconnects due to network issues, THE remaining player SHALL see "The [Host/Client] disconnected."
3. WHEN a player presses F9 to simulate a disconnect, THE local player SHALL see "You have disconnected. Reconnecting..."

### Requirement 10: Debug Disconnect Tool

**User Story:** As a developer, I want to simulate network disconnects without closing the game window, so that I can test disconnect handling.

#### Acceptance Criteria

1. PRESSING F9 SHALL toggle between disconnect and reconnect states.
2. IF the player is connected, F9 SHALL simulate a network disconnect by closing the ENet peer.
3. IF the player is disconnected, F9 SHALL reconnect (re-host for host, rejoin for client).
4. THE F9 handler SHALL be role-aware: host re-hosts on the same port, client rejoins the last host address.
5. WHEN the host simulates a disconnect, THE NetworkManager SHALL manually trigger `_on_peer_disconnected` for all remote peers to ensure `_inactive_peers` is populated correctly.
6. F9 actions SHALL be logged to the DebugConsole overlay.

## Known Limitations

1. Troop state is not synchronized on reconnect. When a client disconnects and reconnects, they will not see troops that were spawned while they were disconnected. This requires a troop resync mechanism (e.g., MultiplayerSpawner or snapshot RPC) which is planned as a future feature.

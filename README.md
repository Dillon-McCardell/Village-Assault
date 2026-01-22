# Village Assault

A 2D multiplayer side-on, block-based game built in Godot 4.

## Open the Project

1. Open Godot 4.x.
2. Import the project at `./village-assault/` (select the folder containing `project.godot`).
3. Run the project (main scene is `res://scenes/game.tscn`).

## Multiplayer Test (Host/Join)

The minimal networking slice uses an autoloaded `NetworkManager`.

- Host: In the Godot output console, run `NetworkManager.host()`.
- Join: In another instance, run `NetworkManager.join("127.0.0.1")` (replace with host IP if needed).

Once connected, press **Spawn Test Unit** to request a server-authoritative spawn that broadcasts to all peers.

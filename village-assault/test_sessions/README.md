# Custom Test Sessions

Custom test sessions launch a deterministic game directly from a JSON map and troop
description. They use the normal lobby, multiplayer spawner, terrain manager, and game
scene, so they are suitable for visual QA and multiplayer reproduction cases.

From the repository root, launch one local player:

```sh
./tools/run_test_session.py village-assault/test_sessions/fog_cavern.json
```

Launch host and client windows against the same scenario:

```sh
./tools/run_test_session.py village-assault/test_sessions/fog_cavern.json --players 2
```

Use `--headless --exit-after-ready` for an automated setup smoke test. Event and process
logs are written to the artifact directory printed by the launcher.

## Scenario Schema

The `map` object requires positive `width` and `height` values and accepts a deterministic
`seed`. Set either `surface_y` for a flat map or `surface_heights` with one height per map
column. Omitting both retains the seeded procedural surface.

`map.carve` and `map.fill` accept three shape lists:

```json
{
  "tiles": [[4, 8], [5, 8]],
  "rects": [{"position": [8, 10], "size": [12, 4]}],
  "lines": [{"from": [4, 8], "to": [10, 14], "thickness": 2}]
}
```

Coordinates are tile coordinates. Fill shapes are applied after carve shapes, which makes
it possible to add supports or terrain islands inside a carved region.

Each troop entry supports `type`, `team`, `tile`, optional `unit_id`, optional `frozen`,
and optional `spawn_payload` overrides. `tile` is the troop's standing air tile. Supported
types are `troop_grunt`, `troop_ranger`, `troop_brute`, `troop_scout`, and `troop_miner`.

```json
{
  "type": "troop_scout",
  "team": "left",
  "tile": [12, 16],
  "unit_id": 101,
  "frozen": true,
  "spawn_payload": {"vision_radius_tiles": 6.0}
}
```

Camera settings may define a `default` preset and override it with `host` or `client`.
Each preset accepts a center `tile` and scalar `zoom`.

extends Node2D
class_name TerritoryManager

signal tile_destroyed(tile_pos: Vector2i)
signal ore_revealed_for_team(team: int, tiles: Array)
signal ore_depleted(tile_pos: Vector2i)

@export var grid_width: int = 64
@export var grid_height: int = 20
@export var tile_size: int = 16
@export_range(0.05, 0.45, 0.05) var left_territory_ratio: float = 0.2
@export_range(0.05, 0.45, 0.05) var right_territory_ratio: float = 0.2

@export var base_flat_width: int = 10
@export var base_surface_height: int = 8
@export var min_surface_height: int = 6
@export var max_surface_height: int = 12
@export_range(0.0, 1.0, 0.05) var roughness: float = 0.6
@export var max_step: int = 2
@export var smooth_passes: int = 2
@export var terrain_seed: int = 0
@export var gold_min_depth_below_surface: int = 3
@export var gold_window_size: int = 10
@export var gold_max_per_window: int = 2
@export_range(0.0, 1.0, 0.01) var gold_target_ratio: float = 0.03

@onready var tile_map: TileMap = $WorldTileMap

var _spawn_offsets: Dictionary = {
	GameState.Team.LEFT: 0,
	GameState.Team.RIGHT: 0,
}

var _heightmap: Array[int] = []
var _gold_tiles: Dictionary = {}
var _tile_health: Dictionary = {}
var _ore_health: Dictionary = {}
var _depleted_ore_tiles: Dictionary = {}
var _revealed_ore_tiles_by_team: Dictionary = {}
var _resolved_terrain_seed: int = 0
var _harvest_queue_overlay_tiles: Array[Vector2i] = []
var _harvest_queue_overlay_visible: bool = false

const MAX_MINER_OVERLAY_LAYERS: int = 6
const TILE_HEALTH_DEFAULT: int = 2
const TERRAIN_LAYER: int = 0
const RESOURCE_LAYER: int = 1
const UNDERGROUND_LAYER: int = 2
const MINING_DRAFT_LAYER: int = 3
const MINING_INVALID_LAYER: int = 4
const MINING_COMMITTED_LAYER_START: int = 5
const MINING_COMMITTED_LAYER: int = MINING_COMMITTED_LAYER_START
const MINING_COMMITTED_LAYER_END: int = MINING_COMMITTED_LAYER_START + MAX_MINER_OVERLAY_LAYERS - 1
const GOLD_SEED_SALT: int = 7919
const TILE_DIRT: Vector2i = Vector2i(0, 0)
const TILE_GRASS: Vector2i = Vector2i(1, 0)
const TILE_GOLD: Vector2i = Vector2i(2, 0)
const TILE_UNDERGROUND: Vector2i = Vector2i(3, 0)
const MINING_DRAFT_ALPHA: float = 0.45
const MINING_COMMITTED_ALPHA: float = 0.25
const MINING_INVALID_COLOR: Color = Color(0.86, 0.18, 0.18, 0.75)
const UNDERGROUND_COLOR: Color = Color(0.27, 0.16, 0.08, 1.0)
const ORE_HEALTH_DEFAULT: int = 100
const HARVEST_QUEUE_TEXT_COLOR: Color = Color(0, 0, 0, 1)
const HARVEST_QUEUE_FONT_SIZE: int = 16

func _ready() -> void:
	GameState.world_settings_updated.connect(_on_world_settings_updated)
	_apply_world_settings()
	_ensure_tilemap_layers()
	_ensure_tileset()
	_build_terrain()

func _draw() -> void:
	if not _harvest_queue_overlay_visible:
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	for i in range(_harvest_queue_overlay_tiles.size()):
		var tile := _harvest_queue_overlay_tiles[i]
		var center := tile_to_world_center(tile) + Vector2(0, 5)
		draw_string(
			font,
			center,
			str(i + 1),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1.0,
			HARVEST_QUEUE_FONT_SIZE,
			HARVEST_QUEUE_TEXT_COLOR
		)

func is_world_pos_in_team_territory(world_pos: Vector2, team: int) -> bool:
	var tile := world_to_tile(world_pos)
	if tile.x < 0 or tile.y < 0 or tile.x >= grid_width or tile.y >= grid_height:
		return false
	var bounds := _get_team_bounds(team)
	return bounds.has_point(tile)

func get_next_spawn_position_for_team(team: int) -> Vector2:
	var bounds := _get_team_bounds(team)
	if bounds.size.x <= 0:
		return Vector2.ZERO
	var offset: int = int(_spawn_offsets.get(team, 0))
	var spawn_x: int = bounds.position.x + int(offset % bounds.size.x)
	var surface_y: int = _get_surface_height(spawn_x)
	var spawn_y: int = int(clamp(surface_y - 1, 0, grid_height - 1))
	var spawn_tile := Vector2i(spawn_x, spawn_y)
	_spawn_offsets[team] = offset + 1
	return tile_to_world_center(spawn_tile)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / tile_size), floor(world_pos.y / tile_size))

func tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x + 0.5) * tile_size, (tile_pos.y + 0.5) * tile_size)

func get_gold_tiles() -> Dictionary:
	return _gold_tiles.duplicate()

func has_gold_at_tile(tile_pos: Vector2i) -> bool:
	return _gold_tiles.has(tile_pos)

func is_ore_tile(tile_pos: Vector2i) -> bool:
	return _gold_tiles.has(tile_pos)

func is_mineable_terrain_tile(tile_pos: Vector2i) -> bool:
	return has_ground_at_tile(tile_pos) and not is_ore_tile(tile_pos)

func has_ground_at_tile(tile_pos: Vector2i) -> bool:
	if not is_tile_in_bounds(tile_pos):
		return false
	return tile_map.get_cell_source_id(TERRAIN_LAYER, tile_pos) != -1

func is_underground_tile(tile_pos: Vector2i) -> bool:
	if not is_tile_in_bounds(tile_pos):
		return false
	return tile_map.get_cell_source_id(UNDERGROUND_LAYER, tile_pos) != -1

func is_walkable_air_tile(tile_pos: Vector2i) -> bool:
	return is_tile_in_bounds(tile_pos) and not has_ground_at_tile(tile_pos)

func is_tile_in_bounds(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= 0 and tile_pos.y >= 0 and tile_pos.x < grid_width and tile_pos.y < grid_height

func get_tile_health(tile_pos: Vector2i) -> int:
	return int(_tile_health.get(tile_pos, 0))

func get_ore_health(tile_pos: Vector2i) -> int:
	return int(_ore_health.get(tile_pos, 0))

func is_ore_revealed_to_team(tile_pos: Vector2i, team: int) -> bool:
	var team_lookup: Dictionary = _revealed_ore_tiles_by_team.get(team, {})
	return team_lookup.has(tile_pos)

func get_revealed_ore_tiles_for_team(team: int) -> Dictionary:
	var team_lookup: Dictionary = _revealed_ore_tiles_by_team.get(team, {})
	return team_lookup.duplicate(true)

func get_destroyed_terrain_tiles() -> Array[Vector2i]:
	var destroyed_tiles: Array[Vector2i] = []
	for raw_tile in tile_map.get_used_cells(UNDERGROUND_LAYER):
		var tile: Vector2i = raw_tile
		destroyed_tiles.append(tile)
	destroyed_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	return destroyed_tiles

func get_depleted_ore_tiles() -> Array[Vector2i]:
	var depleted_tiles: Array[Vector2i] = []
	for raw_tile in _depleted_ore_tiles.keys():
		var tile: Vector2i = raw_tile
		depleted_tiles.append(tile)
	depleted_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	return depleted_tiles

func get_revealed_ore_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for raw_team in _revealed_ore_tiles_by_team.keys():
		var team := int(raw_team)
		var ordered_tiles: Array[Vector2i] = []
		for raw_tile in (_revealed_ore_tiles_by_team.get(team, {}) as Dictionary).keys():
			var tile: Vector2i = raw_tile
			ordered_tiles.append(tile)
		ordered_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		)
		snapshot[team] = ordered_tiles
	return snapshot

func apply_world_state_snapshot(destroyed_tiles: Array, depleted_ore_tiles: Array, revealed_snapshot: Dictionary) -> void:
	for raw_tile in destroyed_tiles:
		if raw_tile is Vector2i:
			destroy_tile(raw_tile)
	for raw_tile in depleted_ore_tiles:
		if raw_tile is Vector2i:
			deplete_ore_tile(raw_tile)
	for raw_team in revealed_snapshot.keys():
		var team := int(raw_team)
		reveal_ore_tiles_for_team(team, revealed_snapshot.get(raw_team, []))

func set_harvest_queue_overlay(ordered_tiles: Array) -> void:
	_harvest_queue_overlay_tiles = []
	for tile in ordered_tiles:
		if tile is Vector2i:
			_harvest_queue_overlay_tiles.append(tile)
	_harvest_queue_overlay_visible = not _harvest_queue_overlay_tiles.is_empty()
	queue_redraw()

func clear_harvest_queue_overlay() -> void:
	if _harvest_queue_overlay_tiles.is_empty() and not _harvest_queue_overlay_visible:
		return
	_harvest_queue_overlay_tiles.clear()
	_harvest_queue_overlay_visible = false
	queue_redraw()

func set_mining_draft_tiles(tiles: Dictionary, color: Color = Color(1, 1, 1, MINING_DRAFT_ALPHA)) -> void:
	_rebuild_overlay_layer(MINING_DRAFT_LAYER, tiles, color)

func set_mining_invalid_tiles(tiles: Dictionary) -> void:
	_rebuild_overlay_layer(MINING_INVALID_LAYER, tiles, MINING_INVALID_COLOR)

func set_mining_committed_tiles(tiles: Dictionary, color: Color = Color(1, 1, 1, MINING_COMMITTED_ALPHA)) -> void:
	_rebuild_overlay_layer(MINING_COMMITTED_LAYER_START, tiles, color)

func set_passive_mining_assignments(assignments: Dictionary, colors: Dictionary) -> void:
	for layer in range(MINING_COMMITTED_LAYER_START, MINING_COMMITTED_LAYER_END + 1):
		_clear_layer_cells(layer)
	var unit_ids: Array[int] = []
	for raw_unit_id in assignments.keys():
		unit_ids.append(int(raw_unit_id))
	unit_ids.sort()
	for i in range(min(unit_ids.size(), MAX_MINER_OVERLAY_LAYERS)):
		var unit_id := unit_ids[i]
		var tiles: Dictionary = assignments.get(unit_id, {})
		var base_color: Color = colors.get(unit_id, Color(1, 1, 1, 1))
		var color := Color(base_color.r, base_color.g, base_color.b, MINING_COMMITTED_ALPHA)
		_rebuild_overlay_layer(MINING_COMMITTED_LAYER_START + i, tiles, color)

func clear_mining_selection_visuals() -> void:
	_clear_layer_cells(MINING_DRAFT_LAYER)
	_clear_layer_cells(MINING_INVALID_LAYER)
	for layer in range(MINING_COMMITTED_LAYER_START, MINING_COMMITTED_LAYER_END + 1):
		_clear_layer_cells(layer)

func get_invalid_mining_selection_tiles(selected_tiles: Dictionary) -> Dictionary:
	var valid_tiles := _get_air_connected_selected_tiles(selected_tiles)
	var invalid_tiles: Dictionary = {}
	for raw_tile in selected_tiles.keys():
		var tile: Vector2i = raw_tile
		if not valid_tiles.has(tile):
			invalid_tiles[tile] = true
	return invalid_tiles

func find_path_to_any_walkable_tile(start_tile: Vector2i, goal_tiles: Array[Vector2i]) -> Array[Vector2i]:
	if not is_walkable_air_tile(start_tile):
		return []
	if goal_tiles.is_empty():
		return []
	var goal_lookup: Dictionary = {}
	for tile in goal_tiles:
		if is_walkable_air_tile(tile):
			goal_lookup[tile] = true
	if goal_lookup.is_empty():
		return []
	if goal_lookup.has(start_tile):
		return [start_tile]
	var frontier: Array[Vector2i] = [start_tile]
	var visited: Dictionary = {start_tile: true}
	var previous: Dictionary = {}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in get_orthogonal_neighbors(current):
			if not is_walkable_air_tile(neighbor):
				continue
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			previous[neighbor] = current
			if goal_lookup.has(neighbor):
				return _reconstruct_path(previous, start_tile, neighbor)
			frontier.append(neighbor)
	return []

func get_orthogonal_neighbors(tile: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var candidates: Array[Vector2i] = [
		tile + Vector2i.LEFT,
		tile + Vector2i.RIGHT,
		tile + Vector2i.UP,
		tile + Vector2i.DOWN,
	]
	for candidate in candidates:
		if is_tile_in_bounds(candidate):
			neighbors.append(candidate)
	return neighbors

func get_adjacent_walkable_tiles(tile: Vector2i) -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	for neighbor in get_orthogonal_neighbors(tile):
		if is_walkable_air_tile(neighbor):
			walkable.append(neighbor)
	return walkable

func get_miner_attack_tiles(tile: Vector2i) -> Array[Vector2i]:
	var attack_tiles: Array[Vector2i] = []
	for neighbor in get_orthogonal_neighbors(tile):
		if is_walkable_air_tile(neighbor):
			attack_tiles.append(neighbor)
	var diagonals: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]
	for diagonal in diagonals:
		var attack_tile: Vector2i = tile + diagonal
		if not is_walkable_air_tile(attack_tile):
			continue
		var shared_horizontal: Vector2i = tile + Vector2i(diagonal.x, 0)
		var shared_vertical: Vector2i = tile + Vector2i(0, diagonal.y)
		if is_walkable_air_tile(shared_horizontal) or is_walkable_air_tile(shared_vertical):
			attack_tiles.append(attack_tile)
	return attack_tiles

func is_standable_tile(tile_pos: Vector2i) -> bool:
	if not is_tile_in_bounds(tile_pos):
		return false
	if has_ground_at_tile(tile_pos):
		return false
	var support_tile := tile_pos + Vector2i.DOWN
	if not is_tile_in_bounds(support_tile):
		return false
	return has_ground_at_tile(support_tile)

func is_troop_standable_tile(tile_pos: Vector2i, width_tiles: int, height_tiles: int) -> bool:
	var clamped_width := maxi(1, width_tiles)
	var clamped_height := maxi(1, height_tiles)
	if not _is_troop_body_clear_at(tile_pos, clamped_width, clamped_height):
		return false
	var has_support := false
	for x_offset in range(clamped_width):
		var body_x := tile_pos.x + x_offset
		var support_tile := Vector2i(body_x, tile_pos.y + 1)
		if not is_tile_in_bounds(support_tile):
			return false
		if has_ground_at_tile(support_tile):
			has_support = true
	return has_support

func _is_troop_body_clear_at(tile_pos: Vector2i, width_tiles: int, height_tiles: int) -> bool:
	var clamped_width := maxi(1, width_tiles)
	var clamped_height := maxi(1, height_tiles)
	for x_offset in range(clamped_width):
		var body_x := tile_pos.x + x_offset
		for y_offset in range(clamped_height):
			var body_tile := Vector2i(body_x, tile_pos.y - y_offset)
			if not is_tile_in_bounds(body_tile):
				return false
			if has_ground_at_tile(body_tile):
				return false
	return true

func _get_troop_max_drop_tiles(height_tiles: int) -> int:
	return 2 if maxi(1, height_tiles) >= 2 else 1

func _get_troop_max_climb_tiles(height_tiles: int) -> int:
	return 2 if maxi(1, height_tiles) >= 2 else 1

func stand_tile_to_world_position(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x + 0.5) * tile_size, (tile_pos.y + 1.0) * tile_size)

func troop_stand_tile_to_world_position(tile_pos: Vector2i, width_tiles: int) -> Vector2:
	var clamped_width := maxi(1, width_tiles)
	return Vector2((tile_pos.x + clamped_width * 0.5) * tile_size, (tile_pos.y + 1.0) * tile_size)

func get_stand_surface_world_y_at_x(world_x: float, reference_world_y: float) -> float:
	var tile_x: int = int(clamp(int(floor(world_x / tile_size)), 0, grid_width - 1))
	var best_y: float = reference_world_y
	var best_distance: float = INF
	for tile_y in range(grid_height):
		var candidate := Vector2i(tile_x, tile_y)
		if not is_standable_tile(candidate):
			continue
		var candidate_y: float = stand_tile_to_world_position(candidate).y
		var distance_to_reference: float = absf(candidate_y - reference_world_y)
		if distance_to_reference < best_distance:
			best_distance = distance_to_reference
			best_y = candidate_y
	return best_y

func get_standable_tile_for_world_position(world_pos: Vector2) -> Vector2i:
	var base_tile := world_to_tile(world_pos)
	var candidates: Array[Vector2i] = [
		base_tile,
		base_tile + Vector2i.UP,
		base_tile + Vector2i.DOWN,
		base_tile + Vector2i.LEFT,
		base_tile + Vector2i.RIGHT,
		base_tile + Vector2i(-1, -1),
		base_tile + Vector2i(1, -1),
		base_tile + Vector2i(-1, 1),
		base_tile + Vector2i(1, 1),
	]
	for candidate in candidates:
		if is_standable_tile(candidate):
			return candidate
	return Vector2i(-1, -1)

func get_troop_standable_tile_for_world_position(world_pos: Vector2, width_tiles: int, height_tiles: int) -> Vector2i:
	var clamped_width := maxi(1, width_tiles)
	var base_tile_x := int(round((world_pos.x / tile_size) - (clamped_width * 0.5)))
	var base_tile_y := int(floor(world_pos.y / tile_size)) - 1
	var candidates: Array[Vector2i] = [
		Vector2i(base_tile_x, base_tile_y),
		Vector2i(base_tile_x, base_tile_y - 1),
		Vector2i(base_tile_x, base_tile_y + 1),
		Vector2i(base_tile_x - 1, base_tile_y),
		Vector2i(base_tile_x + 1, base_tile_y),
		Vector2i(base_tile_x - 1, base_tile_y - 1),
		Vector2i(base_tile_x + 1, base_tile_y - 1),
		Vector2i(base_tile_x - 1, base_tile_y + 1),
		Vector2i(base_tile_x + 1, base_tile_y + 1),
	]
	for candidate in candidates:
		if is_troop_standable_tile(candidate, width_tiles, height_tiles):
			return candidate
	return Vector2i(-1, -1)

func get_troop_walk_target(tile_pos: Vector2i, direction_x: int, width_tiles: int, height_tiles: int) -> Vector2i:
	if direction_x == 0:
		return Vector2i(-1, -1)
	var same_level := tile_pos + Vector2i(direction_x, 0)
	if is_troop_standable_tile(same_level, width_tiles, height_tiles):
		return same_level
	var max_climb := _get_troop_max_climb_tiles(height_tiles)
	for climb_distance in range(1, max_climb + 1):
		var climb := tile_pos + Vector2i(direction_x, -climb_distance)
		if is_troop_standable_tile(climb, width_tiles, height_tiles):
			return climb
	var max_drop := _get_troop_max_drop_tiles(height_tiles)
	for drop_distance in range(1, max_drop + 1):
		var drop := tile_pos + Vector2i(direction_x, drop_distance)
		if not is_troop_standable_tile(drop, width_tiles, height_tiles):
			continue
		var clear_drop := true
		for step in range(0, drop_distance + 1):
			var step_tile := tile_pos + Vector2i(direction_x, step)
			if not _is_troop_body_clear_at(step_tile, width_tiles, height_tiles):
				clear_drop = false
				break
		if clear_drop:
			return drop
	return Vector2i(-1, -1)

func get_miner_walk_neighbors(tile: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var lateral_directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT]
	var fall_distances: Array[int] = [1, 2]
	for direction in lateral_directions:
		var same_level: Vector2i = tile + direction
		if is_standable_tile(same_level):
			neighbors.append(same_level)
		var climb: Vector2i = tile + direction + Vector2i.UP
		if is_standable_tile(climb):
			neighbors.append(climb)
		for fall_distance in fall_distances:
			var fall: Vector2i = tile + direction + Vector2i.DOWN * fall_distance
			if not is_standable_tile(fall):
				continue
			var clear_fall := true
			for step in range(1, fall_distance + 1):
				if has_ground_at_tile(tile + direction + Vector2i.DOWN * step):
					clear_fall = false
					break
			if clear_fall:
				neighbors.append(fall)
	for drop_distance in fall_distances:
		var drop: Vector2i = tile + Vector2i.DOWN * drop_distance
		if not is_standable_tile(drop):
			continue
		var clear_drop := true
		for step in range(1, drop_distance + 1):
			if has_ground_at_tile(tile + Vector2i.DOWN * step):
				clear_drop = false
				break
		if clear_drop:
			neighbors.append(drop)
	return neighbors

func get_air_tile_for_world_position(world_pos: Vector2) -> Vector2i:
	var tile := world_to_tile(world_pos)
	if is_walkable_air_tile(tile):
		return tile
	var above := tile + Vector2i.UP
	if is_walkable_air_tile(above):
		return above
	var below := tile + Vector2i.DOWN
	if is_walkable_air_tile(below):
		return below
	for neighbor in get_orthogonal_neighbors(tile):
		if is_walkable_air_tile(neighbor):
			return neighbor
	return above

func find_miner_path(start_tile: Vector2i, goal_tiles: Array[Vector2i]) -> Array[Vector2i]:
	if not is_standable_tile(start_tile):
		return []
	if goal_tiles.is_empty():
		return []
	var goal_lookup: Dictionary = {}
	for tile in goal_tiles:
		if is_standable_tile(tile):
			goal_lookup[tile] = true
	if goal_lookup.is_empty():
		return []
	if goal_lookup.has(start_tile):
		return [start_tile]
	var frontier: Array[Vector2i] = [start_tile]
	var visited: Dictionary = {start_tile: true}
	var previous: Dictionary = {}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in get_miner_walk_neighbors(current):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			previous[neighbor] = current
			if goal_lookup.has(neighbor):
				return _reconstruct_path(previous, start_tile, neighbor)
			frontier.append(neighbor)
	return []

func apply_tile_damage(tile_pos: Vector2i, amount: int) -> bool:
	if amount <= 0:
		return false
	if is_ore_tile(tile_pos):
		return false
	if not has_ground_at_tile(tile_pos):
		return false
	var remaining_health: int = max(0, get_tile_health(tile_pos) - amount)
	if remaining_health <= 0:
		destroy_tile(tile_pos)
		return true
	_tile_health[tile_pos] = remaining_health
	return false

func destroy_tile(tile_pos: Vector2i) -> void:
	if not has_ground_at_tile(tile_pos):
		return
	tile_map.erase_cell(TERRAIN_LAYER, tile_pos)
	tile_map.erase_cell(RESOURCE_LAYER, tile_pos)
	tile_map.set_cell(UNDERGROUND_LAYER, tile_pos, 0, TILE_UNDERGROUND)
	_gold_tiles.erase(tile_pos)
	_tile_health.erase(tile_pos)
	_ore_health.erase(tile_pos)
	for team in _revealed_ore_tiles_by_team.keys():
		var team_lookup: Dictionary = _revealed_ore_tiles_by_team.get(team, {})
		team_lookup.erase(tile_pos)
		_revealed_ore_tiles_by_team[team] = team_lookup
	tile_destroyed.emit(tile_pos)

func apply_ore_damage(tile_pos: Vector2i, amount: int) -> bool:
	if amount <= 0 or not is_ore_tile(tile_pos):
		return false
	var remaining_health: int = max(0, get_ore_health(tile_pos) - amount)
	if remaining_health <= 0:
		deplete_ore_tile(tile_pos)
		return true
	_ore_health[tile_pos] = remaining_health
	return false

func deplete_ore_tile(tile_pos: Vector2i) -> void:
	if not is_ore_tile(tile_pos):
		return
	tile_map.erase_cell(TERRAIN_LAYER, tile_pos)
	tile_map.erase_cell(RESOURCE_LAYER, tile_pos)
	tile_map.set_cell(UNDERGROUND_LAYER, tile_pos, 0, TILE_UNDERGROUND)
	_gold_tiles.erase(tile_pos)
	_ore_health.erase(tile_pos)
	_tile_health.erase(tile_pos)
	_depleted_ore_tiles[tile_pos] = true
	for team in _revealed_ore_tiles_by_team.keys():
		var team_lookup: Dictionary = _revealed_ore_tiles_by_team.get(team, {})
		team_lookup.erase(tile_pos)
		_revealed_ore_tiles_by_team[team] = team_lookup
	ore_depleted.emit(tile_pos)

func reveal_ore_from_exposed_tile(tile_pos: Vector2i, team: int) -> Array[Vector2i]:
	var newly_revealed: Array[Vector2i] = []
	var team_lookup: Dictionary = _revealed_ore_tiles_by_team.get(team, {})
	for neighbor in get_orthogonal_neighbors(tile_pos):
		if not is_ore_tile(neighbor):
			continue
		if team_lookup.has(neighbor):
			continue
		team_lookup[neighbor] = true
		newly_revealed.append(neighbor)
	_revealed_ore_tiles_by_team[team] = team_lookup
	if not newly_revealed.is_empty():
		DebugConsole.log_msg("OreReveal: team=%d tiles=%s" % [team, str(newly_revealed)])
		ore_revealed_for_team.emit(team, newly_revealed.duplicate())
	return newly_revealed

func reveal_ore_tiles_for_team(team: int, tiles: Array) -> void:
	var team_lookup: Dictionary = _revealed_ore_tiles_by_team.get(team, {})
	for tile in tiles:
		if tile is Vector2i and is_ore_tile(tile):
			team_lookup[tile] = true
	_revealed_ore_tiles_by_team[team] = team_lookup

func get_base_anchor_world(team: int) -> Vector2:
	var flat_width: int = _get_flat_width()
	var center_x: int = 0
	match team:
		GameState.Team.RIGHT:
			center_x = grid_width - 1 - int(floor(flat_width / 2.0))
		_:
			center_x = int(floor(flat_width / 2.0))
	var surface_y: int = _get_surface_height(center_x)
	var camera_tile := Vector2i(center_x, clamp(surface_y - 2, 0, grid_height - 1))
	return tile_to_world_center(camera_tile)

func get_world_pixel_rect() -> Rect2:
	var width: float = grid_width * tile_size
	var height: float = grid_height * tile_size
	return Rect2(0.0, 0.0, width, height)

func get_surface_tile_y_at_x(world_x: float) -> int:
	var tile_x: int = int(clamp(int(floor(world_x / tile_size)), 0, grid_width - 1))
	return _get_surface_height(tile_x)

func get_surface_world_y_at_x(world_x: float, unit_half_height: float) -> float:
	var surface_tile_y: int = get_surface_tile_y_at_x(world_x)
	return (surface_tile_y * tile_size) - unit_half_height

func _get_team_bounds(team: int) -> Rect2i:
	var left_width: int = int(max(1, int(round(grid_width * left_territory_ratio))))
	var right_width: int = int(max(1, int(round(grid_width * right_territory_ratio))))
	match team:
		GameState.Team.LEFT:
			return Rect2i(0, 0, left_width, grid_height)
		GameState.Team.RIGHT:
			return Rect2i(grid_width - right_width, 0, right_width, grid_height)
		_:
			return Rect2i(0, 0, 0, 0)

func _build_terrain() -> void:
	_resolved_terrain_seed = _resolve_terrain_seed()
	_heightmap = _generate_heightmap(_resolved_terrain_seed)
	_gold_tiles = _generate_gold_tiles(_resolved_terrain_seed)
	_tile_health.clear()
	_ore_health.clear()
	_depleted_ore_tiles.clear()
	_revealed_ore_tiles_by_team = {
		GameState.Team.LEFT: {},
		GameState.Team.RIGHT: {},
	}
	tile_map.clear()
	for x in range(grid_width):
		var surface_y: int = _get_surface_height(x)
		for y in range(surface_y, grid_height):
			var atlas_coords := TILE_DIRT
			if y == surface_y:
				atlas_coords = TILE_GRASS
			var tile := Vector2i(x, y)
			tile_map.set_cell(TERRAIN_LAYER, tile, 0, atlas_coords)
			_tile_health[tile] = TILE_HEALTH_DEFAULT
	for raw_tile in _gold_tiles.keys():
		var tile: Vector2i = raw_tile
		tile_map.set_cell(RESOURCE_LAYER, tile, 0, TILE_GOLD)
		_ore_health[tile] = ORE_HEALTH_DEFAULT
	clear_mining_selection_visuals()
	clear_harvest_queue_overlay()

func _generate_heightmap(terrain_seed_value: int) -> Array[int]:
	var heights: Array[int] = []
	heights.resize(grid_width)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed_value
	var base_height: int = int(clamp(base_surface_height, min_surface_height, max_surface_height))
	var flat_width: int = _get_flat_width()
	for x in range(grid_width):
		if _is_in_flat_pad(x, flat_width):
			heights[x] = base_height
			continue
		var prev: int = heights[x - 1] if x > 0 else base_height
		var delta: int = rng.randi_range(-max_step, max_step)
		if rng.randf() > roughness:
			delta = 0
		var next_height: int = int(clamp(prev + delta, min_surface_height, max_surface_height))
		heights[x] = next_height
	var passes: int = int(max(0, smooth_passes))
	for pass_index in range(passes):
		heights = _smooth_heights(heights)
	_apply_flat_pads(heights, base_height, flat_width)
	return heights

func _smooth_heights(source: Array[int]) -> Array[int]:
	var smoothed: Array[int] = []
	smoothed.resize(grid_width)
	var flat_width: int = _get_flat_width()
	for x in range(grid_width):
		if _is_in_flat_pad(x, flat_width):
			smoothed[x] = source[x]
			continue
		var left_index: int = int(clamp(x - 1, 0, grid_width - 1))
		var right_index: int = int(clamp(x + 1, 0, grid_width - 1))
		var left: int = source[left_index]
		var center: int = source[x]
		var right: int = source[right_index]
		var avg: int = int(round((left + center + right) / 3.0))
		smoothed[x] = int(clamp(avg, min_surface_height, max_surface_height))
	return smoothed

func _get_surface_height(x: int) -> int:
	if _heightmap.is_empty():
		return int(clamp(base_surface_height, min_surface_height, max_surface_height))
	return int(clamp(_heightmap[x], min_surface_height, max_surface_height))

func _get_flat_width() -> int:
	var max_width: int = int(max(1.0, floor(grid_width / 2.0)))
	return int(clamp(base_flat_width, 1, max_width))

func _is_in_flat_pad(x: int, flat_width: int) -> bool:
	return x < flat_width or x >= grid_width - flat_width

func _apply_flat_pads(heights: Array[int], base_height: int, flat_width: int) -> void:
	for i in range(flat_width):
		var left_index: int = i
		var right_index: int = grid_width - 1 - i
		heights[left_index] = base_height
		heights[right_index] = base_height

func _resolve_terrain_seed() -> int:
	if terrain_seed != 0:
		return terrain_seed
	if GameState.map_seed != GameState.DEFAULT_MAP_SEED:
		return GameState.map_seed
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()

func _generate_gold_tiles(terrain_seed_value: int) -> Dictionary:
	var gold_tiles: Dictionary = {}
	var eligible_tiles: Array[Vector2i] = _get_eligible_gold_tiles()
	if eligible_tiles.is_empty():
		return gold_tiles
	var target_count: int = int(round(eligible_tiles.size() * gold_target_ratio))
	if gold_target_ratio > 0.0:
		target_count = max(target_count, 1)
	target_count = int(clamp(target_count, 0, eligible_tiles.size()))
	if target_count == 0:
		return gold_tiles
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed_value + GOLD_SEED_SALT
	_shuffle_tiles(eligible_tiles, rng)
	for tile in eligible_tiles:
		if gold_tiles.size() >= target_count:
			break
		if _can_place_gold_at(tile, gold_tiles):
			gold_tiles[tile] = true
	return gold_tiles

func _get_eligible_gold_tiles() -> Array[Vector2i]:
	var eligible_tiles: Array[Vector2i] = []
	var min_depth: int = max(0, gold_min_depth_below_surface)
	for x in range(grid_width):
		var start_y: int = _get_surface_height(x) + min_depth
		for y in range(start_y, grid_height):
			eligible_tiles.append(Vector2i(x, y))
	return eligible_tiles

func _shuffle_tiles(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(tiles.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, i)
		var tmp: Vector2i = tiles[i]
		tiles[i] = tiles[swap_index]
		tiles[swap_index] = tmp

func _can_place_gold_at(tile: Vector2i, gold_tiles: Dictionary) -> bool:
	var max_gold: int = max(0, gold_max_per_window)
	if max_gold <= 0:
		return false
	var window_width: int = min(max(1, gold_window_size), grid_width)
	var window_height: int = min(max(1, gold_window_size), grid_height)
	var min_window_x: int = max(0, tile.x - window_width + 1)
	var max_window_x: int = min(tile.x, grid_width - window_width)
	var min_window_y: int = max(0, tile.y - window_height + 1)
	var max_window_y: int = min(tile.y, grid_height - window_height)
	for window_x in range(min_window_x, max_window_x + 1):
		for window_y in range(min_window_y, max_window_y + 1):
			var count: int = 0
			for raw_existing_tile in gold_tiles.keys():
				var existing_tile: Vector2i = raw_existing_tile
				if existing_tile.x < window_x or existing_tile.x >= window_x + window_width:
					continue
				if existing_tile.y < window_y or existing_tile.y >= window_y + window_height:
					continue
				count += 1
				if count >= max_gold:
					return false
	return true

func _ensure_tilemap_layers() -> void:
	tile_map.z_index = -10
	while tile_map.get_layers_count() <= MINING_COMMITTED_LAYER_END:
		tile_map.add_layer(tile_map.get_layers_count())
	tile_map.set_layer_z_index(TERRAIN_LAYER, 0)
	tile_map.set_layer_z_index(RESOURCE_LAYER, 1)
	tile_map.set_layer_z_index(UNDERGROUND_LAYER, 2)
	tile_map.set_layer_z_index(MINING_DRAFT_LAYER, 3)
	tile_map.set_layer_z_index(MINING_INVALID_LAYER, 4)
	for i in range(MAX_MINER_OVERLAY_LAYERS):
		tile_map.set_layer_z_index(MINING_COMMITTED_LAYER_START + i, 5 + i)
	tile_map.set_layer_modulate(MINING_DRAFT_LAYER, Color(1, 1, 1, MINING_DRAFT_ALPHA))
	tile_map.set_layer_modulate(MINING_INVALID_LAYER, MINING_INVALID_COLOR)
	for i in range(MAX_MINER_OVERLAY_LAYERS):
		tile_map.set_layer_modulate(
			MINING_COMMITTED_LAYER_START + i,
			Color(1, 1, 1, MINING_COMMITTED_ALPHA)
		)

func _ensure_tileset() -> void:
	if tile_map.tile_set != null:
		return
	var image := Image.create(tile_size * 4, tile_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_fill_rect(image, Rect2i(0, 0, tile_size, tile_size), Color(0.45, 0.32, 0.18, 1))
	_fill_rect(image, Rect2i(tile_size, 0, tile_size, tile_size), Color(0.3, 0.6, 0.25, 1))
	_fill_rect(image, Rect2i(tile_size * 2, 0, tile_size, tile_size), Color(0.9, 0.76, 0.18, 1))
	_fill_rect(image, Rect2i(tile_size * 3, 0, tile_size, tile_size), UNDERGROUND_COLOR)
	var texture := ImageTexture.create_from_image(image)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	var _source_id := tileset.add_source(source)
	source.create_tile(TILE_DIRT)
	source.create_tile(TILE_GRASS)
	source.create_tile(TILE_GOLD)
	source.create_tile(TILE_UNDERGROUND)
	tile_map.tile_set = tileset

func _apply_world_settings() -> void:
	grid_width = GameState.map_width
	grid_height = GameState.map_height
	terrain_seed = GameState.map_seed

func _on_world_settings_updated(_map_width: int, _map_height: int, _map_seed: int) -> void:
	_apply_world_settings()
	_build_terrain()

func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			image.set_pixel(x, y, color)

func _rebuild_overlay_layer(layer: int, tiles: Dictionary, color: Color) -> void:
	_clear_layer_cells(layer)
	tile_map.set_layer_modulate(layer, color)
	for raw_tile in tiles.keys():
		var tile: Vector2i = raw_tile
		if not has_ground_at_tile(tile):
			continue
		tile_map.set_cell(layer, tile, 0, TILE_GOLD)

func _clear_layer_cells(layer: int) -> void:
	tile_map.clear_layer(layer)

func _get_air_connected_selected_tiles(selected_tiles: Dictionary) -> Dictionary:
	var connected: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for raw_tile in selected_tiles.keys():
		var tile: Vector2i = raw_tile
		if not has_ground_at_tile(tile):
			continue
		for neighbor in get_orthogonal_neighbors(tile):
			if is_walkable_air_tile(neighbor):
				connected[tile] = true
				frontier.append(tile)
				break
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in get_orthogonal_neighbors(current):
			if not selected_tiles.has(neighbor):
				continue
			if connected.has(neighbor):
				continue
			connected[neighbor] = true
			frontier.append(neighbor)
	return connected

func _reconstruct_path(previous: Dictionary, start_tile: Vector2i, goal_tile: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal_tile]
	var cursor := goal_tile
	while cursor != start_tile and previous.has(cursor):
		cursor = previous[cursor]
		path.push_front(cursor)
	return path

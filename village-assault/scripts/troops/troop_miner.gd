extends "res://scripts/test_unit.gd"

const BASE_BODY_COLOR: Color = Color(0.54, 0.34, 0.14, 1.0)
const MINER_DEFAULT_COLOR: Color = Color(0.9, 0.78, 0.24, 1.0)
var _miner_top_color: Color = MINER_DEFAULT_COLOR
@export var miner_top_color: Color = MINER_DEFAULT_COLOR:
	set(value):
		_miner_top_color = value
		_update_miner_visuals()
	get:
		return _miner_top_color
@export var mining_assignment_serialized: String = ""

var _assigned_tiles: Array[Vector2i] = []
var _path_tiles: Array[Vector2i] = []
var _path_index: int = 0
var _current_target_tile: Vector2i = Vector2i(-1, -1)
@onready var _top_body: Polygon2D = $TopBody

func _ready() -> void:
	super._ready()
	set_body_polygon(_body_polygon())
	body.color = BASE_BODY_COLOR
	_ensure_top_body()
	_update_miner_visuals()

func _configure_synchronizer() -> void:
	super._configure_synchronizer()
	if synchronizer == null or synchronizer.replication_config == null:
		return
	var config: SceneReplicationConfig = synchronizer.replication_config
	if not config.has_property(NodePath(":miner_top_color")):
		_add_replicated_property(config, NodePath(":miner_top_color"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	if not config.has_property(NodePath(":mining_assignment_serialized")):
		_add_replicated_property(config, NodePath(":mining_assignment_serialized"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = config

func _physics_process(delta: float) -> void:
	if not _has_simulation_authority():
		return
	if not is_alive():
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_prune_completed_assignments()
	if _assigned_tiles.is_empty():
		return
	if _territory_manager == null:
		return
	var current_stand_tile := _territory_manager.get_standable_tile_for_world_position(position)
	if current_stand_tile == Vector2i(-1, -1):
		return
	var next_target := _choose_reachable_target(current_stand_tile)
	if next_target.is_empty():
		return
	var target_tile: Vector2i = next_target["tile"]
	var target_path: Array[Vector2i] = next_target["path"]
	if _path_tiles.is_empty() or _current_target_tile != target_tile:
		_current_target_tile = target_tile
		_path_tiles = target_path
		_path_index = 0
	if _path_tiles.is_empty():
		return
	if _path_index < _path_tiles.size():
		var path_tile: Vector2i = _path_tiles[_path_index]
		var path_world := _territory_manager.stand_tile_to_world_position(path_tile)
		var move_step: float = speed * delta
		var next_x: float = move_toward(position.x, path_world.x, move_step)
		position.x = next_x
		position.y = _territory_manager.get_stand_surface_world_y_at_x(position.x, position.y)
		if absf(position.x - path_world.x) <= 0.01:
			position = path_world
			_path_index += 1
		return
	if _attack_cooldown > 0.0:
		return
	if tile_damage <= 0:
		return
	var was_destroyed := _territory_manager.apply_tile_damage(target_tile, tile_damage)
	_attack_cooldown = attack_interval
	if was_destroyed:
		_assigned_tiles.erase(target_tile)
		_path_tiles.clear()
		_path_index = 0
		_current_target_tile = Vector2i(-1, -1)
		mining_assignment_serialized = _serialize_tiles(_assigned_tiles)

func initialize_from_spawn_payload(spawn_payload: Dictionary) -> void:
	super.initialize_from_spawn_payload(spawn_payload)
	var payload_color: Variant = spawn_payload.get("miner_top_color", null)
	if payload_color is Color:
		miner_top_color = payload_color
	if spawn_payload.has("mining_assignment"):
		set_mining_assignment(spawn_payload.get("mining_assignment", []))

func _update_color() -> void:
	if body == null:
		body = get_node_or_null("Body") as Polygon2D
	if body == null:
		return
	body.color = BASE_BODY_COLOR
	_update_miner_visuals()

func get_miner_top_color() -> Color:
	return _miner_top_color

func set_miner_top_color(value: Color) -> void:
	miner_top_color = value

func get_mining_assignment() -> Array[Vector2i]:
	return _assigned_tiles.duplicate()

func set_mining_assignment(tiles: Array) -> void:
	_assigned_tiles.clear()
	for raw_tile in tiles:
		_assigned_tiles.append(raw_tile)
	_path_tiles.clear()
	_path_index = 0
	_current_target_tile = Vector2i(-1, -1)
	mining_assignment_serialized = _serialize_tiles(_assigned_tiles)

func _ensure_top_body() -> void:
	if _top_body == null:
		_top_body = get_node_or_null("TopBody") as Polygon2D
	if _top_body == null:
		return
	_top_body.polygon = _top_polygon()
	_top_body.position = body.position

func _update_miner_visuals() -> void:
	_ensure_top_body()
	if _top_body == null:
		return
	_top_body.color = miner_top_color
	_top_body.position = body.position

func _serialize_tiles(tiles: Array[Vector2i]) -> String:
	var serialized: Array[String] = []
	for tile in tiles:
		serialized.append("%d,%d" % [tile.x, tile.y])
	return ";".join(serialized)

func _body_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-8, -10),
		Vector2(8, -10),
		Vector2(8, 10),
		Vector2(-8, 10),
	])

func _top_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-8, -10),
		Vector2(8, -10),
		Vector2(8, 0),
		Vector2(-8, 0),
	])

func _prune_completed_assignments() -> void:
	var remaining: Array[Vector2i] = []
	for tile in _assigned_tiles:
		if _territory_manager != null and _territory_manager.has_ground_at_tile(tile):
			remaining.append(tile)
	_assigned_tiles = remaining
	mining_assignment_serialized = _serialize_tiles(_assigned_tiles)

func _choose_reachable_target(start_stand_tile: Vector2i) -> Dictionary:
	var best_tile := Vector2i(-1, -1)
	var best_path: Array[Vector2i] = []
	for target_tile in _assigned_tiles:
		var stand_tiles: Array[Vector2i] = _territory_manager.get_miner_attack_tiles(target_tile)
		var valid_stand_tiles: Array[Vector2i] = []
		for stand_tile in stand_tiles:
			if _territory_manager.is_standable_tile(stand_tile):
				valid_stand_tiles.append(stand_tile)
		if valid_stand_tiles.is_empty():
			continue
		var path := _territory_manager.find_miner_path(start_stand_tile, valid_stand_tiles)
		if path.is_empty():
			continue
		if best_tile == Vector2i(-1, -1) or path.size() < best_path.size():
			best_tile = target_tile
			best_path = path
		elif path.size() == best_path.size() and target_tile.y < best_tile.y:
			best_tile = target_tile
			best_path = path
	if best_tile == Vector2i(-1, -1):
		return {}
	return {
		"tile": best_tile,
		"path": best_path,
	}

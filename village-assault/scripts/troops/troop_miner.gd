extends "res://scripts/test_unit.gd"

const BASE_BODY_COLOR: Color = Color(0.54, 0.34, 0.14, 1.0)
const MINER_DEFAULT_COLOR: Color = Color(0.9, 0.78, 0.24, 1.0)
const INVALID_TILE: Vector2i = Vector2i(-1, -1)
const ORE_HITS_PER_DEPOSIT: int = 2
const ORE_DEPOSIT_GOLD: int = 20
const BLOCKED_RETURN_RETRY_INTERVAL_SEC: float = 0.5
const FALL_ACCELERATION: float = 900.0
const MAX_FALL_SPEED: float = 400.0

enum MinerJobType {
	IDLE,
	DIG,
	HARVEST,
}

enum MinerRuntimeState {
	IDLE,
	MOVING_TO_DIG_TARGET,
	DIGGING,
	MOVING_TO_ORE,
	HARVESTING,
	RETURNING_TO_BASE,
}

var _miner_top_color: Color = MINER_DEFAULT_COLOR
@export var miner_top_color: Color = MINER_DEFAULT_COLOR:
	set(value):
		_miner_top_color = value
		_update_miner_visuals()
	get:
		return _miner_top_color

var _miner_job_serialized: String = ""
@export var miner_job_serialized: String = "":
	set(value):
		_miner_job_serialized = value
		_apply_deserialized_job(_deserialize_payload(value))
	get:
		return _miner_job_serialized

var _miner_runtime_serialized: String = ""
@export var miner_runtime_serialized: String = "":
	set(value):
		_miner_runtime_serialized = value
		_runtime_snapshot = _deserialize_payload(value)
	get:
		return _miner_runtime_serialized

var _job_payload: Dictionary = _make_idle_job()
var _runtime_snapshot: Dictionary = _make_runtime_snapshot()
var _path_tiles: Array[Vector2i] = []
var _path_index: int = 0
var _current_target_tile: Vector2i = INVALID_TILE
var _current_target_path_goal: Vector2i = INVALID_TILE
var _blocked_return_current_tile: Vector2i = INVALID_TILE
var _blocked_return_base_tile: Vector2i = INVALID_TILE
var _blocked_return_retry_remaining: float = 0.0
var _fall_velocity: float = 0.0

@onready var _top_body: Polygon2D = $TopBody

func _ready() -> void:
	super._ready()
	set_body_polygon(_body_polygon())
	body.color = BASE_BODY_COLOR
	_ensure_top_body()
	_update_miner_visuals()
	_refresh_runtime_snapshot()

func _configure_synchronizer() -> void:
	super._configure_synchronizer()
	if synchronizer == null or synchronizer.replication_config == null:
		return
	var config: SceneReplicationConfig = synchronizer.replication_config
	if not config.has_property(NodePath(":miner_top_color")):
		_add_replicated_property(config, NodePath(":miner_top_color"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	if not config.has_property(NodePath(":miner_job_serialized")):
		_add_replicated_property(config, NodePath(":miner_job_serialized"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	if not config.has_property(NodePath(":miner_runtime_serialized")):
		_add_replicated_property(config, NodePath(":miner_runtime_serialized"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = config

func _physics_process(delta: float) -> void:
	if not _has_simulation_authority():
		return
	if not is_alive():
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_blocked_return_retry_remaining = maxf(_blocked_return_retry_remaining - delta, 0.0)
	if _territory_manager == null:
		_refresh_runtime_snapshot()
		return
	_runtime_snapshot["home_base_world"] = _territory_manager.get_base_anchor_world(team)
	var current_stand_tile := _get_exact_stand_tile_from_position()
	if _apply_fall_if_unsupported(delta, current_stand_tile):
		_refresh_runtime_snapshot()
		return
	if current_stand_tile == INVALID_TILE:
		current_stand_tile = _territory_manager.get_standable_tile_for_world_position(position)
	match int(_job_payload.get("job_type", MinerJobType.IDLE)):
		MinerJobType.DIG:
			_process_dig_job(delta, current_stand_tile)
		MinerJobType.HARVEST:
			_process_harvest_job(delta, current_stand_tile)
		_:
			_set_runtime_state(MinerRuntimeState.IDLE)
			_clear_movement_path()
	_refresh_runtime_snapshot()

func initialize_from_spawn_payload(spawn_payload: Dictionary) -> void:
	super.initialize_from_spawn_payload(spawn_payload)
	var payload_color: Variant = spawn_payload.get("miner_top_color", null)
	if payload_color is Color:
		miner_top_color = payload_color
	set_miner_job(_make_idle_job())

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

func get_miner_job() -> Dictionary:
	return _job_payload.duplicate(true)

func get_runtime_snapshot() -> Dictionary:
	return _runtime_snapshot.duplicate(true)

func set_miner_job(job_payload: Dictionary) -> void:
	_apply_deserialized_job(_sanitize_job_payload(job_payload))
	_miner_job_serialized = var_to_str(_job_payload)

func get_passive_status_text() -> String:
	var runtime_state := int(_runtime_snapshot.get("runtime_state", MinerRuntimeState.IDLE))
	match runtime_state:
		MinerRuntimeState.RETURNING_TO_BASE:
			return "Returning"
	var job_type := int(_job_payload.get("job_type", MinerJobType.IDLE))
	match job_type:
		MinerJobType.DIG:
			if bool(_job_payload.get("dig_auto_harvest_first_ore", false)):
				return "Dig + Auto"
			return "Dig"
		MinerJobType.HARVEST:
			return "Harvest"
		_:
			return "Idle"

func _process_dig_job(delta: float, current_stand_tile: Vector2i) -> void:
	_prune_completed_dig_tiles()
	var dig_tiles: Array[Vector2i] = _typed_vector_array(_job_payload.get("dig_tiles", []))
	if dig_tiles.is_empty():
		set_miner_job(_make_idle_job())
		_set_runtime_state(MinerRuntimeState.IDLE)
		return
	if current_stand_tile == INVALID_TILE:
		_set_runtime_state(MinerRuntimeState.IDLE)
		return
	var next_target := _choose_reachable_dig_target(current_stand_tile, dig_tiles)
	if next_target.is_empty():
		_set_runtime_state(MinerRuntimeState.IDLE)
		return
	var target_tile: Vector2i = next_target["tile"]
	var target_path: Array[Vector2i] = next_target["path"]
	if _follow_or_prepare_path(target_tile, target_path, delta, MinerRuntimeState.MOVING_TO_DIG_TARGET):
		return
	if _attack_cooldown > 0.0 or tile_damage <= 0:
		_set_runtime_state(MinerRuntimeState.DIGGING)
		return
	var was_destroyed := _territory_manager.apply_tile_damage(target_tile, tile_damage)
	_attack_cooldown = attack_interval
	_set_runtime_state(MinerRuntimeState.DIGGING)
	if not was_destroyed:
		return
	var revealed_tiles := _territory_manager.reveal_ore_from_exposed_tile(target_tile, team)
	_remove_dig_tile(target_tile)
	_clear_movement_path()
	if bool(_job_payload.get("dig_auto_harvest_first_ore", false)):
		_try_auto_convert_to_harvest(current_stand_tile, revealed_tiles)

func _process_harvest_job(delta: float, current_stand_tile: Vector2i) -> void:
	var ore_queue: Array[Vector2i] = _typed_vector_array(_job_payload.get("assigned_ore_tiles", []))
	var active_ore_index: int = int(_job_payload.get("active_ore_index", 0))
	if bool(_runtime_snapshot.get("cargo_full", false)):
		if current_stand_tile == INVALID_TILE:
			_set_runtime_state(MinerRuntimeState.RETURNING_TO_BASE)
			return
		var base_target := _territory_manager.get_standable_tile_for_world_position(_territory_manager.get_base_anchor_world(team))
		if base_target == INVALID_TILE:
			_set_runtime_state(MinerRuntimeState.RETURNING_TO_BASE)
			return
		if current_stand_tile == base_target:
			_clear_blocked_return_state()
			_deposit_ore_and_continue()
			return
		if _is_waiting_to_retry_blocked_return(current_stand_tile, base_target):
			_set_runtime_state(MinerRuntimeState.RETURNING_TO_BASE)
			return
		var return_path := _territory_manager.find_miner_path(current_stand_tile, [base_target])
		if _follow_or_prepare_path(base_target, return_path, delta, MinerRuntimeState.RETURNING_TO_BASE):
			_clear_blocked_return_state()
			return
		_set_runtime_state(MinerRuntimeState.RETURNING_TO_BASE)
		_set_blocked_return_state(current_stand_tile, base_target)
		return
	if ore_queue.is_empty() or active_ore_index >= ore_queue.size():
		set_miner_job(_make_idle_job())
		_set_runtime_state(MinerRuntimeState.IDLE)
		return
	var ore_tile := ore_queue[active_ore_index]
	if not _territory_manager.is_ore_tile(ore_tile):
		_advance_or_finish_harvest_queue(active_ore_index)
		return
	if current_stand_tile == INVALID_TILE:
		_clear_blocked_return_state()
		_set_runtime_state(MinerRuntimeState.MOVING_TO_ORE)
		return
	var attack_tiles := _territory_manager.get_miner_attack_tiles(ore_tile)
	var valid_attack_tiles: Array[Vector2i] = []
	for attack_tile in attack_tiles:
		if _territory_manager.is_standable_tile(attack_tile):
			valid_attack_tiles.append(attack_tile)
	if valid_attack_tiles.is_empty():
		_clear_blocked_return_state()
		_set_runtime_state(MinerRuntimeState.IDLE)
		return
	var ore_path := _territory_manager.find_miner_path(current_stand_tile, valid_attack_tiles)
	if _follow_or_prepare_path(ore_tile, ore_path, delta, MinerRuntimeState.MOVING_TO_ORE):
		_clear_blocked_return_state()
		return
	_clear_blocked_return_state()
	if _attack_cooldown > 0.0 or damage <= 0:
		_set_runtime_state(MinerRuntimeState.HARVESTING)
		return
	var ore_depleted := _territory_manager.apply_ore_damage(ore_tile, damage)
	_attack_cooldown = attack_interval
	_set_runtime_state(MinerRuntimeState.HARVESTING)
	var ore_hits: int = int(_runtime_snapshot.get("ore_hits_since_last_deposit", 0)) + 1
	_runtime_snapshot["ore_hits_since_last_deposit"] = ore_hits
	if ore_hits >= ORE_HITS_PER_DEPOSIT:
		_runtime_snapshot["cargo_full"] = true
	if ore_depleted:
		if bool(_runtime_snapshot.get("cargo_full", false)):
			_remove_ore_from_queue(active_ore_index)
		else:
			_advance_or_finish_harvest_queue(active_ore_index)

func _follow_or_prepare_path(
	target_tile: Vector2i,
	target_path: Array[Vector2i],
	delta: float,
	runtime_state: int
) -> bool:
	if _path_tiles.is_empty() or _current_target_tile != target_tile or _current_target_path_goal != _get_path_goal_tile(target_path):
		_current_target_tile = target_tile
		_current_target_path_goal = _get_path_goal_tile(target_path)
		_path_tiles = target_path.duplicate()
		_path_index = 0
	if _path_tiles.is_empty():
		return false
	if _path_index >= _path_tiles.size():
		return false
	_set_runtime_state(runtime_state)
	var path_tile: Vector2i = _path_tiles[_path_index]
	var path_world := _territory_manager.stand_tile_to_world_position(path_tile)
	var move_step: float = speed * delta
	position.x = move_toward(position.x, path_world.x, move_step)
	position.y = _territory_manager.get_stand_surface_world_y_at_x(position.x, position.y)
	if absf(position.x - path_world.x) <= 0.01:
		position = path_world
		_path_index += 1
	return true

func _get_exact_stand_tile_from_position() -> Vector2i:
	if _territory_manager == null:
		return INVALID_TILE
	var probe_position := position + Vector2(0.0, -1.0)
	var exact_tile := _territory_manager.world_to_tile(probe_position)
	if _territory_manager.is_standable_tile(exact_tile):
		return exact_tile
	return INVALID_TILE

func _apply_fall_if_unsupported(delta: float, current_stand_tile: Vector2i) -> bool:
	if _territory_manager == null:
		return false
	if current_stand_tile != INVALID_TILE:
		if _fall_velocity > 0.0:
			position = _territory_manager.stand_tile_to_world_position(current_stand_tile)
			_fall_velocity = 0.0
		return false
	if _fall_velocity == 0.0:
		_clear_movement_path()
	_debug_fall_started_if_needed()
	_fall_velocity = minf(_fall_velocity + FALL_ACCELERATION * delta, MAX_FALL_SPEED)
	position.y += _fall_velocity * delta
	var landed_tile := _get_exact_stand_tile_from_position()
	if landed_tile != INVALID_TILE:
		position = _territory_manager.stand_tile_to_world_position(landed_tile)
		_fall_velocity = 0.0
	return true

func _debug_fall_started_if_needed() -> void:
	if _fall_velocity > 0.0:
		return
	DebugConsole.log_msg("MiningJob: miner=%d runtime=falling" % unit_id)

func _prune_completed_dig_tiles() -> void:
	var remaining: Array[Vector2i] = []
	for tile in _typed_vector_array(_job_payload.get("dig_tiles", [])):
		if _territory_manager != null and _territory_manager.is_mineable_terrain_tile(tile):
			remaining.append(tile)
	if remaining.size() == _typed_vector_array(_job_payload.get("dig_tiles", [])).size():
		return
	_job_payload["dig_tiles"] = remaining
	_job_payload["dig_tiles_lookup"] = _build_lookup(remaining)
	_miner_job_serialized = var_to_str(_job_payload)

func _choose_reachable_dig_target(start_stand_tile: Vector2i, dig_tiles: Array[Vector2i]) -> Dictionary:
	var best_tile := INVALID_TILE
	var best_path: Array[Vector2i] = []
	for target_tile in dig_tiles:
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
		if best_tile == INVALID_TILE or path.size() < best_path.size() or (
			path.size() == best_path.size() and (
				target_tile.y < best_tile.y or (target_tile.y == best_tile.y and target_tile.x < best_tile.x)
			)
		):
			best_tile = target_tile
			best_path = path
	if best_tile == INVALID_TILE:
		return {}
	return {"tile": best_tile, "path": best_path}

func _try_auto_convert_to_harvest(current_stand_tile: Vector2i, revealed_tiles: Array[Vector2i]) -> void:
	if revealed_tiles.is_empty() or current_stand_tile == INVALID_TILE:
		return
	var best_tile := INVALID_TILE
	var best_path_size := INF
	for ore_tile in revealed_tiles:
		var attack_tiles := _territory_manager.get_miner_attack_tiles(ore_tile)
		var valid_attack_tiles: Array[Vector2i] = []
		for attack_tile in attack_tiles:
			if _territory_manager.is_standable_tile(attack_tile):
				valid_attack_tiles.append(attack_tile)
		if valid_attack_tiles.is_empty():
			continue
		var path := _territory_manager.find_miner_path(current_stand_tile, valid_attack_tiles)
		if path.is_empty():
			continue
		if path.size() < best_path_size or (
			path.size() == best_path_size and (
				ore_tile.y < best_tile.y or (ore_tile.y == best_tile.y and ore_tile.x < best_tile.x)
			)
		):
			best_tile = ore_tile
			best_path_size = path.size()
	if best_tile == INVALID_TILE:
		return
	DebugConsole.log_msg("MiningJob: miner=%d auto_convert ore=%s" % [unit_id, str(best_tile)])
	set_miner_job({
		"unit_id": unit_id,
		"job_type": MinerJobType.HARVEST,
		"dig_auto_harvest_first_ore": false,
		"dig_tiles": [],
		"dig_tiles_lookup": {},
		"assigned_ore_tiles": [best_tile],
		"assigned_ore_lookup": _build_lookup([best_tile]),
		"active_ore_index": 0,
		"miner_color": miner_top_color,
	})
	_clear_movement_path()

func _deposit_ore_and_continue() -> void:
	_runtime_snapshot["cargo_full"] = false
	_runtime_snapshot["ore_hits_since_last_deposit"] = 0
	var team_peer_id := GameState.get_peer_id_for_team(team)
	if team_peer_id != -1:
		var current_money := GameState.get_money_for_peer(team_peer_id)
		GameState.set_money_for_peer(team_peer_id, current_money + ORE_DEPOSIT_GOLD)
		DebugConsole.log_msg("HarvestLoop: miner=%d deposit=%d peer=%d" % [unit_id, ORE_DEPOSIT_GOLD, team_peer_id])
	var active_ore_index: int = int(_job_payload.get("active_ore_index", 0))
	var ore_queue: Array[Vector2i] = _typed_vector_array(_job_payload.get("assigned_ore_tiles", []))
	if active_ore_index >= ore_queue.size() or not _territory_manager.is_ore_tile(ore_queue[active_ore_index]):
		_advance_or_finish_harvest_queue(active_ore_index)
		return
	_clear_movement_path()

func _advance_or_finish_harvest_queue(active_index: int) -> void:
	_remove_ore_from_queue(active_index)
	var ore_queue: Array[Vector2i] = _typed_vector_array(_job_payload.get("assigned_ore_tiles", []))
	if ore_queue.is_empty():
		set_miner_job(_make_idle_job())
		_set_runtime_state(MinerRuntimeState.IDLE)
		return
	_job_payload["active_ore_index"] = mini(active_index, ore_queue.size() - 1)
	_miner_job_serialized = var_to_str(_job_payload)
	_clear_movement_path()

func _remove_ore_from_queue(index: int) -> void:
	var ore_queue: Array[Vector2i] = _typed_vector_array(_job_payload.get("assigned_ore_tiles", []))
	if index < 0 or index >= ore_queue.size():
		return
	ore_queue.remove_at(index)
	_job_payload["assigned_ore_tiles"] = ore_queue
	_job_payload["assigned_ore_lookup"] = _build_lookup(ore_queue)
	_job_payload["active_ore_index"] = maxi(0, mini(index, ore_queue.size() - 1))
	_miner_job_serialized = var_to_str(_job_payload)

func _remove_dig_tile(tile: Vector2i) -> void:
	var dig_tiles: Array[Vector2i] = _typed_vector_array(_job_payload.get("dig_tiles", []))
	dig_tiles.erase(tile)
	_job_payload["dig_tiles"] = dig_tiles
	_job_payload["dig_tiles_lookup"] = _build_lookup(dig_tiles)
	_miner_job_serialized = var_to_str(_job_payload)

func _set_runtime_state(new_state: int) -> void:
	if int(_runtime_snapshot.get("runtime_state", MinerRuntimeState.IDLE)) == new_state:
		return
	_runtime_snapshot["runtime_state"] = new_state
	DebugConsole.log_msg("MiningJob: miner=%d runtime=%s" % [unit_id, str(new_state)])

func _refresh_runtime_snapshot() -> void:
	_runtime_snapshot["path_tiles"] = _path_tiles.duplicate()
	_runtime_snapshot["path_index"] = _path_index
	_runtime_snapshot["current_target_tile"] = _current_target_tile
	_runtime_snapshot["home_base_world"] = _territory_manager.get_base_anchor_world(team) if _territory_manager != null else Vector2.ZERO
	_miner_runtime_serialized = var_to_str(_runtime_snapshot)

func _clear_movement_path() -> void:
	_path_tiles.clear()
	_path_index = 0
	_current_target_tile = INVALID_TILE
	_current_target_path_goal = INVALID_TILE
	_clear_blocked_return_state()

func _clear_blocked_return_state() -> void:
	_blocked_return_current_tile = INVALID_TILE
	_blocked_return_base_tile = INVALID_TILE
	_blocked_return_retry_remaining = 0.0

func _is_waiting_to_retry_blocked_return(current_tile: Vector2i, base_tile: Vector2i) -> bool:
	return _blocked_return_current_tile == current_tile \
		and _blocked_return_base_tile == base_tile \
		and _blocked_return_retry_remaining > 0.0

func _set_blocked_return_state(current_tile: Vector2i, base_tile: Vector2i) -> void:
	var is_new_block := _blocked_return_current_tile != current_tile or _blocked_return_base_tile != base_tile
	_blocked_return_current_tile = current_tile
	_blocked_return_base_tile = base_tile
	_blocked_return_retry_remaining = BLOCKED_RETURN_RETRY_INTERVAL_SEC
	if is_new_block:
		DebugConsole.log_msg("HarvestLoop: miner=%d blocked_return current=%s base=%s" % [
			unit_id,
			str(current_tile),
			str(base_tile),
		])

func _get_path_goal_tile(path: Array[Vector2i]) -> Vector2i:
	if path.is_empty():
		return INVALID_TILE
	return path[path.size() - 1]

func _apply_deserialized_job(job_payload: Dictionary) -> void:
	_job_payload = _sanitize_job_payload(job_payload)
	_clear_movement_path()

func _sanitize_job_payload(job_payload: Dictionary) -> Dictionary:
	var sanitized := _make_idle_job()
	if job_payload.is_empty():
		return sanitized
	sanitized["unit_id"] = int(job_payload.get("unit_id", unit_id))
	sanitized["job_type"] = int(job_payload.get("job_type", MinerJobType.IDLE))
	sanitized["dig_auto_harvest_first_ore"] = bool(job_payload.get("dig_auto_harvest_first_ore", false))
	sanitized["dig_tiles"] = _typed_vector_array(job_payload.get("dig_tiles", []))
	sanitized["dig_tiles_lookup"] = _build_lookup(sanitized["dig_tiles"])
	sanitized["assigned_ore_tiles"] = _typed_vector_array(job_payload.get("assigned_ore_tiles", []))
	sanitized["assigned_ore_lookup"] = _build_lookup(sanitized["assigned_ore_tiles"])
	sanitized["active_ore_index"] = maxi(0, int(job_payload.get("active_ore_index", 0)))
	sanitized["miner_color"] = job_payload.get("miner_color", miner_top_color)
	if sanitized["job_type"] == MinerJobType.DIG and (sanitized["dig_tiles"] as Array[Vector2i]).is_empty():
		sanitized["job_type"] = MinerJobType.IDLE
	if sanitized["job_type"] == MinerJobType.HARVEST and (sanitized["assigned_ore_tiles"] as Array[Vector2i]).is_empty():
		sanitized["job_type"] = MinerJobType.IDLE
	return sanitized

func _make_idle_job() -> Dictionary:
	return {
		"unit_id": unit_id,
		"job_type": MinerJobType.IDLE,
		"dig_auto_harvest_first_ore": false,
		"dig_tiles": [],
		"dig_tiles_lookup": {},
		"assigned_ore_tiles": [],
		"assigned_ore_lookup": {},
		"active_ore_index": 0,
		"miner_color": miner_top_color,
	}

func _make_runtime_snapshot() -> Dictionary:
	return {
		"runtime_state": MinerRuntimeState.IDLE,
		"path_tiles": [],
		"path_index": 0,
		"current_target_tile": INVALID_TILE,
		"ore_hits_since_last_deposit": 0,
		"cargo_full": false,
		"home_base_world": Vector2.ZERO,
	}

func _deserialize_payload(payload_text: String) -> Dictionary:
	if payload_text.is_empty():
		return {}
	var value: Variant = str_to_var(payload_text)
	if value is Dictionary:
		return value
	return {}

func _typed_vector_array(raw_tiles: Variant) -> Array[Vector2i]:
	var typed_tiles: Array[Vector2i] = []
	if raw_tiles is Array:
		for raw_tile in raw_tiles:
			if raw_tile is Vector2i:
				typed_tiles.append(raw_tile)
	return typed_tiles

func _build_lookup(tiles: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for tile in tiles:
		lookup[tile] = true
	return lookup

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

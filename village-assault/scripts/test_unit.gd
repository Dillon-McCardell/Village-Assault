extends Node2D

const TROOP_INVALID_TILE := Vector2i(-1, -1)
const TROOP_FALL_ACCELERATION: float = 900.0
const TROOP_MAX_FALL_SPEED: float = 400.0
const DEFEND_PURSUIT_RADIUS: float = 64.0

enum TacticalOrder {
	MOVE,
	ADVANCE,
	DEFEND,
	RETREAT,
}

enum TroopStatus {
	IDLE,
	MOVING,
	ADVANCING,
	DEFENDING,
	RETREATING,
	ENGAGING_ENEMY,
	MINING,
	MOVING_TO_DIG_SITE,
	HARVESTING_ORE,
	RETURNING_ORE_TO_BASE,
}

@export var speed: float = 32.0
@export var stop_range: float = 12.0
@export var unit_height: float = 16.0
@export var attack_range: float = 12.0
@export var attack_interval: float = 1.0
@export var item_id: String = ""
@export var unit_id: int = -1
var _team: int = GameState.Team.NONE
@export var team: int = GameState.Team.NONE:
	set(value):
		_team = value
		_update_color()
	get:
		return _team
var _max_health: int = 1
@export var max_health: int = 1:
	set(value):
		_max_health = maxi(1, value)
		if _current_health > _max_health:
			_current_health = _max_health
		_refresh_health_bar()
	get:
		return _max_health
var _current_health: int = 1
@export var current_health: int = 1:
	set(value):
		_current_health = clampi(value, 0, max_health)
		_refresh_health_bar()
	get:
		return _current_health
@export var damage: int = 0
@export var defense: int = 0
@export var tile_damage: int = 0
@export var current_order: int = TacticalOrder.DEFEND
@export var command_target_tile: Vector2i = TROOP_INVALID_TILE
@export var defense_anchor_tile: Vector2i = TROOP_INVALID_TILE
@export var order_revision: int = 0
@export var current_status: int = TroopStatus.DEFENDING

const HEALTH_BAR_WIDTH: float = 20.0
const HEALTH_BAR_HEIGHT: float = 4.0
const HEALTH_BAR_OFFSET: float = 6.0
const HEALTH_BAR_BORDER_COLOR := Color(0.06, 0.06, 0.06, 0.95)
const HEALTH_BAR_BACKGROUND_COLOR := Color(0.18, 0.18, 0.18, 0.9)
const HEALTH_BAR_FILL_HIGH := Color(0.2, 0.82, 0.34, 1.0)
const HEALTH_BAR_FILL_LOW := Color(0.92, 0.18, 0.18, 1.0)

@onready var body: Polygon2D = $Body
var synchronizer: MultiplayerSynchronizer = null

var _target: Node2D
var _attack_cooldown: float = 0.0
var _territory_manager: TerritoryManager
var _world_rect: Rect2
@onready var _health_bar_root: Node2D = $HealthBar
@onready var _health_bar_border: ColorRect = $HealthBar/Border
@onready var _health_bar_background: ColorRect = $HealthBar/Background
@onready var _health_bar_fill: ColorRect = $HealthBar/Fill
var _visual_max_health: int = -1
var _visual_current_health: int = -1
var _troop_occupancy_width_tiles: int = 1
var _troop_occupancy_height_tiles: int = 1
var _troop_fall_velocity: float = 0.0
var _troop_movement_target_tile: Vector2i = TROOP_INVALID_TILE
var _troop_path_tiles: Array[Vector2i] = []
var _troop_path_index: int = 0
var _troop_path_goal_tile: Vector2i = TROOP_INVALID_TILE

func _enter_tree() -> void:
	_configure_synchronizer()

func prepare_for_network_spawn() -> void:
	_configure_synchronizer()

func _ready() -> void:
	_ensure_health_bar()
	if multiplayer.multiplayer_peer != null:
		set_multiplayer_authority(1, true)
	add_to_group("troops")
	var current_scene := get_tree().get_current_scene()
	if current_scene != null:
		_territory_manager = current_scene.get_node_or_null("TerritoryManager") as TerritoryManager
	if _territory_manager:
		_world_rect = _territory_manager.get_world_pixel_rect()
	_snap_to_ground()
	_initialize_defense_anchor_if_needed()
	_update_color()
	_refresh_health_bar()

func _process(_delta: float) -> void:
	_refresh_health_bar_if_needed()

func _physics_process(delta: float) -> void:
	if not _has_simulation_authority():
		return
	if not is_alive():
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_target = _get_enemy_target()
	if _target != null:
		current_status = TroopStatus.ENGAGING_ENEMY
		_attack_target()
		return
	_process_current_order(delta)
	_check_despawn()

func set_team(value: int) -> void:
	team = value

func set_item_id(value: String) -> void:
	item_id = value

func set_unit_id(value: int) -> void:
	unit_id = value

func initialize_from_spawn_payload(spawn_payload: Dictionary) -> void:
	initialize_runtime_state(
		max(1, int(spawn_payload.get("health", 1))),
		max(0, int(spawn_payload.get("damage", 0))),
		max(0, int(spawn_payload.get("defense", 0))),
		max(0, int(spawn_payload.get("tile_damage", 0)))
	)
	var vision_component := get_node_or_null("VisionComponent") as VisionComponent
	if vision_component != null:
		vision_component.configure_from_spawn_payload(spawn_payload)

func get_vision_source() -> Dictionary:
	var vision_component := get_node_or_null("VisionComponent") as VisionComponent
	if vision_component == null:
		return {}
	return vision_component.get_vision_source()

func initialize_runtime_state(health: int, damage_value: int, defense_value: int, tile_damage_value: int = 0) -> void:
	max_health = max(1, health)
	current_health = max_health
	damage = max(0, damage_value)
	defense = max(0, defense_value)
	tile_damage = max(0, tile_damage_value)

func sync_current_health(value: int) -> void:
	current_health = value

func _get_enemy_target() -> Node2D:
	for node in get_tree().get_nodes_in_group("troops"):
		if node == self:
			continue
		if not node is Node2D:
			continue
		if not node.has_method("is_alive") or not node.is_alive():
			continue
		if not node.has_method("get_team"):
			continue
		if node.get_team() == team:
			continue
		if current_order == TacticalOrder.DEFEND and not _is_within_defense_pursuit_radius(node.position):
			continue
		if position.distance_to(node.position) <= attack_range:
			return node as Node2D
	return null

func _is_within_defense_pursuit_radius(world_pos: Vector2) -> bool:
	if _territory_manager == null or defense_anchor_tile == TROOP_INVALID_TILE:
		return true
	var anchor_world := _territory_manager.troop_stand_tile_to_world_position(
		defense_anchor_tile,
		_troop_occupancy_width_tiles
	)
	return anchor_world.distance_to(world_pos) <= DEFEND_PURSUIT_RADIUS

func _attack_target() -> void:
	if not _has_combat_authority():
		return
	if _target == null or not _target.has_method("take_damage") or not _target.is_alive():
		return
	if _attack_cooldown > 0.0:
		return
	_target.take_damage(damage)
	_attack_cooldown = attack_interval

func _check_despawn() -> void:
	if _territory_manager == null:
		return
	if position.x < _world_rect.position.x - 1.0:
		queue_free()
		return
	if position.x > _world_rect.position.x + _world_rect.size.x + 1.0:
		queue_free()

func _update_color() -> void:
	var current_body := _get_body()
	if current_body == null:
		return
	match team:
		GameState.Team.LEFT:
			current_body.color = Color(0.25, 0.45, 0.85, 1)
		GameState.Team.RIGHT:
			current_body.color = Color(0.85, 0.35, 0.35, 1)
		_:
			current_body.color = Color(0.9, 0.75, 0.25, 1)

func get_team() -> int:
	return team

func get_unit_id() -> int:
	return unit_id

func issue_tactical_order(order: int, target_tile: Vector2i = TROOP_INVALID_TILE) -> void:
	current_order = order
	command_target_tile = target_tile
	order_revision += 1
	_troop_movement_target_tile = TROOP_INVALID_TILE
	_clear_troop_path()
	_on_tactical_order_replaced()
	match current_order:
		TacticalOrder.MOVE:
			current_status = TroopStatus.MOVING
		TacticalOrder.ADVANCE:
			current_status = TroopStatus.ADVANCING
		TacticalOrder.RETREAT:
			current_status = TroopStatus.RETREATING
		_:
			_set_defense_anchor_from_current_position()
			current_status = TroopStatus.DEFENDING

func get_command_state() -> Dictionary:
	return {
		"current_order": current_order,
		"target_tile": command_target_tile,
		"defense_anchor": defense_anchor_tile,
		"order_revision": order_revision,
		"current_status": current_status,
	}

func get_role_actions() -> Array[Dictionary]:
	return []

func _on_tactical_order_replaced() -> void:
	pass

func is_alive() -> bool:
	return current_health > 0

func take_damage(amount: int) -> void:
	if not _has_combat_authority():
		return
	if not is_alive():
		return
	var applied_damage: int = maxi(1, amount - defense)
	current_health = maxi(0, current_health - applied_damage)
	if current_health == 0:
		_die()

func _snap_to_ground() -> void:
	if _territory_manager == null:
		return
	var stand_tile := _territory_manager.get_troop_standable_tile_for_world_position(
		position,
		_troop_occupancy_width_tiles,
		_troop_occupancy_height_tiles
	)
	if stand_tile == TROOP_INVALID_TILE:
		stand_tile = _find_spawn_stand_tile_in_column()
	if stand_tile == TROOP_INVALID_TILE:
		return
	position = _territory_manager.troop_stand_tile_to_world_position(stand_tile, _troop_occupancy_width_tiles)
	_troop_fall_velocity = 0.0
	_troop_movement_target_tile = TROOP_INVALID_TILE
	if defense_anchor_tile == TROOP_INVALID_TILE:
		defense_anchor_tile = stand_tile

func set_body_polygon(points: PackedVector2Array) -> void:
	var current_body := _get_body()
	if current_body == null or points.is_empty():
		return
	current_body.polygon = points
	var bounds := _get_polygon_vertical_bounds(points)
	unit_height = bounds.y - bounds.x
	var tile_size_value := float(_territory_manager.tile_size if _territory_manager != null else 16)
	var polygon_width := 0.0
	for point in points:
		polygon_width = maxf(polygon_width, absf(point.x))
	_troop_occupancy_width_tiles = maxi(1, int(ceil((polygon_width * 2.0) / tile_size_value)))
	_troop_occupancy_height_tiles = maxi(1, int(ceil(unit_height / float(_territory_manager.tile_size if _territory_manager != null else 16))))
	current_body.position.y = -bounds.y
	_update_health_bar_position(bounds)
	_snap_to_ground()

func _get_polygon_vertical_bounds(points: PackedVector2Array) -> Vector2:
	var min_y := points[0].y
	var max_y := points[0].y
	for point in points:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	return Vector2(min_y, max_y)

func _die() -> void:
	queue_free()

func get_health_bar_root() -> Node2D:
	return _health_bar_root

func get_health_bar_fill() -> ColorRect:
	return _health_bar_fill

func _ensure_health_bar() -> void:
	if _health_bar_root == null:
		_health_bar_root = get_node_or_null("HealthBar") as Node2D
	if _health_bar_border == null:
		_health_bar_border = get_node_or_null("HealthBar/Border") as ColorRect
	if _health_bar_background == null:
		_health_bar_background = get_node_or_null("HealthBar/Background") as ColorRect
	if _health_bar_fill == null:
		_health_bar_fill = get_node_or_null("HealthBar/Fill") as ColorRect
	if _health_bar_root == null or _health_bar_border == null or _health_bar_background == null or _health_bar_fill == null:
		return

	_health_bar_border.color = HEALTH_BAR_BORDER_COLOR
	_health_bar_border.position = Vector2(-HEALTH_BAR_WIDTH * 0.5 - 1.0, -1.0)
	_health_bar_border.size = Vector2(HEALTH_BAR_WIDTH + 2.0, HEALTH_BAR_HEIGHT + 2.0)
	_health_bar_background.color = HEALTH_BAR_BACKGROUND_COLOR
	_health_bar_background.position = Vector2(-HEALTH_BAR_WIDTH * 0.5, 0.0)
	_health_bar_background.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_fill.color = HEALTH_BAR_FILL_HIGH
	_health_bar_fill.position = Vector2(-HEALTH_BAR_WIDTH * 0.5, 0.0)
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)

	var current_body := _get_body()
	if current_body != null and not current_body.polygon.is_empty():
		_update_health_bar_position(_get_polygon_vertical_bounds(current_body.polygon))
	else:
		_health_bar_root.position = Vector2(0.0, -unit_height - HEALTH_BAR_OFFSET)

func _update_health_bar_position(bounds: Vector2) -> void:
	if _health_bar_root == null:
		return
	var top_y: float = bounds.x - bounds.y
	_health_bar_root.position = Vector2(0.0, top_y - HEALTH_BAR_OFFSET)

func _refresh_health_bar() -> void:
	_ensure_health_bar()
	if _health_bar_root == null or _health_bar_fill == null:
		return
	var clamped_max_health: int = maxi(1, max_health)
	var clamped_current_health: int = clampi(current_health, 0, clamped_max_health)
	var ratio: float = float(clamped_current_health) / float(clamped_max_health)
	_visual_max_health = clamped_max_health
	_visual_current_health = clamped_current_health
	_health_bar_root.visible = clamped_current_health > 0 and clamped_current_health < clamped_max_health
	_health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	_health_bar_fill.color = HEALTH_BAR_FILL_LOW.lerp(HEALTH_BAR_FILL_HIGH, ratio)

func _get_body() -> Polygon2D:
	if body == null:
		body = get_node_or_null("Body") as Polygon2D
	return body

func _refresh_health_bar_if_needed() -> void:
	var clamped_max_health: int = maxi(1, max_health)
	var clamped_current_health: int = clampi(current_health, 0, clamped_max_health)
	if clamped_max_health == _visual_max_health and clamped_current_health == _visual_current_health:
		return
	_refresh_health_bar()

func _has_combat_authority() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

func _has_simulation_authority() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return is_multiplayer_authority()

func _process_current_order(delta: float) -> void:
	match current_order:
		TacticalOrder.MOVE:
			current_status = TroopStatus.MOVING
			_process_move_order(delta)
		TacticalOrder.ADVANCE:
			current_status = TroopStatus.ADVANCING
			_process_advance_order(delta)
		TacticalOrder.RETREAT:
			current_status = TroopStatus.RETREATING
			_process_retreat_order(delta)
		_:
			current_status = TroopStatus.DEFENDING
			_process_defend_order(delta)

func _process_advance_order(delta: float) -> void:
	var direction_x := 0
	if team == GameState.Team.LEFT:
		direction_x = 1
	elif team == GameState.Team.RIGHT:
		direction_x = -1
	if direction_x == 0:
		return
	if _territory_manager == null:
		position.x += float(direction_x) * speed * delta
		return
	if _troop_movement_target_tile != TROOP_INVALID_TILE:
		if _territory_manager.is_troop_standable_tile(
			_troop_movement_target_tile,
			_troop_occupancy_width_tiles,
			_troop_occupancy_height_tiles
		):
			_follow_troop_ground_target(_troop_movement_target_tile, delta)
			return
		_troop_movement_target_tile = TROOP_INVALID_TILE
	var current_tile := _get_troop_exact_stand_tile_from_position()
	if _apply_troop_fall_if_unsupported(delta, current_tile):
		return
	if current_tile == TROOP_INVALID_TILE:
		current_tile = _territory_manager.get_troop_standable_tile_for_world_position(
			position,
			_troop_occupancy_width_tiles,
			_troop_occupancy_height_tiles
		)
	if current_tile == TROOP_INVALID_TILE:
		return
	var forward_tile := _territory_manager.get_troop_walk_target(
		current_tile,
		direction_x,
		_troop_occupancy_width_tiles,
		_troop_occupancy_height_tiles
	)
	if forward_tile == TROOP_INVALID_TILE:
		_troop_movement_target_tile = TROOP_INVALID_TILE
		return
	_follow_troop_ground_target(forward_tile, delta)

func _process_move_order(delta: float) -> void:
	if _territory_manager == null or command_target_tile == TROOP_INVALID_TILE:
		issue_tactical_order(TacticalOrder.DEFEND)
		return
	var current_tile := _get_current_troop_stand_tile()
	if current_tile == TROOP_INVALID_TILE:
		return
	var fallback_tile := _territory_manager.find_nearest_reachable_troop_tile(
		current_tile,
		command_target_tile,
		_troop_occupancy_width_tiles,
		_troop_occupancy_height_tiles
	)
	if fallback_tile == TROOP_INVALID_TILE:
		issue_tactical_order(TacticalOrder.DEFEND)
		return
	if _troop_path_tiles.is_empty() or _troop_path_goal_tile != fallback_tile:
		_troop_path_tiles = _territory_manager.find_troop_path(
			current_tile,
			[fallback_tile],
			_troop_occupancy_width_tiles,
			_troop_occupancy_height_tiles
		)
		_troop_path_index = 0
		_troop_path_goal_tile = fallback_tile
	if _follow_troop_path(delta):
		return
	defense_anchor_tile = fallback_tile
	issue_tactical_order(TacticalOrder.DEFEND, fallback_tile)

func _process_retreat_order(delta: float) -> void:
	if _territory_manager == null:
		issue_tactical_order(TacticalOrder.DEFEND)
		return
	var base_tile := _territory_manager.get_troop_standable_tile_for_world_position(
		_territory_manager.get_base_anchor_world(team),
		_troop_occupancy_width_tiles,
		_troop_occupancy_height_tiles
	)
	if base_tile == TROOP_INVALID_TILE:
		issue_tactical_order(TacticalOrder.DEFEND)
		return
	command_target_tile = base_tile
	_process_move_order(delta)
	current_status = TroopStatus.RETREATING if current_order == TacticalOrder.MOVE else current_status

func _process_defend_order(delta: float) -> void:
	if _territory_manager == null:
		return
	if defense_anchor_tile == TROOP_INVALID_TILE:
		_set_defense_anchor_from_current_position()
	var current_tile := _get_current_troop_stand_tile()
	if current_tile == TROOP_INVALID_TILE:
		return
	var anchor_world := _territory_manager.troop_stand_tile_to_world_position(defense_anchor_tile, _troop_occupancy_width_tiles)
	if position.distance_to(anchor_world) <= 0.01:
		return
	if position.distance_to(anchor_world) <= DEFEND_PURSUIT_RADIUS:
		command_target_tile = defense_anchor_tile
		_process_move_order(delta)
		current_order = TacticalOrder.DEFEND
		current_status = TroopStatus.DEFENDING

func _follow_troop_path(delta: float) -> bool:
	if _territory_manager == null or _troop_path_tiles.is_empty():
		return false
	while _troop_path_index < _troop_path_tiles.size():
		var target_tile: Vector2i = _troop_path_tiles[_troop_path_index]
		var current_tile := _get_current_troop_stand_tile()
		if current_tile == target_tile:
			_troop_path_index += 1
			continue
		_follow_troop_ground_target(target_tile, delta)
		return true
	return false

func _get_current_troop_stand_tile() -> Vector2i:
	if _territory_manager == null:
		return TROOP_INVALID_TILE
	var current_tile := _get_troop_exact_stand_tile_from_position()
	if _apply_troop_fall_if_unsupported(0.0, current_tile):
		return TROOP_INVALID_TILE
	if current_tile == TROOP_INVALID_TILE:
		current_tile = _territory_manager.get_troop_standable_tile_for_world_position(
			position,
			_troop_occupancy_width_tiles,
			_troop_occupancy_height_tiles
		)
	return current_tile

func _clear_troop_path() -> void:
	_troop_path_tiles.clear()
	_troop_path_index = 0
	_troop_path_goal_tile = TROOP_INVALID_TILE

func _initialize_defense_anchor_if_needed() -> void:
	if defense_anchor_tile != TROOP_INVALID_TILE:
		return
	_set_defense_anchor_from_current_position()

func _set_defense_anchor_from_current_position() -> void:
	if _territory_manager == null:
		return
	var current_tile := _territory_manager.get_troop_standable_tile_for_world_position(
		position,
		_troop_occupancy_width_tiles,
		_troop_occupancy_height_tiles
	)
	if current_tile != TROOP_INVALID_TILE:
		defense_anchor_tile = current_tile

func _follow_troop_ground_target(target_tile: Vector2i, delta: float) -> void:
	if _territory_manager == null:
		return
	_troop_movement_target_tile = target_tile
	var target_world := _territory_manager.troop_stand_tile_to_world_position(target_tile, _troop_occupancy_width_tiles)
	var move_step := speed * delta
	position.x = move_toward(position.x, target_world.x, move_step)
	position.y = move_toward(position.y, target_world.y, move_step)
	if position.distance_to(target_world) <= 0.01:
		position = target_world
		_troop_movement_target_tile = TROOP_INVALID_TILE

func _get_troop_exact_stand_tile_from_position() -> Vector2i:
	if _territory_manager == null:
		return TROOP_INVALID_TILE
	var exact_tile := Vector2i(
		int(round((position.x / _territory_manager.tile_size) - (_troop_occupancy_width_tiles * 0.5))),
		int(floor(position.y / _territory_manager.tile_size)) - 1
	)
	if _territory_manager.is_troop_standable_tile(exact_tile, _troop_occupancy_width_tiles, _troop_occupancy_height_tiles):
		return exact_tile
	return TROOP_INVALID_TILE

func _apply_troop_fall_if_unsupported(delta: float, current_tile: Vector2i) -> bool:
	if _territory_manager == null:
		return false
	if current_tile != TROOP_INVALID_TILE:
		if _troop_fall_velocity > 0.0:
			position = _territory_manager.troop_stand_tile_to_world_position(current_tile, _troop_occupancy_width_tiles)
		_troop_fall_velocity = 0.0
		return false
	_troop_fall_velocity = minf(_troop_fall_velocity + TROOP_FALL_ACCELERATION * delta, TROOP_MAX_FALL_SPEED)
	position.y += _troop_fall_velocity * delta
	var landed_tile := _territory_manager.get_troop_standable_tile_for_world_position(
		position,
		_troop_occupancy_width_tiles,
		_troop_occupancy_height_tiles
	)
	if landed_tile != TROOP_INVALID_TILE:
		position = _territory_manager.troop_stand_tile_to_world_position(landed_tile, _troop_occupancy_width_tiles)
		_troop_fall_velocity = 0.0
	return true

func _find_spawn_stand_tile_in_column() -> Vector2i:
	if _territory_manager == null:
		return TROOP_INVALID_TILE
	var max_tile_x := _territory_manager.grid_width - _troop_occupancy_width_tiles
	var base_tile_x := int(round((position.x / _territory_manager.tile_size) - (_troop_occupancy_width_tiles * 0.5)))
	base_tile_x = clampi(base_tile_x, 0, maxi(0, max_tile_x))
	for tile_y in range(_territory_manager.grid_height):
		var candidate := Vector2i(base_tile_x, tile_y)
		if _territory_manager.is_troop_standable_tile(
			candidate,
			_troop_occupancy_width_tiles,
			_troop_occupancy_height_tiles
		):
			return candidate
	return TROOP_INVALID_TILE

func _configure_synchronizer() -> void:
	if synchronizer == null:
		synchronizer = get_node_or_null("Synchronizer") as MultiplayerSynchronizer
	if synchronizer == null:
		return
	synchronizer.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	_add_replicated_property(config, NodePath(":position"), true, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	_add_replicated_property(config, NodePath(":team"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":item_id"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":unit_id"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":max_health"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":current_health"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":damage"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":defense"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":tile_damage"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":current_order"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":command_target_tile"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":defense_anchor_tile"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":order_revision"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_add_replicated_property(config, NodePath(":current_status"), true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = config

func _add_replicated_property(
	config: SceneReplicationConfig,
	path: NodePath,
	include_on_spawn: bool,
	replication_mode: SceneReplicationConfig.ReplicationMode
) -> void:
	config.add_property(path)
	config.property_set_spawn(path, include_on_spawn)
	config.property_set_replication_mode(path, replication_mode)

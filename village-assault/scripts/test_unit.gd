extends Node2D

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
		_attack_target()
		return
	var direction := Vector2.ZERO
	if team == GameState.Team.LEFT:
		direction = Vector2.RIGHT
	elif team == GameState.Team.RIGHT:
		direction = Vector2.LEFT
	position.x += direction.x * speed * delta
	_snap_to_ground()
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
		max(0, int(spawn_payload.get("defense", 0)))
	)

func initialize_runtime_state(health: int, damage_value: int, defense_value: int) -> void:
	max_health = max(1, health)
	current_health = max_health
	damage = max(0, damage_value)
	defense = max(0, defense_value)

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
		if position.distance_to(node.position) <= attack_range:
			return node as Node2D
	return null

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
	position.y = _territory_manager.get_surface_world_y_at_x(position.x, 0.0)

func set_body_polygon(points: PackedVector2Array) -> void:
	var current_body := _get_body()
	if current_body == null or points.is_empty():
		return
	current_body.polygon = points
	var bounds := _get_polygon_vertical_bounds(points)
	unit_height = bounds.y - bounds.x
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

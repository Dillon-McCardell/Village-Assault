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
@export var max_health: int = 1
@export var current_health: int = 1
@export var damage: int = 0
@export var defense: int = 0

@onready var body: Polygon2D = $Body
var synchronizer: MultiplayerSynchronizer = null

var _target: Node2D
var _attack_cooldown: float = 0.0
var _territory_manager: TerritoryManager
var _world_rect: Rect2

func _enter_tree() -> void:
	_configure_synchronizer()

func prepare_for_network_spawn() -> void:
	_configure_synchronizer()

func _ready() -> void:
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
	current_health = clampi(value, 0, max_health)

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
	if body == null:
		return
	match team:
		GameState.Team.LEFT:
			body.color = Color(0.25, 0.45, 0.85, 1)
		GameState.Team.RIGHT:
			body.color = Color(0.85, 0.35, 0.35, 1)
		_:
			body.color = Color(0.9, 0.75, 0.25, 1)

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
	if body == null or points.is_empty():
		return
	body.polygon = points
	var bounds := _get_polygon_vertical_bounds(points)
	unit_height = bounds.y - bounds.x
	body.position.y = -bounds.y
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

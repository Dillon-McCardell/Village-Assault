extends Node2D

@export var speed: float = 32.0
@export var stop_range: float = 12.0
@export var unit_height: float = 16.0
@export var attack_range: float = 12.0
@export var attack_interval: float = 1.0

@onready var body: Polygon2D = $Body

var item_id: String = ""
var unit_id: int = -1
var team: int = GameState.Team.NONE
var max_health: int = 1
var current_health: int = 1
var damage: int = 0
var defense: int = 0
var _target: Node2D
var _attack_cooldown: float = 0.0
var _territory_manager: TerritoryManager
var _world_rect: Rect2
var _unit_half_height: float = 8.0

func _ready() -> void:
	add_to_group("troops")
	_territory_manager = get_tree().get_current_scene().get_node_or_null("TerritoryManager") as TerritoryManager
	if _territory_manager:
		_world_rect = _territory_manager.get_world_pixel_rect()
	_unit_half_height = unit_height * 0.5
	_snap_to_ground()
	_update_color()

func _physics_process(delta: float) -> void:
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
	_update_color()

func set_item_id(value: String) -> void:
	item_id = value

func set_unit_id(value: int) -> void:
	unit_id = value

func initialize_from_spawn_payload(spawn_payload: Dictionary) -> void:
	max_health = max(1, int(spawn_payload.get("health", 1)))
	current_health = max_health
	damage = max(0, int(spawn_payload.get("damage", 0)))
	defense = max(0, int(spawn_payload.get("defense", 0)))

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
	_sync_health()
	if current_health == 0:
		_die()

func _snap_to_ground() -> void:
	if _territory_manager == null:
		return
	position.y = _territory_manager.get_surface_world_y_at_x(position.x, _unit_half_height)

func _sync_health() -> void:
	var game: Node = get_tree().get_current_scene()
	if game != null and game.has_method("sync_unit_health") and unit_id >= 0:
		game.sync_unit_health(unit_id, current_health)
		if _should_replicate_via_rpc(game):
			game.sync_unit_health.rpc(unit_id, current_health)

func _die() -> void:
	var game: Node = get_tree().get_current_scene()
	if game != null and game.has_method("destroy_unit") and unit_id >= 0:
		game.destroy_unit(unit_id)
		if _should_replicate_via_rpc(game):
			game.destroy_unit.rpc(unit_id)
	else:
		queue_free()

func _has_combat_authority() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

func _should_replicate_via_rpc(game: Node) -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if not multiplayer.is_server():
		return false
	var script := game.get_script() as Script
	return script != null and script.resource_path == "res://scripts/game.gd"

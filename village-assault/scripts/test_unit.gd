extends Node2D

@export var speed: float = 32.0
@export var stop_range: float = 12.0
@export var unit_height: float = 16.0

@onready var body: Polygon2D = $Body

var team: int = GameState.Team.NONE
var _stopped: bool = false
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
	if _stopped:
		return
	if _has_enemy_in_range():
		_stopped = true
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

func _has_enemy_in_range() -> bool:
	for node in get_tree().get_nodes_in_group("troops"):
		if node == self:
			continue
		if not node is Node2D:
			continue
		if not node.has_method("get_team"):
			continue
		if node.get_team() == team:
			continue
		if position.distance_to(node.position) <= stop_range:
			return true
	return false

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

func _snap_to_ground() -> void:
	if _territory_manager == null:
		return
	position.y = _territory_manager.get_surface_world_y_at_x(position.x, _unit_half_height)

extends Node2D

@onready var units_root: Node2D = $Units
@onready var spawn_button: Button = $CanvasLayer/UI/SpawnButton
@onready var status_label: Label = $CanvasLayer/UI/StatusLabel
@onready var territory_manager: TerritoryManager = $TerritoryManager
@onready var camera: Camera2D = $Camera2D

var _test_unit_scene: PackedScene = preload("res://scenes/test_unit.tscn")

func _ready() -> void:
	spawn_button.pressed.connect(_on_spawn_pressed)
	GameState.local_state_updated.connect(_on_local_state_updated)
	GameState.world_settings_updated.connect(_on_world_settings_updated)
	_update_status()
	_update_camera_limits()

func _on_spawn_pressed() -> void:
	if multiplayer.multiplayer_peer == null:
		push_warning("Not connected. Host or join before spawning.")
		return
	if multiplayer.is_server():
		request_spawn_test_unit()
	else:
		request_spawn_test_unit.rpc_id(1)

func _update_status() -> void:
	if multiplayer.multiplayer_peer == null:
		status_label.text = "Status: Offline"
	elif multiplayer.is_server():
		status_label.text = "Status: Hosting"
	else:
		status_label.text = "Status: Connected"
	if GameState.local_team != GameState.Team.NONE:
		status_label.text += " | Team: %s | $%d" % [GameState.get_team_name(GameState.local_team), GameState.local_money]

func _on_local_state_updated(_team: int, _money: int) -> void:
	_update_status()
	_update_camera_anchor()

func _on_world_settings_updated(_map_width: int, _map_height: int, _map_seed: int) -> void:
	_update_camera_limits()
	_update_camera_anchor()

func _update_camera_anchor() -> void:
	if GameState.local_team == GameState.Team.NONE:
		return
	camera.position = territory_manager.get_base_anchor_world(GameState.local_team)

func _update_camera_limits() -> void:
	var world_rect := territory_manager.get_world_pixel_rect()
	camera.limit_left = int(world_rect.position.x)
	camera.limit_top = int(world_rect.position.y)
	camera.limit_right = int(world_rect.position.x + world_rect.size.x)
	camera.limit_bottom = int(world_rect.position.y + world_rect.size.y)

@rpc("any_peer", "reliable")
func request_spawn_test_unit() -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id == 0:
		requester_id = 1
	var team := GameState.get_team_for_peer(requester_id)
	if team == GameState.Team.NONE:
		return
	var spawn_pos: Vector2 = territory_manager.get_next_spawn_position_for_team(team)
	if not territory_manager.is_world_pos_in_team_territory(spawn_pos, team):
		return
	spawn_test_unit.rpc(spawn_pos, team)

@rpc("authority", "reliable", "call_local")
func spawn_test_unit(position: Vector2, team: int) -> void:
	var unit := _test_unit_scene.instantiate() as Node2D
	unit.position = position
	if unit.has_method("set_team"):
		unit.set_team(team)
	units_root.add_child(unit)

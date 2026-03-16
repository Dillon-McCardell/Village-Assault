extends Node2D

@onready var units_root: Node2D = $Units
@onready var spawn_button: Button = $CanvasLayer/UI/SpawnButton
@onready var status_label: Label = $CanvasLayer/UI/StatusLabel
@onready var territory_manager: TerritoryManager = $TerritoryManager
@onready var camera: Camera2D = $Camera2D
@onready var debug_overlay: TextEdit = $DebugLayer/DebugOverlay

var _test_unit_scene: PackedScene = preload("res://scenes/test_unit.tscn")

const TROOP_CATEGORY: String = "Troops"
var _troop_scenes: Dictionary = {
	"troop_grunt":  preload("res://scenes/troops/troop_grunt.tscn"),
	"troop_ranger": preload("res://scenes/troops/troop_ranger.tscn"),
	"troop_brute":  preload("res://scenes/troops/troop_brute.tscn"),
	"troop_scout":  preload("res://scenes/troops/troop_scout.tscn"),
}

func _physics_process(_delta: float) -> void:
	_process_spawn_queue()

func _ready() -> void:
	spawn_button.pressed.connect(_on_spawn_pressed)
	GameState.local_state_updated.connect(_on_local_state_updated)
	GameState.world_settings_updated.connect(_on_world_settings_updated)
	if camera.has_signal("zoom_changed"):
		camera.zoom_changed.connect(_on_camera_zoom_changed)
	_update_status()
	_update_camera_limits()
	DebugConsole.set_label(debug_overlay)
	DebugConsole.log_msg("Game ready. is_server=%s" % str(multiplayer.is_server()))

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

func _on_camera_zoom_changed() -> void:
	_update_camera_limits()

func _update_camera_anchor() -> void:
	if GameState.local_team == GameState.Team.NONE:
		return
	camera.position = territory_manager.get_base_anchor_world(GameState.local_team)

func _update_camera_limits() -> void:
	var world_rect := territory_manager.get_world_pixel_rect()
	var viewport_size := get_viewport_rect().size
	var half_view := (viewport_size * 0.5) / camera.zoom
	var left_limit := world_rect.position.x + half_view.x
	var right_limit := world_rect.position.x + world_rect.size.x - half_view.x
	var top_limit := world_rect.position.y + half_view.y
	var bottom_limit := world_rect.position.y + world_rect.size.y - half_view.y
	if left_limit > right_limit:
		var center_x := world_rect.position.x + world_rect.size.x * 0.5
		left_limit = center_x
		right_limit = center_x
	if top_limit > bottom_limit:
		var center_y := world_rect.position.y + world_rect.size.y * 0.5
		top_limit = center_y
		bottom_limit = center_y
	camera.limit_left = -1000000
	camera.limit_right = 1000000
	camera.limit_top = -1000000
	camera.limit_bottom = 1000000
	if camera.has_method("set_world_rect"):
		camera.set_world_rect(world_rect)

func _process_spawn_queue() -> void:
	if not multiplayer.is_server():
		return
	var request := GameState.dequeue_spawn()
	if request.is_empty():
		return
	DebugConsole.log_msg("Processing spawn: %s" % str(request))
	if request.get("team", GameState.Team.NONE) == GameState.Team.NONE:
		DebugConsole.log_msg("DISCARD: team is NONE")
		return
	var team: int = request["team"]
	var pos: Vector2 = territory_manager.get_next_spawn_position_for_team(team)
	if not territory_manager.is_world_pos_in_team_territory(pos, team):
		DebugConsole.log_msg("DISCARD: pos %s not in territory for team %d" % [str(pos), team])
		return
	var scene: PackedScene = _troop_scenes.get(request.get("item_id", ""))
	if scene == null:
		DebugConsole.log_msg("DISCARD: no scene for item_id '%s'" % request.get("item_id", ""))
		return
	DebugConsole.log_msg("Spawning %s at %s team %d" % [request["item_id"], str(pos), team])
	spawn_unit.rpc(pos, team, request["item_id"])

@rpc("authority", "reliable", "call_local")
func spawn_unit(pos: Vector2, team: int, item_id: String) -> void:
	var scene: PackedScene = _troop_scenes.get(item_id)
	if scene == null:
		return
	var unit := scene.instantiate() as Node2D
	unit.position = pos
	if unit.has_method("set_team"):
		unit.set_team(team)
	units_root.add_child(unit)

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
func spawn_test_unit(spawn_pos: Vector2, team: int) -> void:
	var unit := _test_unit_scene.instantiate() as Node2D
	unit.position = spawn_pos
	if unit.has_method("set_team"):
		unit.set_team(team)
	units_root.add_child(unit)
	DebugConsole.log_msg("spawn_test_unit: pos=%s team=%d" % [str(unit.position), team])

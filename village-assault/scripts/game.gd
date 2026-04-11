extends Node2D

signal test_unit_spawned(unit_id: int)
signal mining_selection_confirmed(tiles: Dictionary)

enum MiningSelectionState {
	INACTIVE,
	SELECTING,
	CONFIRMED,
}

@onready var units_root: Node2D = $Units
@onready var troop_spawner: MultiplayerSpawner = $TroopSpawner
@onready var spawn_button: Button = $CanvasLayer/UI/SpawnButton
@onready var status_label: Label = $CanvasLayer/UI/StatusLabel
@onready var territory_manager: TerritoryManager = $TerritoryManager
@onready var camera: Camera2D = $Camera2D
@onready var debug_overlay: TextEdit = $DebugLayer/DebugOverlay
@onready var mining_menu: Control = $CanvasLayer/UI/MiningMenu

var _test_unit_scene: PackedScene = preload("res://scenes/test_unit.tscn")
var _disconnect_overlay_scene: PackedScene = preload("res://scenes/ui/disconnect_overlay.tscn")
var _disconnect_overlay: CanvasLayer
var _pause_menu_scene: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
var _pause_menu: CanvasLayer
var _local_paused: bool = false
var _camera_anchor_initialized: bool = false
var _anchored_team: int = GameState.Team.NONE
## Set to true when the remote peer sent a "leaving" RPC before disconnecting
var _peer_left_intentionally: bool = false

const TROOP_CATEGORY: String = "Troops"
var _troop_scenes: Dictionary = {
	"troop_grunt":  preload("res://scenes/troops/troop_grunt.tscn"),
	"troop_ranger": preload("res://scenes/troops/troop_ranger.tscn"),
	"troop_brute":  preload("res://scenes/troops/troop_brute.tscn"),
	"troop_scout":  preload("res://scenes/troops/troop_scout.tscn"),
	"troop_miner":  preload("res://scenes/troops/troop_miner.tscn"),
}
var _troop_items: Dictionary = {
	"troop_grunt": preload("res://scripts/shop/troops/troop_grunt.gd").new(),
	"troop_ranger": preload("res://scripts/shop/troops/troop_ranger.gd").new(),
	"troop_brute": preload("res://scripts/shop/troops/troop_brute.gd").new(),
	"troop_scout": preload("res://scripts/shop/troops/troop_scout.gd").new(),
	"troop_miner": preload("res://scripts/shop/troops/troop_miner.gd").new(),
}
var _next_unit_id: int = 1
var _mining_selection_state: int = MiningSelectionState.INACTIVE
var _draft_mining_tiles: Dictionary = {}
var _committed_mining_tiles: Dictionary = {}
var _stroke_toggled_tiles: Dictionary = {}
var _selection_drag_active: bool = false
var _stroke_select_mode: Variant = null

func _has_active_multiplayer_peer() -> bool:
	return multiplayer.multiplayer_peer != null

func _is_multiplayer_server() -> bool:
	return _has_active_multiplayer_peer() and multiplayer.is_server()

func _get_local_peer_id_or_default(default_value: int = 0) -> int:
	if not _has_active_multiplayer_peer():
		return default_value
	return multiplayer.get_unique_id()

func _physics_process(_delta: float) -> void:
	_process_spawn_queue()

func _ready() -> void:
	GameState.set_current_scene("game")
	_configure_troop_spawner()

	_disconnect_overlay = _disconnect_overlay_scene.instantiate()
	add_child(_disconnect_overlay)

	_pause_menu = _pause_menu_scene.instantiate()
	add_child(_pause_menu)
	_pause_menu.back_pressed.connect(_on_pause_back)
	_pause_menu.main_menu_pressed.connect(_on_pause_main_menu)

	GameState.peer_disconnected_graceful.connect(_on_peer_disconnected_graceful)
	GameState.peer_reconnected.connect(_on_peer_reconnected)

	NetworkManager.server_disconnected.connect(_on_server_disconnected_game)
	NetworkManager.reconnect_succeeded.connect(_on_reconnect_succeeded_game)
	NetworkManager.local_disconnected.connect(_on_local_disconnected_game)

	_disconnect_overlay.return_to_menu_pressed.connect(_on_disconnect_return_to_menu)

	spawn_button.pressed.connect(_on_spawn_pressed)
	if mining_menu.has_signal("mine_mode_requested"):
		mining_menu.mine_mode_requested.connect(enter_mining_mode)
	if mining_menu.has_signal("confirm_pressed"):
		mining_menu.confirm_pressed.connect(confirm_mining_selection)
	if mining_menu.has_signal("cancel_pressed"):
		mining_menu.cancel_pressed.connect(cancel_mining_selection)
	GameState.local_state_updated.connect(_on_local_state_updated)
	GameState.world_settings_updated.connect(_on_world_settings_updated)
	if camera.has_signal("zoom_changed"):
		camera.zoom_changed.connect(_on_camera_zoom_changed)
	_update_status()
	_update_camera_limits()
	_refresh_mining_selection_visuals()
	DebugConsole.set_label(debug_overlay)
	DebugConsole.log_msg("Game ready. is_server=%s" % str(_is_multiplayer_server()))
	if TestHarness.is_active():
		TestHarness.on_game_ready(self)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_handle_mining_selection_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if multiplayer.multiplayer_peer == null:
			return
		if _local_paused:
			# Unpause is handled by pause_menu's own ESC handler
			return
		_request_pause()

func _on_spawn_pressed() -> void:
	if multiplayer.multiplayer_peer == null:
		push_warning("Not connected. Host or join before spawning.")
		return
	if _is_multiplayer_server():
		request_spawn_test_unit()
	else:
		request_spawn_test_unit.rpc_id(1)

func _update_status() -> void:
	if multiplayer.multiplayer_peer == null:
		status_label.text = "Status: Offline"
	elif _is_multiplayer_server():
		status_label.text = "Status: Hosting"
	else:
		status_label.text = "Status: Connected"
	if GameState.local_team != GameState.Team.NONE:
		status_label.text += " | Team: %s | $%d" % [GameState.get_team_name(GameState.local_team), GameState.local_money]

func _on_local_state_updated(_team: int, _money: int) -> void:
	_update_status()
	if _team != GameState.Team.NONE and (not _camera_anchor_initialized or _team != _anchored_team):
		_update_camera_anchor()

func _on_world_settings_updated(_map_width: int, _map_height: int, _map_seed: int) -> void:
	_update_camera_limits()
	if GameState.local_team != GameState.Team.NONE and not _camera_anchor_initialized:
		_update_camera_anchor()
	_refresh_mining_selection_visuals()

func _on_camera_zoom_changed() -> void:
	_update_camera_limits()

func _update_camera_anchor() -> void:
	if GameState.local_team == GameState.Team.NONE:
		return
	camera.position = territory_manager.get_base_anchor_world(GameState.local_team)
	_camera_anchor_initialized = true
	_anchored_team = GameState.local_team

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
	if not _is_multiplayer_server():
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
	var spawn_payload: Dictionary = get_troop_spawn_payload(request["item_id"])
	if spawn_payload.is_empty():
		DebugConsole.log_msg("DISCARD: no spawn payload for item_id '%s'" % request.get("item_id", ""))
		return
	DebugConsole.log_msg("Spawning %s at %s team %d" % [request["item_id"], str(pos), team])
	spawn_unit(pos, team, request["item_id"], _next_available_unit_id(), spawn_payload)

func spawn_unit(pos: Vector2, team: int, item_id: String, unit_id: int, spawn_payload: Dictionary) -> void:
	var scene: PackedScene = _troop_scenes.get(item_id)
	if scene == null:
		return
	var unit := scene.instantiate() as Node2D
	_initialize_spawned_unit(unit, pos, team, item_id, unit_id, spawn_payload)
	units_root.add_child(unit)

func get_troop_spawn_payload(item_id: String) -> Dictionary:
	var item = _troop_items.get(item_id)
	if item == null:
		return {}
	return item.get_spawn_payload()

func get_unit_by_id(unit_id: int) -> Node2D:
	return units_root.get_node_or_null("Troop_%d" % unit_id) as Node2D

@rpc("any_peer", "reliable")
func request_spawn_test_unit() -> void:
	if not _is_multiplayer_server():
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
	var spawn_payload: Dictionary = get_troop_spawn_payload("troop_grunt")
	spawn_test_unit(spawn_pos, team, _next_available_unit_id(), spawn_payload)

func spawn_test_unit(spawn_pos: Vector2, team: int, unit_id: int, spawn_payload: Dictionary) -> void:
	var unit := _test_unit_scene.instantiate() as Node2D
	_initialize_spawned_unit(unit, spawn_pos, team, "troop_grunt", unit_id, spawn_payload)
	units_root.add_child(unit)
	DebugConsole.log_msg("spawn_test_unit: pos=%s team=%d unit_id=%d" % [str(unit.position), team, unit_id])
	test_unit_spawned.emit(unit_id)

func _configure_troop_spawner() -> void:
	troop_spawner.spawn_path = NodePath("../Units")
	troop_spawner.clear_spawnable_scenes()
	troop_spawner.add_spawnable_scene("res://scenes/test_unit.tscn")
	for item_id in _troop_scenes.keys():
		var scene := _troop_scenes[item_id] as PackedScene
		if scene == null:
			continue
		troop_spawner.add_spawnable_scene(scene.resource_path)

func _initialize_spawned_unit(
	unit: Node2D,
	pos: Vector2,
	team: int,
	item_id: String,
	unit_id: int,
	spawn_payload: Dictionary
) -> void:
	unit.name = "Troop_%d" % unit_id
	unit.position = pos
	if unit.has_method("prepare_for_network_spawn"):
		unit.prepare_for_network_spawn()
	if multiplayer.multiplayer_peer != null:
		unit.set_multiplayer_authority(1, true)
	if unit.has_method("set_team"):
		unit.set_team(team)
	if unit.has_method("set_item_id"):
		unit.set_item_id(item_id)
	if unit.has_method("set_unit_id"):
		unit.set_unit_id(unit_id)
	if unit.has_method("initialize_runtime_state"):
		unit.initialize_runtime_state(
			int(spawn_payload.get("health", 1)),
			int(spawn_payload.get("damage", 0)),
			int(spawn_payload.get("defense", 0))
		)
	elif unit.has_method("initialize_from_spawn_payload"):
		unit.initialize_from_spawn_payload(spawn_payload)

func _next_available_unit_id() -> int:
	var unit_id := _next_unit_id
	_next_unit_id += 1
	return unit_id


# --- Disconnect handling ---

func _on_peer_disconnected_graceful(_peer_id: int) -> void:
	DebugConsole.log_msg("peer_disconnected_graceful: peer_id=%d, intentional=%s" % [_peer_id, str(_peer_left_intentionally)])
	# Host side: client disconnected or left
	_pause_menu.hide_menu()
	_local_paused = false
	get_tree().paused = true
	if _peer_left_intentionally:
		_peer_left_intentionally = false
		_disconnect_overlay.show_client_left()
	else:
		_disconnect_overlay.show_client_disconnected()

func _on_peer_reconnected(_peer_id: int) -> void:
	DebugConsole.log_msg("peer_reconnected: peer_id=%d, unpausing" % _peer_id)
	_pause_menu.hide_menu()
	_local_paused = false
	_disconnect_overlay.hide_overlay()
	get_tree().paused = false
	_update_camera_anchor()

func _on_server_disconnected_game() -> void:
	# Client side: host disconnected or left
	_pause_menu.hide_menu()
	_local_paused = false
	get_tree().paused = true
	if _peer_left_intentionally:
		_peer_left_intentionally = false
		_disconnect_overlay.show_host_left()
	else:
		_disconnect_overlay.show_host_disconnected()
		NetworkManager.start_auto_reconnect()

func _on_reconnect_succeeded_game() -> void:
	DebugConsole.log_msg("reconnect_succeeded: unpausing")
	_pause_menu.hide_menu()
	_local_paused = false
	_disconnect_overlay.hide_overlay()
	get_tree().paused = false

func _on_local_disconnected_game() -> void:
	DebugConsole.log_msg("local_disconnected: pausing and showing self-disconnect overlay")
	# Local side pressed F9 — show "you disconnected" and pause
	_pause_menu.hide_menu()
	_local_paused = false
	get_tree().paused = true
	_disconnect_overlay.show_self_disconnected()

func _on_disconnect_return_to_menu() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/boot_menu.tscn")


# --- Pause menu ---

func _request_pause() -> void:
	if _is_multiplayer_server():
		_set_paused.rpc(true, 1)
	else:
		_request_pause_from_client.rpc_id(1)

func _request_unpause() -> void:
	if _is_multiplayer_server():
		_set_paused.rpc(false, 0)
	else:
		_request_unpause_from_client.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_pause_from_client() -> void:
	if not _is_multiplayer_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	_set_paused.rpc(true, requester)

@rpc("any_peer", "reliable")
func _request_unpause_from_client() -> void:
	if not _is_multiplayer_server():
		return
	_set_paused.rpc(false, 0)

@rpc("authority", "reliable", "call_local")
func _set_paused(paused: bool, pauser_id: int = 0) -> void:
	get_tree().paused = paused
	if paused:
		var my_id := _get_local_peer_id_or_default()
		if pauser_id == my_id:
			_local_paused = true
			_pause_menu.show_pause_menu()
		else:
			_local_paused = false
			_pause_menu.show_remote_paused()
	else:
		_local_paused = false
		_pause_menu.hide_menu()

func _on_pause_back() -> void:
	_request_unpause()

func _on_pause_main_menu() -> void:
	# Tell the other player we're leaving intentionally, then disconnect
	if multiplayer.multiplayer_peer != null:
		_notify_leaving.rpc()
	# Small delay so the RPC has time to send before we kill the peer
	await get_tree().create_timer(0.1).timeout
	NetworkManager.shutdown()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/boot_menu.tscn")

## Sent by a player right before they intentionally leave via Main Menu.
## The receiving side uses this to show "left" instead of "disconnected".
@rpc("any_peer", "reliable", "call_local")
func _notify_leaving() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		return  # Ignore local call
	_peer_left_intentionally = true

func spawn_local_test_unit_for_test() -> void:
	if not _is_multiplayer_server():
		return
	request_spawn_test_unit()

func get_test_snapshot() -> Dictionary:
	var unit_ids: Array[int] = []
	for child in units_root.get_children():
		if child != null and child.has_method("get_unit_id"):
			unit_ids.append(int(child.get_unit_id()))
	unit_ids.sort()
	return {
		"scene": GameState.current_scene,
		"peer_id": _get_local_peer_id_or_default(),
		"is_server": _is_multiplayer_server(),
		"local_team": GameState.local_team,
		"local_money": GameState.local_money,
		"map_width": GameState.map_width,
		"map_height": GameState.map_height,
		"map_seed": GameState.map_seed,
		"paused": get_tree().paused,
		"disconnect_overlay_visible": _disconnect_overlay.is_overlay_visible(),
		"disconnect_overlay_message": _disconnect_overlay.get_message_text(),
		"visible_unit_ids": unit_ids,
	}

func enter_mining_mode() -> void:
	_draft_mining_tiles = _committed_mining_tiles.duplicate(true)
	_mining_selection_state = MiningSelectionState.SELECTING
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	DebugConsole.log_msg("Mining: enter mode committed=%d" % _committed_mining_tiles.size())
	if mining_menu.has_method("show_confirm_state"):
		mining_menu.show_confirm_state()
	_refresh_mining_selection_visuals()

func cancel_mining_selection() -> void:
	_draft_mining_tiles.clear()
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	if _committed_mining_tiles.is_empty():
		_mining_selection_state = MiningSelectionState.INACTIVE
	else:
		_mining_selection_state = MiningSelectionState.CONFIRMED
	DebugConsole.log_msg("Mining: cancel committed=%d" % _committed_mining_tiles.size())
	if mining_menu.has_method("show_pickaxe_state"):
		mining_menu.show_pickaxe_state()
	_refresh_mining_selection_visuals()

func confirm_mining_selection() -> void:
	if _draft_mining_tiles.is_empty():
		cancel_mining_selection()
		return
	_committed_mining_tiles = _draft_mining_tiles.duplicate(true)
	_draft_mining_tiles.clear()
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	_mining_selection_state = MiningSelectionState.CONFIRMED
	DebugConsole.log_msg("Mining: confirm tiles=%d" % _committed_mining_tiles.size())
	if mining_menu.has_method("show_pickaxe_state"):
		mining_menu.show_pickaxe_state()
	_refresh_mining_selection_visuals()
	mining_selection_confirmed.emit(_committed_mining_tiles.duplicate(true))

func toggle_draft_tile(tile: Vector2i) -> bool:
	if _mining_selection_state != MiningSelectionState.SELECTING:
		return false
	if not territory_manager.has_ground_at_tile(tile):
		return false
	if _draft_mining_tiles.has(tile):
		_draft_mining_tiles.erase(tile)
		DebugConsole.log_msg("Mining: deselect tile=%s" % str(tile))
		_refresh_mining_selection_visuals()
		return false
	else:
		_draft_mining_tiles[tile] = true
		DebugConsole.log_msg("Mining: select tile=%s" % str(tile))
		_refresh_mining_selection_visuals()
		return true

func get_committed_mining_tiles() -> Dictionary:
	return _committed_mining_tiles.duplicate(true)

func get_draft_mining_tiles() -> Dictionary:
	return _draft_mining_tiles.duplicate(true)

func get_mining_selection_state() -> int:
	return _mining_selection_state

func world_to_screen_position(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _handle_mining_selection_input(event: InputEvent) -> void:
	if _mining_selection_state != MiningSelectionState.SELECTING:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_pointer_over_blocking_ui():
				DebugConsole.log_msg("Mining: blocked by UI on press")
				return
			_selection_drag_active = true
			_stroke_toggled_tiles.clear()
			_stroke_select_mode = null
			_apply_drag_tile_from_screen_position(event.position)
		else:
			_selection_drag_active = false
			_stroke_toggled_tiles.clear()
			_stroke_select_mode = null
		return
	if event is InputEventMouseMotion and _selection_drag_active:
		if _is_pointer_over_blocking_ui():
			DebugConsole.log_msg("Mining: blocked by UI on drag")
			return
		if (event.button_mask & (1 << (MOUSE_BUTTON_LEFT - 1))) == 0:
			return
		_apply_drag_tile_from_screen_position(event.position)

func _apply_drag_tile_from_screen_position(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_position(screen_pos)
	var tile := territory_manager.world_to_tile(world_pos)
	if _stroke_toggled_tiles.has(tile):
		return
	if not territory_manager.has_ground_at_tile(tile):
		DebugConsole.log_msg("Mining: no ground screen=%s world=%s tile=%s" % [str(screen_pos), str(world_pos), str(tile)])
		return
	_stroke_toggled_tiles[tile] = true
	if _stroke_select_mode == null:
		_stroke_select_mode = toggle_draft_tile(tile)
		DebugConsole.log_msg("Mining: drag mode=%s" % ("select" if _stroke_select_mode else "deselect"))
		return
	if _stroke_select_mode:
		if _draft_mining_tiles.has(tile):
			return
		_draft_mining_tiles[tile] = true
		DebugConsole.log_msg("Mining: drag select tile=%s" % str(tile))
	else:
		if not _draft_mining_tiles.has(tile):
			return
		_draft_mining_tiles.erase(tile)
		DebugConsole.log_msg("Mining: drag deselect tile=%s" % str(tile))
	_refresh_mining_selection_visuals()

func _screen_to_world_position(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _is_pointer_over_blocking_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if not hovered.is_visible_in_tree():
		return false
	if hovered.name == "UI":
		return false
	if hovered is Button or hovered is LineEdit or hovered is OptionButton or hovered is CheckBox:
		return true
	return hovered.mouse_filter == Control.MOUSE_FILTER_STOP

func _refresh_mining_selection_visuals() -> void:
	if territory_manager == null:
		return
	match _mining_selection_state:
		MiningSelectionState.SELECTING:
			territory_manager.set_mining_committed_tiles({})
			territory_manager.set_mining_draft_tiles(_draft_mining_tiles)
		MiningSelectionState.CONFIRMED:
			territory_manager.set_mining_draft_tiles({})
			territory_manager.set_mining_committed_tiles(_committed_mining_tiles)
		_:
			territory_manager.clear_mining_selection_visuals()

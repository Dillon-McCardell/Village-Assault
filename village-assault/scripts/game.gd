extends Node2D

signal test_unit_spawned(unit_id: int)
signal mining_selection_confirmed(payload: Dictionary)

enum MiningSelectionState {
	INACTIVE,
	PICKING_MINER,
	JOB_PROMPT,
	SELECTING_DIG,
	SELECTING_HARVEST,
	CONFIRMED,
}

enum MinerJobType {
	IDLE,
	DIG,
	HARVEST,
}

@onready var units_root: Node2D = $Units
@onready var troop_spawner: MultiplayerSpawner = $TroopSpawner
@onready var spawn_button: Button = $CanvasLayer/UI/SpawnButton
@onready var status_label: Label = $CanvasLayer/UI/StatusLabel
@onready var territory_manager: TerritoryManager = $TerritoryManager
@onready var camera: Camera2D = $Camera2D
@onready var debug_overlay: TextEdit = $DebugLayer/DebugOverlay
@onready var mining_menu: Control = $CanvasLayer/UI/MiningMenu
const MINER_SCRIPT: GDScript = preload("res://scripts/troops/troop_miner.gd")

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
var _selected_miner_unit_id: int = -1
var _draft_mining_tiles: Dictionary = {}
var _draft_mining_order: Array[Vector2i] = []
var _invalid_draft_mining_tiles: Dictionary = {}
var _draft_harvest_order: Array[Vector2i] = []
var _draft_harvest_lookup: Dictionary = {}
var _draft_auto_harvest_first_ore: bool = false
var _miner_colors: Dictionary = {}
var _stroke_toggled_tiles: Dictionary = {}
var _selection_drag_active: bool = false
var _stroke_select_mode: Variant = null

const MAX_MINERS_PER_PLAYER: int = 6
const MINER_COLOR_PALETTE: Array[Color] = [
	Color(0.20, 0.70, 0.90, 1.0),
	Color(0.95, 0.45, 0.75, 1.0),
	Color(0.90, 0.72, 0.20, 1.0),
	Color(0.30, 0.82, 0.46, 1.0),
	Color(0.98, 0.56, 0.24, 1.0),
	Color(0.42, 0.62, 0.96, 1.0),
	Color(0.18, 0.78, 0.72, 1.0),
	Color(0.86, 0.38, 0.52, 1.0),
	Color(0.62, 0.52, 0.92, 1.0),
	Color(0.78, 0.84, 0.28, 1.0),
	Color(0.94, 0.62, 0.86, 1.0),
	Color(0.34, 0.88, 0.58, 1.0),
]

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
	_prune_dead_miner_state()

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
	territory_manager.tile_destroyed.connect(_on_territory_tile_destroyed)
	territory_manager.ore_revealed_for_team.connect(_on_ore_revealed_for_team)
	territory_manager.ore_depleted.connect(_on_ore_depleted)

	NetworkManager.server_disconnected.connect(_on_server_disconnected_game)
	NetworkManager.reconnect_succeeded.connect(_on_reconnect_succeeded_game)
	NetworkManager.local_disconnected.connect(_on_local_disconnected_game)

	_disconnect_overlay.return_to_menu_pressed.connect(_on_disconnect_return_to_menu)

	spawn_button.pressed.connect(_on_spawn_pressed)
	if mining_menu.has_signal("mine_mode_requested"):
		mining_menu.mine_mode_requested.connect(_on_mine_mode_requested)
	if mining_menu.has_signal("confirm_pressed"):
		mining_menu.confirm_pressed.connect(confirm_mining_selection)
	if mining_menu.has_signal("cancel_pressed"):
		mining_menu.cancel_pressed.connect(cancel_mining_selection)
	if mining_menu.has_signal("miner_selected"):
		mining_menu.miner_selected.connect(select_miner_for_mining)
	if mining_menu.has_signal("dig_job_requested"):
		mining_menu.dig_job_requested.connect(_on_dig_job_requested)
	if mining_menu.has_signal("harvest_job_requested"):
		mining_menu.harvest_job_requested.connect(_on_harvest_job_requested)
	_connect_picker_cancel_buttons()
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
	if request["item_id"] == "troop_miner":
		spawn_payload["miner_top_color"] = _generate_miner_top_color()
	DebugConsole.log_msg("Spawning %s at %s team %d" % [request["item_id"], str(pos), team])
	spawn_unit(pos, team, request["item_id"], _next_available_unit_id(), spawn_payload)

func spawn_unit(pos: Vector2, team: int, item_id: String, unit_id: int, spawn_payload: Dictionary) -> void:
	var scene: PackedScene = _troop_scenes.get(item_id)
	if scene == null:
		return
	var unit := scene.instantiate() as Node2D
	_initialize_spawned_unit(unit, pos, team, item_id, unit_id, spawn_payload)
	units_root.add_child(unit)
	if unit.has_method("_snap_to_ground"):
		unit._snap_to_ground()
	if item_id == "troop_miner":
		_register_spawned_miner(unit_id, unit, spawn_payload)

func get_troop_spawn_payload(item_id: String) -> Dictionary:
	var item = _troop_items.get(item_id)
	if item == null:
		return {}
	return item.get_spawn_payload()

func get_unit_by_id(unit_id: int) -> Node2D:
	return units_root.get_node_or_null("Troop_%d" % unit_id) as Node2D

func get_local_miners() -> Array:
	var miners: Array = []
	for child in units_root.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if not child.has_method("get_unit_id") or not child.has_method("get_team"):
			continue
		if str(child.item_id) != "troop_miner":
			continue
		if child.get_team() != GameState.local_team:
			continue
		if child.has_method("is_alive") and not child.is_alive():
			continue
		var unit_id := int(child.get_unit_id())
		var miner_color: Color = _miner_colors.get(unit_id, Color(0.9, 0.78, 0.24, 1.0))
		if child.has_method("get_miner_top_color"):
			miner_color = child.get_miner_top_color()
			_miner_colors[unit_id] = miner_color
		var status_text := "Idle"
		if child.has_method("get_passive_status_text"):
			status_text = child.get_passive_status_text()
		miners.append({
			"unit_id": unit_id,
			"color": miner_color,
			"status": status_text,
			"node": child,
		})
	miners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["unit_id"]) < int(b["unit_id"])
	)
	return miners

func get_selected_miner_unit_id() -> int:
	return _selected_miner_unit_id

func get_current_invalid_mining_tiles() -> Dictionary:
	return _invalid_draft_mining_tiles.duplicate(true)

func get_all_committed_mining_tiles() -> Dictionary:
	var assignments: Dictionary = {}
	for miner in get_local_miners():
		var node: Variant = miner.get("node")
		if node == null or not node.has_method("get_miner_job"):
			continue
		var job: Dictionary = node.get_miner_job()
		if int(job.get("job_type", MinerJobType.IDLE)) != MinerJobType.DIG:
			continue
		var committed_tiles: Dictionary = {}
		for tile in _typed_tile_array(job.get("dig_tiles", [])):
			committed_tiles[tile] = true
		assignments[int(miner["unit_id"])] = committed_tiles
	return assignments

func get_all_committed_harvest_orders() -> Dictionary:
	var assignments: Dictionary = {}
	for miner in get_local_miners():
		var node: Variant = miner.get("node")
		if node == null or not node.has_method("get_miner_job"):
			continue
		var job: Dictionary = node.get_miner_job()
		if int(job.get("job_type", MinerJobType.IDLE)) != MinerJobType.HARVEST:
			continue
		assignments[int(miner["unit_id"])] = _typed_tile_array(job.get("assigned_ore_tiles", []))
	return assignments

func _register_spawned_miner(unit_id: int, unit: Node2D, spawn_payload: Dictionary) -> void:
	var top_color: Color = spawn_payload.get("miner_top_color", Color(0.9, 0.78, 0.24, 1.0))
	_miner_colors[unit_id] = top_color
	if unit.has_method("set_miner_top_color"):
		unit.set_miner_top_color(top_color)
	if unit.has_method("set_miner_job"):
		unit.set_miner_job(_make_idle_job(unit_id, top_color))

func _prune_dead_miner_state() -> void:
	var live_miner_ids: Dictionary = {}
	for miner in get_local_miners():
		live_miner_ids[int(miner["unit_id"])] = true
	for miner in get_local_miners():
		var unit_id := int(miner["unit_id"])
		if not _miner_colors.has(unit_id):
			_miner_colors[unit_id] = miner.get("color", Color(0.9, 0.78, 0.24, 1.0))
	if _selected_miner_unit_id != -1 and not live_miner_ids.has(_selected_miner_unit_id):
		cancel_mining_selection()
	_refresh_mining_selection_visuals()

func _generate_miner_top_color() -> Color:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var used_palette_indices: Dictionary = {}
	for child in units_root.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if str(child.get("item_id")) != "troop_miner":
			continue
		var miner_color: Color = Color.WHITE
		if child.has_method("get_miner_top_color"):
			miner_color = child.get_miner_top_color()
		for i in range(MINER_COLOR_PALETTE.size()):
			if MINER_COLOR_PALETTE[i].is_equal_approx(miner_color):
				used_palette_indices[i] = true
				break
	var available_indices: Array[int] = []
	for i in range(MINER_COLOR_PALETTE.size()):
		if not used_palette_indices.has(i):
			available_indices.append(i)
	if available_indices.is_empty():
		return MINER_COLOR_PALETTE[0]
	return MINER_COLOR_PALETTE[available_indices[rng.randi_range(0, available_indices.size() - 1)]]

func _get_selected_miner_color() -> Color:
	return _miner_colors.get(_selected_miner_unit_id, Color(1, 1, 1, TerritoryManager.MINING_DRAFT_ALPHA))

func _get_miner_job(unit_id: int) -> Dictionary:
	var miner := get_unit_by_id(unit_id)
	if miner == null or not is_instance_valid(miner) or not miner.has_method("get_miner_job"):
		return {}
	return miner.get_miner_job()

func _make_idle_job(unit_id: int, miner_color: Color = Color.WHITE) -> Dictionary:
	return {
		"unit_id": unit_id,
		"job_type": MinerJobType.IDLE,
		"dig_auto_harvest_first_ore": false,
		"dig_tiles": [],
		"dig_tiles_lookup": {},
		"assigned_ore_tiles": [],
		"assigned_ore_lookup": {},
		"active_ore_index": 0,
		"miner_color": miner_color,
	}

func _build_dig_job(unit_id: int, tile_order: Array[Vector2i], auto_harvest: bool) -> Dictionary:
	var tile_lookup: Dictionary = {}
	for tile in tile_order:
		tile_lookup[tile] = true
	return {
		"unit_id": unit_id,
		"job_type": MinerJobType.DIG if not tile_order.is_empty() else MinerJobType.IDLE,
		"dig_auto_harvest_first_ore": auto_harvest,
		"dig_tiles": tile_order.duplicate(),
		"dig_tiles_lookup": tile_lookup,
		"assigned_ore_tiles": [],
		"assigned_ore_lookup": {},
		"active_ore_index": 0,
		"miner_color": _miner_colors.get(unit_id, Color.WHITE),
	}

func _build_harvest_job(unit_id: int, ore_order: Array[Vector2i]) -> Dictionary:
	var ore_lookup: Dictionary = {}
	for tile in ore_order:
		ore_lookup[tile] = true
	return {
		"unit_id": unit_id,
		"job_type": MinerJobType.HARVEST if not ore_order.is_empty() else MinerJobType.IDLE,
		"dig_auto_harvest_first_ore": false,
		"dig_tiles": [],
		"dig_tiles_lookup": {},
		"assigned_ore_tiles": ore_order.duplicate(),
		"assigned_ore_lookup": ore_lookup,
		"active_ore_index": 0,
		"miner_color": _miner_colors.get(unit_id, Color.WHITE),
	}

func _apply_miner_job(unit_id: int, job_payload: Dictionary) -> void:
	var miner := get_unit_by_id(unit_id)
	if miner == null or not is_instance_valid(miner) or not miner.has_method("set_miner_job"):
		return
	miner.set_miner_job(job_payload)

func _on_territory_tile_destroyed(tile_pos: Vector2i) -> void:
	if not _is_multiplayer_server():
		return
	_sync_destroyed_tile.rpc(tile_pos.x, tile_pos.y)

func _on_ore_revealed_for_team(team: int, tiles: Array) -> void:
	if not _is_multiplayer_server():
		return
	_sync_revealed_ore.rpc(team, tiles)

func _on_ore_depleted(tile_pos: Vector2i) -> void:
	if not _is_multiplayer_server():
		return
	_sync_depleted_ore.rpc(tile_pos.x, tile_pos.y)

func _sync_world_state_to_peer(peer_id: int) -> void:
	if not _is_multiplayer_server() or territory_manager == null or peer_id <= 0:
		return
	var destroyed_tiles := territory_manager.get_destroyed_terrain_tiles()
	var depleted_ore_tiles := territory_manager.get_depleted_ore_tiles()
	var revealed_snapshot := territory_manager.get_revealed_ore_snapshot()
	DebugConsole.log_msg("MiningRPC: replay_world_state peer=%d destroyed=%d depleted_ore=%d" % [
		peer_id,
		destroyed_tiles.size(),
		depleted_ore_tiles.size(),
	])
	_sync_world_state_snapshot.rpc_id(peer_id, destroyed_tiles, depleted_ore_tiles, revealed_snapshot)

@rpc("authority", "reliable", "call_local")
func _sync_destroyed_tile(tile_x: int, tile_y: int) -> void:
	if territory_manager == null:
		return
	territory_manager.destroy_tile(Vector2i(tile_x, tile_y))

@rpc("authority", "reliable", "call_local")
func _sync_revealed_ore(team: int, tiles: Array) -> void:
	if territory_manager == null:
		return
	territory_manager.reveal_ore_tiles_for_team(team, _typed_tile_array(tiles))

@rpc("authority", "reliable", "call_local")
func _sync_depleted_ore(tile_x: int, tile_y: int) -> void:
	if territory_manager == null:
		return
	territory_manager.deplete_ore_tile(Vector2i(tile_x, tile_y))

@rpc("authority", "reliable")
func _sync_world_state_snapshot(destroyed_tiles: Array, depleted_ore_tiles: Array, revealed_snapshot: Dictionary) -> void:
	if territory_manager == null:
		return
	territory_manager.apply_world_state_snapshot(destroyed_tiles, depleted_ore_tiles, revealed_snapshot)

@rpc("any_peer", "reliable")
func _request_assign_miner_job(unit_id: int, job_payload: Dictionary) -> void:
	if not _is_multiplayer_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id == 0:
		requester_id = 1
	var requester_team := GameState.get_team_for_peer(requester_id)
	var miner := get_unit_by_id(unit_id)
	if miner == null or not is_instance_valid(miner):
		return
	if str(miner.get("item_id")) != "troop_miner":
		return
	if int(miner.get("team")) != requester_team:
		return
	if not _validate_requested_miner_job(job_payload, requester_team):
		DebugConsole.log_msg("MiningRPC: reject miner=%d payload=%s" % [unit_id, str(job_payload)])
		return
	DebugConsole.log_msg("MiningRPC: accept miner=%d payload=%s" % [unit_id, str(job_payload)])
	_apply_miner_job(unit_id, job_payload)

func _validate_requested_miner_job(job_payload: Dictionary, requester_team: int) -> bool:
	var job_type := int(job_payload.get("job_type", MinerJobType.IDLE))
	match job_type:
		MinerJobType.DIG:
			for tile in _typed_tile_array(job_payload.get("dig_tiles", [])):
				if not territory_manager.is_mineable_terrain_tile(tile):
					return false
			return true
		MinerJobType.HARVEST:
			for tile in _typed_tile_array(job_payload.get("assigned_ore_tiles", [])):
				if not territory_manager.is_ore_tile(tile):
					return false
				if not territory_manager.is_ore_revealed_to_team(tile, requester_team):
					return false
			return true
		_:
			return true

func _typed_tile_array(raw_tiles: Variant) -> Array[Vector2i]:
	var typed_tiles: Array[Vector2i] = []
	if raw_tiles is Array:
		for raw_tile in raw_tiles:
			typed_tiles.append(raw_tile)
	return typed_tiles

func _has_any_committed_mining_assignments() -> bool:
	for miner in get_local_miners():
		var node: Variant = miner.get("node")
		if node == null or not node.has_method("get_miner_job"):
			continue
		var job: Dictionary = node.get_miner_job()
		if int(job.get("job_type", MinerJobType.IDLE)) != MinerJobType.IDLE:
			return true
	return false

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
			int(spawn_payload.get("defense", 0)),
			int(spawn_payload.get("tile_damage", 0))
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
	if _is_multiplayer_server():
		_sync_world_state_to_peer(_peer_id)
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
		"destroyed_terrain_tiles": territory_manager.get_destroyed_terrain_tiles() if territory_manager != null else [],
		"depleted_ore_tiles": territory_manager.get_depleted_ore_tiles() if territory_manager != null else [],
		"revealed_ore_snapshot": territory_manager.get_revealed_ore_snapshot() if territory_manager != null else {},
	}

func open_miner_picker() -> void:
	_prune_dead_miner_state()
	_selected_miner_unit_id = -1
	_draft_mining_tiles.clear()
	_draft_mining_order.clear()
	_draft_harvest_order.clear()
	_draft_harvest_lookup.clear()
	_invalid_draft_mining_tiles.clear()
	_draft_auto_harvest_first_ore = false
	_mining_selection_state = MiningSelectionState.PICKING_MINER
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	territory_manager.clear_harvest_queue_overlay()
	if mining_menu.has_method("show_pickaxe_state"):
		mining_menu.show_pickaxe_state()
	if mining_menu.has_method("show_miner_picker"):
		mining_menu.show_miner_picker(get_local_miners())
	_refresh_mining_selection_visuals()

func enter_mining_mode() -> void:
	open_miner_picker()

func _on_mine_mode_requested() -> void:
	if _mining_selection_state == MiningSelectionState.PICKING_MINER \
		or _mining_selection_state == MiningSelectionState.JOB_PROMPT \
		or _mining_selection_state == MiningSelectionState.SELECTING_DIG \
		or _mining_selection_state == MiningSelectionState.SELECTING_HARVEST:
		cancel_mining_selection()
		return
	open_miner_picker()

func _connect_picker_cancel_buttons() -> void:
	var mine_button := mining_menu.get_origin_button() as Button if mining_menu.has_method("get_origin_button") else null
	var cancel_button := mining_menu.get_cancel_button() as Button if mining_menu.has_method("get_cancel_button") else null
	for node in $CanvasLayer/UI.find_children("", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		if mining_menu.is_ancestor_of(button):
			continue
		if button == mine_button or button == cancel_button:
			continue
		if button.pressed.is_connected(_on_non_mining_button_pressed):
			continue
		button.pressed.connect(_on_non_mining_button_pressed)

func _on_non_mining_button_pressed() -> void:
	if _mining_selection_state != MiningSelectionState.INACTIVE:
		cancel_mining_selection()

func select_miner_for_mining(unit_id: int) -> void:
	var committed_job := _get_miner_job(unit_id)
	_selected_miner_unit_id = unit_id
	_draft_mining_tiles.clear()
	_draft_mining_order.clear()
	_draft_harvest_order.clear()
	_draft_harvest_lookup.clear()
	_invalid_draft_mining_tiles.clear()
	if int(committed_job.get("job_type", MinerJobType.IDLE)) == MinerJobType.DIG:
		_draft_mining_order = _typed_tile_array(committed_job.get("dig_tiles", []))
		for tile in _draft_mining_order:
			_draft_mining_tiles[tile] = true
		_draft_auto_harvest_first_ore = bool(committed_job.get("dig_auto_harvest_first_ore", false))
	elif int(committed_job.get("job_type", MinerJobType.IDLE)) == MinerJobType.HARVEST:
		_draft_harvest_order = _typed_tile_array(committed_job.get("assigned_ore_tiles", []))
		for tile in _draft_harvest_order:
			_draft_harvest_lookup[tile] = true
	_invalid_draft_mining_tiles = territory_manager.get_invalid_mining_selection_tiles(_draft_mining_tiles)
	_mining_selection_state = MiningSelectionState.JOB_PROMPT
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	if mining_menu.has_method("show_job_prompt"):
		mining_menu.show_job_prompt(_draft_auto_harvest_first_ore)
	territory_manager.clear_harvest_queue_overlay()
	_refresh_mining_selection_visuals()

func _on_dig_job_requested(auto_harvest_first_ore: bool) -> void:
	if _selected_miner_unit_id == -1:
		return
	_draft_auto_harvest_first_ore = auto_harvest_first_ore
	_invalid_draft_mining_tiles = territory_manager.get_invalid_mining_selection_tiles(_draft_mining_tiles)
	_mining_selection_state = MiningSelectionState.SELECTING_DIG
	if mining_menu.has_method("show_confirm_state"):
		mining_menu.show_confirm_state()
	territory_manager.clear_harvest_queue_overlay()
	_refresh_mining_selection_visuals()

func _on_harvest_job_requested() -> void:
	if _selected_miner_unit_id == -1:
		return
	_mining_selection_state = MiningSelectionState.SELECTING_HARVEST
	if mining_menu.has_method("show_confirm_state"):
		mining_menu.show_confirm_state()
	territory_manager.set_harvest_queue_overlay(_draft_harvest_order)
	_refresh_mining_selection_visuals()

func cancel_mining_selection() -> void:
	_draft_mining_tiles.clear()
	_draft_mining_order.clear()
	_draft_harvest_order.clear()
	_draft_harvest_lookup.clear()
	_invalid_draft_mining_tiles.clear()
	_draft_auto_harvest_first_ore = false
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	_selected_miner_unit_id = -1
	territory_manager.clear_harvest_queue_overlay()
	if not _has_any_committed_mining_assignments():
		_mining_selection_state = MiningSelectionState.INACTIVE
	else:
		_mining_selection_state = MiningSelectionState.CONFIRMED
	if mining_menu.has_method("show_pickaxe_state"):
		mining_menu.show_pickaxe_state()
	_refresh_mining_selection_visuals()

func confirm_mining_selection() -> void:
	if _selected_miner_unit_id == -1:
		cancel_mining_selection()
		return
	var selected_unit_id := _selected_miner_unit_id
	var committed_job := _make_idle_job(selected_unit_id, _miner_colors.get(selected_unit_id, Color.WHITE))
	if _mining_selection_state == MiningSelectionState.SELECTING_DIG:
		for raw_tile in _invalid_draft_mining_tiles.keys():
			var tile: Vector2i = raw_tile
			_draft_mining_tiles.erase(tile)
			_draft_mining_order.erase(tile)
		committed_job = _build_dig_job(selected_unit_id, _draft_mining_order, _draft_auto_harvest_first_ore)
	elif _mining_selection_state == MiningSelectionState.SELECTING_HARVEST:
		committed_job = _build_harvest_job(selected_unit_id, _draft_harvest_order)
	DebugConsole.log_msg("MiningJob: confirm miner=%d payload=%s" % [selected_unit_id, str(committed_job)])
	_apply_miner_job(selected_unit_id, committed_job)
	_draft_mining_tiles.clear()
	_draft_mining_order.clear()
	_draft_harvest_order.clear()
	_draft_harvest_lookup.clear()
	_invalid_draft_mining_tiles.clear()
	_draft_auto_harvest_first_ore = false
	_selection_drag_active = false
	_stroke_toggled_tiles.clear()
	_stroke_select_mode = null
	_mining_selection_state = MiningSelectionState.CONFIRMED
	territory_manager.clear_harvest_queue_overlay()
	if not _is_multiplayer_server():
		_request_assign_miner_job.rpc_id(1, selected_unit_id, committed_job)
	_selected_miner_unit_id = -1
	if mining_menu.has_method("show_pickaxe_state"):
		mining_menu.show_pickaxe_state()
	_refresh_mining_selection_visuals()
	mining_selection_confirmed.emit({
		"unit_id": selected_unit_id,
		"job_type": int(committed_job.get("job_type", MinerJobType.IDLE)),
		"tiles": _typed_tile_array(committed_job.get("dig_tiles", [])),
		"tile_order": _typed_tile_array(committed_job.get("dig_tiles", [])),
		"ore_order": _typed_tile_array(committed_job.get("assigned_ore_tiles", [])),
	})

func toggle_draft_tile(tile: Vector2i) -> bool:
	if _mining_selection_state != MiningSelectionState.SELECTING_DIG:
		return false
	if not territory_manager.is_mineable_terrain_tile(tile):
		return false
	if _draft_mining_tiles.has(tile):
		_draft_mining_tiles.erase(tile)
		_draft_mining_order.erase(tile)
		_invalid_draft_mining_tiles = territory_manager.get_invalid_mining_selection_tiles(_draft_mining_tiles)
		_refresh_mining_selection_visuals()
		return false
	_draft_mining_tiles[tile] = true
	if not _draft_mining_order.has(tile):
		_draft_mining_order.append(tile)
	_invalid_draft_mining_tiles = territory_manager.get_invalid_mining_selection_tiles(_draft_mining_tiles)
	_refresh_mining_selection_visuals()
	return true

func toggle_draft_ore_tile(tile: Vector2i) -> bool:
	if _mining_selection_state != MiningSelectionState.SELECTING_HARVEST:
		return false
	if not territory_manager.is_ore_tile(tile):
		DebugConsole.log_msg("MiningJob: reject harvest tile=%s reason=not_ore" % str(tile))
		return false
	if not territory_manager.is_ore_revealed_to_team(tile, GameState.local_team):
		DebugConsole.log_msg("MiningJob: reject harvest tile=%s reason=hidden" % str(tile))
		return false
	if _draft_harvest_lookup.has(tile):
		_draft_harvest_lookup.erase(tile)
		_draft_harvest_order.erase(tile)
	else:
		_draft_harvest_lookup[tile] = true
		_draft_harvest_order.append(tile)
	territory_manager.set_harvest_queue_overlay(_draft_harvest_order)
	return true

func get_committed_mining_tiles() -> Dictionary:
	if _selected_miner_unit_id != -1:
		var job := _get_miner_job(_selected_miner_unit_id)
		var committed: Dictionary = {}
		for tile in _typed_tile_array(job.get("dig_tiles", [])):
			committed[tile] = true
		return committed
	return {}

func get_draft_mining_tiles() -> Dictionary:
	return _draft_mining_tiles.duplicate(true)

func get_draft_harvest_tiles() -> Array[Vector2i]:
	return _draft_harvest_order.duplicate()

func get_mining_selection_state() -> int:
	return _mining_selection_state

func world_to_screen_position(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _handle_mining_selection_input(event: InputEvent) -> void:
	if _mining_selection_state == MiningSelectionState.PICKING_MINER:
		_handle_miner_picker_input(event)
		return
	if _mining_selection_state != MiningSelectionState.SELECTING_DIG and _mining_selection_state != MiningSelectionState.SELECTING_HARVEST:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_pointer_over_blocking_ui():
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
			return
		if (event.button_mask & (1 << (MOUSE_BUTTON_LEFT - 1))) == 0:
			return
		_apply_drag_tile_from_screen_position(event.position)

func _apply_drag_tile_from_screen_position(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_position(screen_pos)
	var tile := territory_manager.world_to_tile(world_pos)
	if _stroke_toggled_tiles.has(tile):
		return
	_stroke_toggled_tiles[tile] = true
	if _mining_selection_state == MiningSelectionState.SELECTING_HARVEST:
		toggle_draft_ore_tile(tile)
		return
	if not territory_manager.is_mineable_terrain_tile(tile):
		return
	if _stroke_select_mode == null:
		_stroke_select_mode = toggle_draft_tile(tile)
		return
	if _stroke_select_mode:
		if _draft_mining_tiles.has(tile):
			return
		_draft_mining_tiles[tile] = true
		if not _draft_mining_order.has(tile):
			_draft_mining_order.append(tile)
	else:
		if not _draft_mining_tiles.has(tile):
			return
		_draft_mining_tiles.erase(tile)
		_draft_mining_order.erase(tile)
	_invalid_draft_mining_tiles = territory_manager.get_invalid_mining_selection_tiles(_draft_mining_tiles)
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

func _handle_miner_picker_input(_event: InputEvent) -> void:
	return

func _refresh_mining_selection_visuals() -> void:
	if territory_manager == null:
		return
	var passive_assignments := get_all_committed_mining_tiles()
	var active_color := _get_selected_miner_color()
	match _mining_selection_state:
		MiningSelectionState.SELECTING_DIG:
			territory_manager.clear_mining_selection_visuals()
			territory_manager.set_mining_draft_tiles(
				_draft_mining_tiles,
				Color(active_color.r, active_color.g, active_color.b, territory_manager.MINING_DRAFT_ALPHA)
			)
			territory_manager.set_mining_invalid_tiles(_invalid_draft_mining_tiles)
			territory_manager.clear_harvest_queue_overlay()
		MiningSelectionState.SELECTING_HARVEST:
			territory_manager.set_mining_draft_tiles({})
			territory_manager.set_mining_invalid_tiles({})
			territory_manager.set_passive_mining_assignments(passive_assignments, _miner_colors)
			territory_manager.set_harvest_queue_overlay(_draft_harvest_order)
		MiningSelectionState.CONFIRMED, MiningSelectionState.PICKING_MINER, MiningSelectionState.JOB_PROMPT:
			territory_manager.set_mining_draft_tiles({})
			territory_manager.set_mining_invalid_tiles({})
			territory_manager.set_passive_mining_assignments(passive_assignments, _miner_colors)
			territory_manager.clear_harvest_queue_overlay()
		_:
			territory_manager.clear_mining_selection_visuals()
			territory_manager.clear_harvest_queue_overlay()

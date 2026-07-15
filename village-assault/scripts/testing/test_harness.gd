extends Node

const ROLE_HOST: String = "host"
const ROLE_CLIENT: String = "client"
const SCENE_BOOT: String = "boot_menu"
const SCENE_LOBBY: String = "lobby"
const SCENE_GAME: String = "game"
const SCENARIO_GAME_RECONNECT: String = "game_reconnect"
const SCENARIO_LOBBY_RECONNECT: String = "lobby_reconnect"
const SCENARIO_CUSTOM_SESSION: String = "custom_session"
const POST_RECONNECT_DEADLINE_MSEC: int = 5000
const GROUPED_MINING_ASSIGNMENT_HOLD_MSEC: int = 750
const MINER_JOB_IDLE: int = 0
const MINER_JOB_DIG: int = 1
const TACTICAL_ORDER_DEFEND: int = 2
const TROOP_STATUS_DEFENDING: int = 3
const TROOP_STATUS_MINING: int = 6
const TROOP_STATUS_MOVING_TO_DIG_SITE: int = 7
const TEST_SESSION_CONFIGURATOR: GDScript = preload(
	"res://scripts/testing/test_session_configurator.gd"
)

var _active: bool = false
var _role: String = ""
var _scenario: String = SCENARIO_GAME_RECONNECT
var _address: String = "127.0.0.1"
var _port: int = NetworkManager.DEFAULT_PORT
var _artifacts_dir: String = ""
var _run_id: String = ""
var _event_path: String = ""
var _event_file: FileAccess
var _session_config_path: String = ""
var _session_player_count: int = 1
var _session_config: Dictionary = {}
var _session_configurator: TestSessionConfigurator = null
var _custom_session_applied: bool = false
var _custom_session_ready: bool = false
var _custom_automation_command_sent: bool = false
var _custom_automation_assignment_observed: bool = false
var _custom_automation_progress_observed: bool = false
var _custom_automation_workers_released: bool = false
var _custom_automation_release_msec: int = -1
var _custom_automation_deadline_msec: int = -1
var _custom_automation_complete_sent: bool = false

var _host_started: bool = false
var _join_started: bool = false
var _match_started: bool = false
var _spawn_requested: bool = false
var _spawned_unit_id: int = -1
var _client_pre_disconnect_snapshot_sent: bool = false
var _client_disconnect_triggered: bool = false
var _client_reconnect_started: bool = false
var _client_reconnect_succeeded: bool = false
var _client_complete_sent: bool = false
var _host_complete_sent: bool = false
var _post_reconnect_deadline_msec: int = -1
var _client_lobby_complete_deadline_msec: int = -1

var _current_game: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var raw_args := PackedStringArray()
	raw_args.append_array(OS.get_cmdline_args())
	raw_args.append_array(OS.get_cmdline_user_args())
	var args := _parse_args(raw_args)
	_active = args.has("test-mode")
	if not _active:
		return
	_role = String(args.get("test-role", ""))
	_scenario = String(args.get("test-scenario", SCENARIO_GAME_RECONNECT))
	_address = String(args.get("test-address", "127.0.0.1"))
	_port = int(args.get("test-port", NetworkManager.DEFAULT_PORT))
	_artifacts_dir = String(args.get("test-artifacts-dir", "user://test_harness"))
	_run_id = String(args.get("test-run-id", "manual"))
	if _role != ROLE_HOST and _role != ROLE_CLIENT:
		push_error("TestHarness: invalid test role '%s'" % _role)
		_active = false
		return
	if _scenario not in [SCENARIO_GAME_RECONNECT, SCENARIO_LOBBY_RECONNECT, SCENARIO_CUSTOM_SESSION]:
		push_error("TestHarness: invalid test scenario '%s'" % _scenario)
		_active = false
		return
	if _scenario == SCENARIO_CUSTOM_SESSION:
		_session_config_path = String(args.get("test-session-config", ""))
		_session_player_count = clampi(int(args.get("test-session-players", 1)), 1, 2)
		_session_configurator = TEST_SESSION_CONFIGURATOR.new()
		_session_config = _session_configurator.load_scenario(_session_config_path)
		if _session_config.is_empty():
			push_error(
				"TestHarness: invalid custom session '%s': %s" % [
					_session_config_path,
					"; ".join(_session_configurator.errors),
				]
			)
			_active = false
			return
	if not _open_event_file():
		push_error("TestHarness: failed to open event file '%s'" % _event_path)
		_active = false
		return
	_connect_runtime_signals()
	_emit_event("harness_ready", {"run_id": _run_id, "role": _role, "port": _port})

func _process(_delta: float) -> void:
	if not _active:
		return
	if _scenario == SCENARIO_CUSTOM_SESSION:
		_drive_custom_session_automation()
	elif _role == ROLE_CLIENT:
		match _scenario:
			SCENARIO_GAME_RECONNECT:
				_drive_client_game_scenario()
			SCENARIO_LOBBY_RECONNECT:
				_drive_client_lobby_scenario()

func is_active() -> bool:
	return _active

func on_boot_menu_ready(menu: BootMenu) -> void:
	if not _active:
		return
	_emit_event("boot_ready", {"scene": SCENE_BOOT})
	if _role == ROLE_HOST and not _host_started:
		_host_started = true
		if _scenario == SCENARIO_CUSTOM_SESSION:
			var settings := _session_configurator.get_world_settings(_session_config)
			menu.call_deferred(
				"start_custom_test_host",
				_port,
				int(settings["width"]),
				int(settings["height"]),
				int(settings["seed"])
			)
		else:
			menu.call_deferred("start_host_for_test", _port)
	elif _role == ROLE_CLIENT and not _join_started:
		_join_started = true
		menu.call_deferred("join_for_test", _address, _port)

func on_lobby_ready(lobby: Control) -> void:
	if not _active:
		return
	_emit_event("lobby_ready", {
		"scene": SCENE_LOBBY,
		"player_count": _get_lobby_player_count(lobby),
		"snapshot": _capture_scene_snapshot(),
	})
	on_lobby_state_changed(lobby)

func on_lobby_state_changed(lobby: Control) -> void:
	if not _active:
		return
	_emit_event("lobby_state_changed", {
		"scene": SCENE_LOBBY,
		"player_count": _get_lobby_player_count(lobby),
		"snapshot": _capture_scene_snapshot(),
	})
	if _role != ROLE_HOST or _match_started:
		return
	if _scenario == SCENARIO_CUSTOM_SESSION:
		if _get_lobby_player_count(lobby) < _session_player_count:
			return
		_match_started = true
		_emit_event("match_started", {
			"scene": SCENE_LOBBY,
			"session_players": _session_player_count,
		})
		lobby.call_deferred("start_game_for_test")
		return
	if _scenario != SCENARIO_GAME_RECONNECT:
		return
	if _get_lobby_player_count(lobby) < 2:
		return
	_match_started = true
	_emit_event("match_started", {"scene": SCENE_LOBBY})
	lobby.call_deferred("start_game_for_test")

func on_game_ready(game: Node) -> void:
	if not _active:
		return
	_current_game = game
	var spawned_callable := Callable(self, "_on_game_test_unit_spawned")
	if not game.is_connected("test_unit_spawned", spawned_callable):
		game.connect("test_unit_spawned", spawned_callable)
	_emit_event("game_ready", {
		"scene": SCENE_GAME,
		"snapshot": game.call("get_test_snapshot"),
	})
	if _scenario == SCENARIO_CUSTOM_SESSION:
		call_deferred("_apply_custom_session", game)
		return
	if _role == ROLE_HOST and not _spawn_requested:
		_spawn_requested = true
		game.call_deferred("spawn_local_test_unit_for_test")

func _apply_custom_session(game: Node) -> void:
	if _custom_session_applied or game == null or not is_instance_valid(game):
		return
	_custom_session_applied = true
	if not _session_configurator.apply_terrain(game, _session_config):
		_emit_event("failure", {
			"message": "Failed to apply custom terrain",
			"errors": Array(_session_configurator.errors),
		})
		return
	var spawned_ids: Array[int] = []
	if _role == ROLE_HOST:
		spawned_ids = _session_configurator.spawn_troops(game, _session_config)
	else:
		var expected_ids := _session_configurator.get_troop_unit_ids(_session_config)
		var replication_deadline := Time.get_ticks_msec() + POST_RECONNECT_DEADLINE_MSEC
		while not _game_has_units(game, expected_ids):
			if Time.get_ticks_msec() >= replication_deadline:
				_emit_event("failure", {
					"message": "Timed out waiting for custom session troops",
					"expected_unit_ids": expected_ids,
					"snapshot": game.call("get_test_snapshot"),
				})
				return
			await get_tree().process_frame
	_session_configurator.apply_camera(game, _session_config, _role)
	_custom_session_ready = true
	var automation: Dictionary = _session_config.get("automation", {})
	if not automation.is_empty():
		_custom_automation_deadline_msec = Time.get_ticks_msec() \
			+ int(float(automation.get("timeout_sec", 15.0)) * 1000.0)
	_emit_event("custom_session_ready", {
		"config": _session_config_path,
		"name": String(_session_config.get("name", _session_config_path.get_file())),
		"spawned_unit_ids": spawned_ids,
		"snapshot": game.call("get_test_snapshot"),
	})

func _drive_custom_session_automation() -> void:
	if not _custom_session_ready or _custom_automation_complete_sent:
		return
	if _current_game == null or not is_instance_valid(_current_game):
		return
	var automation: Dictionary = _session_config.get("automation", {})
	if automation.is_empty():
		return
	var unit_ids := _session_configurator.get_automation_unit_ids(_session_config)
	var tiles := _session_configurator.get_automation_tiles(_session_config)
	if _role == String(automation.get("command_role", "")) \
		and not _custom_automation_command_sent:
		_custom_automation_command_sent = true
		if not _issue_grouped_mining_command(_current_game, unit_ids, tiles):
			_fail_custom_automation("Failed to issue grouped mining command")
			return
	if not _custom_automation_assignment_observed \
		and _has_expected_grouped_mining_assignment(_current_game, unit_ids, tiles):
		_custom_automation_assignment_observed = true
		_emit_event("custom_session_assignment", {
			"state": _capture_grouped_mining_state(_current_game, unit_ids, tiles),
		})
		if _role == ROLE_HOST:
			_custom_automation_release_msec = Time.get_ticks_msec() \
				+ GROUPED_MINING_ASSIGNMENT_HOLD_MSEC
	if _role == ROLE_HOST \
		and _custom_automation_assignment_observed \
		and not _custom_automation_workers_released \
		and Time.get_ticks_msec() >= _custom_automation_release_msec:
		_custom_automation_workers_released = true
		_set_units_physics_processing(_current_game, unit_ids, true)
		_emit_event("custom_session_workers_released", {
			"state": _capture_grouped_mining_state(_current_game, unit_ids, tiles),
		})
	if _custom_automation_assignment_observed \
		and not _custom_automation_progress_observed \
		and _has_grouped_mining_progress(_current_game, unit_ids, tiles):
		_custom_automation_progress_observed = true
		_emit_event("custom_session_progress", {
			"state": _capture_grouped_mining_state(_current_game, unit_ids, tiles),
		})
	if _custom_automation_progress_observed \
		and _has_completed_grouped_mining(_current_game, unit_ids, tiles):
		_custom_automation_complete_sent = true
		_emit_event("custom_session_complete", {
			"state": _capture_grouped_mining_state(_current_game, unit_ids, tiles),
		})
		return
	if _custom_automation_deadline_msec > 0 \
		and Time.get_ticks_msec() >= _custom_automation_deadline_msec:
		_fail_custom_automation("Timed out waiting for grouped mining completion")

func _issue_grouped_mining_command(
	game: Node,
	unit_ids: Array[int],
	tiles: Array[Vector2i]
) -> bool:
	game.call("select_troops_by_ids", unit_ids)
	if game.call("get_active_troop_selection_ids") != unit_ids:
		return false
	game.call("_on_role_action_requested", "miner_dig", unit_ids)
	for tile in tiles:
		if not bool(game.call("toggle_draft_tile", tile)):
			return false
	game.call("confirm_mining_selection")
	_emit_event("custom_session_command_issued", {
		"unit_ids": unit_ids,
		"tiles": _tile_array_for_json(tiles),
	})
	return true

func _has_expected_grouped_mining_assignment(
	game: Node,
	unit_ids: Array[int],
	tiles: Array[Vector2i]
) -> bool:
	var expected: Dictionary = {}
	for tile in tiles:
		expected[tile] = true
	var assigned: Dictionary = {}
	for unit_id in unit_ids:
		var unit := game.call("get_unit_by_id", unit_id) as Node
		if unit == null or not unit.has_method("get_miner_job"):
			return false
		var job: Dictionary = unit.call("get_miner_job")
		if int(job.get("job_type", MINER_JOB_IDLE)) != MINER_JOB_DIG:
			return false
		var unit_tiles: Array = job.get("dig_tiles", [])
		if unit_tiles.is_empty():
			return false
		for raw_tile in unit_tiles:
			var tile: Vector2i = raw_tile
			if not expected.has(tile) or assigned.has(tile):
				return false
			assigned[tile] = true
	return assigned.size() == expected.size()

func _has_grouped_mining_progress(
	game: Node,
	unit_ids: Array[int],
	tiles: Array[Vector2i]
) -> bool:
	var territory := game.get_node_or_null("TerritoryManager") as TerritoryManager
	if territory == null:
		return false
	var destroyed_count := 0
	for tile in tiles:
		if not territory.is_mineable_terrain_tile(tile):
			destroyed_count += 1
	if destroyed_count <= 0 or destroyed_count >= tiles.size():
		return false
	for unit_id in unit_ids:
		var unit := game.call("get_unit_by_id", unit_id) as Node
		if unit == null:
			continue
		if int(unit.get("current_status")) in [
			TROOP_STATUS_MINING,
			TROOP_STATUS_MOVING_TO_DIG_SITE,
		]:
			return true
	return false

func _has_completed_grouped_mining(
	game: Node,
	unit_ids: Array[int],
	tiles: Array[Vector2i]
) -> bool:
	var territory := game.get_node_or_null("TerritoryManager") as TerritoryManager
	if territory == null:
		return false
	for tile in tiles:
		if territory.is_mineable_terrain_tile(tile):
			return false
	for unit_id in unit_ids:
		var unit := game.call("get_unit_by_id", unit_id) as Node2D
		if unit == null or not unit.has_method("get_miner_job"):
			return false
		var job: Dictionary = unit.call("get_miner_job")
		if int(job.get("job_type", -1)) != MINER_JOB_IDLE:
			return false
		if int(unit.get("current_order")) != TACTICAL_ORDER_DEFEND:
			return false
		if int(unit.get("current_status")) != TROOP_STATUS_DEFENDING:
			return false
		var stand_tile := territory.get_standable_tile_for_world_position(unit.position)
		if unit.get("defense_anchor_tile") != stand_tile:
			return false
	return true

func _capture_grouped_mining_state(
	game: Node,
	unit_ids: Array[int],
	tiles: Array[Vector2i]
) -> Dictionary:
	var territory := game.get_node_or_null("TerritoryManager") as TerritoryManager
	var unit_states: Array[Dictionary] = []
	var destroyed_count := 0
	for tile in tiles:
		if not territory.is_mineable_terrain_tile(tile):
			destroyed_count += 1
	for unit_id in unit_ids:
		var unit := game.call("get_unit_by_id", unit_id) as Node2D
		if unit == null:
			continue
		var job: Dictionary = unit.call("get_miner_job")
		unit_states.append({
			"unit_id": unit_id,
			"job_type": int(job.get("job_type", -1)),
			"dig_tiles": _tile_array_for_json(job.get("dig_tiles", [])),
			"current_order": int(unit.get("current_order")),
			"current_status": int(unit.get("current_status")),
			"defense_anchor": _tile_for_json(unit.get("defense_anchor_tile")),
			"stand_tile": _tile_for_json(
				territory.get_standable_tile_for_world_position(unit.position)
			),
		})
	return {
		"unit_states": unit_states,
		"target_tiles": _tile_array_for_json(tiles),
		"target_tiles_destroyed": destroyed_count == tiles.size(),
		"target_tiles_destroyed_count": destroyed_count,
	}

func _set_units_physics_processing(game: Node, unit_ids: Array[int], enabled: bool) -> void:
	for unit_id in unit_ids:
		var unit := game.call("get_unit_by_id", unit_id) as Node
		if unit != null:
			unit.set_physics_process(enabled)

func _fail_custom_automation(message: String) -> void:
	_custom_automation_complete_sent = true
	var payload := {
		"message": message,
		"snapshot": _capture_scene_snapshot(),
	}
	if _current_game != null and is_instance_valid(_current_game):
		var unit_ids := _session_configurator.get_automation_unit_ids(_session_config)
		var tiles := _session_configurator.get_automation_tiles(_session_config)
		payload["state"] = _capture_grouped_mining_state(_current_game, unit_ids, tiles)
	_emit_event("failure", payload)

func _tile_array_for_json(raw_tiles: Variant) -> Array[Array]:
	var result: Array[Array] = []
	for raw_tile in raw_tiles:
		result.append(_tile_for_json(raw_tile))
	return result

func _tile_for_json(raw_tile: Variant) -> Array:
	var tile: Vector2i = raw_tile
	return [tile.x, tile.y]

func _game_has_units(game: Node, unit_ids: Array[int]) -> bool:
	for unit_id in unit_ids:
		if game.call("get_unit_by_id", unit_id) == null:
			return false
	return true

func _connect_runtime_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.local_disconnected.connect(_on_local_disconnected)
	NetworkManager.reconnect_attempted.connect(_on_reconnect_attempted)
	NetworkManager.reconnect_succeeded.connect(_on_reconnect_succeeded)
	GameState.peer_disconnected_graceful.connect(_on_peer_disconnected_graceful)
	GameState.peer_reconnected.connect(_on_peer_reconnected)

func _on_connected_to_server() -> void:
	_emit_event("connected", {
		"scene": GameState.current_scene,
		"peer_id": _safe_peer_id(),
	})

func _on_local_disconnected() -> void:
	call_deferred("_handle_local_disconnected_deferred")

func _on_reconnect_attempted() -> void:
	_emit_event("reconnect_started", {
		"scene": GameState.current_scene,
		"peer_id": _safe_peer_id(),
	})

func _on_reconnect_succeeded() -> void:
	call_deferred("_handle_reconnect_succeeded_deferred")

func _on_peer_disconnected_graceful(peer_id: int) -> void:
	if _role != ROLE_HOST:
		return
	call_deferred("_handle_peer_disconnected_deferred", peer_id)

func _on_peer_reconnected(peer_id: int) -> void:
	if _role != ROLE_HOST:
		return
	call_deferred("_handle_peer_reconnected_deferred", peer_id)

func _handle_local_disconnected_deferred() -> void:
	_emit_event("disconnected", {
		"reason": "local_disconnected",
		"snapshot": _capture_scene_snapshot(),
	})
	if _role == ROLE_CLIENT and not _client_reconnect_started:
		_client_reconnect_started = true
		NetworkManager.attempt_reconnect()

func _handle_reconnect_succeeded_deferred() -> void:
	_client_reconnect_succeeded = true
	_post_reconnect_deadline_msec = Time.get_ticks_msec() + POST_RECONNECT_DEADLINE_MSEC
	_emit_event("reconnect_succeeded", {
		"scene": GameState.current_scene,
		"peer_id": _safe_peer_id(),
		"snapshot": _capture_scene_snapshot(),
	})
	if _scenario == SCENARIO_LOBBY_RECONNECT:
		_client_lobby_complete_deadline_msec = Time.get_ticks_msec() + POST_RECONNECT_DEADLINE_MSEC

func _handle_peer_disconnected_deferred(peer_id: int) -> void:
	_emit_event("disconnected", {
		"reason": "peer_disconnected",
		"peer_id": peer_id,
		"snapshot": _capture_scene_snapshot(),
	})

func _handle_peer_reconnected_deferred(peer_id: int) -> void:
	_emit_event("snapshot", {
		"stage": "post_reconnect",
		"peer_id": peer_id,
		"snapshot": _capture_scene_snapshot(),
	})
	if not _host_complete_sent:
		_host_complete_sent = true
		_emit_event("complete", {
			"role": _role,
			"snapshot": _capture_scene_snapshot(),
		})

func _on_game_test_unit_spawned(unit_id: int) -> void:
	_spawned_unit_id = unit_id
	_emit_event("spawn_confirmed", {
		"unit_id": unit_id,
		"snapshot": _capture_scene_snapshot(),
	})

func _drive_client_game_scenario() -> void:
	if GameState.current_scene != SCENE_GAME:
		return
	var snapshot := _capture_scene_snapshot()
	if not _client_pre_disconnect_snapshot_sent:
		var unit_ids: Array = snapshot.get("visible_unit_ids", [])
		var has_replicated_unit := false
		for unit_id in unit_ids:
			if int(unit_id) > 0:
				has_replicated_unit = true
				break
		if not has_replicated_unit:
			return
		_client_pre_disconnect_snapshot_sent = true
		_emit_event("snapshot", {
			"stage": "pre_disconnect",
			"snapshot": snapshot,
		})
		if not _client_disconnect_triggered:
			_client_disconnect_triggered = true
			NetworkManager.simulate_disconnect()
		return
	if not _client_reconnect_succeeded:
		return
	var post_unit_ids: Array = snapshot.get("visible_unit_ids", [])
	if not post_unit_ids.is_empty():
		_emit_client_complete(snapshot)
		return
	if _post_reconnect_deadline_msec > 0 and Time.get_ticks_msec() >= _post_reconnect_deadline_msec:
		_emit_event("failure", {
			"message": "Timed out waiting for replicated unit after reconnect",
			"snapshot": snapshot,
		})
		_emit_client_complete(snapshot)

func _drive_client_lobby_scenario() -> void:
	if GameState.current_scene != SCENE_LOBBY:
		return
	var scene := get_tree().get_current_scene()
	if scene == null or not scene.has_method("get_player_count"):
		return
	var snapshot := _capture_scene_snapshot()
	if not _client_pre_disconnect_snapshot_sent:
		if int(scene.call("get_player_count")) < 2:
			return
		_client_pre_disconnect_snapshot_sent = true
		_emit_event("snapshot", {
			"stage": "pre_disconnect",
			"snapshot": snapshot,
		})
		if not _client_disconnect_triggered:
			_client_disconnect_triggered = true
			NetworkManager.simulate_disconnect()
		return
	if not _client_reconnect_succeeded:
		return
	if snapshot.get("scene", "") == SCENE_LOBBY and not bool(snapshot.get("disconnect_overlay_visible", true)):
		_emit_client_complete(snapshot)
		return
	if _client_lobby_complete_deadline_msec > 0 and Time.get_ticks_msec() >= _client_lobby_complete_deadline_msec:
		_emit_event("failure", {
			"message": "Timed out waiting for lobby restore after reconnect",
			"snapshot": snapshot,
		})
		_emit_client_complete(snapshot)

func _emit_client_complete(snapshot: Dictionary) -> void:
	if _client_complete_sent:
		return
	_client_complete_sent = true
	_emit_event("snapshot", {
		"stage": "post_reconnect",
		"snapshot": snapshot,
	})
	_emit_event("complete", {
		"role": _role,
		"snapshot": snapshot,
	})

func _capture_scene_snapshot() -> Dictionary:
	var scene := get_tree().get_current_scene()
	if scene != null and scene.has_method("get_test_snapshot"):
		return scene.call("get_test_snapshot")
	return {
		"scene": GameState.current_scene,
		"peer_id": _safe_peer_id(),
		"is_server": multiplayer.is_server(),
		"local_team": GameState.local_team,
		"local_money": GameState.local_money,
		"map_width": GameState.map_width,
		"map_height": GameState.map_height,
		"map_seed": GameState.map_seed,
		"paused": get_tree().paused,
		"disconnect_overlay_visible": false,
		"disconnect_overlay_message": "",
		"visible_unit_ids": [],
	}

func _get_lobby_player_count(lobby: Control) -> int:
	if lobby.has_method("get_player_count"):
		return int(lobby.call("get_player_count"))
	return 1

func _open_event_file() -> bool:
	_event_path = _build_event_path()
	var dir_path := _event_path.get_base_dir()
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		return false
	_event_file = FileAccess.open(_event_path, FileAccess.WRITE)
	return _event_file != null

func _build_event_path() -> String:
	var base := _artifacts_dir
	if base.begins_with("user://"):
		base = ProjectSettings.globalize_path(base)
	return "%s/%s_%s.events.jsonl" % [base, _run_id, _role]

func _emit_event(event_name: String, payload: Dictionary = {}) -> void:
	if _event_file == null:
		return
	var event := {
		"timestamp_msec": Time.get_ticks_msec(),
		"event": event_name,
		"role": _role,
	}
	for key in payload.keys():
		event[key] = payload[key]
	_event_file.store_line(JSON.stringify(event))
	_event_file.flush()

func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		if not token.begins_with("--test-"):
			index += 1
			continue
		var key := token.trim_prefix("--")
		if index + 1 < args.size() and not args[index + 1].begins_with("--"):
			parsed[key] = args[index + 1]
			index += 2
		else:
			parsed[key] = true
			index += 1
	return parsed

func _safe_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

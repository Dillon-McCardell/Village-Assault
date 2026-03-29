extends Node

const ROLE_HOST: String = "host"
const ROLE_CLIENT: String = "client"
const SCENE_BOOT: String = "boot_menu"
const SCENE_LOBBY: String = "lobby"
const SCENE_GAME: String = "game"
const SCENARIO_GAME_RECONNECT: String = "game_reconnect"
const SCENARIO_LOBBY_RECONNECT: String = "lobby_reconnect"
const POST_RECONNECT_DEADLINE_MSEC: int = 5000

var _active: bool = false
var _role: String = ""
var _scenario: String = SCENARIO_GAME_RECONNECT
var _address: String = "127.0.0.1"
var _port: int = NetworkManager.DEFAULT_PORT
var _artifacts_dir: String = ""
var _run_id: String = ""
var _event_path: String = ""
var _event_file: FileAccess

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
	if _scenario != SCENARIO_GAME_RECONNECT and _scenario != SCENARIO_LOBBY_RECONNECT:
		push_error("TestHarness: invalid test scenario '%s'" % _scenario)
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
	if _role == ROLE_CLIENT:
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
	if not _active or _role != ROLE_HOST or _match_started:
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
	if _role == ROLE_HOST and not _spawn_requested:
		_spawn_requested = true
		game.call_deferred("spawn_local_test_unit_for_test")

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

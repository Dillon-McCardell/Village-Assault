extends Node

signal team_assigned(peer_id: int, team: int)
signal money_updated(peer_id: int, money: int)
signal local_state_updated(team: int, money: int)
signal world_settings_updated(map_width: int, map_height: int, map_seed: int)
signal player_removed(peer_id: int)
signal peer_disconnected_graceful(peer_id: int)
signal peer_reconnected(peer_id: int)

enum Team {
	NONE = -1,
	LEFT = 0,
	RIGHT = 1,
}

const STARTING_MONEY: int = 100
const PASSIVE_INCOME_INTERVAL_SEC: float = 10.0
const PASSIVE_INCOME_AMOUNT: int = 1
# TODO: Replace or supplement passive income with host-authoritative miner delivery income.
# TODO: Add an explicit resource-return money credit API for mined gold hand-ins.
## Which scene the game is currently in, so reconnecting clients land in the right place.
## Set by scene scripts on _ready(). Values: "boot_menu", "lobby", "game"
var current_scene: String = "boot_menu"
const DEFAULT_MAP_WIDTH: int = 64
const DEFAULT_MAP_HEIGHT: int = 20
const DEFAULT_MAP_SEED: int = 0

var local_team: int = Team.NONE
var local_money: int = 0
var map_width: int = DEFAULT_MAP_WIDTH
var map_height: int = DEFAULT_MAP_HEIGHT
var map_seed: int = DEFAULT_MAP_SEED

var _peer_team: Dictionary = {}
var _peer_money: Dictionary = {}
var _spawn_queue: Array[Dictionary] = []
var _inactive_peers: Dictionary = {}
var _disconnected_peer_id: int = -1
var _passive_income_timer: Timer = null

func _ready() -> void:
	_setup_passive_income_timer()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if NetworkManager:
		NetworkManager.host_started.connect(_on_host_started)
		NetworkManager.join_started.connect(_on_join_started)

func _on_host_started(_port: int) -> void:
	DebugConsole.log_msg("GS._on_host_started: is_server=%s peer_team=%s inactive=%s" % [str(multiplayer.is_server()), str(_peer_team.keys()), str(_inactive_peers.keys())])
	if not multiplayer.is_server():
		return
	var is_rehost := _peer_team.has(1)
	_assign_team_to_peer(1)
	_update_passive_income_timer_state()
	if not is_rehost:
		if map_seed == DEFAULT_MAP_SEED:
			map_seed = _generate_seed()
		_send_world_settings_to_local()

func _on_join_started(_address: String, _port: int) -> void:
	_update_passive_income_timer_state()
	if not NetworkManager._is_reconnecting:
		_reset_local_state()
		_reset_world_settings()

func _on_peer_connected(peer_id: int) -> void:
	DebugConsole.log_msg("GS._on_peer_connected: peer=%d is_server=%s inactive=%s" % [peer_id, str(multiplayer.is_server()), str(_inactive_peers.keys())])
	if multiplayer.is_server():
		if not try_restore_peer(peer_id):
			_assign_team_to_peer(peer_id)
		_send_world_settings(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	DebugConsole.log_msg("GS._on_peer_disconnected: peer=%d team=%d" % [peer_id, _peer_team.get(peer_id, Team.NONE)])
	var team: int = _peer_team.get(peer_id, Team.NONE)
	if team != Team.NONE:
		_inactive_peers[peer_id] = {
			"team": team,
			"money": _peer_money.get(peer_id, 0),
			"disconnect_time": Time.get_ticks_msec(),
		}
		_disconnected_peer_id = peer_id
		peer_disconnected_graceful.emit(peer_id)
	_peer_team.erase(peer_id)
	_peer_money.erase(peer_id)
	player_removed.emit(peer_id)

func try_restore_peer(new_peer_id: int) -> bool:
	if _inactive_peers.is_empty():
		DebugConsole.log_msg("GS.try_restore_peer: no inactive peers")
		return false
	var old_peer_id: int = _inactive_peers.keys()[0]
	DebugConsole.log_msg("GS.try_restore_peer: restoring old=%d as new=%d" % [old_peer_id, new_peer_id])
	var record: Dictionary = _inactive_peers[old_peer_id]
	var team: int = record["team"]
	var money: int = record["money"]
	_peer_team[new_peer_id] = team
	_peer_money[new_peer_id] = money
	if new_peer_id == 1:
		_receive_player_state(team, money)
	else:
		_receive_player_state.rpc_id(new_peer_id, team, money)
		# Tell the reconnecting client which scene to load
		_receive_scene_redirect.rpc_id(new_peer_id, current_scene)
	clear_inactive_peer(old_peer_id)
	peer_reconnected.emit(new_peer_id)
	team_assigned.emit(new_peer_id, team)
	money_updated.emit(new_peer_id, money)
	return true

func clear_inactive_peer(peer_id: int) -> void:
	_inactive_peers.erase(peer_id)
	_disconnected_peer_id = -1

func _assign_team_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _peer_team.has(peer_id):
		return
	var left_count := _count_team(Team.LEFT)
	var right_count := _count_team(Team.RIGHT)
	var team := Team.LEFT if left_count <= right_count else Team.RIGHT
	_peer_team[peer_id] = team
	_peer_money[peer_id] = STARTING_MONEY
	team_assigned.emit(peer_id, team)
	money_updated.emit(peer_id, STARTING_MONEY)
	if peer_id == 1:
		_receive_player_state(team, STARTING_MONEY)
	else:
		_receive_player_state.rpc_id(peer_id, team, STARTING_MONEY)

func set_world_settings(width: int, height: int, map_seed_val: int) -> void:
	map_width = width
	map_height = height
	map_seed = map_seed_val
	world_settings_updated.emit(map_width, map_height, map_seed)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_broadcast_world_settings()

func set_world_size(width: int, height: int) -> void:
	set_world_settings(width, height, map_seed)

func _count_team(team: int) -> int:
	var count := 0
	for assigned_team in _peer_team.values():
		if assigned_team == team:
			count += 1
	for record in _inactive_peers.values():
		if record["team"] == team:
			count += 1
	return count

@rpc("authority", "reliable")
func _receive_player_state(team: int, money: int) -> void:
	local_team = team
	local_money = money
	local_state_updated.emit(team, money)

## Called by the host to tell a reconnecting client which scene to load.
@rpc("authority", "reliable")
func _receive_scene_redirect(scene_name: String) -> void:
	# Skip if we're already on the correct scene
	if current_scene == scene_name:
		return
	var scene_path: String = ""
	match scene_name:
		"game":
			scene_path = "res://scenes/game.tscn"
		"lobby":
			scene_path = "res://scenes/lobby.tscn"
		_:
			scene_path = "res://scenes/boot_menu.tscn"
	get_tree().change_scene_to_file(scene_path)

func get_team_for_peer(peer_id: int) -> int:
	return _peer_team.get(peer_id, Team.NONE)

func get_money_for_peer(peer_id: int) -> int:
	return _peer_money.get(peer_id, 0)

func set_current_scene(scene_name: String) -> void:
	current_scene = scene_name
	_update_passive_income_timer_state()

func set_money_for_peer(peer_id: int, money: int) -> void:
	if not multiplayer.is_server():
		return
	_peer_money[peer_id] = money
	money_updated.emit(peer_id, money)
	if peer_id == 1:
		_receive_player_state(_peer_team.get(peer_id, Team.NONE), money)
	else:
		_receive_player_state.rpc_id(peer_id, _peer_team.get(peer_id, Team.NONE), money)

func enqueue_spawn(request: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_spawn_queue.append(request)

func dequeue_spawn() -> Dictionary:
	if _spawn_queue.is_empty():
		return {}
	return _spawn_queue.pop_front()

func _reset_local_state() -> void:
	local_team = Team.NONE
	local_money = 0
	local_state_updated.emit(local_team, local_money)

func _reset_world_settings() -> void:
	map_width = DEFAULT_MAP_WIDTH
	map_height = DEFAULT_MAP_HEIGHT
	map_seed = DEFAULT_MAP_SEED
	world_settings_updated.emit(map_width, map_height, map_seed)

## Clears all session data. Call when starting a brand new game session.
func reset_all() -> void:
	_peer_team.clear()
	_peer_money.clear()
	_inactive_peers.clear()
	_disconnected_peer_id = -1
	_spawn_queue.clear()
	if _passive_income_timer != null:
		_passive_income_timer.stop()
	_reset_local_state()
	_reset_world_settings()

func _broadcast_world_settings() -> void:
	_send_world_settings_to_local()
	for peer_id in _peer_team.keys():
		if peer_id != 1:
			_send_world_settings(peer_id)

func _send_world_settings(peer_id: int) -> void:
	_receive_world_settings.rpc_id(peer_id, map_width, map_height, map_seed)

func _send_world_settings_to_local() -> void:
	_receive_world_settings(map_width, map_height, map_seed)

@rpc("authority", "reliable")
func _receive_world_settings(width: int, height: int, map_seed_val: int) -> void:
	map_width = width
	map_height = height
	map_seed = map_seed_val
	world_settings_updated.emit(map_width, map_height, map_seed)

func _generate_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()

func _setup_passive_income_timer() -> void:
	if _passive_income_timer != null:
		return
	_passive_income_timer = Timer.new()
	_passive_income_timer.wait_time = PASSIVE_INCOME_INTERVAL_SEC
	_passive_income_timer.one_shot = false
	_passive_income_timer.timeout.connect(_on_passive_income_timer_timeout)
	add_child(_passive_income_timer)

func _update_passive_income_timer_state() -> void:
	if _passive_income_timer == null:
		return
	var should_run := multiplayer.multiplayer_peer != null \
		and multiplayer.is_server() \
		and current_scene == "game"
	if should_run:
		if _passive_income_timer.is_stopped():
			_passive_income_timer.start()
	else:
		_passive_income_timer.stop()

func _on_passive_income_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if current_scene != "game":
		return
	for raw_peer_id in _peer_money.keys():
		var peer_id := int(raw_peer_id)
		var current_money := get_money_for_peer(peer_id)
		set_money_for_peer(peer_id, current_money + PASSIVE_INCOME_AMOUNT)

func get_team_name(team: int) -> String:
	match team:
		Team.LEFT:
			return "Left"
		Team.RIGHT:
			return "Right"
		_:
			return "Unassigned"

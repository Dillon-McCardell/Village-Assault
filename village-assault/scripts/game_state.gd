extends Node

signal team_assigned(peer_id: int, team: int)
signal money_updated(peer_id: int, money: int)
signal local_state_updated(team: int, money: int)
signal world_settings_updated(map_width: int, map_height: int, map_seed: int)
signal player_removed(peer_id: int)

enum Team {
	NONE = -1,
	LEFT = 0,
	RIGHT = 1,
}

const STARTING_MONEY: int = 100
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

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if NetworkManager:
		NetworkManager.host_started.connect(_on_host_started)
		NetworkManager.join_started.connect(_on_join_started)

func _on_host_started(_port: int) -> void:
	if not multiplayer.is_server():
		return
	_assign_team_to_peer(1)
	if map_seed == DEFAULT_MAP_SEED:
		map_seed = _generate_seed()
	_send_world_settings_to_local()

func _on_join_started(_address: String, _port: int) -> void:
	_reset_local_state()
	_reset_world_settings()

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_assign_team_to_peer(peer_id)
		_send_world_settings(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_peer_team.erase(peer_id)
	_peer_money.erase(peer_id)
	player_removed.emit(peer_id)

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

func set_world_settings(width: int, height: int, seed: int) -> void:
	map_width = width
	map_height = height
	map_seed = seed
	world_settings_updated.emit(map_width, map_height, map_seed)
	if multiplayer.is_server():
		_broadcast_world_settings()

func set_world_size(width: int, height: int) -> void:
	set_world_settings(width, height, map_seed)

func _count_team(team: int) -> int:
	var count := 0
	for assigned_team in _peer_team.values():
		if assigned_team == team:
			count += 1
	return count

@rpc("authority", "reliable")
func _receive_player_state(team: int, money: int) -> void:
	local_team = team
	local_money = money
	local_state_updated.emit(team, money)

func get_team_for_peer(peer_id: int) -> int:
	return _peer_team.get(peer_id, Team.NONE)

func get_money_for_peer(peer_id: int) -> int:
	return _peer_money.get(peer_id, 0)

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
func _receive_world_settings(width: int, height: int, seed: int) -> void:
	map_width = width
	map_height = height
	map_seed = seed
	world_settings_updated.emit(map_width, map_height, map_seed)

func _generate_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()

func get_team_name(team: int) -> String:
	match team:
		Team.LEFT:
			return "Left"
		Team.RIGHT:
			return "Right"
		_:
			return "Unassigned"

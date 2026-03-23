extends Node

const DEFAULT_PORT: int = 12345
const DEFAULT_MAX_CLIENTS: int = 32

signal host_started(port: int)
signal join_started(address: String, port: int)
signal connection_failed
signal connected_to_server
signal server_disconnected
signal reconnect_attempted
signal reconnect_succeeded
signal reconnect_failed
signal local_disconnected

var peer: ENetMultiplayerPeer
var _last_host_address: String = ""
var _last_host_port: int = DEFAULT_PORT
var _last_host_max_clients: int = DEFAULT_MAX_CLIENTS
var _was_host: bool = false
var _auto_reconnect_timer: Timer = null
var _is_reconnecting: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _unhandled_input(event: InputEvent) -> void:
	# F9: toggle simulated disconnect / reconnect for testing
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		if peer == null:
			if _was_host:
				DebugConsole.log_msg("F9: Re-hosting on port %d" % _last_host_port)
				host(_last_host_port, _last_host_max_clients)
			else:
				DebugConsole.log_msg("F9: Reconnecting to %s:%d" % [_last_host_address, _last_host_port])
				attempt_reconnect()
		else:
			DebugConsole.log_msg("F9: Simulating disconnect")
			simulate_disconnect()

func host(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> void:
	_last_host_port = port
	_last_host_max_clients = max_clients
	_was_host = true
	var enet := ENetMultiplayerPeer.new()
	var result := enet.create_server(port, max_clients)
	if result != OK:
		push_error("Failed to host server. Error %s" % result)
		return
	multiplayer.multiplayer_peer = enet
	peer = enet
	host_started.emit(port)

func join(address: String, port: int = DEFAULT_PORT) -> void:
	_last_host_address = address
	_last_host_port = port
	var enet := ENetMultiplayerPeer.new()
	var result := enet.create_client(address, port)
	if result != OK:
		push_error("Failed to join server. Error %s" % result)
		return
	multiplayer.multiplayer_peer = enet
	peer = enet
	join_started.emit(address, port)

func is_host() -> bool:
	return multiplayer.is_server()

func shutdown() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer = null

## Simulate a network disconnect without closing the window.
## Useful for testing disconnect handling. Closes the ENet peer so the
## remote side sees a proper peer_disconnected / server_disconnected event.
func simulate_disconnect() -> void:
	if peer == null:
		push_warning("simulate_disconnect: no active peer to disconnect")
		return
	var was_server := multiplayer.is_server()
	push_warning("simulate_disconnect: forcing ENet peer disconnect (was_server=%s)" % str(was_server))
	# Manually trigger peer_disconnected for all remote peers before closing,
	# because peer.close() + nulling multiplayer_peer races with Godot's
	# internal disconnect callbacks.
	if was_server:
		var remote_peers := multiplayer.get_peers()
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
		for remote_id in remote_peers:
			GameState._on_peer_disconnected(remote_id)
	else:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
	local_disconnected.emit()

func attempt_reconnect() -> void:
	# Clean up any stale peer before reconnecting
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
	_is_reconnecting = true
	reconnect_attempted.emit()
	join(_last_host_address, _last_host_port)

func start_auto_reconnect(interval: float = 5.0) -> void:
	stop_auto_reconnect()
	_auto_reconnect_timer = Timer.new()
	_auto_reconnect_timer.wait_time = interval
	_auto_reconnect_timer.one_shot = false
	_auto_reconnect_timer.timeout.connect(attempt_reconnect)
	add_child(_auto_reconnect_timer)
	_auto_reconnect_timer.start()

func stop_auto_reconnect() -> void:
	if _auto_reconnect_timer != null:
		_auto_reconnect_timer.stop()
		_auto_reconnect_timer.queue_free()
		_auto_reconnect_timer = null

func _on_connected_to_server() -> void:
	if _is_reconnecting:
		_is_reconnecting = false
		stop_auto_reconnect()
		reconnect_succeeded.emit()
	connected_to_server.emit()

func _on_connection_failed() -> void:
	if _is_reconnecting:
		reconnect_failed.emit()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	server_disconnected.emit()

extends Node

const DEFAULT_PORT: int = 12345
const DEFAULT_MAX_CLIENTS: int = 32

signal host_started(port: int)
signal join_started(address: String, port: int)
signal connection_failed
signal connected_to_server
signal server_disconnected

var peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> void:
	var enet := ENetMultiplayerPeer.new()
	var result := enet.create_server(port, max_clients)
	if result != OK:
		push_error("Failed to host server. Error %s" % result)
		return
	multiplayer.multiplayer_peer = enet
	peer = enet
	host_started.emit(port)

func join(address: String, port: int = DEFAULT_PORT) -> void:
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

func _on_connected_to_server() -> void:
	connected_to_server.emit()

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	server_disconnected.emit()

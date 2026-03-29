extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var player_label: Label = $VBox/PlayerLabel
@onready var start_button: Button = $VBox/StartButton

const GAME_SCENE: String = "res://scenes/game.tscn"
const BOOT_MENU_SCENE: String = "res://scenes/boot_menu.tscn"

var _disconnect_overlay_scene: PackedScene = preload("res://scenes/ui/disconnect_overlay.tscn")
var _disconnect_overlay: CanvasLayer

var _player_count: int = 1

func _ready() -> void:
	# Register current scene for reconnect routing
	GameState.set_current_scene("lobby")

	# Disconnect overlay setup
	_disconnect_overlay = _disconnect_overlay_scene.instantiate()
	add_child(_disconnect_overlay)

	# GameState disconnect signals
	GameState.peer_disconnected_graceful.connect(_on_peer_disconnected_graceful)
	GameState.peer_reconnected.connect(_on_peer_reconnected)

	# NetworkManager disconnect signals
	NetworkManager.server_disconnected.connect(_on_server_disconnected_lobby)
	NetworkManager.reconnect_succeeded.connect(_on_reconnect_succeeded_lobby)
	NetworkManager.local_disconnected.connect(_on_local_disconnected_lobby)

	# Overlay button signals
	_disconnect_overlay.return_to_menu_pressed.connect(_on_return_to_menu_pressed)

	multiplayer.peer_connected.connect(_on_peer_changed)
	multiplayer.peer_disconnected.connect(_on_peer_changed)
	_update_player_count()
	_update_ui()
	if TestHarness.is_active():
		TestHarness.on_lobby_ready(self)

func _on_peer_changed(_peer_id: int) -> void:
	_update_player_count()
	_update_ui()

func _update_player_count() -> void:
	_player_count = 1 + multiplayer.get_peers().size()

func _update_ui() -> void:
	player_label.text = "Players: %d/2" % _player_count
	if multiplayer.is_server():
		if _player_count >= 2:
			status_label.text = "All players connected."
			start_button.disabled = false
		else:
			status_label.text = "Waiting for player..."
			start_button.disabled = true
		start_button.visible = true
	else:
		status_label.text = "Waiting for host to start..."
		start_button.visible = false
	if TestHarness.is_active():
		TestHarness.on_lobby_state_changed(self)

func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	start_game.rpc()

@rpc("authority", "reliable", "call_local")
func start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


# --- Disconnect handling (Tasks 7.1, 7.2) ---

func _on_peer_disconnected_graceful(_peer_id: int) -> void:
	_disconnect_overlay.show_client_disconnected()

func _on_peer_reconnected(_peer_id: int) -> void:
	_disconnect_overlay.hide_overlay()
	_update_player_count()
	_update_ui()

func _on_server_disconnected_lobby() -> void:
	# Client side: host disconnected — show overlay and try to reconnect
	_disconnect_overlay.show_host_disconnected()
	NetworkManager.start_auto_reconnect()

func _on_reconnect_succeeded_lobby() -> void:
	_disconnect_overlay.hide_overlay()
	_update_player_count()
	_update_ui()

func _on_local_disconnected_lobby() -> void:
	_disconnect_overlay.show_client_disconnected()

func _on_return_to_menu_pressed() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	get_tree().change_scene_to_file(BOOT_MENU_SCENE)

func get_player_count() -> int:
	return _player_count

func start_game_for_test() -> void:
	_on_start_pressed()

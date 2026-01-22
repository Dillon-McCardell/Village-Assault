extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var player_label: Label = $VBox/PlayerLabel
@onready var start_button: Button = $VBox/StartButton

const GAME_SCENE: String = "res://scenes/game.tscn"

var _player_count: int = 1

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_changed)
	multiplayer.peer_disconnected.connect(_on_peer_changed)
	_update_player_count()
	_update_ui()

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

func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	start_game.rpc()

@rpc("authority", "reliable", "call_local")
func start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

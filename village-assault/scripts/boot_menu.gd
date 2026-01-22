extends Control

@onready var main_panel: Control = $MainPanel
@onready var host_panel: Control = $HostPanel
@onready var join_panel: Control = $JoinPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var status_label: Label = $StatusLabel

@onready var join_address_input: LineEdit = $JoinPanel/JoinVBox/JoinAddressInput
@onready var map_size_slider: HSlider = $HostPanel/HostVBox/MapSizeSlider
@onready var map_size_value: Label = $HostPanel/HostVBox/MapSizeValue

const DEFAULT_ADDRESS: String = "127.0.0.1"
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

func _ready() -> void:
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	map_size_slider.value_changed.connect(_on_map_size_changed)
	_show_panel(main_panel)
	_set_status("Idle")
	_update_map_size_label(map_size_slider.value)

func _on_host_pressed() -> void:
	var map_size := _get_map_size_from_slider()
	var seed: int = _generate_seed()
	GameState.set_world_settings(map_size.x, map_size.y, seed)
	NetworkManager.host()
	_set_status("Hosting...")
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_join_pressed() -> void:
	var address := join_address_input.text.strip_edges()
	if address.is_empty():
		address = DEFAULT_ADDRESS
	NetworkManager.join(address)
	_set_status("Connecting to %s..." % address)

func _on_connected_to_server() -> void:
	_set_status("Connected")
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_connection_failed() -> void:
	_set_status("Connection failed")
	_show_panel(join_panel)

func _on_server_disconnected() -> void:
	_set_status("Disconnected")
	_show_panel(main_panel)

func _on_main_host_pressed() -> void:
	_show_panel(host_panel)

func _on_main_join_pressed() -> void:
	_show_panel(join_panel)

func _on_main_settings_pressed() -> void:
	_show_panel(settings_panel)

func _on_back_pressed() -> void:
	_show_panel(main_panel)
	_set_status("Idle")

func _show_panel(panel: Control) -> void:
	main_panel.visible = panel == main_panel
	host_panel.visible = panel == host_panel
	join_panel.visible = panel == join_panel
	settings_panel.visible = panel == settings_panel

func _set_status(text: String) -> void:
	status_label.text = "Status: %s" % text

func _on_map_size_changed(_value: float) -> void:
	_update_map_size_label(map_size_slider.value)

func _get_map_size_from_slider() -> Vector2i:
	var base_width: int = GameState.DEFAULT_MAP_WIDTH
	var base_height: int = GameState.DEFAULT_MAP_HEIGHT
	var t: float = map_size_slider.value
	var width_scale: float = 1.0 + t
	var height_scale: float = 1.0 + (t * 2.0)
	var width: int = int(round(base_width * width_scale))
	var height: int = int(round(base_height * height_scale))
	return Vector2i(width, height)

func _update_map_size_label(value: float) -> void:
	var size := _get_map_size_from_slider()
	map_size_value.text = "Size: %d x %d (%.0f%%)" % [size.x, size.y, 100.0 + (value * 100.0)]

func _generate_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()

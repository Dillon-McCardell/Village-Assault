extends CanvasLayer

signal settings_pressed
signal main_menu_pressed
signal back_pressed

@onready var _background: ColorRect = $Background
@onready var _message_label: Label = $Background/CenterContainer/VBoxContainer/MessageLabel
@onready var _settings_button: Button = $Background/CenterContainer/VBoxContainer/ButtonContainer/SettingsButton
@onready var _main_menu_button: Button = $Background/CenterContainer/VBoxContainer/ButtonContainer/MainMenuButton
@onready var _back_button: Button = $Background/CenterContainer/VBoxContainer/ButtonContainer/BackButton

var _is_local_pauser: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	_main_menu_button.pressed.connect(func() -> void: main_menu_pressed.emit())
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	hide_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not _background.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _is_local_pauser:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


func show_pause_menu() -> void:
	_background.visible = true
	_message_label.text = "Game Paused"
	_settings_button.visible = true
	_main_menu_button.visible = true
	_back_button.visible = true
	_is_local_pauser = true


func show_remote_paused() -> void:
	_background.visible = true
	_message_label.text = "The other player has paused the game."
	_settings_button.visible = false
	_main_menu_button.visible = false
	_back_button.visible = false
	_is_local_pauser = false


func hide_menu() -> void:
	_background.visible = false
	_is_local_pauser = false

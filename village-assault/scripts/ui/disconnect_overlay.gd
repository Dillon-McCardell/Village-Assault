extends CanvasLayer

signal return_to_menu_pressed

@onready var _background: ColorRect = $Background
@onready var _message_label: Label = $Background/CenterContainer/VBoxContainer/MessageLabel
@onready var _return_button: Button = $Background/CenterContainer/VBoxContainer/ButtonContainer/ReturnButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_return_button.pressed.connect(func() -> void: return_to_menu_pressed.emit())
	hide_overlay()


## You disconnected yourself (F9) — reconnecting automatically
func show_self_disconnected() -> void:
	_background.visible = true
	_message_label.text = "You have disconnected.\nReconnecting..."
	_return_button.visible = true

## Host sees this when client left via Main Menu
func show_client_left() -> void:
	_background.visible = true
	_message_label.text = "The Client has left the game."
	_return_button.visible = true

## Host sees this when client disconnected (network/crash)
func show_client_disconnected() -> void:
	_background.visible = true
	_message_label.text = "The Client disconnected."
	_return_button.visible = true

## Client sees this when host left via Main Menu (unrecoverable)
func show_host_left() -> void:
	_background.visible = true
	_message_label.text = "The Host has left the game."
	_return_button.visible = true

## Client sees this when host disconnected (network/crash)
func show_host_disconnected() -> void:
	_background.visible = true
	_message_label.text = "The Host disconnected."
	_return_button.visible = true


func hide_overlay() -> void:
	_background.visible = false

func is_overlay_visible() -> bool:
	return _background.visible

func get_message_text() -> String:
	return _message_label.text

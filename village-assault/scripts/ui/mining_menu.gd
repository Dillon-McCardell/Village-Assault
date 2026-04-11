extends Control

signal mine_mode_requested
signal confirm_pressed
signal cancel_pressed

@export var button_size: Vector2 = Vector2(140, 44)
@export var spacing: Vector2 = Vector2(8, 8)
@export var margin: Vector2 = Vector2(16, 16)

const PICKAXE_GLYPH: String = "⛏ Mine"
const CONFIRM_GLYPH: String = "✓ Confirm"
const CANCEL_GLYPH: String = "✕"
const DEFAULT_FONT_COLOR: Color = Color(1, 1, 1, 1)
const CONFIRM_FONT_COLOR: Color = Color(0.55, 0.9, 0.4, 1)
const CANCEL_FONT_COLOR: Color = Color(0.95, 0.35, 0.35, 1)

var _origin_button: Button
var _cancel_button: Button
var _draft_active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_buttons()
	_layout_buttons()
	show_pickaxe_state()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_buttons()

func show_pickaxe_state() -> void:
	_draft_active = false
	_origin_button.text = PICKAXE_GLYPH
	_origin_button.add_theme_color_override("font_color", DEFAULT_FONT_COLOR)
	_cancel_button.visible = false

func show_confirm_state() -> void:
	_draft_active = true
	_origin_button.text = CONFIRM_GLYPH
	_origin_button.add_theme_color_override("font_color", CONFIRM_FONT_COLOR)
	_cancel_button.visible = true

func is_draft_active() -> bool:
	return _draft_active

func get_origin_button() -> Button:
	return _origin_button

func get_cancel_button() -> Button:
	return _cancel_button

func _build_buttons() -> void:
	_origin_button = _make_button(PICKAXE_GLYPH, _on_origin_pressed)
	_origin_button.name = "MineButton"
	add_child(_origin_button)
	_origin_button.visible = true

	_cancel_button = _make_button(CANCEL_GLYPH, _on_cancel_button_pressed)
	_cancel_button.name = "CancelButton"
	_cancel_button.add_theme_color_override("font_color", CANCEL_FONT_COLOR)
	add_child(_cancel_button)

func _layout_buttons() -> void:
	if _origin_button == null or _cancel_button == null:
		return
	var viewport_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	)
	var origin_pos := Vector2(
		viewport_size.x - margin.x - button_size.x,
		viewport_size.y - margin.y - button_size.y
	)
	_origin_button.position = origin_pos
	_origin_button.size = button_size
	_cancel_button.position = Vector2(origin_pos.x, origin_pos.y - button_size.y - spacing.y)
	_cancel_button.size = button_size

func _on_origin_pressed() -> void:
	if _draft_active:
		confirm_pressed.emit()
		return
	mine_mode_requested.emit()

func _on_cancel_button_pressed() -> void:
	cancel_pressed.emit()

func _make_button(label: String, pressed_callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.visible = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = false
	button.pressed.connect(pressed_callback)
	return button

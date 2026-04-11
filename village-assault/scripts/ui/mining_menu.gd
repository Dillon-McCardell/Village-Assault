extends Control

signal mine_mode_requested
signal confirm_pressed
signal cancel_pressed
signal miner_selected(unit_id: int)

@export var button_size: Vector2 = Vector2(140, 44)
@export var spacing: Vector2 = Vector2(8, 8)
@export var margin: Vector2 = Vector2(16, 16)

const PICKAXE_GLYPH: String = "⛏ Mine"
const CONFIRM_GLYPH: String = "✓ Confirm"
const CANCEL_GLYPH: String = "✕"
const DEFAULT_FONT_COLOR: Color = Color(1, 1, 1, 1)
const CONFIRM_FONT_COLOR: Color = Color(0.55, 0.9, 0.4, 1)
const CANCEL_FONT_COLOR: Color = Color(0.95, 0.35, 0.35, 1)
const PREVIEW_BASE_COLOR: Color = Color(0.54, 0.34, 0.14, 1.0)

var _origin_button: Button
var _cancel_button: Button
var _draft_active: bool = false
var _picker_panel: Panel
var _picker_grid: GridContainer
var _picker_status: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_buttons()
	_build_picker()
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
	hide_miner_picker()

func show_confirm_state() -> void:
	_draft_active = true
	_origin_button.text = CONFIRM_GLYPH
	_origin_button.add_theme_color_override("font_color", CONFIRM_FONT_COLOR)
	_cancel_button.visible = true
	hide_miner_picker()

func show_miner_picker(miners: Array) -> void:
	_rebuild_picker_slots(miners)
	_picker_panel.visible = true

func hide_miner_picker() -> void:
	if _picker_panel != null:
		_picker_panel.visible = false

func is_draft_active() -> bool:
	return _draft_active

func get_origin_button() -> Button:
	return _origin_button

func get_cancel_button() -> Button:
	return _cancel_button

func get_picker_panel() -> Panel:
	return _picker_panel

func get_picker_grid() -> GridContainer:
	return _picker_grid

func _build_buttons() -> void:
	_origin_button = _make_button(PICKAXE_GLYPH, _on_origin_pressed)
	_origin_button.name = "MineButton"
	add_child(_origin_button)
	_origin_button.visible = true

	_cancel_button = _make_button(CANCEL_GLYPH, _on_cancel_button_pressed)
	_cancel_button.name = "CancelButton"
	_cancel_button.add_theme_color_override("font_color", CANCEL_FONT_COLOR)
	add_child(_cancel_button)

func _build_picker() -> void:
	_picker_panel = Panel.new()
	_picker_panel.name = "MinerPicker"
	_picker_panel.visible = false
	add_child(_picker_panel)

	var margin_container := MarginContainer.new()
	margin_container.anchor_right = 1.0
	margin_container.anchor_bottom = 1.0
	margin_container.offset_left = 16.0
	margin_container.offset_top = 16.0
	margin_container.offset_right = -16.0
	margin_container.offset_bottom = -16.0
	_picker_panel.add_child(margin_container)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 12)
	margin_container.add_child(layout)

	var title := Label.new()
	title.text = "Select Miner"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)

	_picker_status = Label.new()
	_picker_status.text = "No miners available."
	_picker_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_picker_status)

	_picker_grid = GridContainer.new()
	_picker_grid.name = "MinerGrid"
	_picker_grid.columns = 3
	_picker_grid.add_theme_constant_override("h_separation", 18)
	_picker_grid.add_theme_constant_override("v_separation", 18)
	layout.add_child(_picker_grid)

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
	if _picker_panel != null:
		_picker_panel.position = Vector2(viewport_size.x * 0.5 - 220.0, viewport_size.y * 0.5 - 170.0)
		_picker_panel.size = Vector2(440.0, 340.0)

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

func _rebuild_picker_slots(miners: Array) -> void:
	for child in _picker_grid.get_children():
		child.queue_free()
	_picker_status.visible = miners.is_empty()
	for miner in miners:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(108, 96)
		slot.focus_mode = Control.FOCUS_NONE
		slot.text = ""
		slot.pressed.connect(func() -> void:
			miner_selected.emit(int(miner.get("unit_id", -1)))
		)
		var preview := _build_miner_preview(miner.get("color", PREVIEW_BASE_COLOR))
		slot.add_child(preview)
		_picker_grid.add_child(slot)

func _build_miner_preview(top_color: Color) -> Control:
	var wrapper := Control.new()
	wrapper.anchor_right = 1.0
	wrapper.anchor_bottom = 1.0
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bottom := ColorRect.new()
	bottom.color = PREVIEW_BASE_COLOR
	bottom.position = Vector2(26, 18)
	bottom.size = Vector2(56, 60)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(bottom)

	var top := ColorRect.new()
	top.color = top_color
	top.position = Vector2(26, 18)
	top.size = Vector2(56, 30)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(top)

	return wrapper

extends Camera2D

signal zoom_changed

@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5
@export var zoom_step: float = 0.1
@export var drag_button: int = MOUSE_BUTTON_LEFT
@export var zoom_sensitivity: float = 0.1
@export var move_speed: float = 300.0

var _dragging: bool = false
var _world_rect: Rect2 = Rect2()
var _has_world_rect: bool = false

func _ready() -> void:
	_ensure_input_actions()
	set_process(true)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if _is_over_ui():
		return
	var event_class := event.get_class()
	if event_class == "InputEventMagnify" or event_class == "InputEventMagnifyGesture":
		var factor: float = float(event.get("factor"))
		var delta: float = factor - 1.0
		_apply_zoom(1.0 + delta * zoom_sensitivity)
		return
	if event_class == "InputEventPanGesture":
		var raw_delta: Variant = event.get("delta")
		if raw_delta is Vector2:
			var delta: Vector2 = raw_delta
			var pan := Vector2(-delta.x, -delta.y) * (zoom.x * 1.25)
			global_position -= pan
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(1.0 - zoom_step)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(1.0 + zoom_step)
			return
		if event.button_index == drag_button:
			_dragging = event.pressed
			return
	if event is InputEventMouseMotion:
		if _dragging or (event.button_mask & (1 << (drag_button - 1))) != 0:
			global_position -= event.relative * (zoom.x * 0.6)

func _process(delta: float) -> void:
	_handle_keyboard_move(delta)
	_handle_keyboard_zoom()
	_apply_limits()

func _handle_keyboard_move(delta: float) -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("cam_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("cam_right"):
		dir.x += 1.0
	if Input.is_action_pressed("cam_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("cam_down"):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		global_position += dir.normalized() * move_speed * delta
	return dir

func _handle_keyboard_zoom() -> void:
	if Input.is_action_just_pressed("cam_zoom_in"):
		_apply_zoom(1.0 - zoom_step)
	elif Input.is_action_just_pressed("cam_zoom_out"):
		_apply_zoom(1.0 + zoom_step)

func _ensure_input_actions() -> void:
	_add_action_if_missing("cam_left", [KEY_LEFT, KEY_A])
	_add_action_if_missing("cam_right", [KEY_RIGHT, KEY_D])
	_add_action_if_missing("cam_up", [KEY_UP, KEY_W])
	_add_action_if_missing("cam_down", [KEY_DOWN, KEY_S])
	_add_action_if_missing("cam_zoom_in", [KEY_Q, KEY_EQUAL, KEY_KP_ADD])
	_add_action_if_missing("cam_zoom_out", [KEY_E, KEY_MINUS, KEY_KP_SUBTRACT])

func _add_action_if_missing(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	for keycode in keys:
		var ev := InputEventKey.new()
		ev.keycode = int(keycode)
		InputMap.action_add_event(action_name, ev)

func _apply_zoom(factor: float) -> void:
	var next := zoom * factor
	next.x = clamp(next.x, min_zoom, max_zoom)
	next.y = clamp(next.y, min_zoom, max_zoom)
	zoom = next
	zoom_changed.emit()

func _is_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if not hovered.is_visible_in_tree():
		return false
	if hovered.name == "UI":
		return false
	if hovered is Button or hovered is LineEdit or hovered is OptionButton or hovered is CheckBox or hovered is HSlider or hovered is VSlider:
		return true
	return hovered.mouse_filter == Control.MOUSE_FILTER_STOP and hovered != self


func _apply_limits() -> void:
	if not _has_world_rect:
		return
	var viewport_size := get_viewport_rect().size
	var half_view := (viewport_size * 0.5) / zoom
	var left_limit := _world_rect.position.x + half_view.x
	var right_limit := _world_rect.position.x + _world_rect.size.x - half_view.x
	var top_limit := _world_rect.position.y + half_view.y
	var bottom_limit := _world_rect.position.y + _world_rect.size.y - half_view.y
	if left_limit > right_limit:
		var center_x := _world_rect.position.x + _world_rect.size.x * 0.5
		left_limit = center_x
		right_limit = center_x
	if top_limit > bottom_limit:
		var center_y := _world_rect.position.y + _world_rect.size.y * 0.5
		top_limit = center_y
		bottom_limit = center_y
	var x := global_position.x
	var y := global_position.y
	if left_limit <= right_limit:
		x = clamp(x, left_limit, right_limit)
	if top_limit <= bottom_limit:
		y = clamp(y, top_limit, bottom_limit)
	global_position = Vector2(x, y)

func set_world_rect(rect: Rect2) -> void:
	_world_rect = rect
	_has_world_rect = rect.size != Vector2.ZERO

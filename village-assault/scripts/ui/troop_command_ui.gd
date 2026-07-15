extends Control
class_name TroopCommandUI

signal order_requested(order: int)
signal restore_all_requested
signal type_filter_requested(item_id: String, additive: bool)
signal role_actions_requested

const ORDER_MOVE: int = 0
const ORDER_ADVANCE: int = 1
const ORDER_DEFEND: int = 2
const ORDER_RETREAT: int = 3

const TOOLBAR_WIDTH: float = 620.0
const TOOLBAR_HEIGHT: float = 104.0
const TOOLBAR_TOP_MARGIN: float = 12.0
const COMMAND_BUTTON_SIZE := Vector2(52.0, 38.0)
const TYPE_BUTTON_SIZE := Vector2(76.0, 36.0)
const ACTIVE_COLOR := Color(0.25, 0.78, 0.92, 1.0)
const INACTIVE_COLOR := Color(0.55, 0.57, 0.60, 0.55)

const TYPE_LABELS: Dictionary = {
	"troop_grunt": "Grunt",
	"troop_ranger": "Ranger",
	"troop_brute": "Brute",
	"troop_scout": "Scout",
	"troop_miner": "Miner",
}

var _toolbar: PanelContainer
var _command_row: HBoxContainer
var _composition_row: HBoxContainer
var _order_buttons: Dictionary = {}
var _role_button: Button
var _all_button: Button
var _type_buttons: Dictionary = {}
var _selection_rect: Panel
var _active_order: int = ORDER_MOVE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_toolbar()
	_build_selection_rect()
	_layout_toolbar()
	_toolbar.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_toolbar()

func update_selection(cohort: Array[Dictionary], active_ids: Dictionary, active_order: int) -> void:
	_active_order = active_order
	_toolbar.visible = not cohort.is_empty()
	if cohort.is_empty():
		return
	_update_order_buttons(not active_ids.is_empty())
	_rebuild_composition_row(cohort, active_ids)
	_update_role_button(cohort, active_ids)

func show_selection_rect(rect: Rect2) -> void:
	_selection_rect.position = rect.position
	_selection_rect.size = rect.size
	_selection_rect.visible = true

func hide_selection_rect() -> void:
	_selection_rect.visible = false

func get_toolbar() -> PanelContainer:
	return _toolbar

func get_order_button(order: int) -> Button:
	return _order_buttons.get(order) as Button

func get_all_button() -> Button:
	return _all_button

func get_role_button() -> Button:
	return _role_button

func get_type_button(item_id: String) -> Button:
	return _type_buttons.get(item_id) as Button

func _build_toolbar() -> void:
	_toolbar = PanelContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	panel_style.border_color = Color(0.28, 0.31, 0.35, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	_toolbar.add_theme_stylebox_override("panel", panel_style)
	add_child(_toolbar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_toolbar.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	_command_row = HBoxContainer.new()
	_command_row.name = "UniversalCommands"
	_command_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_command_row.add_theme_constant_override("separation", 6)
	rows.add_child(_command_row)

	_add_order_button(ORDER_MOVE, "M", "Move: right-click a visible or explored destination")
	_add_order_button(ORDER_ADVANCE, "A", "Advance: move forward and engage enemies")
	_add_order_button(ORDER_DEFEND, "D", "Defend: hold the current position")
	_add_order_button(ORDER_RETREAT, "R", "Retreat: return toward your base")

	var separator := VSeparator.new()
	separator.custom_minimum_size.x = 8.0
	_command_row.add_child(separator)

	_role_button = _make_button("Role 0", "Role Actions")
	_role_button.name = "RoleActionsButton"
	_role_button.custom_minimum_size = Vector2(100.0, COMMAND_BUTTON_SIZE.y)
	_role_button.pressed.connect(func() -> void: role_actions_requested.emit())
	_command_row.add_child(_role_button)

	var composition_scroll := ScrollContainer.new()
	composition_scroll.name = "CompositionScroll"
	composition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	composition_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	composition_scroll.custom_minimum_size.y = TYPE_BUTTON_SIZE.y
	rows.add_child(composition_scroll)

	_composition_row = HBoxContainer.new()
	_composition_row.name = "SelectionComposition"
	_composition_row.add_theme_constant_override("separation", 6)
	composition_scroll.add_child(_composition_row)

func _build_selection_rect() -> void:
	_selection_rect = Panel.new()
	_selection_rect.name = "WorldSelectionRect"
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_rect.visible = false
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.22, 0.75, 0.93, 0.12)
	border.border_color = Color(0.35, 0.85, 1.0, 0.9)
	border.set_border_width_all(1)
	_selection_rect.add_theme_stylebox_override("panel", border)
	add_child(_selection_rect)
	move_child(_selection_rect, 0)

func _layout_toolbar() -> void:
	if _toolbar == null:
		return
	var viewport_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	)
	_toolbar.position = Vector2((viewport_size.x - TOOLBAR_WIDTH) * 0.5, TOOLBAR_TOP_MARGIN)
	_toolbar.size = Vector2(TOOLBAR_WIDTH, TOOLBAR_HEIGHT)

func _add_order_button(order: int, glyph: String, tooltip: String) -> void:
	var button := _make_button(glyph, tooltip)
	button.name = "%sButton" % tooltip.get_slice(":", 0)
	button.toggle_mode = true
	button.custom_minimum_size = COMMAND_BUTTON_SIZE
	button.pressed.connect(func() -> void: order_requested.emit(order))
	_order_buttons[order] = button
	_command_row.add_child(button)

func _update_order_buttons(has_active_selection: bool) -> void:
	for raw_order in _order_buttons.keys():
		var order := int(raw_order)
		var button := _order_buttons[order] as Button
		button.disabled = not has_active_selection
		button.button_pressed = order == _active_order

func _rebuild_composition_row(cohort: Array[Dictionary], active_ids: Dictionary) -> void:
	for child in _composition_row.get_children():
		child.queue_free()
	_type_buttons.clear()

	_all_button = _make_button("All %d" % cohort.size(), "Restore the full selection")
	_all_button.name = "AllButton"
	_all_button.custom_minimum_size = TYPE_BUTTON_SIZE
	_all_button.modulate = ACTIVE_COLOR if active_ids.size() == cohort.size() else INACTIVE_COLOR
	_all_button.pressed.connect(func() -> void: restore_all_requested.emit())
	_composition_row.add_child(_all_button)

	var counts: Dictionary = {}
	var active_counts: Dictionary = {}
	var type_order: Array[String] = []
	for entry in cohort:
		var item_id := String(entry.get("item_id", ""))
		if not counts.has(item_id):
			counts[item_id] = 0
			active_counts[item_id] = 0
			type_order.append(item_id)
		counts[item_id] = int(counts[item_id]) + 1
		if active_ids.has(int(entry.get("unit_id", -1))):
			active_counts[item_id] = int(active_counts[item_id]) + 1
	type_order.sort()

	for item_id in type_order:
		var count := int(counts[item_id])
		var active_count := int(active_counts[item_id])
		var label := String(TYPE_LABELS.get(item_id, item_id.trim_prefix("troop_").capitalize()))
		var count_label := "%d" % count if active_count == count else "%d/%d" % [active_count, count]
		var button := _make_button("%s %s" % [label.left(3), count_label], "%s selection filter" % label)
		button.name = "%sTypeButton" % label
		button.custom_minimum_size = TYPE_BUTTON_SIZE
		button.modulate = ACTIVE_COLOR if active_count > 0 else INACTIVE_COLOR
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				type_filter_requested.emit(item_id, event.shift_pressed)
				button.accept_event()
		)
		_type_buttons[item_id] = button
		_composition_row.add_child(button)

func _update_role_button(cohort: Array[Dictionary], active_ids: Dictionary) -> void:
	var eligible_types: Dictionary = {}
	for entry in cohort:
		var unit_id := int(entry.get("unit_id", -1))
		if not active_ids.has(unit_id):
			continue
		var role_actions: Array = entry.get("role_actions", [])
		if not role_actions.is_empty():
			eligible_types[String(entry.get("item_id", ""))] = true
	_role_button.text = "Role %d" % eligible_types.size()
	_role_button.disabled = eligible_types.is_empty()

func _make_button(label: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

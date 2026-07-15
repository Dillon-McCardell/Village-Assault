extends Control
class_name TroopCommandUI

signal order_requested(order: int)
signal restore_all_requested
signal type_filter_requested(item_id: String, additive: bool)
signal roster_selection_requested(unit_ids: Array, active: bool)
signal roster_type_selection_requested(item_id: String, active: bool)
signal role_action_requested(action_id: String, unit_ids: Array)

const ORDER_MOVE: int = 0
const ORDER_ADVANCE: int = 1
const ORDER_DEFEND: int = 2
const ORDER_RETREAT: int = 3

const TOOLBAR_WIDTH: float = 620.0
const TOOLBAR_HEIGHT: float = 104.0
const TOOLBAR_TOP_MARGIN: float = 12.0
const COMMAND_BUTTON_SIZE := Vector2(52.0, 38.0)
const TYPE_BUTTON_SIZE := Vector2(76.0, 36.0)
const TYPE_FILTER_BUTTON_WIDTH: float = 58.0
const TYPE_DISCLOSURE_BUTTON_WIDTH: float = 18.0
const ROSTER_WIDTH: float = 300.0
const ROSTER_ROW_HEIGHT: float = 42.0
const ROSTER_VIEWPORT_HEIGHT_RATIO: float = 0.4
const ACTIVE_COLOR := Color(0.25, 0.78, 0.92, 1.0)
const INACTIVE_COLOR := Color(0.55, 0.57, 0.60, 0.55)

const TYPE_LABELS: Dictionary = {
	"troop_grunt": "Grunt",
	"troop_ranger": "Ranger",
	"troop_brute": "Brute",
	"troop_scout": "Scout",
	"troop_miner": "Miner",
}

const STATUS_ICONS: Dictionary = {
	0: "I",
	1: "M",
	2: "A",
	3: "D",
	4: "R",
	5: "X",
	6: "Dg",
	7: "Md",
	8: "Hv",
	9: "Rt",
}

const STATUS_TOOLTIPS: Dictionary = {
	0: "Idle",
	1: "Moving",
	2: "Advancing",
	3: "Defending",
	4: "Retreating",
	5: "Engaging enemy",
	6: "Mining",
	7: "Moving to dig site",
	8: "Harvesting ore",
	9: "Returning ore to base",
}

var _toolbar: PanelContainer
var _command_row: HBoxContainer
var _composition_row: HBoxContainer
var _order_buttons: Dictionary = {}
var _role_button: Button
var _all_button: Button
var _type_buttons: Dictionary = {}
var _type_disclosure_buttons: Dictionary = {}
var _selection_rect: Panel
var _active_order: int = ORDER_MOVE
var _selection_signature: String = ""
var _cohort: Array[Dictionary] = []
var _active_ids: Dictionary = {}
var _roster_panel: PanelContainer
var _roster_scroll: ScrollContainer
var _roster_rows: VBoxContainer
var _roster_all_checkbox: CheckBox
var _roster_header_label: Label
var _roster_item_id: String = ""
var _roster_range_anchor_unit_id: int = -1
var _roster_row_controls: Dictionary = {}
var _updating_roster_controls: bool = false
var _role_menu_panel: PanelContainer
var _role_menu_groups: VBoxContainer
var _role_groups: Dictionary = {}
var _role_groups_signature: String = ""
var _role_action_buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_toolbar()
	_build_roster_panel()
	_build_role_menu()
	_build_selection_rect()
	_layout_toolbar()
	_toolbar.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_toolbar()
		_position_roster_popover()
		_position_role_menu()

func update_selection(cohort: Array[Dictionary], active_ids: Dictionary, active_order: int) -> void:
	_active_order = active_order
	_cohort = cohort.duplicate()
	_active_ids = active_ids.duplicate()
	_toolbar.visible = not cohort.is_empty()
	if cohort.is_empty():
		close_roster()
		close_role_menu()
		_selection_signature = ""
		return
	_update_order_buttons(not active_ids.is_empty())
	var signature := _build_selection_signature(cohort)
	if signature != _selection_signature:
		_selection_signature = signature
		_rebuild_composition_row(cohort, active_ids)
		if not _roster_item_id.is_empty():
			_rebuild_roster()
	else:
		_refresh_roster_rows()
	_update_composition_buttons(cohort, active_ids)
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

func get_type_disclosure_button(item_id: String) -> Button:
	return _type_disclosure_buttons.get(item_id) as Button

func get_roster_panel() -> PanelContainer:
	return _roster_panel

func get_roster_rows() -> VBoxContainer:
	return _roster_rows

func get_roster_row(unit_id: int) -> Button:
	var controls: Dictionary = _roster_row_controls.get(unit_id, {})
	return controls.get("row") as Button

func get_roster_all_checkbox() -> CheckBox:
	return _roster_all_checkbox

func get_role_menu_panel() -> PanelContainer:
	return _role_menu_panel

func get_role_action_button(action_id: String) -> Button:
	return _role_action_buttons.get(action_id) as Button

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
	_role_button.pressed.connect(_toggle_role_menu)
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

func _build_roster_panel() -> void:
	_roster_panel = PanelContainer.new()
	_roster_panel.name = "TroopRosterPopover"
	_roster_panel.visible = false
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_roster_panel.z_index = 100
	_roster_panel.custom_minimum_size.x = ROSTER_WIDTH
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	panel_style.border_color = Color(0.34, 0.38, 0.43, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	_roster_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_roster_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_roster_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.name = "RosterHeader"
	header.add_theme_constant_override("separation", 6)
	layout.add_child(header)

	_roster_all_checkbox = CheckBox.new()
	_roster_all_checkbox.name = "RosterAllCheckBox"
	_roster_all_checkbox.tooltip_text = "Select or deselect every troop of this type"
	_roster_all_checkbox.focus_mode = Control.FOCUS_NONE
	_roster_all_checkbox.toggled.connect(_on_roster_all_toggled)
	header.add_child(_roster_all_checkbox)

	_roster_header_label = Label.new()
	_roster_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_roster_header_label)

	var close_button := _make_button("x", "Close roster")
	close_button.name = "RosterCloseButton"
	close_button.custom_minimum_size = Vector2(28.0, 28.0)
	close_button.pressed.connect(close_roster)
	header.add_child(close_button)

	_roster_scroll = ScrollContainer.new()
	_roster_scroll.name = "RosterScroll"
	_roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(_roster_scroll)

	_roster_rows = VBoxContainer.new()
	_roster_rows.name = "RosterRows"
	_roster_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_rows.add_theme_constant_override("separation", 4)
	_roster_scroll.add_child(_roster_rows)

func _build_role_menu() -> void:
	_role_menu_panel = PanelContainer.new()
	_role_menu_panel.name = "RoleActionsMenu"
	_role_menu_panel.visible = false
	_role_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_role_menu_panel.z_index = 110
	_role_menu_panel.custom_minimum_size.x = 240.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	panel_style.border_color = Color(0.34, 0.38, 0.43, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	_role_menu_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_role_menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_role_menu_panel.add_child(margin)

	_role_menu_groups = VBoxContainer.new()
	_role_menu_groups.name = "RoleActionGroups"
	_role_menu_groups.add_theme_constant_override("separation", 8)
	margin.add_child(_role_menu_groups)

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
	_position_roster_popover()
	_position_role_menu()

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
	_type_disclosure_buttons.clear()

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
		var entry_controls := HBoxContainer.new()
		entry_controls.name = "%sCompositionEntry" % label
		entry_controls.add_theme_constant_override("separation", 0)
		entry_controls.custom_minimum_size = TYPE_BUTTON_SIZE
		_composition_row.add_child(entry_controls)

		var button := _make_button("%s %s" % [label.left(3), count_label], "%s selection filter" % label)
		button.name = "%sTypeButton" % label
		button.custom_minimum_size = Vector2(TYPE_FILTER_BUTTON_WIDTH, TYPE_BUTTON_SIZE.y)
		button.modulate = ACTIVE_COLOR if active_count > 0 else INACTIVE_COLOR
		button.gui_input.connect(func(event: InputEvent) -> void:
			if not event is InputEventMouseButton or not event.pressed:
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				type_filter_requested.emit(item_id, event.shift_pressed)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				open_roster_for_type(item_id)
			else:
				return
			button.accept_event()
		)
		_type_buttons[item_id] = button
		entry_controls.add_child(button)

		var disclosure := _make_button("v", "Open %s roster" % label)
		disclosure.name = "%sRosterDisclosureButton" % label
		disclosure.custom_minimum_size = Vector2(TYPE_DISCLOSURE_BUTTON_WIDTH, TYPE_BUTTON_SIZE.y)
		disclosure.modulate = button.modulate
		disclosure.pressed.connect(_toggle_roster_for_type.bind(item_id))
		_type_disclosure_buttons[item_id] = disclosure
		entry_controls.add_child(disclosure)
	if not _roster_item_id.is_empty():
		_position_roster_popover.call_deferred()

func _build_selection_signature(cohort: Array[Dictionary]) -> String:
	var cohort_parts: Array[String] = []
	for entry in cohort:
		cohort_parts.append("%d:%s" % [
			int(entry.get("unit_id", -1)),
			String(entry.get("item_id", "")),
		])
	return "|".join(cohort_parts)

func _update_composition_buttons(cohort: Array[Dictionary], active_ids: Dictionary) -> void:
	if _all_button != null:
		_all_button.text = "All %d" % cohort.size()
		_all_button.modulate = ACTIVE_COLOR if active_ids.size() == cohort.size() else INACTIVE_COLOR
	var counts: Dictionary = {}
	var active_counts: Dictionary = {}
	for entry in cohort:
		var item_id := String(entry.get("item_id", ""))
		counts[item_id] = int(counts.get(item_id, 0)) + 1
		if active_ids.has(int(entry.get("unit_id", -1))):
			active_counts[item_id] = int(active_counts.get(item_id, 0)) + 1
	for raw_item_id in counts.keys():
		var item_id := String(raw_item_id)
		var count := int(counts[item_id])
		var active_count := int(active_counts.get(item_id, 0))
		var label := String(TYPE_LABELS.get(item_id, item_id.trim_prefix("troop_").capitalize()))
		var count_label := "%d" % count if active_count == count else "%d/%d" % [active_count, count]
		var modulate_color := ACTIVE_COLOR if active_count > 0 else INACTIVE_COLOR
		var button := _type_buttons.get(item_id) as Button
		if button != null:
			button.text = "%s %s" % [label.left(3), count_label]
			button.modulate = modulate_color
		var disclosure := _type_disclosure_buttons.get(item_id) as Button
		if disclosure != null:
			disclosure.modulate = modulate_color

func open_roster_for_type(item_id: String) -> void:
	if _get_roster_entries(item_id).is_empty():
		close_roster()
		return
	if _roster_item_id != item_id:
		_roster_range_anchor_unit_id = -1
	close_role_menu()
	_roster_item_id = item_id
	_roster_panel.visible = true
	_rebuild_roster()
	_position_roster_popover()
	_position_roster_popover.call_deferred()

func close_roster() -> void:
	_roster_item_id = ""
	_roster_range_anchor_unit_id = -1
	_roster_row_controls.clear()
	if _roster_panel != null:
		_roster_panel.visible = false

func _toggle_roster_for_type(item_id: String) -> void:
	if _roster_panel.visible and _roster_item_id == item_id:
		close_roster()
		return
	open_roster_for_type(item_id)

func _rebuild_roster() -> void:
	if _roster_item_id.is_empty():
		return
	var entries := _get_roster_entries(_roster_item_id)
	if entries.is_empty():
		close_roster()
		return
	for child in _roster_rows.get_children():
		child.queue_free()
	_roster_row_controls.clear()

	for entry in entries:
		var unit_id := int(entry.get("unit_id", -1))
		var row := Button.new()
		row.name = "RosterRow_%d" % unit_id
		row.text = ""
		row.toggle_mode = true
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.custom_minimum_size = Vector2(ROSTER_WIDTH - 18.0, ROSTER_ROW_HEIGHT)
		row.gui_input.connect(_on_roster_row_gui_input.bind(unit_id))
		_roster_rows.add_child(row)

		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_bottom", 4)
		row.add_child(margin)

		var contents := HBoxContainer.new()
		contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.add_theme_constant_override("separation", 7)
		margin.add_child(contents)

		var selected_checkbox := CheckBox.new()
		selected_checkbox.name = "SelectedCheckBox"
		selected_checkbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selected_checkbox.focus_mode = Control.FOCUS_NONE
		contents.add_child(selected_checkbox)

		var portrait := ColorRect.new()
		portrait.name = "Portrait"
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(24.0, 24.0)
		portrait.color = entry.get("portrait_color", Color(0.65, 0.68, 0.72, 1.0))
		contents.add_child(portrait)

		var unit_label := Label.new()
		unit_label.name = "UnitLabel"
		unit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit_label.custom_minimum_size.x = 72.0
		unit_label.text = "%s %d" % [
			String(TYPE_LABELS.get(_roster_item_id, _roster_item_id.trim_prefix("troop_").capitalize())),
			unit_id,
		]
		contents.add_child(unit_label)

		var health := ProgressBar.new()
		health.name = "HealthBar"
		health.custom_minimum_size = Vector2(82.0, 10.0)
		health.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		health.show_percentage = false
		health.mouse_filter = Control.MOUSE_FILTER_PASS
		contents.add_child(health)

		var status := Label.new()
		status.name = "StatusIcon"
		status.custom_minimum_size.x = 26.0
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		contents.add_child(status)

		_roster_row_controls[unit_id] = {
			"row": row,
			"checkbox": selected_checkbox,
			"health": health,
			"status": status,
		}

	var viewport_height := float(ProjectSettings.get_setting(
		"display/window/size/viewport_height",
		648
	))
	var max_panel_height := viewport_height * ROSTER_VIEWPORT_HEIGHT_RATIO
	var scroll_height := minf(
		float(entries.size()) * (ROSTER_ROW_HEIGHT + 4.0),
		maxf(ROSTER_ROW_HEIGHT, max_panel_height - 50.0)
	)
	_roster_scroll.custom_minimum_size.y = scroll_height
	_roster_panel.size = Vector2(ROSTER_WIDTH, scroll_height + 50.0)
	_refresh_roster_rows()

func _refresh_roster_rows() -> void:
	if _roster_panel == null or not _roster_panel.visible or _roster_item_id.is_empty():
		return
	var entries := _get_roster_entries(_roster_item_id)
	if entries.is_empty():
		close_roster()
		return
	var all_active := true
	for entry in entries:
		var unit_id := int(entry.get("unit_id", -1))
		all_active = all_active and _active_ids.has(unit_id)
		var controls: Dictionary = _roster_row_controls.get(unit_id, {})
		if controls.is_empty():
			continue
		var selected := _active_ids.has(unit_id)
		var row := controls.get("row") as Button
		var selected_checkbox := controls.get("checkbox") as CheckBox
		var health := controls.get("health") as ProgressBar
		var status := controls.get("status") as Label
		row.set_pressed_no_signal(selected)
		selected_checkbox.set_pressed_no_signal(selected)
		var max_health := maxi(1, int(entry.get("max_health", 1)))
		var current_health := clampi(int(entry.get("current_health", 0)), 0, max_health)
		var health_ratio := float(current_health) / float(max_health)
		health.value = health_ratio * 100.0
		health.modulate = Color(0.92, 0.24, 0.22, 1.0).lerp(
			Color(0.24, 0.82, 0.38, 1.0),
			health_ratio
		)
		health.tooltip_text = "Health: %d/%d" % [current_health, max_health]
		var current_status := int(entry.get("current_status", 0))
		status.text = String(STATUS_ICONS.get(current_status, "?"))
		status.tooltip_text = String(STATUS_TOOLTIPS.get(current_status, "Unknown action"))
	_roster_header_label.text = "%s %d" % [
		String(TYPE_LABELS.get(_roster_item_id, _roster_item_id.trim_prefix("troop_").capitalize())),
		entries.size(),
	]
	_updating_roster_controls = true
	_roster_all_checkbox.set_pressed_no_signal(all_active)
	_updating_roster_controls = false

func _get_roster_entries(item_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in _cohort:
		if String(entry.get("item_id", "")) == item_id:
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("unit_id", -1)) < int(b.get("unit_id", -1))
	)
	return entries

func _on_roster_row_gui_input(event: InputEvent, unit_id: int) -> void:
	if not event is InputEventMouseButton \
		or not event.pressed \
		or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var unit_ids: Array[int] = [unit_id]
	var target_active := not _active_ids.has(unit_id)
	if event.shift_pressed and _roster_range_anchor_unit_id != -1:
		var ordered_entries := _get_roster_entries(_roster_item_id)
		var anchor_index := -1
		var unit_index := -1
		for index in range(ordered_entries.size()):
			var entry_unit_id := int(ordered_entries[index].get("unit_id", -1))
			if entry_unit_id == _roster_range_anchor_unit_id:
				anchor_index = index
			if entry_unit_id == unit_id:
				unit_index = index
		if anchor_index != -1 and unit_index != -1:
			unit_ids.clear()
			for index in range(mini(anchor_index, unit_index), maxi(anchor_index, unit_index) + 1):
				unit_ids.append(int(ordered_entries[index].get("unit_id", -1)))
	_roster_range_anchor_unit_id = unit_id
	roster_selection_requested.emit(unit_ids, target_active)
	var controls: Dictionary = _roster_row_controls.get(unit_id, {})
	var row := controls.get("row") as Button
	if row != null:
		row.accept_event()

func _on_roster_all_toggled(active: bool) -> void:
	if _updating_roster_controls or _roster_item_id.is_empty():
		return
	roster_type_selection_requested.emit(_roster_item_id, active)

func _position_roster_popover() -> void:
	if _roster_panel == null or not _roster_panel.visible or _roster_item_id.is_empty():
		return
	var viewport_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	)
	var anchor_x := _toolbar.position.x + _toolbar.size.x
	var source := _type_disclosure_buttons.get(_roster_item_id) as Control
	if source != null and is_instance_valid(source):
		anchor_x = source.global_position.x + source.size.x
	var panel_x := clampf(anchor_x - ROSTER_WIDTH, 8.0, viewport_size.x - ROSTER_WIDTH - 8.0)
	var panel_y := _toolbar.position.y + _toolbar.size.y + 6.0
	_roster_panel.position = Vector2(panel_x, panel_y)

func _update_role_button(cohort: Array[Dictionary], active_ids: Dictionary) -> void:
	var groups: Dictionary = {}
	for entry in cohort:
		var unit_id := int(entry.get("unit_id", -1))
		if not active_ids.has(unit_id):
			continue
		var actions: Array = entry.get("role_actions", [])
		if actions.is_empty():
			continue
		var item_id := String(entry.get("item_id", ""))
		if not groups.has(item_id):
			groups[item_id] = {
				"unit_ids": [],
				"actions": actions.duplicate(true),
			}
		(groups[item_id]["unit_ids"] as Array).append(unit_id)
	_role_groups = groups
	_role_button.text = "Role %d" % groups.size()
	_role_button.disabled = groups.is_empty()
	if groups.is_empty():
		close_role_menu()
		return
	var signature := _build_role_groups_signature(groups)
	if signature != _role_groups_signature:
		_role_groups_signature = signature
		if _role_menu_panel.visible:
			_rebuild_role_menu()

func _build_role_groups_signature(groups: Dictionary) -> String:
	var parts: Array[String] = []
	var item_ids: Array[String] = []
	for raw_item_id in groups.keys():
		item_ids.append(String(raw_item_id))
	item_ids.sort()
	for item_id in item_ids:
		var group: Dictionary = groups[item_id]
		var action_ids: Array[String] = []
		for action in group.get("actions", []):
			action_ids.append(String(action.get("id", "")))
		parts.append("%s:%s:%s" % [
			item_id,
			",".join(action_ids),
			str(group.get("unit_ids", [])),
		])
	return "|".join(parts)

func _toggle_role_menu() -> void:
	if _role_menu_panel.visible:
		close_role_menu()
		return
	if _role_groups.is_empty():
		return
	close_roster()
	_rebuild_role_menu()
	_role_menu_panel.visible = true
	_position_role_menu()
	_position_role_menu.call_deferred()

func close_role_menu() -> void:
	if _role_menu_panel != null:
		_role_menu_panel.visible = false

func _rebuild_role_menu() -> void:
	for child in _role_menu_groups.get_children():
		child.queue_free()
	_role_action_buttons.clear()
	var item_ids: Array[String] = []
	for raw_item_id in _role_groups.keys():
		item_ids.append(String(raw_item_id))
	item_ids.sort()
	for item_id in item_ids:
		var group: Dictionary = _role_groups[item_id]
		var label := Label.new()
		label.text = String(TYPE_LABELS.get(item_id, item_id.trim_prefix("troop_").capitalize()))
		_role_menu_groups.add_child(label)
		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 6)
		_role_menu_groups.add_child(action_row)
		for action in group.get("actions", []):
			var action_id := String(action.get("id", ""))
			var action_button := _make_button(
				String(action.get("label", action_id.capitalize())),
				String(action.get("tooltip", ""))
			)
			action_button.name = "%sRoleActionButton" % action_id.to_pascal_case()
			action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action_button.pressed.connect(_on_role_action_pressed.bind(
				action_id,
				(group.get("unit_ids", []) as Array).duplicate()
			))
			_role_action_buttons[action_id] = action_button
			action_row.add_child(action_button)

func _on_role_action_pressed(action_id: String, unit_ids: Array) -> void:
	close_role_menu()
	role_action_requested.emit(action_id, unit_ids)

func _position_role_menu() -> void:
	if _role_menu_panel == null or not _role_menu_panel.visible or _role_button == null:
		return
	var viewport_width := float(ProjectSettings.get_setting(
		"display/window/size/viewport_width",
		1152
	))
	var anchor_x := _role_button.global_position.x + _role_button.size.x
	var panel_x := clampf(anchor_x - 240.0, 8.0, viewport_width - 248.0)
	_role_menu_panel.position = Vector2(
		panel_x,
		_toolbar.position.y + _toolbar.size.y + 6.0
	)

func _make_button(label: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = label
	button.clip_text = true
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

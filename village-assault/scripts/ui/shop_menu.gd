extends Control

signal item_purchased(item_id: String, price: int)

@export var button_size: Vector2 = Vector2(140, 44)
@export var spacing: Vector2 = Vector2(8, 8)
@export var margin: Vector2 = Vector2(16, 16)

const ITEM_SCRIPTS: Array = [
	preload("res://scripts/shop/troops/troop_grunt.gd"),
	preload("res://scripts/shop/troops/troop_ranger.gd"),
	preload("res://scripts/shop/troops/troop_brute.gd"),
	preload("res://scripts/shop/troops/troop_scout.gd"),
	preload("res://scripts/shop/defense/defense_gate.gd"),
	preload("res://scripts/shop/defense/defense_stairs.gd"),
	preload("res://scripts/shop/defense/defense_tower.gd"),
	preload("res://scripts/shop/defense/defense_wall.gd"),
	preload("res://scripts/shop/turrets/turret_archer.gd"),
	preload("res://scripts/shop/turrets/turret_ballista.gd"),
	preload("res://scripts/shop/turrets/turret_cannon.gd"),
	preload("res://scripts/shop/turrets/turret_laser.gd"),
]

var _origin_button: Button
var _category_buttons: Array[Button] = []
var _item_buttons: Array = []
var _category_expanded: Array[bool] = []
var _shop_open: bool = false
var _shop_data: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shop_data()
	_build_buttons()
	_layout_buttons()
	_collapse_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_buttons()

func _unhandled_input(event: InputEvent) -> void:
	if not _shop_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _is_point_on_visible_button(event.position):
			_collapse_all()

func _build_shop_data() -> void:
	_shop_data.clear()
	var categories: Dictionary = {}
	for script in ITEM_SCRIPTS:
		var item := (script as GDScript).new() as ShopItem
		if item == null:
			continue
		if not categories.has(item.category):
			categories[item.category] = []
		categories[item.category].append(item)
	for category_label in categories.keys():
		var items: Array = categories[category_label]
		_shop_data.append({
			"id": category_label.to_lower(),
			"label": category_label,
			"items": items,
		})

func _build_buttons() -> void:
	_origin_button = _make_button("Shop", _on_origin_pressed)
	add_child(_origin_button)
	_origin_button.visible = true

	_category_buttons.clear()
	_item_buttons.clear()
	_category_expanded.clear()

	for i in range(_shop_data.size()):
		var category: Dictionary = _shop_data[i]
		var category_button := _make_button(category["label"], func() -> void:
			_on_category_pressed(i)
		)
		add_child(category_button)
		_category_buttons.append(category_button)
		_category_expanded.append(false)

		var item_row: Array = []
		var items: Array = category["items"]
		for j in range(items.size()):
			var item: ShopItem = items[j]
			var label := item.get_display_label()
			var item_button := _make_button(label, func() -> void:
				_on_item_pressed(i, j)
			)
			add_child(item_button)
			item_row.append(item_button)
		_item_buttons.append(item_row)

func _layout_buttons() -> void:
	var viewport_size := get_viewport_rect().size
	var origin_pos := Vector2(margin.x, viewport_size.y - margin.y - button_size.y)
	_origin_button.position = origin_pos
	_origin_button.size = button_size

	for i in range(_category_buttons.size()):
		var category_pos := Vector2(
			origin_pos.x,
			origin_pos.y - (i + 1) * (button_size.y + spacing.y)
		)
		_category_buttons[i].position = category_pos
		_category_buttons[i].size = button_size

		for j in range(_item_buttons[i].size()):
			var item_pos := Vector2(
				category_pos.x + (j + 1) * (button_size.x + spacing.x),
				category_pos.y
			)
			_item_buttons[i][j].position = item_pos
			_item_buttons[i][j].size = button_size

func _on_origin_pressed() -> void:
	if _shop_open:
		_collapse_all()
		return
	_open_shop()

func _on_category_pressed(index: int) -> void:
	if index < 0 or index >= _category_buttons.size():
		return
	if _category_expanded[index]:
		_collapse_category(index)
		return
	_expand_category(index)

func _on_item_pressed(category_index: int, item_index: int) -> void:
	var item := _get_item(category_index, item_index)
	if item == null:
		return
	if multiplayer.is_server():
		_process_purchase_request(multiplayer.get_unique_id(), item)
	else:
		_request_purchase.rpc_id(1, category_index, item_index)

func _open_shop() -> void:
	_shop_open = true
	for button in _category_buttons:
		button.visible = true

func _collapse_all() -> void:
	_shop_open = false
	for i in range(_category_buttons.size()):
		_category_buttons[i].visible = false
		_category_expanded[i] = false
		for item_button in _item_buttons[i]:
			item_button.visible = false

func _expand_category(index: int) -> void:
	_category_expanded[index] = true
	for item_button in _item_buttons[index]:
		item_button.visible = true

func _collapse_category(index: int) -> void:
	_category_expanded[index] = false
	for item_button in _item_buttons[index]:
		item_button.visible = false

func _is_point_on_visible_button(point: Vector2) -> bool:
	if _origin_button.visible and _origin_button.get_global_rect().has_point(point):
		return true
	for i in range(_category_buttons.size()):
		var category_button := _category_buttons[i]
		if category_button.visible and category_button.get_global_rect().has_point(point):
			return true
		for item_button in _item_buttons[i]:
			if item_button.visible and item_button.get_global_rect().has_point(point):
				return true
	return false

func _make_button(label: String, pressed_callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(pressed_callback)
	button.visible = false
	button.focus_mode = Control.FOCUS_NONE
	return button

func _get_item(category_index: int, item_index: int) -> ShopItem:
	if category_index < 0 or category_index >= _shop_data.size():
		return null
	var category: Dictionary = _shop_data[category_index]
	var items: Array = category["items"]
	if item_index < 0 or item_index >= items.size():
		return null
	return items[item_index]

@rpc("any_peer", "reliable")
func _request_purchase(category_index: int, item_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1
	var item := _get_item(category_index, item_index)
	if item == null:
		return
	_process_purchase_request(peer_id, item)

func _process_purchase_request(peer_id: int, item: ShopItem) -> void:
	var price: int = item.price
	var current_money := GameState.get_money_for_peer(peer_id)
	if current_money < price:
		return
	GameState.set_money_for_peer(peer_id, current_money - price)
	item_purchased.emit(item.id, price)
	# TODO: Spawn or queue the selected item here.

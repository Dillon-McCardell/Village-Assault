## Feature: mining-selection
## Scene-level tests for miner picker, per-miner mining UI, and validation flow.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const MiningSelectionState = preload("res://scripts/game.gd").MiningSelectionState

func _reset_runtime_state() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")
	get_tree().paused = false

func _mount_node(node: Node) -> void:
	get_tree().root.add_child(node)
	get_tree().current_scene = node

func _clear_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	get_tree().current_scene = null
	get_tree().paused = false

func _start_host_game() -> Node:
	_reset_runtime_state()
	NetworkManager.host(NetworkManager.DEFAULT_PORT)
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _mining_menu(game: Node) -> Control:
	return game.get_node("CanvasLayer/UI/MiningMenu") as Control

func _mine_button(game: Node) -> Button:
	return game.get_node("CanvasLayer/UI/MiningMenu/MineButton") as Button

func _picker_panel(game: Node) -> Panel:
	return (_mining_menu(game) as Control).get_picker_panel() as Panel

func _picker_grid(game: Node) -> GridContainer:
	return (_mining_menu(game) as Control).get_picker_grid() as GridContainer

func _sample_ground_tile(game: Node, tile_x: int = 12, extra_depth: int = 0) -> Vector2i:
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	return Vector2i(tile_x, territory.get_surface_tile_y_at_x(float(tile_x * territory.tile_size)) + extra_depth)

func _tile_screen_position(game: Node, tile: Vector2i) -> Vector2:
	return game.world_to_screen_position(game.territory_manager.tile_to_world_center(tile))

func _left_mouse_button_event(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _spawn_miner(game: Node, unit_id: int, color: Color) -> Node2D:
	var payload: Dictionary = game.get_troop_spawn_payload("troop_miner")
	payload["miner_top_color"] = color
	game.spawn_unit(Vector2(32 * unit_id, 0), GameState.Team.LEFT, "troop_miner", unit_id, payload)
	return game.get_unit_by_id(unit_id)

func _shop_button(game: Node) -> Button:
	var shop_menu := game.get_node("CanvasLayer/UI/ShopMenu")
	return shop_menu._origin_button as Button

func test_mine_button_opens_centered_miner_picker() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_mine_button(game).emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.PICKING_MINER)
	assert_bool(_picker_panel(game).visible).is_true()
	assert_int(_picker_grid(game).get_child_count()).is_equal(1)

	_clear_node(game)
	_reset_runtime_state()

func test_pressing_mine_again_closes_empty_miner_picker() -> void:
	var game := _start_host_game()

	_mine_button(game).emit_signal("pressed")
	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.PICKING_MINER)
	assert_bool(_picker_panel(game).visible).is_true()

	_mine_button(game).emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(_picker_panel(game).visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_pressing_other_button_closes_miner_picker() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_mine_button(game).emit_signal("pressed")
	assert_bool(_picker_panel(game).visible).is_true()

	var shop_button := _shop_button(game)
	shop_button.emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(_picker_panel(game).visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_selecting_miner_enters_tile_selection_for_that_miner() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	game.open_miner_picker()
	(_picker_grid(game).get_child(0) as Button).emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING)
	assert_int(game.get_selected_miner_unit_id()).is_equal(1)
	assert_bool(_picker_panel(game).visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_clicking_picker_slot_selects_miner() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_mine_button(game).emit_signal("pressed")
	var slot := _picker_grid(game).get_child(0) as Button
	slot.emit_signal("pressed")

	assert_int(game.get_selected_miner_unit_id()).is_equal(1)
	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING)

	_clear_node(game)
	_reset_runtime_state()

func test_picker_uses_live_miner_color_from_unit() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	miner.miner_top_color = Color(0.95, 0.45, 0.75, 1.0)

	_mine_button(game).emit_signal("pressed")

	var slot := _picker_grid(game).get_child(0) as Button
	var wrapper := slot.get_child(0) as Control
	var top_rect := wrapper.get_child(1) as ColorRect
	assert_float(top_rect.color.r).is_equal_approx(0.95, 0.001)
	assert_float(top_rect.color.g).is_equal_approx(0.45, 0.001)
	assert_float(top_rect.color.b).is_equal_approx(0.75, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_confirmed_selection_is_stored_per_miner_and_shown_in_passive_view() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	_spawn_miner(game, 2, Color(0.2, 0.9, 0.4, 1.0))
	var tile_a := _sample_ground_tile(game, 12)
	var tile_b := _sample_ground_tile(game, 13)

	game.select_miner_for_mining(1)
	game.toggle_draft_tile(tile_a)
	game.confirm_mining_selection()
	game.select_miner_for_mining(2)
	game.toggle_draft_tile(tile_b)
	game.confirm_mining_selection()

	var all_tiles: Dictionary = game.get_all_committed_mining_tiles()
	assert_bool((all_tiles.get(1, {}) as Dictionary).has(tile_a)).is_true()
	assert_bool((all_tiles.get(2, {}) as Dictionary).has(tile_b)).is_true()
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_COMMITTED_LAYER_START, tile_a)).is_equal(0)
	assert_float(game.territory_manager.tile_map.get_layer_modulate(game.territory_manager.MINING_COMMITTED_LAYER_START).a).is_equal_approx(
		game.territory_manager.MINING_COMMITTED_ALPHA,
		0.001
	)

	_clear_node(game)
	_reset_runtime_state()

func test_invalid_unreachable_tiles_highlight_red_and_are_removed_on_confirm() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var valid_tile := _sample_ground_tile(game, 12)
	var invalid_tile := _sample_ground_tile(game, 12, 2)

	game.select_miner_for_mining(1)
	game.toggle_draft_tile(valid_tile)
	game.toggle_draft_tile(invalid_tile)

	assert_bool(game.get_current_invalid_mining_tiles().has(invalid_tile)).is_true()
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_INVALID_LAYER, invalid_tile)).is_equal(0)

	game.confirm_mining_selection()

	assert_bool((game.get_all_committed_mining_tiles().get(1, {}) as Dictionary).has(valid_tile)).is_true()
	assert_bool((game.get_all_committed_mining_tiles().get(1, {}) as Dictionary).has(invalid_tile)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_miner_assignment_mines_tile_into_underground_air() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game, 12)
	miner.position = game.territory_manager.tile_to_world_center(Vector2i(tile.x, tile.y - 1))

	game.select_miner_for_mining(1)
	game.toggle_draft_tile(tile)
	game.confirm_mining_selection()

	for _i in range(12):
		miner._physics_process(0.5)

	assert_bool(game.territory_manager.has_ground_at_tile(tile)).is_false()
	assert_bool(game.territory_manager.is_underground_tile(tile)).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_left_click_toggles_ground_tile_only_while_selecting() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game)

	game.select_miner_for_mining(1)
	var click_position := _tile_screen_position(game, tile)
	game._input(_left_mouse_button_event(click_position, true))
	game._input(_left_mouse_button_event(click_position, false))

	assert_bool(game.get_draft_mining_tiles().has(tile)).is_true()

	_clear_node(game)
	_reset_runtime_state()

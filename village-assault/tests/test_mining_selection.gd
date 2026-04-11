## Feature: mining-selection
## Scene-level tests for mining UI, tile selection, and camera drag ownership.
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

func _start_game() -> Node:
	_reset_runtime_state()
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _mining_menu(game: Node) -> Control:
	return game.get_node("CanvasLayer/UI/MiningMenu") as Control

func _mine_button(game: Node) -> Button:
	return game.get_node("CanvasLayer/UI/MiningMenu/MineButton") as Button

func _cancel_button(game: Node) -> Button:
	return game.get_node("CanvasLayer/UI/MiningMenu/CancelButton") as Button

func _sample_ground_tile(game: Node, tile_x: int = 12) -> Vector2i:
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	return Vector2i(tile_x, territory.get_surface_tile_y_at_x(float(tile_x * territory.tile_size)))

func _tile_screen_position(game: Node, tile: Vector2i) -> Vector2:
	return game.world_to_screen_position(game.territory_manager.tile_to_world_center(tile))

func _left_mouse_button_event(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _mouse_motion_event(position: Vector2, relative: Vector2, button_mask: int) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = button_mask
	return event

func _right_drag_mask() -> int:
	return 1 << (MOUSE_BUTTON_RIGHT - 1)

func test_mining_button_starts_collapsed_with_pickaxe_icon() -> void:
	var game := _start_game()
	var mine_button := _mine_button(game)
	var cancel_button := _cancel_button(game)

	assert_str(mine_button.text).is_equal("⛏ Mine")
	assert_bool(cancel_button.visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_pressing_pickaxe_enters_draft_mode_and_reveals_cancel() -> void:
	var game := _start_game()
	var mine_button := _mine_button(game)
	var cancel_button := _cancel_button(game)

	mine_button.emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING)
	assert_str(mine_button.text).is_equal("✓ Confirm")
	assert_bool(cancel_button.visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_cancel_from_draft_clears_selection_and_restores_pickaxe() -> void:
	var game := _start_game()
	var mine_button := _mine_button(game)
	var cancel_button := _cancel_button(game)
	var tile := _sample_ground_tile(game)

	game.enter_mining_mode()
	game.toggle_draft_tile(tile)
	cancel_button.emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(game.get_draft_mining_tiles().is_empty()).is_true()
	assert_bool(game.get_committed_mining_tiles().is_empty()).is_true()
	assert_str(mine_button.text).is_equal("⛏ Mine")
	assert_bool(cancel_button.visible).is_false()
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_DRAFT_LAYER, tile)).is_equal(-1)
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_COMMITTED_LAYER, tile)).is_equal(-1)

	_clear_node(game)
	_reset_runtime_state()

func test_confirm_without_tiles_behaves_like_cancel() -> void:
	var game := _start_game()
	var mine_button := _mine_button(game)
	var cancel_button := _cancel_button(game)

	game.enter_mining_mode()
	mine_button.emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(game.get_committed_mining_tiles().is_empty()).is_true()
	assert_str(mine_button.text).is_equal("⛏ Mine")
	assert_bool(cancel_button.visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_confirm_persists_tiles_and_reopen_uses_committed_set_as_draft() -> void:
	var game := _start_game()
	var tile := _sample_ground_tile(game)

	game.enter_mining_mode()
	game.toggle_draft_tile(tile)
	game.confirm_mining_selection()

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.CONFIRMED)
	assert_bool(game.get_committed_mining_tiles().has(tile)).is_true()
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_COMMITTED_LAYER, tile)).is_equal(0)
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_DRAFT_LAYER, tile)).is_equal(-1)
	assert_float(game.territory_manager.tile_map.get_layer_modulate(game.territory_manager.MINING_COMMITTED_LAYER).a).is_equal_approx(
		game.territory_manager.MINING_COMMITTED_ALPHA,
		0.001
	)

	game.enter_mining_mode()

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING)
	assert_bool(game.get_draft_mining_tiles().has(tile)).is_true()
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_DRAFT_LAYER, tile)).is_equal(0)
	assert_int(game.territory_manager.tile_map.get_cell_source_id(game.territory_manager.MINING_COMMITTED_LAYER, tile)).is_equal(-1)
	assert_float(game.territory_manager.tile_map.get_layer_modulate(game.territory_manager.MINING_DRAFT_LAYER).a).is_equal_approx(
		game.territory_manager.MINING_DRAFT_ALPHA,
		0.001
	)

	_clear_node(game)
	_reset_runtime_state()

func test_left_click_toggles_one_ground_tile_only_while_selecting() -> void:
	var game := _start_game()
	var tile := _sample_ground_tile(game)

	game.toggle_draft_tile(tile)
	assert_bool(game.get_draft_mining_tiles().is_empty()).is_true()

	game.enter_mining_mode()
	var click_position := _tile_screen_position(game, tile)
	game._input(_left_mouse_button_event(click_position, true))
	game._input(_left_mouse_button_event(click_position, false))

	assert_bool(game.get_draft_mining_tiles().has(tile)).is_true()

	game._input(_left_mouse_button_event(click_position, true))
	game._input(_left_mouse_button_event(click_position, false))

	assert_bool(game.get_draft_mining_tiles().has(tile)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_left_click_on_air_does_nothing() -> void:
	var game := _start_game()
	var tile := Vector2i(12, 0)

	game.enter_mining_mode()
	game._input(_left_mouse_button_event(_tile_screen_position(game, tile), true))
	game._input(_left_mouse_button_event(_tile_screen_position(game, tile), false))

	assert_bool(game.get_draft_mining_tiles().is_empty()).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_left_drag_toggles_each_crossed_tile_once_per_drag_stroke() -> void:
	var game := _start_game()
	var territory := game.territory_manager as TerritoryManager
	var first_tile := _sample_ground_tile(game, 12)
	var second_tile := _sample_ground_tile(game, 13)
	var first_position := _tile_screen_position(game, first_tile)
	var second_position := _tile_screen_position(game, second_tile)

	game.enter_mining_mode()
	game._input(_left_mouse_button_event(first_position, true))
	game._input(_mouse_motion_event(
		second_position,
		second_position - first_position,
		1 << (MOUSE_BUTTON_LEFT - 1)
	))
	game._input(_mouse_motion_event(
		first_position,
		first_position - second_position,
		1 << (MOUSE_BUTTON_LEFT - 1)
	))
	game._input(_left_mouse_button_event(first_position, false))

	assert_bool(game.get_draft_mining_tiles().has(first_tile)).is_true()
	assert_bool(game.get_draft_mining_tiles().has(second_tile)).is_true()
	assert_int(game.get_draft_mining_tiles().size()).is_equal(2)
	assert_int(territory.tile_map.get_cell_source_id(territory.MINING_DRAFT_LAYER, first_tile)).is_equal(0)
	assert_int(territory.tile_map.get_cell_source_id(territory.MINING_DRAFT_LAYER, second_tile)).is_equal(0)

	_clear_node(game)
	_reset_runtime_state()

func test_drag_after_first_select_only_adds_tiles() -> void:
	var game := _start_game()
	var first_tile := _sample_ground_tile(game, 12)
	var second_tile := _sample_ground_tile(game, 13)
	var first_position := _tile_screen_position(game, first_tile)
	var second_position := _tile_screen_position(game, second_tile)

	game.enter_mining_mode()
	game.toggle_draft_tile(second_tile)

	game._input(_left_mouse_button_event(first_position, true))
	game._input(_mouse_motion_event(
		second_position,
		second_position - first_position,
		1 << (MOUSE_BUTTON_LEFT - 1)
	))
	game._input(_left_mouse_button_event(second_position, false))

	assert_bool(game.get_draft_mining_tiles().has(first_tile)).is_true()
	assert_bool(game.get_draft_mining_tiles().has(second_tile)).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_drag_after_first_deselect_only_removes_tiles() -> void:
	var game := _start_game()
	var first_tile := _sample_ground_tile(game, 12)
	var second_tile := _sample_ground_tile(game, 13)
	var first_position := _tile_screen_position(game, first_tile)
	var second_position := _tile_screen_position(game, second_tile)

	game.enter_mining_mode()
	game.toggle_draft_tile(first_tile)

	game._input(_left_mouse_button_event(first_position, true))
	game._input(_mouse_motion_event(
		second_position,
		second_position - first_position,
		1 << (MOUSE_BUTTON_LEFT - 1)
	))
	game._input(_left_mouse_button_event(second_position, false))

	assert_bool(game.get_draft_mining_tiles().has(first_tile)).is_false()
	assert_bool(game.get_draft_mining_tiles().has(second_tile)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_right_drag_moves_camera_and_left_drag_does_not() -> void:
	var game := _start_game()
	var camera := game.get_node("Camera2D") as Camera2D
	var start_position := camera.global_position

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(320, 240)
	camera._input(right_press)
	camera._input(_mouse_motion_event(Vector2(360, 260), Vector2(40, 20), _right_drag_mask()))
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	right_release.position = Vector2(360, 260)
	camera._input(right_release)

	var after_right_drag := camera.global_position
	assert_vector(after_right_drag).is_not_equal(start_position)

	var left_press := InputEventMouseButton.new()
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	left_press.position = Vector2(320, 240)
	camera._input(left_press)
	camera._input(_mouse_motion_event(Vector2(380, 280), Vector2(20, 20), 1 << (MOUSE_BUTTON_LEFT - 1)))
	var left_release := InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	left_release.position = Vector2(380, 280)
	camera._input(left_release)

	assert_vector(camera.global_position).is_equal(after_right_drag)

	_clear_node(game)
	_reset_runtime_state()

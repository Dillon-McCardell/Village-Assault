## Feature: troop-selection
## Scene-level coverage for world selection, filtering, and command routing.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const TacticalOrder = preload("res://scripts/game.gd").TacticalOrder

var _next_test_port: int = NetworkManager.DEFAULT_PORT + 700

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
	NetworkManager.host(_next_test_port)
	_next_test_port += 1
	GameState.local_team = GameState.Team.LEFT
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _spawn_troop(game: Node, item_id: String, unit_id: int, tile_x: int) -> Node2D:
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	var tile := Vector2i(
		tile_x,
		territory.get_surface_tile_y_at_x(float(tile_x * territory.tile_size)) - 1
	)
	var payload: Dictionary = game.get_troop_spawn_payload(item_id)
	var position := territory.troop_stand_tile_to_world_position(tile, 1)
	game.spawn_unit(position, GameState.Team.LEFT, item_id, unit_id, payload)
	var troop: Node2D = game.get_unit_by_id(unit_id)
	troop.position = territory.troop_stand_tile_to_world_position(
		tile,
		int(troop.get("_troop_occupancy_width_tiles"))
	)
	return troop

func _mouse_button(
	position: Vector2,
	button: int,
	pressed: bool,
	shift_pressed: bool = false
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button as MouseButton
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event

func _click_troop(game: Node, troop: Node2D, shift_pressed: bool = false) -> void:
	var screen_position: Vector2 = game.world_to_screen_position(troop.global_position)
	game._input(_mouse_button(screen_position, MOUSE_BUTTON_LEFT, true, shift_pressed))
	game._input(_mouse_button(screen_position, MOUSE_BUTTON_LEFT, false, shift_pressed))

func test_click_and_shift_click_toggle_selection_cohort() -> void:
	var game := _start_host_game()
	var grunt := _spawn_troop(game, "troop_grunt", 1, 12)
	var ranger := _spawn_troop(game, "troop_ranger", 2, 18)

	_click_troop(game, grunt)
	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([1])

	_click_troop(game, ranger, true)
	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([1, 2])

	_click_troop(game, grunt, true)
	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([2])

	_clear_node(game)
	_reset_runtime_state()

func test_drag_selection_captures_multiple_allied_troops() -> void:
	var game := _start_host_game()
	var grunt := _spawn_troop(game, "troop_grunt", 1, 12)
	var ranger := _spawn_troop(game, "troop_ranger", 2, 18)
	var grunt_screen: Vector2 = game.world_to_screen_position(grunt.global_position)
	var ranger_screen: Vector2 = game.world_to_screen_position(ranger.global_position)
	var start := Vector2(minf(grunt_screen.x, ranger_screen.x) - 24.0, grunt_screen.y - 36.0)
	var finish := Vector2(maxf(grunt_screen.x, ranger_screen.x) + 24.0, ranger_screen.y + 36.0)

	game._input(_mouse_button(start, MOUSE_BUTTON_LEFT, true))
	game._input(_mouse_button(finish, MOUSE_BUTTON_LEFT, false))

	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([1, 2])
	assert_array(game.get_active_troop_selection_ids()).contains_exactly([1, 2])

	_clear_node(game)
	_reset_runtime_state()

func test_type_filter_preserves_cohort_and_commands_only_active_subset() -> void:
	var game := _start_host_game()
	var grunt := _spawn_troop(game, "troop_grunt", 1, 12)
	var ranger := _spawn_troop(game, "troop_ranger", 2, 18)
	game.select_troops_by_ids([1, 2])

	game.filter_troop_selection_to_type("troop_ranger")
	game._on_tactical_order_requested(TacticalOrder.ADVANCE)

	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([1, 2])
	assert_array(game.get_active_troop_selection_ids()).contains_exactly([2])
	assert_int(grunt.current_order).is_equal(TacticalOrder.DEFEND)
	assert_int(ranger.current_order).is_equal(TacticalOrder.ADVANCE)
	assert_bool(game.troop_command_ui.get_toolbar().visible).is_true()
	assert_str(game.troop_command_ui.get_type_button("troop_ranger").text).is_equal("Ran 1")
	assert_str(game.troop_command_ui.get_type_button("troop_grunt").text).is_equal("Gru 0/1")

	_clear_node(game)
	_reset_runtime_state()

func test_restore_all_reactivates_every_troop_in_the_cohort() -> void:
	var game := _start_host_game()
	_spawn_troop(game, "troop_grunt", 1, 12)
	_spawn_troop(game, "troop_miner", 2, 18)
	game.select_troops_by_ids([1, 2])
	game.filter_troop_selection_to_type("troop_miner")

	game.restore_full_troop_selection()

	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([1, 2])
	assert_array(game.get_active_troop_selection_ids()).contains_exactly([1, 2])
	assert_str(game.troop_command_ui.get_all_button().text).is_equal("All 2")

	_clear_node(game)
	_reset_runtime_state()

func test_right_click_move_routes_target_to_active_selection() -> void:
	var game := _start_host_game()
	var grunt := _spawn_troop(game, "troop_grunt", 1, 12)
	var ranger := _spawn_troop(game, "troop_ranger", 2, 18)
	game.select_troops_by_ids([1, 2])
	game.filter_troop_selection_to_type("troop_grunt")
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	var target_tile := Vector2i(
		24,
		territory.get_surface_tile_y_at_x(24.0 * territory.tile_size) - 1
	)
	var target_screen: Vector2 = game.world_to_screen_position(
		territory.troop_stand_tile_to_world_position(target_tile, 1)
	)

	game._input(_mouse_button(target_screen, MOUSE_BUTTON_RIGHT, true))
	game._input(_mouse_button(target_screen, MOUSE_BUTTON_RIGHT, false))

	assert_int(grunt.current_order).is_equal(TacticalOrder.MOVE)
	assert_vector(grunt.command_target_tile).is_equal(target_tile)
	assert_int(ranger.current_order).is_equal(TacticalOrder.DEFEND)

	_clear_node(game)
	_reset_runtime_state()

## Feature: troop-selection
## Scene-level coverage for world selection, filtering, and command routing.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const TacticalOrder = preload("res://scripts/game.gd").TacticalOrder
const TroopStatus = preload("res://scripts/test_unit.gd").TroopStatus

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

func _open_roster(game: Node, item_id: String) -> void:
	var type_button := game.troop_command_ui.get_type_button(item_id) as Button
	type_button.gui_input.emit(_mouse_button(Vector2.ZERO, MOUSE_BUTTON_RIGHT, true))

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

func test_retreat_command_disengages_and_moves_selected_troop_toward_base() -> void:
	var game := _start_host_game()
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	var base_anchor := territory.get_base_anchor_world(GameState.Team.LEFT)
	var base_tile := Vector2i(
		territory.world_to_tile(base_anchor).x,
		territory.get_surface_tile_y_at_x(base_anchor.x) - 1
	)
	assert_bool(territory.is_troop_standable_tile(base_tile, 1, 1)).is_true()
	var start_tile := territory.get_troop_walk_target(base_tile, 1, 1, 1)
	assert_vector(start_tile).is_not_equal(Vector2i(-1, -1))
	var troop := _spawn_troop(game, "troop_grunt", 1, start_tile.x)
	troop.position = territory.troop_stand_tile_to_world_position(start_tile, 1)
	var enemy_position := troop.position + Vector2(8.0, 0.0)
	game.spawn_unit(
		enemy_position,
		GameState.Team.RIGHT,
		"troop_grunt",
		2,
		game.get_troop_spawn_payload("troop_grunt")
	)
	var enemy: Node2D = game.get_unit_by_id(2)
	enemy.position = enemy_position
	game.select_troops_by_ids([1])
	var start_position := troop.position

	game.troop_command_ui.order_requested.emit(TacticalOrder.RETREAT)
	troop._physics_process(0.1)

	assert_int(troop.current_order).is_equal(TacticalOrder.RETREAT)
	assert_int(troop.current_status).is_equal(TroopStatus.RETREATING)
	assert_float(troop.position.x).is_less(start_position.x)

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

func test_type_roster_opens_from_right_click_and_disclosure() -> void:
	var game := _start_host_game()
	_spawn_troop(game, "troop_miner", 1, 12)
	_spawn_troop(game, "troop_miner", 2, 16)
	_spawn_troop(game, "troop_miner", 3, 20)
	game.select_troops_by_ids([1, 2, 3])

	_open_roster(game, "troop_miner")

	assert_bool(game.troop_command_ui.get_roster_panel().visible).is_true()
	assert_int(game.troop_command_ui.get_roster_rows().get_child_count()).is_equal(3)
	assert_str(game.troop_command_ui.get_roster_rows().get_child(0).name).is_equal("RosterRow_1")
	assert_bool(game.troop_command_ui.get_roster_all_checkbox().button_pressed).is_true()

	game.troop_command_ui.close_roster()
	game.troop_command_ui.get_type_disclosure_button("troop_miner").pressed.emit()
	assert_bool(game.troop_command_ui.get_roster_panel().visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_roster_narrows_three_miners_and_commands_only_active_rows() -> void:
	var game := _start_host_game()
	var first := _spawn_troop(game, "troop_miner", 1, 12)
	var second := _spawn_troop(game, "troop_miner", 2, 16)
	var third := _spawn_troop(game, "troop_miner", 3, 20)
	game.select_troops_by_ids([1, 2, 3])
	_open_roster(game, "troop_miner")

	game.troop_command_ui.get_roster_row(2).gui_input.emit(
		_mouse_button(Vector2.ZERO, MOUSE_BUTTON_LEFT, true)
	)
	game._on_tactical_order_requested(TacticalOrder.ADVANCE)

	assert_array(game.get_troop_selection_cohort_ids()).contains_exactly([1, 2, 3])
	assert_array(game.get_active_troop_selection_ids()).contains_exactly([1, 3])
	assert_int(first.current_order).is_equal(TacticalOrder.ADVANCE)
	assert_int(second.current_order).is_equal(TacticalOrder.DEFEND)
	assert_int(third.current_order).is_equal(TacticalOrder.ADVANCE)
	assert_bool(game.troop_command_ui.get_roster_panel().visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_roster_shift_click_toggles_stable_contiguous_range() -> void:
	var game := _start_host_game()
	for unit_id in range(1, 5):
		_spawn_troop(game, "troop_grunt", unit_id, 8 + unit_id * 4)
	game.select_troops_by_ids([1, 2, 3, 4])
	game.set_troop_type_active("troop_grunt", false)
	_open_roster(game, "troop_grunt")

	game.troop_command_ui.get_roster_row(2).gui_input.emit(
		_mouse_button(Vector2.ZERO, MOUSE_BUTTON_LEFT, true)
	)
	game.troop_command_ui.get_roster_row(4).gui_input.emit(
		_mouse_button(Vector2.ZERO, MOUSE_BUTTON_LEFT, true, true)
	)

	assert_array(game.get_active_troop_selection_ids()).contains_exactly([2, 3, 4])
	assert_bool(game.troop_command_ui.get_roster_all_checkbox().button_pressed).is_false()
	assert_bool(game.troop_command_ui.get_roster_panel().visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_roster_refreshes_replicated_health_and_status_without_reordering() -> void:
	var game := _start_host_game()
	var first := _spawn_troop(game, "troop_ranger", 1, 12)
	_spawn_troop(game, "troop_ranger", 2, 18)
	game.select_troops_by_ids([1, 2])
	_open_roster(game, "troop_ranger")

	first.max_health = 10
	first.current_health = 3
	first.current_status = TroopStatus.ENGAGING_ENEMY
	game._refresh_troop_selection_state()
	var first_row := game.troop_command_ui.get_roster_row(1) as Button
	var health := first_row.find_child("HealthBar", true, false) as ProgressBar
	var status := first_row.find_child("StatusIcon", true, false) as Label

	assert_float(health.value).is_equal_approx(30.0, 0.01)
	assert_str(health.tooltip_text).is_equal("Health: 3/10")
	assert_str(status.text).is_equal("X")
	assert_str(status.tooltip_text).is_equal("Engaging enemy")
	assert_str(game.troop_command_ui.get_roster_rows().get_child(0).name).is_equal("RosterRow_1")

	_clear_node(game)
	_reset_runtime_state()

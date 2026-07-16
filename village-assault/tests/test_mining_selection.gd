## Feature: mining-selection
## Scene-level tests for miner picker, per-miner mining UI, and validation flow.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
var _next_test_port: int = NetworkManager.DEFAULT_PORT + 200
const MiningSelectionState = preload("res://scripts/game.gd").MiningSelectionState
const MinerJobType = preload("res://scripts/game.gd").MinerJobType
const TacticalOrder = preload("res://scripts/game.gd").TacticalOrder
const MinerRuntimeState = preload("res://scripts/troops/troop_miner.gd").MinerRuntimeState
const TroopStatus = preload("res://scripts/test_unit.gd").TroopStatus

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
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _mining_menu(game: Node) -> Control:
	return game.get_node("CanvasLayer/UI/MiningMenu") as Control

func _role_button(game: Node) -> Button:
	return game.troop_command_ui.get_role_button() as Button

func _open_role_menu(game: Node, unit_ids: Array = [1]) -> void:
	game.select_troops_by_ids(unit_ids)
	_role_button(game).emit_signal("pressed")

func _role_menu(game: Node) -> PanelContainer:
	return game.troop_command_ui.get_role_menu_panel() as PanelContainer

func _picker_panel(game: Node) -> Panel:
	return (_mining_menu(game) as Control).get_picker_panel() as Panel

func _picker_grid(game: Node) -> GridContainer:
	return (_mining_menu(game) as Control).get_picker_grid() as GridContainer

func _job_panel(game: Node) -> Panel:
	return (_mining_menu(game) as Control).get_job_panel() as Panel

func _job_checkbox(game: Node) -> CheckBox:
	return (_mining_menu(game) as Control).get_job_auto_checkbox() as CheckBox

func _sample_ground_tile(game: Node, tile_x: int = 12, extra_depth: int = 0) -> Vector2i:
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	return Vector2i(tile_x, territory.get_surface_tile_y_at_x(float(tile_x * territory.tile_size)) + extra_depth)

func _sample_gold_tile(game: Node) -> Vector2i:
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	for raw_tile in territory.get_gold_tiles().keys():
		return raw_tile
	return Vector2i(-1, -1)

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

func _spawn_troop(game: Node, item_id: String, unit_id: int, team: int, tile_x: int = 12) -> Node2D:
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	var stand_tile := Vector2i(tile_x, territory.get_surface_tile_y_at_x(float(tile_x * territory.tile_size)) - 1)
	var payload: Dictionary = game.get_troop_spawn_payload(item_id)
	game.spawn_unit(territory.troop_stand_tile_to_world_position(stand_tile, 1), team, item_id, unit_id, payload)
	var troop: Node2D = game.get_unit_by_id(unit_id)
	troop.position = territory.troop_stand_tile_to_world_position(stand_tile, int(troop.get("_troop_occupancy_width_tiles")))
	return troop

func _shop_button(game: Node) -> Button:
	var shop_menu := game.get_node("CanvasLayer/UI/ShopMenu")
	return shop_menu._origin_button as Button

func _press_job_button(game: Node, button_name: String) -> void:
	(_job_panel(game).find_child(button_name, true, false) as Button).emit_signal("pressed")

func test_role_actions_button_opens_capability_driven_miner_actions() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_open_role_menu(game)

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(_role_menu(game).visible).is_true()
	assert_bool(game.troop_command_ui.get_role_action_button("miner_dig") != null).is_true()
	assert_bool(game.troop_command_ui.get_role_action_button("miner_harvest") != null).is_true()
	assert_bool(_picker_panel(game).visible).is_false()
	assert_bool((_mining_menu(game).get_origin_button() as Button).visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_pressing_role_actions_again_closes_grouped_menu() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_open_role_menu(game)
	assert_bool(_role_menu(game).visible).is_true()

	_role_button(game).emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(_role_menu(game).visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_pressing_other_button_closes_role_actions_menu() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_open_role_menu(game)
	assert_bool(_role_menu(game).visible).is_true()

	var shop_button := _shop_button(game)
	shop_button.emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.INACTIVE)
	assert_bool(_role_menu(game).visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_grouped_dig_action_targets_all_active_eligible_miners() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	_spawn_miner(game, 2, Color(0.2, 0.9, 0.4, 1.0))
	_spawn_troop(game, "troop_grunt", 3, GameState.Team.LEFT, 18)

	_open_role_menu(game, [1, 2, 3])
	game.troop_command_ui.get_role_action_button("miner_dig").pressed.emit()

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING_DIG)
	assert_array(game.get_selected_miner_unit_ids()).contains_exactly([1, 2])
	assert_bool(_role_menu(game).visible).is_false()
	assert_bool((_mining_menu(game).get_origin_button() as Button).visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_host_partitions_one_dig_plan_across_selected_miners_deterministically() -> void:
	var game := _start_host_game()
	var first := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var second := _spawn_miner(game, 2, Color(0.2, 0.9, 0.4, 1.0))
	var third := _spawn_miner(game, 3, Color(0.9, 0.7, 0.2, 1.0))
	second.position = first.position
	third.position = first.position
	first.issue_tactical_order(TacticalOrder.ADVANCE)
	second.issue_tactical_order(TacticalOrder.ADVANCE)
	third.issue_tactical_order(TacticalOrder.ADVANCE)
	var tiles: Array[Vector2i] = [
		_sample_ground_tile(game, 12),
		_sample_ground_tile(game, 13),
		_sample_ground_tile(game, 14),
	]

	var assignments: Dictionary = game._apply_miner_group_job_request(
		[3, 1, 2],
		MinerJobType.DIG,
		tiles,
		false,
		GameState.Team.LEFT
	)

	assert_array(assignments[1]).contains_exactly([tiles[0]])
	assert_array(assignments[2]).contains_exactly([tiles[1]])
	assert_array(assignments[3]).contains_exactly([tiles[2]])
	assert_array(first.get_miner_job().get("dig_tiles", [])).contains_exactly([tiles[0]])
	assert_array(second.get_miner_job().get("dig_tiles", [])).contains_exactly([tiles[1]])
	assert_array(third.get_miner_job().get("dig_tiles", [])).contains_exactly([tiles[2]])
	assert_int(first.current_order).is_equal(TacticalOrder.DEFEND)
	assert_int(second.current_order).is_equal(TacticalOrder.DEFEND)
	assert_int(third.current_order).is_equal(TacticalOrder.DEFEND)

	_clear_node(game)
	_reset_runtime_state()

func test_group_miner_job_rejects_troops_owned_by_another_team() -> void:
	var game := _start_host_game()
	var enemy := _spawn_troop(game, "troop_miner", 9, GameState.Team.RIGHT, 32)
	var tile := _sample_ground_tile(game, 18)
	var tiles: Array[Vector2i] = [tile]

	var assignments: Dictionary = game._apply_miner_group_job_request(
		[9],
		MinerJobType.DIG,
		tiles,
		false,
		GameState.Team.LEFT
	)

	assert_dict(assignments).is_empty()
	assert_int(int(enemy.get_miner_job().get("job_type", MinerJobType.IDLE))).is_equal(
		MinerJobType.IDLE
	)

	_clear_node(game)
	_reset_runtime_state()

func test_selecting_miner_enters_tile_selection_for_that_miner() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	game.open_miner_picker()
	(_picker_grid(game).get_child(0) as Button).emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.JOB_PROMPT)
	assert_int(game.get_selected_miner_unit_id()).is_equal(1)
	assert_bool(_job_panel(game).visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_clicking_picker_slot_selects_miner() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	game.open_miner_picker()
	var slot := _picker_grid(game).get_child(0) as Button
	slot.emit_signal("pressed")

	assert_int(game.get_selected_miner_unit_id()).is_equal(1)
	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.JOB_PROMPT)

	_clear_node(game)
	_reset_runtime_state()

func test_job_prompt_allows_dig_and_harvest_paths() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	game.open_miner_picker()
	(_picker_grid(game).get_child(0) as Button).emit_signal("pressed")
	assert_bool(_job_panel(game).visible).is_true()
	assert_bool(_job_checkbox(game).button_pressed).is_false()

	_job_checkbox(game).button_pressed = true
	_press_job_button(game, "DigButton")
	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING_DIG)

	game.cancel_mining_selection()
	game.open_miner_picker()
	(_picker_grid(game).get_child(0) as Button).emit_signal("pressed")
	_press_job_button(game, "HarvestButton")
	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.SELECTING_HARVEST)

	_clear_node(game)
	_reset_runtime_state()

func test_picker_uses_live_miner_color_from_unit() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	miner.miner_top_color = Color(0.95, 0.45, 0.75, 1.0)

	game.open_miner_picker()

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
	_press_job_button(game, "DigButton")
	game.toggle_draft_tile(tile_a)
	game.confirm_mining_selection()
	game.select_miner_for_mining(2)
	_press_job_button(game, "DigButton")
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
	_press_job_button(game, "DigButton")
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
	_press_job_button(game, "DigButton")
	game.toggle_draft_tile(tile)
	game.confirm_mining_selection()

	for _i in range(200):
		miner._physics_process(0.05)
		if int(miner.get_miner_job().get("job_type", MinerJobType.IDLE)) == MinerJobType.IDLE:
			break

	assert_bool(game.territory_manager.has_ground_at_tile(tile)).is_false()
	assert_bool(game.territory_manager.is_underground_tile(tile)).is_true()
	assert_int(int(miner.get_miner_job().get("job_type", MinerJobType.IDLE))).is_equal(
		MinerJobType.IDLE
	)
	assert_int(miner.current_order).is_equal(TacticalOrder.DEFEND)
	assert_int(miner.current_status).is_equal(TroopStatus.DEFENDING)
	assert_vector(miner.defense_anchor_tile).is_equal(
		game.territory_manager.get_standable_tile_for_world_position(miner.position)
	)

	_clear_node(game)
	_reset_runtime_state()

func test_move_command_reaches_destination_then_defends() -> void:
	var game := _start_host_game()
	GameState.local_team = GameState.Team.LEFT
	var troop := _spawn_troop(game, "troop_grunt", 1, GameState.Team.LEFT, 12)
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	var start_tile := territory.get_troop_standable_tile_for_world_position(troop.position, 1, 1)
	var target_tile := territory.get_troop_walk_target(start_tile, 1, 1, 1)
	if target_tile == Vector2i(-1, -1):
		target_tile = territory.get_troop_walk_target(start_tile, -1, 1, 1)
	assert_vector(target_tile).is_not_equal(Vector2i(-1, -1))
	var target_world := territory.troop_stand_tile_to_world_position(target_tile, 1)

	var accepted: bool = game.issue_troop_order_for_units([1], TacticalOrder.MOVE, target_world)

	assert_bool(accepted).is_true()
	assert_int(troop.current_order).is_equal(TacticalOrder.MOVE)
	for _i in range(80):
		troop._physics_process(0.1)
		if troop.current_order == TacticalOrder.DEFEND:
			break

	assert_int(troop.current_order).is_equal(TacticalOrder.DEFEND)
	assert_vector(troop.defense_anchor_tile).is_equal(target_tile)
	assert_vector(troop.position).is_equal_approx(target_world, Vector2(0.01, 0.01))

	_clear_node(game)
	_reset_runtime_state()

func test_move_command_rejects_enemy_owned_troops() -> void:
	var game := _start_host_game()
	GameState.local_team = GameState.Team.LEFT
	var enemy := _spawn_troop(game, "troop_grunt", 2, GameState.Team.RIGHT, 42)
	var target_world := enemy.position + Vector2(-32, 0)

	var accepted: bool = game.issue_troop_order_for_units([2], TacticalOrder.MOVE, target_world)

	assert_bool(accepted).is_false()
	assert_int(enemy.current_order).is_equal(TacticalOrder.DEFEND)

	_clear_node(game)
	_reset_runtime_state()

func test_tactical_order_cancels_active_miner_job() -> void:
	var game := _start_host_game()
	GameState.local_team = GameState.Team.LEFT
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game, 12)

	game.select_miner_for_mining(1)
	_press_job_button(game, "DigButton")
	game.toggle_draft_tile(tile)
	game.confirm_mining_selection()
	assert_int(int(miner.get_miner_job().get("job_type", MinerJobType.IDLE))).is_equal(MinerJobType.DIG)

	var accepted: bool = game.issue_troop_order_for_units([1], TacticalOrder.DEFEND)

	assert_bool(accepted).is_true()
	assert_int(int(miner.get_miner_job().get("job_type", MinerJobType.IDLE))).is_equal(MinerJobType.IDLE)
	assert_int(miner.current_order).is_equal(TacticalOrder.DEFEND)

	_clear_node(game)
	_reset_runtime_state()

func test_underground_move_requires_explored_air() -> void:
	var game := _start_host_game()
	GameState.local_team = GameState.Team.LEFT
	var troop := _spawn_troop(game, "troop_grunt", 1, GameState.Team.LEFT, 12)
	var territory := game.get_node("TerritoryManager") as TerritoryManager
	var solid_tile := _sample_ground_tile(game, 12)
	var air_tile := solid_tile + Vector2i.UP
	territory.destroy_tile(solid_tile)
	assert_bool(territory.is_underground_tile(solid_tile)).is_true()

	var hidden_accepted: bool = game.issue_troop_order_for_units(
		[1],
		TacticalOrder.MOVE,
		territory.troop_stand_tile_to_world_position(solid_tile, 1)
	)
	territory.reveal_fog_tiles_for_team(GameState.Team.LEFT, [solid_tile, air_tile])
	var explored_accepted: bool = game.issue_troop_order_for_units(
		[1],
		TacticalOrder.MOVE,
		territory.troop_stand_tile_to_world_position(solid_tile, 1)
	)

	assert_bool(hidden_accepted).is_false()
	assert_bool(explored_accepted).is_true()
	assert_int(troop.current_order).is_equal(TacticalOrder.MOVE)

	_clear_node(game)
	_reset_runtime_state()

func test_miner_digging_only_explores_fog_from_the_troop_vision_scan() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game, 12, 1)
	var stand_tile := tile + Vector2i.UP
	game.territory_manager.destroy_tile(stand_tile)
	miner.position = game.territory_manager.stand_tile_to_world_position(stand_tile)
	var dig_order: Array[Vector2i] = [tile]
	miner.set_miner_job(game._build_dig_job(1, dig_order, false))

	for _i in range(12):
		miner._physics_process(0.5)

	assert_bool(game.territory_manager.is_fog_revealed_to_team(tile, GameState.Team.LEFT)).is_false()
	miner.position = game.territory_manager.tile_to_world_center(tile) \
		+ Vector2(0.0, float(miner.unit_height) * 0.5)
	game._fog_reveal_scan_remaining = 0.0
	game._process_troop_fog_reveal(0.2)

	assert_bool(game.territory_manager.is_fog_revealed_to_team(tile, GameState.Team.LEFT)).is_true()
	assert_bool(game.territory_manager.is_fog_revealed_to_team(tile, GameState.Team.RIGHT)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_troop_reveals_radius_three_underground_fog() -> void:
	var game := _start_host_game()
	var center := _sample_ground_tile(game, 12, 3)
	for x_offset in range(5):
		game.territory_manager.destroy_tile(center + Vector2i(x_offset, 0))
	game.spawn_test_unit(game.territory_manager.tile_to_world_center(center), GameState.Team.LEFT, 42, game.get_troop_spawn_payload("troop_grunt"))
	var troop: Node2D = game.get_unit_by_id(42)
	troop.position = game.territory_manager.tile_to_world_center(center)

	game._physics_process(0.2)

	assert_bool(game.territory_manager.is_fog_revealed_to_team(center, GameState.Team.LEFT)).is_true()
	assert_bool(game.territory_manager.is_fog_revealed_to_team(center + Vector2i(3, 0), GameState.Team.LEFT)).is_true()
	assert_bool(game.territory_manager.is_fog_revealed_to_team(center + Vector2i(4, 0), GameState.Team.LEFT)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_troop_fog_reveal_does_not_pass_through_ground() -> void:
	var game := _start_host_game()
	var center := _sample_ground_tile(game, 12, 3)
	var ground_tile := center + Vector2i(1, 0)
	var disconnected_air := center + Vector2i(2, 0)
	game.territory_manager.destroy_tile(center)
	game.territory_manager.destroy_tile(disconnected_air)
	game.spawn_test_unit(game.territory_manager.tile_to_world_center(center), GameState.Team.LEFT, 42, game.get_troop_spawn_payload("troop_grunt"))
	var troop: Node2D = game.get_unit_by_id(42)
	troop.position = game.territory_manager.tile_to_world_center(center)

	game._physics_process(0.2)

	assert_bool(game.territory_manager.is_fog_revealed_to_team(center, GameState.Team.LEFT)).is_true()
	assert_bool(game.territory_manager.has_ground_at_tile(ground_tile)).is_true()
	assert_bool(game.territory_manager.is_fog_revealed_to_team(ground_tile, GameState.Team.LEFT)).is_true()
	assert_bool(game.territory_manager.is_fog_revealed_to_team(disconnected_air, GameState.Team.LEFT)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_enemy_troop_requires_current_vision_even_in_explored_tunnel() -> void:
	var game := _start_host_game()
	var enemy_tile := _sample_ground_tile(game, 12, 3)
	game.territory_manager.destroy_tile(enemy_tile)
	game.spawn_test_unit(
		game.territory_manager.tile_to_world_center(enemy_tile),
		GameState.Team.RIGHT,
		43,
		game.get_troop_spawn_payload("troop_grunt")
	)
	var enemy: Node2D = game.get_unit_by_id(43)
	enemy.position = game.territory_manager.tile_to_world_center(enemy_tile)
	game._on_local_state_updated(GameState.Team.LEFT, 100)

	game._refresh_troop_fog_visibility(0.2)
	assert_bool(enemy.visible).is_false()

	game.territory_manager.reveal_fog_circle_for_team(GameState.Team.LEFT, enemy_tile)
	game._refresh_troop_fog_visibility(0.2)
	assert_bool(enemy.visible).is_false()

	game.spawn_test_unit(
		game.territory_manager.tile_to_world_center(enemy_tile),
		GameState.Team.LEFT,
		44,
		game.get_troop_spawn_payload("troop_grunt")
	)
	var ally: Node2D = game.get_unit_by_id(44)
	ally.position = game.territory_manager.tile_to_world_center(enemy_tile)
	game._fog_vision_refresh_remaining = 0.0
	game._refresh_local_fog_vision(0.05)
	game._refresh_troop_fog_visibility(0.2)
	assert_bool(enemy.visible).is_true()
	assert_float(enemy.modulate.a).is_equal_approx(1.0, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_local_team_change_switches_fog_overlay_team() -> void:
	var game := _start_host_game()

	game._on_local_state_updated(GameState.Team.LEFT, 100)
	assert_int(game.territory_manager._fog_local_team).is_equal(GameState.Team.LEFT)

	game._on_local_state_updated(GameState.Team.RIGHT, 100)
	assert_int(game.territory_manager._fog_local_team).is_equal(GameState.Team.RIGHT)

	_clear_node(game)
	_reset_runtime_state()

func test_game_snapshot_includes_revealed_fog_snapshot() -> void:
	var game := _start_host_game()
	var tile := _sample_ground_tile(game, 12, 2)
	game.territory_manager.reveal_fog_tiles_for_team(GameState.Team.LEFT, [tile])

	var snapshot: Dictionary = game.get_test_snapshot()
	var revealed_fog_snapshot: Dictionary = snapshot.get("revealed_fog_snapshot", {})
	var left_snapshot: Dictionary = revealed_fog_snapshot.get(GameState.Team.LEFT, {})
	var left_data := left_snapshot.get("data", PackedByteArray()) as PackedByteArray

	assert_bool(revealed_fog_snapshot.has(GameState.Team.LEFT)).is_true()
	assert_int(left_snapshot.get("width", 0)).is_greater(0)
	assert_int(left_data.size()).is_greater(0)

	_clear_node(game)
	_reset_runtime_state()

func test_miner_falls_after_destroying_supporting_block() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var support_tile := _sample_ground_tile(game, 12)
	var stand_tile := support_tile + Vector2i.UP
	miner.position = game.territory_manager.stand_tile_to_world_position(stand_tile)
	game.territory_manager._tile_health[support_tile] = 1
	var dig_order: Array[Vector2i] = [support_tile]
	miner.set_miner_job(game._build_dig_job(1, dig_order, false))

	var start_y := miner.position.y
	miner._physics_process(0.5)
	miner._physics_process(0.5)
	miner._physics_process(0.1)

	assert_bool(game.territory_manager.has_ground_at_tile(support_tile)).is_false()
	assert_float(miner.position.y).is_greater(start_y)
	assert_float(miner.position.y).is_equal_approx(
		game.territory_manager.stand_tile_to_world_position(support_tile).y,
		0.001
	)

	_clear_node(game)
	_reset_runtime_state()

func test_left_click_toggles_ground_tile_only_while_selecting() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game)

	game.select_miner_for_mining(1)
	_press_job_button(game, "DigButton")
	var click_position := _tile_screen_position(game, tile)
	game._input(_left_mouse_button_event(click_position, true))
	game._input(_left_mouse_button_event(click_position, false))

	assert_bool(game.get_draft_mining_tiles().has(tile)).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_harvest_selection_shows_numbered_overlay_and_hides_on_confirm_or_cancel() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var ore_a := _sample_gold_tile(game)
	var ore_b := ore_a
	for raw_tile in game.territory_manager.get_gold_tiles().keys():
		if raw_tile != ore_a:
			ore_b = raw_tile
			break
	game.territory_manager.reveal_ore_tiles_for_team(GameState.Team.LEFT, [ore_a, ore_b])

	game.select_miner_for_mining(1)
	_press_job_button(game, "HarvestButton")
	game.toggle_draft_ore_tile(ore_a)
	game.toggle_draft_ore_tile(ore_b)

	assert_array(game.get_draft_harvest_tiles()).is_equal([ore_a, ore_b])
	assert_bool(game.territory_manager._harvest_queue_overlay_visible).is_true()
	assert_array(game.territory_manager._harvest_queue_overlay_tiles).is_equal([ore_a, ore_b])

	game.confirm_mining_selection()
	assert_bool(game.territory_manager._harvest_queue_overlay_visible).is_false()

	game.select_miner_for_mining(1)
	_press_job_button(game, "HarvestButton")
	assert_bool(game.territory_manager._harvest_queue_overlay_visible).is_true()
	assert_array(game.territory_manager._harvest_queue_overlay_tiles).is_equal([ore_a, ore_b])

	game.cancel_mining_selection()
	assert_bool(game.territory_manager._harvest_queue_overlay_visible).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_hidden_ore_cannot_be_selected_for_harvest() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var ore_tile := _sample_gold_tile(game)

	game.select_miner_for_mining(1)
	_press_job_button(game, "HarvestButton")
	assert_bool(game.toggle_draft_ore_tile(ore_tile)).is_false()
	assert_array(game.get_draft_harvest_tiles()).is_empty()

	_clear_node(game)
	_reset_runtime_state()

func test_harvest_confirm_commits_ordered_ore_queue() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var ore_a := _sample_gold_tile(game)
	var ore_b := ore_a
	for raw_tile in game.territory_manager.get_gold_tiles().keys():
		if raw_tile != ore_a:
			ore_b = raw_tile
			break
	game.territory_manager.reveal_ore_tiles_for_team(GameState.Team.LEFT, [ore_a, ore_b])

	game.select_miner_for_mining(1)
	_press_job_button(game, "HarvestButton")
	game.toggle_draft_ore_tile(ore_a)
	game.toggle_draft_ore_tile(ore_b)
	game.confirm_mining_selection()

	var job: Dictionary = miner.get_miner_job()
	assert_int(int(job.get("job_type", MinerJobType.IDLE))).is_equal(MinerJobType.HARVEST)
	assert_array(job.get("assigned_ore_tiles", [])).is_equal([ore_a, ore_b])

	_clear_node(game)
	_reset_runtime_state()

func test_role_actions_menu_is_available_again_after_confirm() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game, 12)

	game.select_miner_for_mining(1)
	_press_job_button(game, "DigButton")
	game.toggle_draft_tile(tile)
	game.confirm_mining_selection()

	_open_role_menu(game)

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.CONFIRMED)
	assert_bool(_role_menu(game).visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_full_harvest_miner_does_not_deposit_without_reaching_base() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var ore_tile := _sample_gold_tile(game)
	game.territory_manager.reveal_ore_tiles_for_team(GameState.Team.LEFT, [ore_tile])

	var stand_tile := ore_tile + Vector2i.LEFT
	game.territory_manager.tile_map.erase_cell(game.territory_manager.TERRAIN_LAYER, stand_tile)
	game.territory_manager.tile_map.set_cell(
		game.territory_manager.UNDERGROUND_LAYER,
		stand_tile,
		0,
		game.territory_manager.TILE_UNDERGROUND
	)
	var support_tile := stand_tile + Vector2i.DOWN
	if not game.territory_manager.has_ground_at_tile(support_tile):
		game.territory_manager.tile_map.set_cell(
			game.territory_manager.TERRAIN_LAYER,
			support_tile,
			0,
			game.territory_manager.TILE_DIRT
		)
		game.territory_manager._tile_health[support_tile] = game.territory_manager.TILE_HEALTH_DEFAULT
	miner.position = game.territory_manager.stand_tile_to_world_position(stand_tile)
	var ore_order: Array[Vector2i] = [ore_tile]
	miner.set_miner_job(game._build_harvest_job(1, ore_order))
	miner._runtime_snapshot["cargo_full"] = true
	miner._runtime_snapshot["ore_hits_since_last_deposit"] = 2

	var start_money := GameState.get_money_for_peer(1)
	miner._physics_process(0.5)

	assert_int(GameState.get_money_for_peer(1)).is_equal(start_money)

	_clear_node(game)
	_reset_runtime_state()

func test_single_ore_depletion_keeps_full_miner_returning_until_deposit() -> void:
	var game := _start_host_game()
	var miner := _spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var ore_tile := Vector2i(-1, -1)
	for raw_tile in game.territory_manager.get_gold_tiles().keys():
		var candidate: Vector2i = raw_tile
		var stand_candidate := candidate + Vector2i.LEFT
		var support_tile := stand_candidate + Vector2i.DOWN
		if not game.territory_manager.is_tile_in_bounds(stand_candidate):
			continue
		if not game.territory_manager.has_ground_at_tile(support_tile):
			continue
		if ore_tile == Vector2i(-1, -1) or candidate.x > ore_tile.x:
			ore_tile = candidate
	assert_vector(ore_tile).is_not_equal(Vector2i(-1, -1))
	game.territory_manager.reveal_ore_tiles_for_team(GameState.Team.LEFT, [ore_tile])
	var stand_tile := ore_tile + Vector2i.LEFT
	game.territory_manager.tile_map.erase_cell(game.territory_manager.TERRAIN_LAYER, stand_tile)
	game.territory_manager.tile_map.set_cell(
		game.territory_manager.UNDERGROUND_LAYER,
		stand_tile,
		0,
		game.territory_manager.TILE_UNDERGROUND
	)
	miner.position = game.territory_manager.stand_tile_to_world_position(stand_tile)
	var ore_order: Array[Vector2i] = [ore_tile]
	miner.set_miner_job(game._build_harvest_job(1, ore_order))
	miner._runtime_snapshot["ore_hits_since_last_deposit"] = 1
	game.territory_manager._ore_health[ore_tile] = 1

	for _i in range(10):
		miner._physics_process(0.1)
		if not game.territory_manager.is_ore_tile(ore_tile):
			break
	assert_bool(game.territory_manager.is_ore_tile(ore_tile)).is_false()
	miner._physics_process(0.1)

	assert_bool(game.territory_manager.is_underground_tile(ore_tile)).is_true()
	assert_bool(bool(miner.get_runtime_snapshot().get("cargo_full", false))).is_true()
	assert_int(int(miner.get_runtime_snapshot().get("runtime_state", -1))).is_equal(MinerRuntimeState.RETURNING_TO_BASE)
	assert_int(int(miner.get_miner_job().get("job_type", MinerJobType.IDLE))).is_equal(MinerJobType.HARVEST)
	assert_array(miner.get_miner_job().get("assigned_ore_tiles", [])).is_empty()

	var territory := game.territory_manager as TerritoryManager
	var base_tile := territory.get_standable_tile_for_world_position(
		territory.get_base_anchor_world(GameState.Team.LEFT)
	)
	var money_before_deposit := GameState.get_money_for_peer(1)
	miner.position = territory.stand_tile_to_world_position(base_tile)
	miner._physics_process(0.1)

	assert_int(GameState.get_money_for_peer(1)).is_equal(money_before_deposit + 20)
	assert_int(int(miner.get_miner_job().get("job_type", MinerJobType.IDLE))).is_equal(
		MinerJobType.IDLE
	)
	assert_int(miner.current_order).is_equal(TacticalOrder.DEFEND)
	assert_int(miner.current_status).is_equal(TroopStatus.DEFENDING)
	assert_vector(miner.defense_anchor_tile).is_equal(base_tile)

	_clear_node(game)
	_reset_runtime_state()

## Feature: mining-selection
## Scene-level tests for miner picker, per-miner mining UI, and validation flow.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
var _next_test_port: int = NetworkManager.DEFAULT_PORT + 200
const MiningSelectionState = preload("res://scripts/game.gd").MiningSelectionState
const MinerJobType = preload("res://scripts/game.gd").MinerJobType
const MinerRuntimeState = preload("res://scripts/troops/troop_miner.gd").MinerRuntimeState

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

func _mine_button(game: Node) -> Button:
	return game.get_node("CanvasLayer/UI/MiningMenu/MineButton") as Button

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

func _shop_button(game: Node) -> Button:
	var shop_menu := game.get_node("CanvasLayer/UI/ShopMenu")
	return shop_menu._origin_button as Button

func _press_job_button(game: Node, button_name: String) -> void:
	(_job_panel(game).find_child(button_name, true, false) as Button).emit_signal("pressed")

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

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.JOB_PROMPT)
	assert_int(game.get_selected_miner_unit_id()).is_equal(1)
	assert_bool(_job_panel(game).visible).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_clicking_picker_slot_selects_miner() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))

	_mine_button(game).emit_signal("pressed")
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

	for _i in range(12):
		miner._physics_process(0.5)

	assert_bool(game.territory_manager.has_ground_at_tile(tile)).is_false()
	assert_bool(game.territory_manager.is_underground_tile(tile)).is_true()

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

func test_mine_button_is_clickable_again_after_confirm() -> void:
	var game := _start_host_game()
	_spawn_miner(game, 1, Color(0.2, 0.7, 0.9, 1.0))
	var tile := _sample_ground_tile(game, 12)

	game.select_miner_for_mining(1)
	_press_job_button(game, "DigButton")
	game.toggle_draft_tile(tile)
	game.confirm_mining_selection()

	_mine_button(game).emit_signal("pressed")

	assert_int(game.get_mining_selection_state()).is_equal(MiningSelectionState.PICKING_MINER)
	assert_bool(_picker_panel(game).visible).is_true()

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

	_clear_node(game)
	_reset_runtime_state()

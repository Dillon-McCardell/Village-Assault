## Feature: territory-manager
## Direct tests for terrain generation, spawn bounds, and anchors.
extends GdUnitTestSuite

func _reset_runtime_state() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")

func _create_manager() -> TerritoryManager:
	var manager := TerritoryManager.new()
	manager.name = "TerritoryManager"
	var tile_map := TileMap.new()
	tile_map.name = "WorldTileMap"
	manager.add_child(tile_map)
	return manager

func _mount_manager(manager: TerritoryManager) -> void:
	get_tree().root.add_child(manager)
	get_tree().current_scene = manager

func _clear_manager(manager: TerritoryManager) -> void:
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
	get_tree().current_scene = null

func test_spawn_positions_always_land_inside_team_territory() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(64, 20, 12345)
	var manager := _create_manager()
	_mount_manager(manager)

	for _i in range(20):
		var left_spawn := manager.get_next_spawn_position_for_team(GameState.Team.LEFT)
		var right_spawn := manager.get_next_spawn_position_for_team(GameState.Team.RIGHT)
		assert_bool(manager.is_world_pos_in_team_territory(left_spawn, GameState.Team.LEFT)).is_true()
		assert_bool(manager.is_world_pos_in_team_territory(right_spawn, GameState.Team.RIGHT)).is_true()
		assert_bool(manager.is_world_pos_in_team_territory(left_spawn, GameState.Team.RIGHT)).is_false()
		assert_bool(manager.is_world_pos_in_team_territory(right_spawn, GameState.Team.LEFT)).is_false()

	_clear_manager(manager)
	_reset_runtime_state()

func test_spawn_positions_cycle_within_team_bounds() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(40, 20, 222)
	var manager := _create_manager()
	_mount_manager(manager)
	var left_bounds := manager._get_team_bounds(GameState.Team.LEFT)
	var right_bounds := manager._get_team_bounds(GameState.Team.RIGHT)
	var left_tiles: Array[int] = []
	var right_tiles: Array[int] = []

	for _i in range(left_bounds.size.x * 2):
		left_tiles.append(manager.world_to_tile(
			manager.get_next_spawn_position_for_team(GameState.Team.LEFT)
		).x)
	for _i in range(right_bounds.size.x * 2):
		right_tiles.append(manager.world_to_tile(
			manager.get_next_spawn_position_for_team(GameState.Team.RIGHT)
		).x)

	for tile_x in left_tiles:
		assert_bool(left_bounds.has_point(Vector2i(tile_x, 0))).is_true()
	for tile_x in right_tiles:
		assert_bool(right_bounds.has_point(Vector2i(tile_x, 0))).is_true()
	for i in range(left_bounds.size.x):
		assert_int(left_tiles[i]).is_equal(left_tiles[i + left_bounds.size.x])
	for i in range(right_bounds.size.x):
		assert_int(right_tiles[i]).is_equal(right_tiles[i + right_bounds.size.x])

	_clear_manager(manager)
	_reset_runtime_state()

func test_territory_checks_reject_out_of_bounds_and_cross_team_points() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(48, 20, 333)
	var manager := _create_manager()
	_mount_manager(manager)
	var left_spawn := manager.get_next_spawn_position_for_team(GameState.Team.LEFT)
	var right_spawn := manager.get_next_spawn_position_for_team(GameState.Team.RIGHT)

	assert_bool(manager.is_world_pos_in_team_territory(Vector2(-8, 0), GameState.Team.LEFT)).is_false()
	assert_bool(manager.is_world_pos_in_team_territory(Vector2(99999, 99999), GameState.Team.RIGHT)).is_false()
	assert_bool(manager.is_world_pos_in_team_territory(left_spawn, GameState.Team.RIGHT)).is_false()
	assert_bool(manager.is_world_pos_in_team_territory(right_spawn, GameState.Team.LEFT)).is_false()

	_clear_manager(manager)
	_reset_runtime_state()

func test_fixed_map_seed_produces_deterministic_heightmap() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(64, 20, 4444)
	var manager_a := _create_manager()
	_mount_manager(manager_a)
	var heights_a = manager_a._heightmap.duplicate()
	_clear_manager(manager_a)

	var manager_b := _create_manager()
	_mount_manager(manager_b)
	var heights_b = manager_b._heightmap.duplicate()

	assert_array(heights_b).is_equal(heights_a)

	_clear_manager(manager_b)
	_reset_runtime_state()

func test_flat_base_pads_are_preserved_after_terrain_generation() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(64, 20, 5555)
	var manager := _create_manager()
	_mount_manager(manager)
	var flat_width := manager._get_flat_width()
	var base_height := int(clamp(
		manager.base_surface_height,
		manager.min_surface_height,
		manager.max_surface_height
	))

	for i in range(flat_width):
		assert_int(manager._heightmap[i]).is_equal(base_height)
		assert_int(manager._heightmap[manager.grid_width - 1 - i]).is_equal(base_height)

	_clear_manager(manager)
	_reset_runtime_state()

func test_base_anchors_stay_in_their_territories_after_world_size_changes() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(64, 20, 6666)
	var manager := _create_manager()
	_mount_manager(manager)

	GameState.set_world_settings(96, 30, 7777)
	await get_tree().process_frame

	var left_anchor := manager.get_base_anchor_world(GameState.Team.LEFT)
	var right_anchor := manager.get_base_anchor_world(GameState.Team.RIGHT)
	assert_bool(manager.is_world_pos_in_team_territory(left_anchor, GameState.Team.LEFT)).is_true()
	assert_bool(manager.is_world_pos_in_team_territory(right_anchor, GameState.Team.RIGHT)).is_true()

	_clear_manager(manager)
	_reset_runtime_state()

func test_world_pixel_rect_matches_world_settings_and_tile_size() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(72, 24, 8888)
	var manager := _create_manager()
	manager.tile_size = 20
	_mount_manager(manager)
	var world_rect := manager.get_world_pixel_rect()

	assert_float(world_rect.size.x).is_equal(72.0 * 20.0)
	assert_float(world_rect.size.y).is_equal(24.0 * 20.0)

	_clear_manager(manager)
	_reset_runtime_state()

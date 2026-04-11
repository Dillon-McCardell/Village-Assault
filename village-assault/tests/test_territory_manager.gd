## Feature: territory-manager
## Direct tests for terrain generation, spawn bounds, and anchors.
extends GdUnitTestSuite

const TERRAIN_TEST_HARNESS: GDScript = preload("res://scripts/testing/terrain_test_harness.gd")

var _terrain_harness: RefCounted = TERRAIN_TEST_HARNESS.new()

func test_spawn_positions_always_land_inside_team_territory() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 12345)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)

	for _i in range(20):
		var left_spawn: Vector2 = manager.get_next_spawn_position_for_team(GameState.Team.LEFT)
		var right_spawn: Vector2 = manager.get_next_spawn_position_for_team(GameState.Team.RIGHT)
		assert_bool(manager.is_world_pos_in_team_territory(left_spawn, GameState.Team.LEFT)).is_true()
		assert_bool(manager.is_world_pos_in_team_territory(right_spawn, GameState.Team.RIGHT)).is_true()
		assert_bool(manager.is_world_pos_in_team_territory(left_spawn, GameState.Team.RIGHT)).is_false()
		assert_bool(manager.is_world_pos_in_team_territory(right_spawn, GameState.Team.LEFT)).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_spawn_positions_cycle_within_team_bounds() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(40, 20, 222)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var left_bounds: Rect2i = manager._get_team_bounds(GameState.Team.LEFT)
	var right_bounds: Rect2i = manager._get_team_bounds(GameState.Team.RIGHT)
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

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_territory_checks_reject_out_of_bounds_and_cross_team_points() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(48, 20, 333)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var left_spawn: Vector2 = manager.get_next_spawn_position_for_team(GameState.Team.LEFT)
	var right_spawn: Vector2 = manager.get_next_spawn_position_for_team(GameState.Team.RIGHT)

	assert_bool(manager.is_world_pos_in_team_territory(Vector2(-8, 0), GameState.Team.LEFT)).is_false()
	assert_bool(manager.is_world_pos_in_team_territory(Vector2(99999, 99999), GameState.Team.RIGHT)).is_false()
	assert_bool(manager.is_world_pos_in_team_territory(left_spawn, GameState.Team.RIGHT)).is_false()
	assert_bool(manager.is_world_pos_in_team_territory(right_spawn, GameState.Team.LEFT)).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_fixed_map_seed_produces_deterministic_heightmap() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 4444)
	var manager_a: TerritoryManager = _terrain_harness.create_manager()
	manager_a.gold_target_ratio = 0.08
	_terrain_harness.mount_manager(manager_a)
	var heights_a: Array[int] = manager_a._heightmap.duplicate()
	var gold_a: Array[String] = _terrain_harness.encode_gold_tiles(manager_a.get_gold_tiles())
	_terrain_harness.clear_manager(manager_a)

	var manager_b: TerritoryManager = _terrain_harness.create_manager()
	manager_b.gold_target_ratio = 0.08
	_terrain_harness.mount_manager(manager_b)
	var heights_b: Array[int] = manager_b._heightmap.duplicate()
	var gold_b: Array[String] = _terrain_harness.encode_gold_tiles(manager_b.get_gold_tiles())

	assert_array(heights_b).is_equal(heights_a)
	assert_array(gold_b).is_equal(gold_a)

	_terrain_harness.clear_manager(manager_b)
	_terrain_harness.reset_runtime_state()

func test_flat_base_pads_are_preserved_after_terrain_generation() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 5555)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var flat_width: int = manager._get_flat_width()
	var base_height := int(clamp(
		manager.base_surface_height,
		manager.min_surface_height,
		manager.max_surface_height
	))

	for i in range(flat_width):
		assert_int(manager._heightmap[i]).is_equal(base_height)
		assert_int(manager._heightmap[manager.grid_width - 1 - i]).is_equal(base_height)

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_base_anchors_stay_in_their_territories_after_world_size_changes() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 6666)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)

	GameState.set_world_settings(96, 30, 7777)
	await get_tree().process_frame

	var left_anchor: Vector2 = manager.get_base_anchor_world(GameState.Team.LEFT)
	var right_anchor: Vector2 = manager.get_base_anchor_world(GameState.Team.RIGHT)
	assert_bool(manager.is_world_pos_in_team_territory(left_anchor, GameState.Team.LEFT)).is_true()
	assert_bool(manager.is_world_pos_in_team_territory(right_anchor, GameState.Team.RIGHT)).is_true()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_world_pixel_rect_matches_world_settings_and_tile_size() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(72, 24, 8888)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	manager.tile_size = 20
	_terrain_harness.mount_manager(manager)
	var world_rect: Rect2 = manager.get_world_pixel_rect()

	assert_float(world_rect.size.x).is_equal(72.0 * 20.0)
	assert_float(world_rect.size.y).is_equal(24.0 * 20.0)

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_gold_tiles_stay_below_surface_and_respect_window_density_limits() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 9991)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	manager.gold_target_ratio = 0.1
	_terrain_harness.mount_manager(manager)

	assert_int(manager.get_gold_tiles().size()).is_greater(0)
	_terrain_harness.assert_gold_tiles_respect_rules(self, manager)

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_gold_tiles_render_on_resource_layer_without_replacing_surface_grass() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 9992)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	manager.gold_target_ratio = 0.1
	_terrain_harness.mount_manager(manager)

	assert_int(manager.get_gold_tiles().size()).is_greater(0)
	for x in range(manager.grid_width):
		var surface_tile := Vector2i(x, manager._get_surface_height(x))
		assert_bool(
			manager.tile_map.get_cell_atlas_coords(manager.TERRAIN_LAYER, surface_tile)
			== manager.TILE_GRASS
		).is_true()
		assert_int(
			manager.tile_map.get_cell_source_id(manager.RESOURCE_LAYER, surface_tile)
		).is_equal(-1)
	for raw_tile in manager.get_gold_tiles().keys():
		var gold_tile: Vector2i = raw_tile
		assert_bool(
			manager.tile_map.get_cell_atlas_coords(manager.RESOURCE_LAYER, gold_tile)
			== manager.TILE_GOLD
		).is_true()
		assert_bool(
			manager.tile_map.get_cell_atlas_coords(manager.TERRAIN_LAYER, gold_tile)
			== manager.TILE_DIRT
		).is_true()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_gold_tiles_regenerate_validly_after_world_settings_change() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 9993)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	manager.gold_target_ratio = 0.08
	_terrain_harness.mount_manager(manager)
	var original_gold: Array[String] = _terrain_harness.encode_gold_tiles(manager.get_gold_tiles())

	GameState.set_world_settings(96, 30, 9994)
	await get_tree().process_frame

	var regenerated_gold: Dictionary = manager.get_gold_tiles()
	assert_array(_terrain_harness.encode_gold_tiles(regenerated_gold)).is_not_equal(original_gold)
	assert_int(regenerated_gold.size()).is_greater(0)
	for raw_tile in regenerated_gold.keys():
		var tile: Vector2i = raw_tile
		assert_bool(tile.x >= 0 and tile.x < manager.grid_width).is_true()
		assert_bool(tile.y >= 0 and tile.y < manager.grid_height).is_true()
	_terrain_harness.assert_gold_tiles_respect_rules(self, manager)

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_mining_selection_layers_render_and_clear_independently() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 9995)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var draft_tile := Vector2i(8, manager._get_surface_height(8))
	var committed_tile := Vector2i(9, manager._get_surface_height(9))

	manager.set_mining_draft_tiles({draft_tile: true})
	manager.set_mining_committed_tiles({committed_tile: true})

	assert_int(manager.tile_map.get_cell_source_id(manager.MINING_DRAFT_LAYER, draft_tile)).is_equal(0)
	assert_int(manager.tile_map.get_cell_source_id(manager.MINING_COMMITTED_LAYER, committed_tile)).is_equal(0)
	assert_float(manager.tile_map.get_layer_modulate(manager.MINING_DRAFT_LAYER).a).is_equal_approx(
		manager.MINING_DRAFT_ALPHA,
		0.001
	)
	assert_float(manager.tile_map.get_layer_modulate(manager.MINING_COMMITTED_LAYER).a).is_equal_approx(
		manager.MINING_COMMITTED_ALPHA,
		0.001
	)

	manager.clear_mining_selection_visuals()

	assert_int(manager.tile_map.get_cell_source_id(manager.MINING_DRAFT_LAYER, draft_tile)).is_equal(-1)
	assert_int(manager.tile_map.get_cell_source_id(manager.MINING_COMMITTED_LAYER, committed_tile)).is_equal(-1)

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

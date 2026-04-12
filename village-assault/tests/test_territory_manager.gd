## Feature: territory-manager
## Direct tests for terrain generation, spawn bounds, and anchors.
extends GdUnitTestSuite

const TERRAIN_TEST_HARNESS: GDScript = preload("res://scripts/testing/terrain_test_harness.gd")

var _terrain_harness: RefCounted = TERRAIN_TEST_HARNESS.new()

func _clear_and_fill_ground(manager: TerritoryManager, tiles: Array[Vector2i]) -> void:
	manager.tile_map.clear()
	manager._gold_tiles.clear()
	manager._tile_health.clear()
	for tile in tiles:
		manager.tile_map.set_cell(manager.TERRAIN_LAYER, tile, 0, manager.TILE_DIRT)
		manager._tile_health[tile] = manager.TILE_HEALTH_DEFAULT

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

func test_invalid_mining_selection_tiles_require_air_connectivity() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 9996)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var valid_tile := Vector2i(12, manager._get_surface_height(12))
	var invalid_tile := Vector2i(12, manager._get_surface_height(12) + 2)

	var invalid_tiles := manager.get_invalid_mining_selection_tiles({
		valid_tile: true,
		invalid_tile: true,
	})

	assert_bool(invalid_tiles.has(valid_tile)).is_false()
	assert_bool(invalid_tiles.has(invalid_tile)).is_true()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_destroyed_tiles_become_underground_air() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(64, 20, 9997)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var tile := Vector2i(12, manager._get_surface_height(12))

	assert_int(manager.get_tile_health(tile)).is_equal(manager.TILE_HEALTH_DEFAULT)
	assert_bool(manager.apply_tile_damage(tile, 1)).is_false()
	assert_int(manager.get_tile_health(tile)).is_equal(1)
	assert_bool(manager.apply_tile_damage(tile, 1)).is_true()
	assert_bool(manager.has_ground_at_tile(tile)).is_false()
	assert_bool(manager.is_underground_tile(tile)).is_true()
	assert_bool(manager.is_walkable_air_tile(tile)).is_true()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_miner_walk_neighbors_allow_one_tile_climb_and_two_tile_drop_only() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 9998)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(2, 5),
		Vector2i(3, 5),
		Vector2i(4, 4),
		Vector2i(4, 7),
	])

	var start_tile := Vector2i(3, 4)
	var neighbors: Array[Vector2i] = manager.get_miner_walk_neighbors(start_tile)

	assert_bool(neighbors.has(Vector2i(2, 4))).is_true()
	assert_bool(neighbors.has(Vector2i(4, 3))).is_true()
	assert_bool(neighbors.has(Vector2i(4, 6))).is_true()
	assert_bool(neighbors.has(Vector2i(4, 2))).is_false()
	assert_bool(neighbors.has(Vector2i(4, 5))).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_stand_surface_world_y_at_x_snaps_to_nearest_supported_floor() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 9999)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(3, 5),
		Vector2i(4, 4),
	])

	var low_floor_y: float = manager.stand_tile_to_world_position(Vector2i(3, 4)).y
	var high_floor_y: float = manager.stand_tile_to_world_position(Vector2i(4, 3)).y

	assert_float(manager.get_stand_surface_world_y_at_x(3.5 * manager.tile_size, high_floor_y)).is_equal_approx(
		low_floor_y,
		0.001
	)
	assert_float(manager.get_stand_surface_world_y_at_x(4.5 * manager.tile_size, low_floor_y)).is_equal_approx(
		high_floor_y,
		0.001
	)

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_troop_standability_respects_unit_height_and_width() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 10000)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(3, 5),
		Vector2i(4, 5),
		Vector2i(5, 5),
		Vector2i(4, 4),
		Vector2i(5, 4),
	])

	assert_bool(manager.is_troop_standable_tile(Vector2i(3, 4), 1, 1)).is_true()
	assert_bool(manager.is_troop_standable_tile(Vector2i(3, 4), 1, 2)).is_true()
	assert_bool(manager.is_troop_standable_tile(Vector2i(4, 4), 1, 1)).is_false()
	assert_bool(manager.is_troop_standable_tile(Vector2i(3, 4), 2, 2)).is_false()
	assert_bool(manager.is_troop_standable_tile(Vector2i(4, 4), 2, 2)).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_wide_troop_can_stand_with_partial_support() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 10004)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(4, 5),
	])

	assert_bool(manager.is_troop_standable_tile(Vector2i(3, 4), 2, 2)).is_true()
	assert_bool(manager.is_troop_standable_tile(Vector2i(4, 4), 2, 2)).is_true()
	assert_bool(manager.is_troop_standable_tile(Vector2i(5, 4), 2, 2)).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_troop_walk_target_allows_one_tile_climb_for_supported_sizes() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 10001)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(6, 9),
		Vector2i(7, 8),
		Vector2i(8, 8),
	])

	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 1)).is_equal(Vector2i(7, 7))
	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 2)).is_equal(Vector2i(7, 7))
	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 2, 2)).is_equal(Vector2i(7, 7))

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_troop_walk_target_allows_two_tile_climb_for_tall_units_only() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 10005)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(6, 9),
		Vector2i(7, 7),
		Vector2i(8, 7),
	])

	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 1)).is_equal(Vector2i(-1, -1))
	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 2)).is_equal(Vector2i(7, 6))
	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 2, 2)).is_equal(Vector2i(7, 6))

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_troop_walk_target_allows_size_based_forward_drops() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 14, 10002)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)

	_clear_and_fill_ground(manager, [
		Vector2i(6, 9),
		Vector2i(7, 10),
	])

	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 1)).is_equal(Vector2i(7, 9))

	_clear_and_fill_ground(manager, [
		Vector2i(6, 9),
		Vector2i(7, 11),
		Vector2i(8, 11),
	])

	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 2)).is_equal(Vector2i(7, 10))
	assert_vector(manager.get_troop_walk_target(Vector2i(6, 8), 1, 2, 2)).is_equal(Vector2i(7, 10))

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_miner_attack_tiles_allow_diagonal_stair_step_when_shared_corner_is_air() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 10000)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(3, 5),
		Vector2i(4, 4),
	])

	var target_tile := Vector2i(4, 4)
	var attack_tiles: Array[Vector2i] = manager.get_miner_attack_tiles(target_tile)

	assert_bool(attack_tiles.has(Vector2i(3, 4))).is_true()
	assert_bool(attack_tiles.has(Vector2i(5, 3))).is_true()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_miner_attack_tiles_reject_diagonal_when_corner_is_fully_blocked() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(12, 12, 10001)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	_clear_and_fill_ground(manager, [
		Vector2i(3, 5),
		Vector2i(4, 4),
		Vector2i(3, 4),
		Vector2i(4, 3),
	])

	var target_tile := Vector2i(4, 4)
	var attack_tiles: Array[Vector2i] = manager.get_miner_attack_tiles(target_tile)

	assert_bool(attack_tiles.has(Vector2i(3, 3))).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_ore_health_defaults_to_100_and_depletion_clears_ore() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(32, 20, 10002)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var ore_tile := Vector2i(-1, -1)
	for raw_tile in manager.get_gold_tiles().keys():
		ore_tile = raw_tile
		break

	assert_bool(manager.is_ore_tile(ore_tile)).is_true()
	assert_int(manager.get_ore_health(ore_tile)).is_equal(manager.ORE_HEALTH_DEFAULT)
	assert_bool(manager.apply_ore_damage(ore_tile, 99)).is_false()
	assert_int(manager.get_ore_health(ore_tile)).is_equal(1)
	assert_bool(manager.apply_ore_damage(ore_tile, 1)).is_true()
	assert_bool(manager.is_ore_tile(ore_tile)).is_false()
	assert_bool(manager.is_underground_tile(ore_tile)).is_true()
	assert_bool(manager.is_walkable_air_tile(ore_tile)).is_true()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_reveal_ore_from_exposed_tile_marks_team_visibility_only() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(32, 20, 10003)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var ore_tile := Vector2i(-1, -1)
	for raw_tile in manager.get_gold_tiles().keys():
		ore_tile = raw_tile
		break
	var exposed_tile := ore_tile + Vector2i.LEFT
	manager.tile_map.erase_cell(manager.TERRAIN_LAYER, exposed_tile)
	manager.tile_map.set_cell(manager.UNDERGROUND_LAYER, exposed_tile, 0, manager.TILE_UNDERGROUND)

	var revealed := manager.reveal_ore_from_exposed_tile(exposed_tile, GameState.Team.LEFT)

	assert_array(revealed).is_equal([ore_tile])
	assert_bool(manager.is_ore_revealed_to_team(ore_tile, GameState.Team.LEFT)).is_true()
	assert_bool(manager.is_ore_revealed_to_team(ore_tile, GameState.Team.RIGHT)).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_harvest_queue_overlay_only_tracks_current_selection_order() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(32, 20, 10004)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var ore_tiles: Array[Vector2i] = []
	for raw_tile in manager.get_gold_tiles().keys():
		ore_tiles.append(raw_tile)
		if ore_tiles.size() == 2:
			break

	manager.set_harvest_queue_overlay(ore_tiles)
	assert_bool(manager._harvest_queue_overlay_visible).is_true()
	assert_array(manager._harvest_queue_overlay_tiles).is_equal(ore_tiles)

	manager.clear_harvest_queue_overlay()
	assert_bool(manager._harvest_queue_overlay_visible).is_false()
	assert_array(manager._harvest_queue_overlay_tiles).is_empty()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

func test_world_state_snapshot_reapplies_destroyed_tiles_depleted_ore_and_revealed_ore() -> void:
	_terrain_harness.reset_runtime_state()
	GameState.set_world_settings(32, 20, 10005)
	var manager: TerritoryManager = _terrain_harness.create_manager()
	_terrain_harness.mount_manager(manager)
	var terrain_tile := Vector2i(10, manager._get_surface_height(10))
	assert_bool(manager.apply_tile_damage(terrain_tile, manager.TILE_HEALTH_DEFAULT)).is_true()

	var ore_tile := Vector2i(-1, -1)
	for raw_tile in manager.get_gold_tiles().keys():
		ore_tile = raw_tile
		break
	assert_bool(manager.is_ore_tile(ore_tile)).is_true()
	var exposed_tile := ore_tile + Vector2i.LEFT
	manager.tile_map.erase_cell(manager.TERRAIN_LAYER, exposed_tile)
	manager.tile_map.set_cell(manager.UNDERGROUND_LAYER, exposed_tile, 0, manager.TILE_UNDERGROUND)
	manager.reveal_ore_from_exposed_tile(exposed_tile, GameState.Team.LEFT)
	assert_bool(manager.apply_ore_damage(ore_tile, manager.ORE_HEALTH_DEFAULT)).is_true()

	var destroyed_tiles := manager.get_destroyed_terrain_tiles()
	var depleted_ore_tiles := manager.get_depleted_ore_tiles()
	var revealed_snapshot := manager.get_revealed_ore_snapshot()

	manager._build_terrain()
	assert_bool(manager.has_ground_at_tile(terrain_tile)).is_true()
	assert_bool(manager.is_ore_revealed_to_team(ore_tile, GameState.Team.LEFT)).is_false()
	assert_bool(manager.is_ore_tile(ore_tile)).is_true()

	manager.apply_world_state_snapshot(destroyed_tiles, depleted_ore_tiles, revealed_snapshot)

	assert_bool(manager.has_ground_at_tile(terrain_tile)).is_false()
	assert_bool(manager.is_ore_tile(ore_tile)).is_false()
	assert_bool(manager.is_ore_revealed_to_team(ore_tile, GameState.Team.LEFT)).is_false()

	_terrain_harness.clear_manager(manager)
	_terrain_harness.reset_runtime_state()

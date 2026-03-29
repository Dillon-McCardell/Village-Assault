extends RefCounted
class_name TerrainTestHarness

func reset_runtime_state() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")

func create_manager() -> TerritoryManager:
	var manager := TerritoryManager.new()
	manager.name = "TerritoryManager"
	var tile_map := TileMap.new()
	tile_map.name = "WorldTileMap"
	manager.add_child(tile_map)
	return manager

func mount_manager(manager: TerritoryManager) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(manager)
	tree.current_scene = manager

func clear_manager(manager: TerritoryManager) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
	tree.current_scene = null

func encode_gold_tiles(gold_tiles: Dictionary) -> Array[String]:
	var encoded: Array[String] = []
	for raw_tile in gold_tiles.keys():
		var tile: Vector2i = raw_tile
		encoded.append("%d,%d" % [tile.x, tile.y])
	encoded.sort()
	return encoded

func count_gold_in_window(
	manager: TerritoryManager,
	window_x: int,
	window_y: int,
	window_width: int,
	window_height: int
) -> int:
	var count: int = 0
	for raw_tile in manager.get_gold_tiles().keys():
		var tile: Vector2i = raw_tile
		if tile.x < window_x or tile.x >= window_x + window_width:
			continue
		if tile.y < window_y or tile.y >= window_y + window_height:
			continue
		count += 1
	return count

func assert_gold_tiles_respect_rules(suite: GdUnitTestSuite, manager: TerritoryManager) -> void:
	for raw_tile in manager.get_gold_tiles().keys():
		var tile: Vector2i = raw_tile
		suite.assert_int(tile.y).is_greater_equal(
			manager._get_surface_height(tile.x) + manager.gold_min_depth_below_surface
		)
	var window_width: int = min(max(1, manager.gold_window_size), manager.grid_width)
	var window_height: int = min(max(1, manager.gold_window_size), manager.grid_height)
	var max_window_x: int = max(0, manager.grid_width - window_width)
	var max_window_y: int = max(0, manager.grid_height - window_height)
	for window_x in range(max_window_x + 1):
		for window_y in range(max_window_y + 1):
			suite.assert_int(
				count_gold_in_window(manager, window_x, window_y, window_width, window_height)
			).is_less_equal(manager.gold_max_per_window)

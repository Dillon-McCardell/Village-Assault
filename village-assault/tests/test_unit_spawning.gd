## Feature: unit-spawning
## Runtime integration tests for the purchase-to-spawn flow.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const TROOP_ITEM_SCRIPTS: Dictionary = {
	"troop_grunt": preload("res://scripts/shop/troops/troop_grunt.gd"),
	"troop_ranger": preload("res://scripts/shop/troops/troop_ranger.gd"),
	"troop_brute": preload("res://scripts/shop/troops/troop_brute.gd"),
	"troop_scout": preload("res://scripts/shop/troops/troop_scout.gd"),
	"troop_miner": preload("res://scripts/shop/troops/troop_miner.gd"),
}
const DEFENSE_GATE_SCRIPT: GDScript = preload("res://scripts/shop/defense/defense_gate.gd")
var _next_test_port: int = NetworkManager.DEFAULT_PORT + 100

class EmptyPayloadItem:
	func get_spawn_payload() -> Dictionary:
		return {}

func _reset_runtime_state() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")

func _mount_node(node: Node) -> void:
	get_tree().root.add_child(node)
	get_tree().current_scene = node

func _clear_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()

func _start_host_game() -> Node:
	_reset_runtime_state()
	NetworkManager.host(_next_test_port)
	_next_test_port += 1
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _get_shop_menu(game: Node) -> Control:
	return game.get_node("CanvasLayer/UI/ShopMenu") as Control

func _carve_tunnel_section(game: Node, air_tiles: Array[Vector2i], support_tiles: Array[Vector2i], solid_tiles: Array[Vector2i] = []) -> void:
	var territory: TerritoryManager = game.territory_manager
	for tile in air_tiles:
		territory.tile_map.erase_cell(territory.TERRAIN_LAYER, tile)
		territory.tile_map.set_cell(territory.UNDERGROUND_LAYER, tile, 0, territory.TILE_UNDERGROUND)
		territory._tile_health.erase(tile)
	for tile in support_tiles:
		territory.tile_map.set_cell(territory.TERRAIN_LAYER, tile, 0, territory.TILE_DIRT)
		territory._tile_health[tile] = territory.TILE_HEALTH_DEFAULT
	for tile in solid_tiles:
		territory.tile_map.set_cell(territory.TERRAIN_LAYER, tile, 0, territory.TILE_DIRT)
		territory._tile_health[tile] = territory.TILE_HEALTH_DEFAULT

func test_troop_purchase_deducts_money_and_enqueues_spawn_request() -> void:
	var game := _start_host_game()
	var shop := _get_shop_menu(game)
	var item := (TROOP_ITEM_SCRIPTS["troop_grunt"] as GDScript).new() as ShopItem
	var start_money := GameState.get_money_for_peer(1)

	shop._process_purchase_request(1, item)

	assert_int(GameState.get_money_for_peer(1)).is_equal(start_money - item.price)
	assert_int(GameState._spawn_queue.size()).is_equal(1)
	assert_str(GameState._spawn_queue[0]["item_id"]).is_equal(item.id)
	assert_int(GameState._spawn_queue[0]["peer_id"]).is_equal(1)
	assert_int(GameState._spawn_queue[0]["team"]).is_equal(GameState.get_team_for_peer(1))

	_clear_node(game)
	_reset_runtime_state()

func test_miner_purchase_deducts_money_and_enqueues_spawn_request() -> void:
	var game := _start_host_game()
	var shop := _get_shop_menu(game)
	var item := (TROOP_ITEM_SCRIPTS["troop_miner"] as GDScript).new() as ShopItem
	var start_money := GameState.get_money_for_peer(1)

	shop._process_purchase_request(1, item)

	assert_int(GameState.get_money_for_peer(1)).is_equal(start_money - item.price)
	assert_int(GameState._spawn_queue.size()).is_equal(1)
	assert_str(GameState._spawn_queue[0]["item_id"]).is_equal("troop_miner")
	assert_int(GameState._spawn_queue[0]["team"]).is_equal(GameState.get_team_for_peer(1))

	_clear_node(game)
	_reset_runtime_state()

func test_insufficient_funds_does_not_deduct_money_or_enqueue_spawn() -> void:
	var game := _start_host_game()
	var shop := _get_shop_menu(game)
	var item := (TROOP_ITEM_SCRIPTS["troop_brute"] as GDScript).new() as ShopItem
	GameState.set_money_for_peer(1, item.price - 1)

	shop._process_purchase_request(1, item)

	assert_int(GameState.get_money_for_peer(1)).is_equal(item.price - 1)
	assert_int(GameState._spawn_queue.size()).is_equal(0)

	_clear_node(game)
	_reset_runtime_state()

func test_non_troop_purchase_deducts_money_without_enqueuing_spawn() -> void:
	var game := _start_host_game()
	var shop := _get_shop_menu(game)
	var item := DEFENSE_GATE_SCRIPT.new() as ShopItem
	var start_money := GameState.get_money_for_peer(1)

	shop._process_purchase_request(1, item)

	assert_int(GameState.get_money_for_peer(1)).is_equal(start_money - item.price)
	assert_int(GameState._spawn_queue.size()).is_equal(0)

	_clear_node(game)
	_reset_runtime_state()

func test_process_spawn_queue_consumes_request_and_spawns_expected_troop() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_ranger",
		"team": GameState.get_team_for_peer(1),
	})

	game._process_spawn_queue()

	assert_int(GameState._spawn_queue.size()).is_equal(0)
	var troop: Node2D = game.get_unit_by_id(1)
	assert_that(troop).is_not_null()
	assert_str(troop.item_id).is_equal("troop_ranger")
	assert_str(troop.get_script().resource_path).is_equal("res://scripts/troops/troop_ranger.gd")

	_clear_node(game)
	_reset_runtime_state()

func test_process_spawn_queue_spawns_miner_with_expected_stats() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_miner",
		"team": GameState.get_team_for_peer(1),
	})

	game._process_spawn_queue()

	assert_int(GameState._spawn_queue.size()).is_equal(0)
	var troop: Node2D = game.get_unit_by_id(1)
	assert_that(troop).is_not_null()
	assert_str(troop.item_id).is_equal("troop_miner")
	assert_int(troop.max_health).is_equal(5)
	assert_int(troop.current_health).is_equal(5)
	assert_int(troop.damage).is_equal(1)
	assert_int(troop.defense).is_equal(0)
	assert_int(troop.tile_damage).is_equal(1)

	_clear_node(game)
	_reset_runtime_state()

func test_regular_troops_snap_to_live_excavated_ground() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()

	var troop: Node2D = game.get_unit_by_id(1)
	assert_that(troop).is_not_null()
	var hole_tile := Vector2i(12, game.territory_manager._get_surface_height(12))
	assert_bool(game.territory_manager.apply_tile_damage(hole_tile, game.territory_manager.TILE_HEALTH_DEFAULT)).is_true()
	var expected_world: Vector2 = game.territory_manager.troop_stand_tile_to_world_position(hole_tile, 1)
	troop.position = Vector2(
		expected_world.x,
		expected_world.y + 2.0
	)
	troop._snap_to_ground()

	assert_float(troop.position.y).is_equal_approx(
		expected_world.y,
		0.001
	)

	_clear_node(game)
	_reset_runtime_state()

func test_regular_troops_halt_at_dead_end_instead_of_teleporting_to_surface() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var troop: Node2D = game.get_unit_by_id(1)
	assert_that(troop).is_not_null()

	_carve_tunnel_section(
		game,
		[Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8)],
		[Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9)],
		[Vector2i(10, 7), Vector2i(10, 8), Vector2i(10, 9)]
	)
	troop.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(8, 8), 1)
	troop._snap_to_ground()
	var start_y := troop.position.y

	for _i in range(20):
		troop._physics_process(0.1)

	assert_float(troop.position.x).is_less_equal(game.territory_manager.troop_stand_tile_to_world_position(Vector2i(9, 8), 1).x)
	assert_float(troop.position.y).is_equal_approx(start_y, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_grunt_fits_one_tile_tunnel_but_ranger_does_not_move_into_it() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.get_team_for_peer(1),
	})
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_ranger",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	game._process_spawn_queue()
	var grunt: Node2D = game.get_unit_by_id(1)
	var ranger: Node2D = game.get_unit_by_id(2)
	assert_that(grunt).is_not_null()
	assert_that(ranger).is_not_null()

	_carve_tunnel_section(
		game,
		[Vector2i(6, 8), Vector2i(6, 7), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8)],
		[Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9)],
		[Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6)]
	)
	grunt.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	ranger.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	grunt._snap_to_ground()
	ranger._snap_to_ground()
	var grunt_start_x := grunt.position.x
	var ranger_start_x := ranger.position.x

	for _i in range(10):
		grunt._physics_process(0.1)
		ranger._physics_process(0.1)

	assert_float(grunt.position.x).is_greater(grunt_start_x)
	assert_float(ranger.position.x).is_equal_approx(ranger_start_x, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_grunt_can_walk_off_one_tile_drop() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var grunt: Node2D = game.get_unit_by_id(1)
	assert_that(grunt).is_not_null()

	_carve_tunnel_section(
		game,
		[Vector2i(6, 8), Vector2i(7, 8), Vector2i(7, 9)],
		[Vector2i(6, 9), Vector2i(7, 10)]
	)
	grunt.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	grunt._snap_to_ground()
	var start_x := grunt.position.x
	var expected_target: Vector2 = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(7, 9), 1)

	for _i in range(20):
		grunt._physics_process(0.1)

	assert_float(grunt.position.x).is_greater(start_x)
	assert_float(grunt.position.x).is_equal_approx(expected_target.x, 0.001)
	assert_float(grunt.position.y).is_equal_approx(expected_target.y, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_ranger_can_walk_off_two_tile_drop() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_ranger",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var ranger: Node2D = game.get_unit_by_id(1)
	assert_that(ranger).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(6, 8), Vector2i(6, 7),
			Vector2i(7, 8), Vector2i(7, 7), Vector2i(7, 9), Vector2i(7, 10)
		],
		[Vector2i(6, 9), Vector2i(7, 11)]
	)
	ranger.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	ranger._snap_to_ground()
	var start_x := ranger.position.x
	var expected_target: Vector2 = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(7, 10), 1)

	for _i in range(24):
		ranger._physics_process(0.1)

	assert_float(ranger.position.x).is_greater(start_x)
	assert_float(ranger.position.x).is_equal_approx(expected_target.x, 0.001)
	assert_float(ranger.position.y).is_equal_approx(expected_target.y, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_grunt_can_climb_one_tile_step() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var grunt: Node2D = game.get_unit_by_id(1)
	assert_that(grunt).is_not_null()

	_carve_tunnel_section(
		game,
		[Vector2i(6, 8), Vector2i(7, 8), Vector2i(7, 7)],
		[Vector2i(6, 9), Vector2i(7, 9), Vector2i(7, 8)]
	)
	grunt.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	grunt._snap_to_ground()
	var climb_target: Vector2i = game.territory_manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 1)

	grunt._physics_process(0.1)

	assert_vector(climb_target).is_equal(Vector2i(7, 7))
	assert_vector(grunt._troop_movement_target_tile).is_equal(Vector2i(7, 7))

	_clear_node(game)
	_reset_runtime_state()

func test_ranger_can_climb_one_tile_step() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_ranger",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var ranger: Node2D = game.get_unit_by_id(1)
	assert_that(ranger).is_not_null()

	_carve_tunnel_section(
		game,
		[Vector2i(6, 8), Vector2i(6, 7), Vector2i(7, 8), Vector2i(7, 7), Vector2i(7, 6)],
		[Vector2i(6, 9), Vector2i(7, 8)]
	)
	ranger.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	ranger._snap_to_ground()
	var climb_target: Vector2i = game.territory_manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 2)

	ranger._physics_process(0.1)

	assert_vector(climb_target).is_equal(Vector2i(7, 7))
	assert_vector(ranger._troop_movement_target_tile).is_equal(Vector2i(7, 7))

	_clear_node(game)
	_reset_runtime_state()

func test_ranger_can_climb_two_tile_step() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_ranger",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var ranger: Node2D = game.get_unit_by_id(1)
	assert_that(ranger).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(6, 8), Vector2i(6, 7),
			Vector2i(7, 8), Vector2i(7, 7), Vector2i(7, 6), Vector2i(7, 5)
		],
		[Vector2i(6, 9), Vector2i(7, 7)]
	)
	ranger.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 1)
	ranger._snap_to_ground()
	var climb_target: Vector2i = game.territory_manager.get_troop_walk_target(Vector2i(6, 8), 1, 1, 2)

	ranger._physics_process(0.1)

	assert_vector(climb_target).is_equal(Vector2i(7, 6))
	assert_vector(ranger._troop_movement_target_tile).is_equal(Vector2i(7, 6))

	_clear_node(game)
	_reset_runtime_state()

func test_brute_can_climb_one_tile_step() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_brute",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var brute: Node2D = game.get_unit_by_id(1)
	assert_that(brute).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 7), Vector2i(7, 7),
			Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 6), Vector2i(8, 6)
		],
		[Vector2i(6, 9), Vector2i(7, 8), Vector2i(8, 8)]
	)
	brute.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 2)
	brute._snap_to_ground()
	var climb_target: Vector2i = game.territory_manager.get_troop_walk_target(Vector2i(6, 8), 1, 2, 2)

	brute._physics_process(0.1)

	assert_vector(climb_target).is_equal(Vector2i(7, 7))
	assert_vector(brute._troop_movement_target_tile).is_equal(Vector2i(7, 7))

	_clear_node(game)
	_reset_runtime_state()

func test_brute_can_climb_two_tile_step() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_brute",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var brute: Node2D = game.get_unit_by_id(1)
	assert_that(brute).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 7), Vector2i(7, 7),
			Vector2i(7, 6), Vector2i(8, 6), Vector2i(7, 5), Vector2i(8, 5)
		],
		[Vector2i(6, 9), Vector2i(7, 7), Vector2i(8, 7)]
	)
	brute.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 2)
	brute._snap_to_ground()
	var climb_target: Vector2i = game.territory_manager.get_troop_walk_target(Vector2i(6, 8), 1, 2, 2)

	brute._physics_process(0.1)

	assert_int(climb_target.y).is_equal(6)
	assert_int(climb_target.x).is_greater_equal(6)
	assert_int(brute._troop_movement_target_tile.y).is_equal(6)
	assert_int(brute._troop_movement_target_tile.x).is_greater_equal(6)

	_clear_node(game)
	_reset_runtime_state()

func test_brute_can_walk_off_two_tile_drop() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_brute",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var brute: Node2D = game.get_unit_by_id(1)
	assert_that(brute).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(5, 8), Vector2i(6, 8), Vector2i(5, 7), Vector2i(6, 7),
			Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 7), Vector2i(7, 7),
			Vector2i(6, 9), Vector2i(7, 9), Vector2i(6, 10), Vector2i(7, 10)
		],
		[Vector2i(5, 9), Vector2i(6, 11), Vector2i(7, 11)]
	)
	brute.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(5, 8), 2)
	brute._snap_to_ground()
	var start_x := brute.position.x
	var start_y := brute.position.y
	var expected_target: Vector2 = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 10), 2)

	for _i in range(24):
		brute._physics_process(0.1)

	assert_float(brute.position.x).is_greater(start_x)
	assert_float(brute.position.y).is_greater(start_y)
	assert_float(brute.position.y).is_equal_approx(expected_target.y, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_brute_can_stand_with_one_support_block_missing() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_brute",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var brute: Node2D = game.get_unit_by_id(1)
	assert_that(brute).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(6, 8), Vector2i(7, 8),
			Vector2i(6, 7), Vector2i(7, 7)
		],
		[Vector2i(6, 9), Vector2i(7, 9)]
	)
	brute.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 2)
	brute._snap_to_ground()
	brute.team = GameState.Team.NONE
	game.territory_manager.apply_tile_damage(Vector2i(6, 9), game.territory_manager.TILE_HEALTH_DEFAULT)
	var start_x := brute.position.x
	var start_y := brute.position.y

	for _i in range(10):
		brute._physics_process(0.1)

	assert_float(brute.position.x).is_equal_approx(start_x, 0.001)
	assert_float(brute.position.y).is_equal_approx(start_y, 0.001)

	_clear_node(game)
	_reset_runtime_state()

func test_brute_can_climb_with_only_one_support_block_at_landing() -> void:
	var game := _start_host_game()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_brute",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	var brute: Node2D = game.get_unit_by_id(1)
	assert_that(brute).is_not_null()

	_carve_tunnel_section(
		game,
		[
			Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 7), Vector2i(7, 7),
			Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 6), Vector2i(8, 6)
		],
		[Vector2i(6, 9), Vector2i(7, 8)]
	)
	brute.position = game.territory_manager.troop_stand_tile_to_world_position(Vector2i(6, 8), 2)
	brute._snap_to_ground()
	var climb_target: Vector2i = game.territory_manager.get_troop_walk_target(Vector2i(6, 8), 1, 2, 2)

	brute._physics_process(0.1)

	assert_vector(climb_target).is_equal(Vector2i(7, 7))
	assert_vector(brute._troop_movement_target_tile).is_equal(Vector2i(7, 7))

	_clear_node(game)
	_reset_runtime_state()

func test_process_spawn_queue_discards_invalid_requests_via_runtime_path() -> void:
	var game := _start_host_game()

	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.Team.NONE,
	})
	game._process_spawn_queue()
	assert_int(game.units_root.get_child_count()).is_equal(0)
	assert_int(GameState._spawn_queue.size()).is_equal(0)

	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "unknown_item",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	assert_int(game.units_root.get_child_count()).is_equal(0)
	assert_int(GameState._spawn_queue.size()).is_equal(0)

	var original_item: Variant = game._troop_items["troop_grunt"]
	game._troop_items["troop_grunt"] = EmptyPayloadItem.new()
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": GameState.get_team_for_peer(1),
	})
	game._process_spawn_queue()
	assert_int(game.units_root.get_child_count()).is_equal(0)
	assert_int(GameState._spawn_queue.size()).is_equal(0)
	game._troop_items["troop_grunt"] = original_item

	_clear_node(game)
	_reset_runtime_state()

func test_spawned_unit_ids_increase_across_multiple_queue_entries() -> void:
	var game := _start_host_game()
	var team := GameState.get_team_for_peer(1)
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_grunt",
		"team": team,
	})
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_scout",
		"team": team,
	})

	game._process_spawn_queue()
	game._process_spawn_queue()

	var first: Node2D = game.get_unit_by_id(1)
	var second: Node2D = game.get_unit_by_id(2)
	assert_that(first).is_not_null()
	assert_that(second).is_not_null()
	assert_int(first.get_unit_id()).is_equal(1)
	assert_int(second.get_unit_id()).is_equal(2)
	assert_str(second.item_id).is_equal("troop_scout")

	_clear_node(game)
	_reset_runtime_state()

func test_spawn_queue_fifo_ordering() -> void:
	_reset_runtime_state()
	NetworkManager.host(_next_test_port)
	_next_test_port += 1

	var requests: Array[Dictionary] = [
		{"peer_id": 1, "item_id": "troop_grunt", "team": GameState.Team.LEFT},
		{"peer_id": 2, "item_id": "troop_ranger", "team": GameState.Team.RIGHT},
		{"peer_id": 3, "item_id": "troop_brute", "team": GameState.Team.LEFT},
	]
	for request in requests:
		GameState.enqueue_spawn(request)

	for index in range(requests.size()):
		var dequeued := GameState.dequeue_spawn()
		assert_str(dequeued["item_id"]).is_equal(requests[index]["item_id"])
		assert_int(dequeued["peer_id"]).is_equal(requests[index]["peer_id"])
		assert_int(dequeued["team"]).is_equal(requests[index]["team"])

	assert_bool(GameState.dequeue_spawn().is_empty()).is_true()
	_reset_runtime_state()

func test_shop_menu_lists_miner_under_troops_category() -> void:
	var game := _start_host_game()
	var shop := _get_shop_menu(game)

	var troop_category_found := false
	var miner_found := false
	for category in shop._shop_data:
		if category["label"] != "Troops":
			continue
		troop_category_found = true
		for item in category["items"]:
			if item is ShopItem and item.id == "troop_miner":
				miner_found = true
				break
		break

	assert_bool(troop_category_found).is_true()
	assert_bool(miner_found).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_miner_purchase_is_blocked_after_six_owned_or_queued_miners() -> void:
	var game := _start_host_game()
	var shop := _get_shop_menu(game)
	var item := (TROOP_ITEM_SCRIPTS["troop_miner"] as GDScript).new() as ShopItem

	for i in range(5):
		game.spawn_unit(Vector2(32 * i, 0), GameState.Team.LEFT, "troop_miner", i + 1, item.get_spawn_payload())
	GameState.enqueue_spawn({
		"peer_id": 1,
		"item_id": "troop_miner",
		"team": GameState.get_team_for_peer(1),
	})
	var start_money := GameState.get_money_for_peer(1)

	shop._process_purchase_request(1, item)

	assert_int(GameState.get_money_for_peer(1)).is_equal(start_money)
	assert_int(GameState._spawn_queue.size()).is_equal(1)

	_clear_node(game)
	_reset_runtime_state()

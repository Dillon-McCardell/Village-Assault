## Feature: unit-spawning
## Runtime integration tests for the purchase-to-spawn flow.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const TROOP_ITEM_SCRIPTS: Dictionary = {
	"troop_grunt": preload("res://scripts/shop/troops/troop_grunt.gd"),
	"troop_ranger": preload("res://scripts/shop/troops/troop_ranger.gd"),
	"troop_brute": preload("res://scripts/shop/troops/troop_brute.gd"),
	"troop_scout": preload("res://scripts/shop/troops/troop_scout.gd"),
}
const DEFENSE_GATE_SCRIPT: GDScript = preload("res://scripts/shop/defense/defense_gate.gd")

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
	NetworkManager.host(NetworkManager.DEFAULT_PORT)
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _get_shop_menu(game: Node) -> Control:
	return game.get_node("CanvasLayer/UI/ShopMenu") as Control

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
	NetworkManager.host(NetworkManager.DEFAULT_PORT)

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

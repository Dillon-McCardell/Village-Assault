## Feature: troop-combat
## Runtime tests for troop stat initialization and combat behavior.
extends GdUnitTestSuite

const TROOP_IDS: Array[String] = [
	"troop_grunt",
	"troop_ranger",
	"troop_brute",
	"troop_scout",
	"troop_miner",
]

const TROOP_ITEM_SCRIPTS: Dictionary = {
	"troop_grunt": preload("res://scripts/shop/troops/troop_grunt.gd"),
	"troop_ranger": preload("res://scripts/shop/troops/troop_ranger.gd"),
	"troop_brute": preload("res://scripts/shop/troops/troop_brute.gd"),
	"troop_scout": preload("res://scripts/shop/troops/troop_scout.gd"),
	"troop_miner": preload("res://scripts/shop/troops/troop_miner.gd"),
}

const TROOP_SCENES: Dictionary = {
	"troop_grunt": preload("res://scenes/troops/troop_grunt.tscn"),
	"troop_ranger": preload("res://scenes/troops/troop_ranger.tscn"),
	"troop_brute": preload("res://scenes/troops/troop_brute.tscn"),
	"troop_scout": preload("res://scenes/troops/troop_scout.tscn"),
	"troop_miner": preload("res://scenes/troops/troop_miner.tscn"),
}

const HEALTH_BAR_WIDTH: float = 20.0

class CombatHarness extends Node2D:
	var units_root: Node2D

	func _ready() -> void:
		units_root = Node2D.new()
		units_root.name = "Units"
		add_child(units_root)

	func add_troop(item_id: String, unit_id: int, team: int, pos: Vector2) -> Node2D:
		var scene: PackedScene = load("res://scenes/troops/%s.tscn" % item_id)
		var troop := scene.instantiate() as Node2D
		troop.name = "Troop_%d" % unit_id
		troop.position = pos
		troop.set_team(team)
		troop.set_item_id(item_id)
		troop.set_unit_id(unit_id)
		troop.initialize_from_spawn_payload(_spawn_payload_for(item_id))
		units_root.add_child(troop)
		return troop

	func get_unit_by_id(unit_id: int) -> Node2D:
		return units_root.get_node_or_null("Troop_%d" % unit_id) as Node2D

	func sync_unit_health(unit_id: int, current_health: int) -> void:
		var troop := get_unit_by_id(unit_id)
		if troop != null:
			troop.sync_current_health(current_health)

	func destroy_unit(unit_id: int) -> void:
		var troop := get_unit_by_id(unit_id)
		if troop != null:
			troop.queue_free()

	func _spawn_payload_for(item_id: String) -> Dictionary:
		return load("res://scripts/shop/troops/%s.gd" % item_id).new().get_spawn_payload()

func _mount_node(node: Node) -> void:
	get_tree().root.add_child(node)
	get_tree().current_scene = node

func _clear_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()

func _health_bar_fill_width(troop: Node2D) -> float:
	var fill: ColorRect = troop.get_health_bar_fill()
	return fill.size.x

func test_shop_items_expose_valid_troop_spawn_payloads() -> void:
	for item_id in TROOP_IDS:
		var item := (TROOP_ITEM_SCRIPTS[item_id] as GDScript).new() as ShopItem
		var payload := item.get_spawn_payload()

		assert_bool(payload.has("health")).is_true()\
			.override_failure_message("Expected spawn payload for %s to include health" % item_id)
		assert_bool(payload.has("damage")).is_true()\
			.override_failure_message("Expected spawn payload for %s to include damage" % item_id)
		assert_bool(payload.has("defense")).is_true()\
			.override_failure_message("Expected spawn payload for %s to include defense" % item_id)

		assert_int(int(payload["health"])).is_greater(0)\
			.override_failure_message("Expected health > 0 for %s" % item_id)
		assert_int(int(payload["damage"])).is_greater_equal(0)\
			.override_failure_message("Expected damage >= 0 for %s" % item_id)
		assert_int(int(payload["defense"])).is_greater_equal(0)\
			.override_failure_message("Expected defense >= 0 for %s" % item_id)

	var miner := (TROOP_ITEM_SCRIPTS["troop_miner"] as GDScript).new() as ShopItem
	assert_int(miner.health).is_equal(5)
	assert_int(miner.damage).is_equal(1)
	assert_int(miner.defense).is_equal(0)

func test_spawn_unit_initializes_runtime_stats_from_shop_items() -> void:
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	_mount_node(game)

	for i in range(TROOP_IDS.size()):
		var item_id: String = TROOP_IDS[i]
		var payload: Dictionary = game.get_troop_spawn_payload(item_id)
		game.spawn_unit(Vector2(32 * i, 0), GameState.Team.LEFT, item_id, i + 1, payload)

		var troop: Node2D = game.get_unit_by_id(i + 1)
		assert_that(troop).is_not_null()\
			.override_failure_message("Expected spawned troop for %s to exist" % item_id)
		assert_int(troop.max_health).is_equal(int(payload["health"]))
		assert_int(troop.current_health).is_equal(int(payload["health"]))
		assert_int(troop.damage).is_equal(int(payload["damage"]))
		assert_int(troop.defense).is_equal(int(payload["defense"]))
		assert_str(troop.item_id).is_equal(item_id)
		assert_that(troop.get_health_bar_root()).is_not_null()\
			.override_failure_message("Expected spawned troop for %s to create a health bar" % item_id)
		assert_bool(troop.get_health_bar_root().visible).is_false()\
			.override_failure_message("Expected spawned troop for %s to hide a full-health bar" % item_id)

	_clear_node(game)

func test_spawn_test_unit_uses_grunt_stats_for_free_debug_spawn() -> void:
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	_mount_node(game)

	var grunt_payload: Dictionary = game.get_troop_spawn_payload("troop_grunt")
	game.spawn_test_unit(Vector2(0, 0), GameState.Team.LEFT, 99, grunt_payload)

	var troop: Node2D = game.get_unit_by_id(99)
	assert_that(troop).is_not_null()\
		.override_failure_message("Expected debug-spawned troop to exist")
	assert_str(troop.item_id).is_equal("troop_grunt")
	assert_int(troop.max_health).is_equal(int(grunt_payload["health"]))
	assert_int(troop.current_health).is_equal(int(grunt_payload["health"]))
	assert_int(troop.damage).is_equal(int(grunt_payload["damage"]))
	assert_int(troop.defense).is_equal(int(grunt_payload["defense"]))
	assert_that(troop.get_health_bar_root()).is_not_null()\
		.override_failure_message("Expected debug-spawned troop to create a health bar")
	assert_bool(troop.get_health_bar_root().visible).is_false()\
		.override_failure_message("Expected debug-spawned troop to hide a full-health bar")

	_clear_node(game)

func test_troop_scene_configures_multiplayer_synchronizer_properties() -> void:
	var troop := TROOP_SCENES["troop_grunt"].instantiate() as Node2D
	_mount_node(troop)

	var synchronizer := troop.get_node_or_null("Synchronizer") as MultiplayerSynchronizer
	assert_that(synchronizer).is_not_null()\
		.override_failure_message("Expected troop scene to include a MultiplayerSynchronizer child")

	var config := synchronizer.replication_config
	assert_that(config).is_not_null()\
		.override_failure_message("Expected troop synchronizer to create a replication config at runtime")
	assert_bool(config.has_property(NodePath(":position"))).is_true()\
		.override_failure_message("Expected troop synchronizer to replicate position")
	assert_bool(config.has_property(NodePath(":current_health"))).is_true()\
		.override_failure_message("Expected troop synchronizer to replicate current_health")
	assert_bool(config.has_property(NodePath(":unit_id"))).is_true()\
		.override_failure_message("Expected troop synchronizer to replicate unit_id")

	_clear_node(troop)

func test_game_scene_configures_multiplayer_spawner_for_troops() -> void:
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	_mount_node(game)

	var spawner := game.get_node_or_null("TroopSpawner") as MultiplayerSpawner
	assert_that(spawner).is_not_null()\
		.override_failure_message("Expected game scene to include a MultiplayerSpawner")
	assert_str(str(spawner.spawn_path)).is_equal("../Units")\
		.override_failure_message("Expected troop spawner spawn_path to target the Units node")

	var spawnable_scenes := spawner.get_spawnable_scene_count()
	assert_int(spawnable_scenes).is_greater_equal(6)\
		.override_failure_message("Expected troop spawner to register all troop scenes and the debug test unit")

	_clear_node(game)

func test_damage_uses_flat_defense_with_minimum_one() -> void:
	var harness := CombatHarness.new()
	_mount_node(harness)

	var target: Node2D = harness.add_troop("troop_brute", 1, GameState.Team.RIGHT, Vector2.ZERO)
	var start_health: int = target.current_health
	target.take_damage(3)

	assert_int(target.current_health).is_equal(start_health - 1)\
		.override_failure_message("Expected defense to reduce damage but still apply minimum 1")
	assert_bool(target.get_health_bar_root().visible).is_true()\
		.override_failure_message("Expected damaged troops to show a health bar")
	assert_float(_health_bar_fill_width(target)).is_equal_approx(
		HEALTH_BAR_WIDTH * float(target.current_health) / float(target.max_health),
		0.01
	)\
		.override_failure_message("Expected health bar width to reflect remaining health")

	_clear_node(harness)

func test_health_bar_sync_updates_visibility_and_fill_ratio() -> void:
	var harness := CombatHarness.new()
	_mount_node(harness)

	var troop: Node2D = harness.add_troop("troop_grunt", 1, GameState.Team.LEFT, Vector2.ZERO)
	assert_bool(troop.get_health_bar_root().visible).is_false()\
		.override_failure_message("Expected full-health troops to hide the health bar")

	harness.sync_unit_health(1, 4)

	assert_int(troop.current_health).is_equal(4)
	assert_bool(troop.get_health_bar_root().visible).is_true()\
		.override_failure_message("Expected synced damaged health to show the health bar")
	assert_float(_health_bar_fill_width(troop)).is_equal_approx(HEALTH_BAR_WIDTH * 0.4, 0.01)\
		.override_failure_message("Expected synced health bar width to match current health")

	harness.sync_unit_health(1, troop.max_health)

	assert_bool(troop.get_health_bar_root().visible).is_false()\
		.override_failure_message("Expected restoring full health to hide the health bar")

	_clear_node(harness)

func test_health_bar_updates_when_health_properties_change_directly() -> void:
	var harness := CombatHarness.new()
	_mount_node(harness)

	var troop: Node2D = harness.add_troop("troop_grunt", 1, GameState.Team.LEFT, Vector2.ZERO)

	troop.current_health = 3

	assert_bool(troop.get_health_bar_root().visible).is_true()\
		.override_failure_message("Expected direct current_health changes to update the health bar")
	assert_float(_health_bar_fill_width(troop)).is_equal_approx(HEALTH_BAR_WIDTH * 0.3, 0.01)\
		.override_failure_message("Expected direct current_health changes to update the fill width")

	troop.max_health = 5

	assert_float(_health_bar_fill_width(troop)).is_equal_approx(HEALTH_BAR_WIDTH * 0.6, 0.01)\
		.override_failure_message("Expected direct max_health changes to recalculate the fill width")

	_clear_node(harness)

func test_health_bar_stays_above_body_for_multiple_troop_sizes() -> void:
	var harness := CombatHarness.new()
	_mount_node(harness)

	var grunt: Node2D = harness.add_troop("troop_grunt", 1, GameState.Team.LEFT, Vector2.ZERO)
	var brute: Node2D = harness.add_troop("troop_brute", 2, GameState.Team.LEFT, Vector2(32, 0))
	var troops: Array[Node2D] = [grunt, brute]

	await get_tree().process_frame

	for troop in troops:
		var health_bar: Node2D = troop.get_health_bar_root()
		var body: Polygon2D = troop.body
		var top_y: float = body.position.y + body.polygon[0].y
		for point in body.polygon:
			top_y = minf(top_y, body.position.y + point.y)
		assert_float(health_bar.position.y).is_less(top_y)\
			.override_failure_message("Expected health bar for %s to sit above the body" % troop.item_id)

	assert_float(brute.get_health_bar_root().position.y).is_less(grunt.get_health_bar_root().position.y)\
		.override_failure_message("Expected taller troops to place the health bar higher than shorter troops")

	_clear_node(harness)

func test_enemy_troops_attack_until_one_dies_and_survivor_resumes_marching() -> void:
	var harness := CombatHarness.new()
	_mount_node(harness)

	var left: Node2D = harness.add_troop("troop_brute", 1, GameState.Team.LEFT, Vector2(0, 0))
	var right: Node2D = harness.add_troop("troop_grunt", 2, GameState.Team.RIGHT, Vector2(8, 0))

	for _i in range(3):
		left._physics_process(left.attack_interval)
		right._physics_process(right.attack_interval)

	await get_tree().process_frame

	assert_bool(is_instance_valid(harness.get_unit_by_id(2))).is_false()\
		.override_failure_message("Expected the grunt to die after repeated combat")

	var start_x: float = left.position.x
	left._physics_process(0.5)
	assert_float(left.position.x).is_greater(start_x)\
		.override_failure_message("Expected the surviving left troop to resume marching right")

	_clear_node(harness)

func test_friendly_troops_do_not_attack_each_other() -> void:
	var harness := CombatHarness.new()
	_mount_node(harness)

	var left_a: Node2D = harness.add_troop("troop_grunt", 1, GameState.Team.LEFT, Vector2(0, 0))
	var left_b: Node2D = harness.add_troop("troop_grunt", 2, GameState.Team.LEFT, Vector2(8, 0))
	var health_a: int = left_a.current_health
	var health_b: int = left_b.current_health
	var start_x: float = left_a.position.x

	left_a._physics_process(left_a.attack_interval)
	left_b._physics_process(left_b.attack_interval)

	assert_int(left_a.current_health).is_equal(health_a)
	assert_int(left_b.current_health).is_equal(health_b)
	assert_float(left_a.position.x).is_greater(start_x)\
		.override_failure_message("Expected friendly troops to keep marching instead of attacking")

	_clear_node(harness)

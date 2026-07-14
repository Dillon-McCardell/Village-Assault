## Feature: custom-test-sessions
## Validation and runtime coverage for deterministic map and troop scenarios.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const EXAMPLE_SCENARIO: String = "res://test_sessions/fog_cavern.json"

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
	get_tree().current_scene = null

func test_example_scenario_loads_and_exposes_world_settings() -> void:
	var configurator := TestSessionConfigurator.new()
	var scenario := configurator.load_scenario(EXAMPLE_SCENARIO)

	assert_array(configurator.errors).is_empty()
	assert_bool(scenario.is_empty()).is_false()
	var settings := configurator.get_world_settings(scenario)
	assert_int(settings["width"]).is_equal(48)
	assert_int(settings["height"]).is_equal(24)
	assert_int(settings["seed"]).is_equal(424242)
	assert_array(configurator.get_troop_unit_ids(scenario)).is_equal([101, 102, 201, 202])

func test_automatic_unit_ids_avoid_explicit_ids() -> void:
	var configurator := TestSessionConfigurator.new()
	var scenario := {
		"troops": [
			{"type": "troop_grunt", "team": "left", "tile": [1, 1]},
			{"type": "troop_scout", "team": "right", "tile": [2, 1], "unit_id": 10001},
		],
	}

	assert_array(configurator.get_troop_unit_ids(scenario)).is_equal([10002, 10001])

func test_validation_reports_out_of_bounds_shapes_and_duplicate_units() -> void:
	var configurator := TestSessionConfigurator.new()
	var scenario := {
		"map": {
			"width": 12,
			"height": 12,
			"surface_y": 6,
			"carve": {
				"rects": [{"position": [10, 10], "size": [4, 3]}],
			},
		},
		"troops": [
			{"type": "troop_scout", "team": "left", "tile": [4, 5], "unit_id": 10},
			{"type": "unknown", "team": "blue", "tile": [20, 5], "unit_id": 10},
		],
	}

	var validation_errors := configurator.validate_scenario(scenario)
	var message := "; ".join(validation_errors)

	assert_bool(message.contains("map.carve.rects[0] must fit inside the map")).is_true()
	assert_bool(message.contains("troops[1].type is not a supported troop")).is_true()
	assert_bool(message.contains("troops[1].team must be left or right")).is_true()
	assert_bool(message.contains("troops[1].tile must be inside the map")).is_true()
	assert_bool(message.contains("troops[1].unit_id duplicates 10")).is_true()

func test_runtime_configuration_applies_map_troop_payload_and_camera() -> void:
	_reset_runtime_state()
	GameState.local_team = GameState.Team.LEFT
	GameState.set_world_settings(16, 16, 12345)
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	var configurator := TestSessionConfigurator.new()
	var scenario := {
		"map": {
			"width": 16,
			"height": 16,
			"seed": 12345,
			"surface_y": 3,
			"carve": {
				"rects": [{"position": [4, 8], "size": [6, 4]}],
				"lines": [{"from": [4, 3], "to": [4, 9], "thickness": 1}],
			},
			"fill": {"tiles": [[6, 10]]},
		},
		"troops": [{
			"type": "troop_scout",
			"team": "left",
			"tile": [5, 11],
			"unit_id": 701,
			"frozen": true,
			"spawn_payload": {"vision_radius_tiles": 6.0},
		}],
		"camera": {"default": {"tile": [8, 10], "zoom": 1.75}},
	}

	assert_array(configurator.validate_scenario(scenario)).is_empty()
	assert_bool(configurator.apply_terrain(game, scenario)).is_true()
	var territory: TerritoryManager = game.territory_manager
	assert_bool(territory.has_ground_at_tile(Vector2i(0, 2))).is_false()
	assert_bool(territory.has_ground_at_tile(Vector2i(0, 3))).is_true()
	assert_bool(territory.has_ground_at_tile(Vector2i(4, 8))).is_false()
	assert_bool(territory.is_underground_tile(Vector2i(4, 8))).is_true()
	assert_bool(territory.has_ground_at_tile(Vector2i(6, 10))).is_true()
	assert_bool(territory.is_underground_tile(Vector2i(6, 10))).is_false()

	var spawned_ids := configurator.spawn_troops(game, scenario)
	assert_array(spawned_ids).is_equal([701])
	var troop: Node2D = game.get_unit_by_id(701) as Node2D
	assert_that(troop).is_not_null()
	assert_int(troop.get_team()).is_equal(GameState.Team.LEFT)
	assert_vector(troop.position).is_equal(
		territory.troop_stand_tile_to_world_position(Vector2i(5, 11), 1)
	)
	assert_bool(troop.is_physics_processing()).is_false()
	assert_float(troop.get_node("VisionComponent").vision_radius_tiles).is_equal(6.0)

	configurator.apply_camera(game, scenario, "host")
	var camera := game.get_node("Camera2D") as Camera2D
	assert_vector(camera.position).is_equal(territory.tile_to_world_center(Vector2i(8, 10)))
	assert_vector(camera.zoom).is_equal(Vector2(1.75, 1.75))

	_clear_node(game)
	_reset_runtime_state()

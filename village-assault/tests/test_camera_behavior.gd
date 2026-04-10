## Feature: camera-behavior
## Scene-level tests for camera anchoring behavior.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")

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

func test_local_state_money_updates_do_not_reset_camera_position() -> void:
	_reset_runtime_state()
	GameState.local_team = GameState.Team.LEFT
	GameState.local_money = 100

	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	game._on_local_state_updated(GameState.local_team, GameState.local_money)

	var camera := game.get_node("Camera2D") as Camera2D
	var anchored_position: Vector2 = camera.position
	var moved_position := anchored_position + Vector2(96, -48)
	camera.position = moved_position

	game._on_local_state_updated(GameState.local_team, GameState.local_money + 5)

	assert_vector(camera.position).is_equal(moved_position)\
		.override_failure_message("Expected local state money updates to preserve the current camera position")

	_clear_node(game)
	_reset_runtime_state()

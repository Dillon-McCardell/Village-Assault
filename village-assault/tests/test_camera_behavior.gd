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

func test_camera_drag_uses_right_mouse_button() -> void:
	_reset_runtime_state()
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	var camera := game.get_node("Camera2D") as Camera2D
	var start_position := camera.global_position

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(320, 240)
	camera._input(right_press)

	var right_motion := InputEventMouseMotion.new()
	right_motion.position = Vector2(360, 260)
	right_motion.relative = Vector2(40, 20)
	right_motion.button_mask = 1 << (MOUSE_BUTTON_RIGHT - 1)
	camera._input(right_motion)
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	right_release.position = Vector2(360, 260)
	camera._input(right_release)

	var after_right_drag := camera.global_position
	assert_vector(after_right_drag).is_not_equal(start_position)

	var left_press := InputEventMouseButton.new()
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	left_press.position = Vector2(320, 240)
	camera._input(left_press)

	var left_motion := InputEventMouseMotion.new()
	left_motion.position = Vector2(380, 280)
	left_motion.relative = Vector2(20, 20)
	left_motion.button_mask = 1 << (MOUSE_BUTTON_LEFT - 1)
	camera._input(left_motion)
	var left_release := InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	left_release.position = Vector2(380, 280)
	camera._input(left_release)

	assert_vector(camera.global_position).is_equal(after_right_drag)

	_clear_node(game)
	_reset_runtime_state()

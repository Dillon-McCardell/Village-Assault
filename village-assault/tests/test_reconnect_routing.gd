## Feature: reconnect-routing
## Tests for scene redirects and restored reconnect state.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LOBBY_SCENE: PackedScene = preload("res://scenes/lobby.tscn")

func _reset_runtime_state() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")

func _mount_node(node: Node) -> void:
	get_tree().root.add_child(node)
	get_tree().current_scene = node

func _clear_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	get_tree().current_scene = null

func _await_scene_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func test_try_restore_peer_preserves_local_state_and_world_settings() -> void:
	_reset_runtime_state()
	GameState.set_world_settings(96, 28, 424242)
	GameState._inactive_peers[17] = {
		"team": GameState.Team.RIGHT,
		"money": 275,
		"disconnect_time": Time.get_ticks_msec(),
	}
	GameState._disconnected_peer_id = 17

	var restored := GameState.try_restore_peer(1)

	assert_bool(restored).is_true()
	assert_int(GameState.local_team).is_equal(GameState.Team.RIGHT)
	assert_int(GameState.local_money).is_equal(275)
	assert_int(GameState.map_width).is_equal(96)
	assert_int(GameState.map_height).is_equal(28)
	assert_int(GameState.map_seed).is_equal(424242)
	assert_bool(GameState._inactive_peers.is_empty()).is_true()

	_reset_runtime_state()

func test_receive_scene_redirect_loads_game_scene() -> void:
	_reset_runtime_state()
	_mount_node(Control.new())

	GameState._receive_scene_redirect("game")
	await _await_scene_change()

	assert_str(get_tree().current_scene.scene_file_path).is_equal("res://scenes/game.tscn")
	assert_str(GameState.current_scene).is_equal("game")

	_clear_current_scene()
	_reset_runtime_state()

func test_receive_scene_redirect_loads_lobby_scene() -> void:
	_reset_runtime_state()
	_mount_node(Control.new())

	GameState._receive_scene_redirect("lobby")
	await _await_scene_change()

	assert_str(get_tree().current_scene.scene_file_path).is_equal("res://scenes/lobby.tscn")
	assert_str(GameState.current_scene).is_equal("lobby")

	_clear_current_scene()
	_reset_runtime_state()

func test_receive_scene_redirect_falls_back_to_boot_menu() -> void:
	_reset_runtime_state()
	_mount_node(Control.new())

	GameState._receive_scene_redirect("unknown_scene")
	await _await_scene_change()

	assert_str(get_tree().current_scene.scene_file_path).is_equal("res://scenes/boot_menu.tscn")
	assert_str(GameState.current_scene).is_equal("boot_menu")

	_clear_current_scene()
	_reset_runtime_state()

func test_receive_scene_redirect_skips_reload_when_scene_matches() -> void:
	_reset_runtime_state()
	var lobby := LOBBY_SCENE.instantiate()
	_mount_node(lobby)
	await _await_scene_change()
	var original_instance_id := lobby.get_instance_id()

	GameState._receive_scene_redirect("lobby")
	await _await_scene_change()

	assert_int(get_tree().current_scene.get_instance_id()).is_equal(original_instance_id)

	_clear_current_scene()
	_reset_runtime_state()

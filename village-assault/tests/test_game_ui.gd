## Feature: game-ui
## Scene-level tests for disconnect and pause UI behavior.
extends GdUnitTestSuite

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const DISCONNECT_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/disconnect_overlay.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")

func _reset_runtime_state() -> void:
	NetworkManager.stop_auto_reconnect()
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")
	get_tree().paused = false

func _mount_node(node: Node) -> void:
	get_tree().root.add_child(node)
	get_tree().current_scene = node

func _clear_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	get_tree().current_scene = null
	get_tree().paused = false

func _start_host_game() -> Node:
	_reset_runtime_state()
	NetworkManager.host(NetworkManager.DEFAULT_PORT)
	var game := GAME_SCENE.instantiate()
	_mount_node(game)
	return game

func _overlay_message(scene: Node) -> String:
	return scene.get_node("DisconnectOverlay/Background/CenterContainer/VBoxContainer/MessageLabel").text

func _overlay_visible(scene: Node) -> bool:
	return scene.get_node("DisconnectOverlay/Background").visible

func _pause_message(scene: Node) -> String:
	return scene.get_node("PauseMenu/Background/CenterContainer/VBoxContainer/MessageLabel").text

func _pause_button_visible(scene: Node, button_name: String) -> bool:
	return scene.get_node("PauseMenu/Background/CenterContainer/VBoxContainer/ButtonContainer/%s" % button_name).visible

func test_host_disconnected_branch_shows_client_disconnected_message() -> void:
	var game := _start_host_game()

	game._on_peer_disconnected_graceful(2)

	assert_bool(get_tree().paused).is_true()
	assert_bool(_overlay_visible(game)).is_true()
	assert_str(_overlay_message(game)).is_equal("The Client disconnected.")

	_clear_node(game)
	_reset_runtime_state()

func test_left_branches_show_left_messages() -> void:
	var game := _start_host_game()

	game._peer_left_intentionally = true
	game._on_peer_disconnected_graceful(2)
	assert_str(_overlay_message(game)).is_equal("The Client has left the game.")

	game._peer_left_intentionally = true
	game._on_server_disconnected_game()
	assert_str(_overlay_message(game)).is_equal("The Host has left the game.")

	_clear_node(game)
	_reset_runtime_state()

func test_local_disconnect_shows_self_disconnect_message_and_pauses() -> void:
	var game := _start_host_game()

	game._on_local_disconnected_game()

	assert_bool(get_tree().paused).is_true()
	assert_bool(_overlay_visible(game)).is_true()
	assert_str(_overlay_message(game)).is_equal("You have disconnected.\nReconnecting...")

	_clear_node(game)
	_reset_runtime_state()

func test_reconnect_success_hides_overlay_and_unpauses() -> void:
	var game := _start_host_game()
	game._on_local_disconnected_game()

	game._on_reconnect_succeeded_game()

	assert_bool(get_tree().paused).is_false()
	assert_bool(_overlay_visible(game)).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_local_pause_shows_actionable_buttons() -> void:
	var game := _start_host_game()

	game._set_paused(true, 1)

	assert_bool(get_tree().paused).is_true()
	assert_str(_pause_message(game)).is_equal("Game Paused")
	assert_bool(_pause_button_visible(game, "SettingsButton")).is_true()
	assert_bool(_pause_button_visible(game, "MainMenuButton")).is_true()
	assert_bool(_pause_button_visible(game, "BackButton")).is_true()

	_clear_node(game)
	_reset_runtime_state()

func test_remote_pause_shows_read_only_state() -> void:
	var game := _start_host_game()

	game._set_paused(true, 2)

	assert_bool(get_tree().paused).is_true()
	assert_str(_pause_message(game)).is_equal("The other player has paused the game.")
	assert_bool(_pause_button_visible(game, "SettingsButton")).is_false()
	assert_bool(_pause_button_visible(game, "MainMenuButton")).is_false()
	assert_bool(_pause_button_visible(game, "BackButton")).is_false()

	_clear_node(game)
	_reset_runtime_state()

func test_disconnect_overlay_messages_and_visibility() -> void:
	_reset_runtime_state()
	var overlay := DISCONNECT_OVERLAY_SCENE.instantiate()
	_mount_node(overlay)

	overlay.show_self_disconnected()
	assert_bool(overlay.is_overlay_visible()).is_true()
	assert_str(overlay.get_message_text()).is_equal("You have disconnected.\nReconnecting...")

	overlay.show_client_left()
	assert_str(overlay.get_message_text()).is_equal("The Client has left the game.")

	overlay.show_host_disconnected()
	assert_str(overlay.get_message_text()).is_equal("The Host disconnected.")

	overlay.hide_overlay()
	assert_bool(overlay.is_overlay_visible()).is_false()

	_clear_node(overlay)
	_reset_runtime_state()

func test_pause_menu_message_and_button_visibility_modes() -> void:
	_reset_runtime_state()
	var pause_menu := PAUSE_MENU_SCENE.instantiate()
	_mount_node(pause_menu)

	pause_menu.show_pause_menu()
	assert_str(pause_menu.get_node("Background/CenterContainer/VBoxContainer/MessageLabel").text).is_equal("Game Paused")
	assert_bool(pause_menu.get_node("Background/CenterContainer/VBoxContainer/ButtonContainer/SettingsButton").visible).is_true()
	assert_bool(pause_menu.get_node("Background/CenterContainer/VBoxContainer/ButtonContainer/MainMenuButton").visible).is_true()
	assert_bool(pause_menu.get_node("Background/CenterContainer/VBoxContainer/ButtonContainer/BackButton").visible).is_true()

	pause_menu.show_remote_paused()
	assert_str(pause_menu.get_node("Background/CenterContainer/VBoxContainer/MessageLabel").text).is_equal("The other player has paused the game.")
	assert_bool(pause_menu.get_node("Background/CenterContainer/VBoxContainer/ButtonContainer/SettingsButton").visible).is_false()
	assert_bool(pause_menu.get_node("Background/CenterContainer/VBoxContainer/ButtonContainer/MainMenuButton").visible).is_false()
	assert_bool(pause_menu.get_node("Background/CenterContainer/VBoxContainer/ButtonContainer/BackButton").visible).is_false()

	pause_menu.hide_menu()
	assert_bool(pause_menu.get_node("Background").visible).is_false()

	_clear_node(pause_menu)
	_reset_runtime_state()

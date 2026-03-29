## Feature: passive-income
## Tests for host-authoritative passive income during active gameplay.
extends GdUnitTestSuite


func _reset_runtime_state() -> void:
	NetworkManager.shutdown()
	GameState.reset_all()
	GameState.set_current_scene("boot_menu")


func _start_host_session() -> void:
	_reset_runtime_state()
	NetworkManager.host(NetworkManager.DEFAULT_PORT)
	GameState.set_current_scene("game")


func test_passive_income_increases_host_money_by_one_per_tick() -> void:
	_start_host_session()

	assert_bool(multiplayer.is_server()).is_true()
	assert_int(GameState.get_money_for_peer(1)).is_equal(GameState.STARTING_MONEY)

	GameState._on_passive_income_timer_timeout()

	assert_int(GameState.get_money_for_peer(1)).is_equal(
		GameState.STARTING_MONEY + GameState.PASSIVE_INCOME_AMOUNT
	)
	assert_int(GameState.local_money).is_equal(
		GameState.STARTING_MONEY + GameState.PASSIVE_INCOME_AMOUNT
	)

	_reset_runtime_state()


func test_passive_income_accumulates_across_multiple_ticks() -> void:
	_start_host_session()

	for _i in range(3):
		GameState._on_passive_income_timer_timeout()

	assert_int(GameState.get_money_for_peer(1)).is_equal(
		GameState.STARTING_MONEY + (GameState.PASSIVE_INCOME_AMOUNT * 3)
	)
	assert_int(GameState.local_money).is_equal(
		GameState.STARTING_MONEY + (GameState.PASSIVE_INCOME_AMOUNT * 3)
	)

	_reset_runtime_state()


func test_passive_income_skips_inactive_peers() -> void:
	_start_host_session()

	GameState._inactive_peers[2] = {
		"team": GameState.Team.RIGHT,
		"money": 250,
		"disconnect_time": Time.get_ticks_msec(),
	}

	GameState._on_passive_income_timer_timeout()

	assert_int(GameState.get_money_for_peer(1)).is_equal(
		GameState.STARTING_MONEY + GameState.PASSIVE_INCOME_AMOUNT
	)
	assert_int(GameState._inactive_peers[2]["money"]).is_equal(250)

	_reset_runtime_state()


func test_passive_income_does_not_run_outside_game_scene() -> void:
	_start_host_session()
	GameState.set_current_scene("lobby")

	GameState._on_passive_income_timer_timeout()

	assert_int(GameState.get_money_for_peer(1)).is_equal(GameState.STARTING_MONEY)
	assert_int(GameState.local_money).is_equal(GameState.STARTING_MONEY)

	_reset_runtime_state()


func test_set_current_scene_starts_and_stops_passive_income_timer() -> void:
	_start_host_session()

	assert_bool(GameState._passive_income_timer.is_stopped()).is_false()

	GameState.set_current_scene("lobby")
	assert_bool(GameState._passive_income_timer.is_stopped()).is_true()

	GameState.set_current_scene("game")
	assert_bool(GameState._passive_income_timer.is_stopped()).is_false()

	_reset_runtime_state()

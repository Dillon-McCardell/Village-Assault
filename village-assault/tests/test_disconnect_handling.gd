## Feature: player-disconnect-handling
## Property-based tests for the disconnect/reconnect handling system.
## Requires GdUnit4 addon: https://github.com/MikeSchulze/gdUnit4
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Clears all peer and inactive-peer state from GameState so each iteration
## starts from a clean slate.
func _clear_game_state() -> void:
	GameState._peer_team.clear()
	GameState._peer_money.clear()
	GameState._inactive_peers.clear()
	GameState._disconnected_peer_id = -1
	# Drain spawn queue just in case
	while not GameState._spawn_queue.is_empty():
		GameState.dequeue_spawn()


# ---------------------------------------------------------------------------
# Property 1: State preservation on disconnect
# Feature: player-disconnect-handling, Property 1: State preservation on disconnect
# Validates: Requirements 1.1, 1.2
# ---------------------------------------------------------------------------
func test_state_preservation_on_disconnect() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10001

	for _i in range(100):
		_clear_game_state()

		var peer_id: int = rng.randi_range(2, 99999)
		var team: int = [GameState.Team.LEFT, GameState.Team.RIGHT][rng.randi() % 2]
		var money: int = rng.randi_range(0, 10000)

		GameState._peer_team[peer_id] = team
		GameState._peer_money[peer_id] = money
		GameState._on_peer_disconnected(peer_id)

		assert_bool(GameState._inactive_peers.has(peer_id)).is_true()\
			.override_failure_message(
				"Iteration %d: _inactive_peers should contain peer %d after disconnect" % [_i, peer_id])

		var record: Dictionary = GameState._inactive_peers[peer_id]
		assert_int(record["team"]).is_equal(team)\
			.override_failure_message(
				"Iteration %d: inactive team should be %d but got %d" % [_i, team, record["team"]])
		assert_int(record["money"]).is_equal(money)\
			.override_failure_message(
				"Iteration %d: inactive money should be %d but got %d" % [_i, money, record["money"]])

		assert_bool(GameState._peer_team.has(peer_id)).is_false()\
			.override_failure_message(
				"Iteration %d: _peer_team should not contain peer %d after disconnect" % [_i, peer_id])
		assert_bool(GameState._peer_money.has(peer_id)).is_false()\
			.override_failure_message(
				"Iteration %d: _peer_money should not contain peer %d after disconnect" % [_i, peer_id])

	_clear_game_state()


# ---------------------------------------------------------------------------
# Property 2: Team reservation during inactive state
# Feature: player-disconnect-handling, Property 2: Team reservation during inactive state
# Validates: Requirements 1.3
# ---------------------------------------------------------------------------
func test_team_reservation_during_inactive_state() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20002

	for _i in range(100):
		_clear_game_state()

		var inactive_peer_id: int = rng.randi_range(2, 99999)
		var inactive_team: int = [GameState.Team.LEFT, GameState.Team.RIGHT][rng.randi() % 2]
		var inactive_money: int = rng.randi_range(0, 10000)

		GameState._inactive_peers[inactive_peer_id] = {
			"team": inactive_team,
			"money": inactive_money,
			"disconnect_time": Time.get_ticks_msec(),
		}

		var count_for_inactive_team: int = GameState._count_team(inactive_team)
		assert_int(count_for_inactive_team).is_greater_equal(1)\
			.override_failure_message(
				"Iteration %d: _count_team(%d) should count the inactive peer (got %d)" % [
					_i, inactive_team, count_for_inactive_team])

		var opposite_team: int = GameState.Team.RIGHT if inactive_team == GameState.Team.LEFT else GameState.Team.LEFT
		var count_opposite: int = GameState._count_team(opposite_team)
		assert_int(count_opposite).is_less(count_for_inactive_team)\
			.override_failure_message(
				"Iteration %d: opposite team count (%d) should be less than inactive team count (%d)" % [
					_i, count_opposite, count_for_inactive_team])

	_clear_game_state()


# ---------------------------------------------------------------------------
# Property 3: State restoration round-trip
# Feature: player-disconnect-handling, Property 3: State restoration round-trip
# Validates: Requirements 4.1, 4.2
# ---------------------------------------------------------------------------
func test_state_restoration_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 30003

	for _i in range(100):
		_clear_game_state()

		var old_peer_id: int = rng.randi_range(2, 99999)
		var team: int = [GameState.Team.LEFT, GameState.Team.RIGHT][rng.randi() % 2]
		var money: int = rng.randi_range(0, 10000)
		var new_peer_id: int = 1

		GameState._inactive_peers[old_peer_id] = {
			"team": team,
			"money": money,
			"disconnect_time": Time.get_ticks_msec(),
		}
		GameState._disconnected_peer_id = old_peer_id

		var restored: bool = GameState.try_restore_peer(new_peer_id)
		assert_bool(restored).is_true()\
			.override_failure_message(
				"Iteration %d: try_restore_peer should return true" % _i)

		assert_int(GameState._peer_team.get(new_peer_id, GameState.Team.NONE)).is_equal(team)\
			.override_failure_message(
				"Iteration %d: restored team should be %d" % [_i, team])
		assert_int(GameState._peer_money.get(new_peer_id, -1)).is_equal(money)\
			.override_failure_message(
				"Iteration %d: restored money should be %d" % [_i, money])

		assert_bool(GameState._inactive_peers.is_empty()).is_true()\
			.override_failure_message(
				"Iteration %d: _inactive_peers should be empty after restore" % _i)

	_clear_game_state()


# ---------------------------------------------------------------------------
# Property 4: Fresh state after clearing inactive peer
# Feature: player-disconnect-handling, Property 4: Fresh state after clearing inactive peer
# Validates: Requirements 4.4
# ---------------------------------------------------------------------------
func test_fresh_state_after_clear() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40004

	for _i in range(100):
		_clear_game_state()

		var old_peer_id: int = rng.randi_range(2, 99999)
		var old_team: int = [GameState.Team.LEFT, GameState.Team.RIGHT][rng.randi() % 2]
		var old_money: int = rng.randi_range(0, 10000)

		GameState._inactive_peers[old_peer_id] = {
			"team": old_team,
			"money": old_money,
			"disconnect_time": Time.get_ticks_msec(),
		}
		GameState._disconnected_peer_id = old_peer_id

		GameState.clear_inactive_peer(old_peer_id)

		assert_bool(GameState._inactive_peers.is_empty()).is_true()\
			.override_failure_message(
				"Iteration %d: _inactive_peers should be empty after clear_inactive_peer" % _i)

		var new_peer_id: int = rng.randi_range(2, 99999)
		GameState._peer_team[new_peer_id] = GameState.Team.LEFT if GameState._count_team(GameState.Team.LEFT) <= GameState._count_team(GameState.Team.RIGHT) else GameState.Team.RIGHT
		GameState._peer_money[new_peer_id] = GameState.STARTING_MONEY

		assert_int(GameState._peer_money[new_peer_id]).is_equal(GameState.STARTING_MONEY)\
			.override_failure_message(
				"Iteration %d: new peer should get STARTING_MONEY (%d) not old money (%d)" % [
					_i, GameState.STARTING_MONEY, old_money])

	_clear_game_state()


# ---------------------------------------------------------------------------
# Property 5: State erasure on clear
# Feature: player-disconnect-handling, Property 5: State erasure on clear
# Validates: Requirements 5.2
# ---------------------------------------------------------------------------
func test_state_erasure_on_clear() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 50005

	for _i in range(100):
		_clear_game_state()

		var peer_id: int = rng.randi_range(2, 99999)
		var team: int = [GameState.Team.LEFT, GameState.Team.RIGHT][rng.randi() % 2]
		var money: int = rng.randi_range(0, 10000)

		GameState._inactive_peers[peer_id] = {
			"team": team,
			"money": money,
			"disconnect_time": Time.get_ticks_msec(),
		}
		GameState._disconnected_peer_id = peer_id

		GameState.clear_inactive_peer(peer_id)

		assert_bool(GameState._inactive_peers.is_empty()).is_true()\
			.override_failure_message(
				"Iteration %d: _inactive_peers should be empty after clear" % _i)
		assert_int(GameState._disconnected_peer_id).is_equal(-1)\
			.override_failure_message(
				"Iteration %d: _disconnected_peer_id should be -1 after clear" % _i)

	_clear_game_state()


# ---------------------------------------------------------------------------
# Property 6: Pause/unpause round-trip
# Feature: player-disconnect-handling, Property 6: Pause/unpause round-trip
# Validates: Requirements 7.1, 7.2
# ---------------------------------------------------------------------------
func test_pause_unpause_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70007

	for _i in range(100):
		_clear_game_state()

		var peer_id: int = rng.randi_range(2, 99999)
		var team: int = [GameState.Team.LEFT, GameState.Team.RIGHT][rng.randi() % 2]
		var money: int = rng.randi_range(0, 10000)

		GameState._peer_team[peer_id] = team
		GameState._peer_money[peer_id] = money

		get_tree().paused = true
		assert_bool(get_tree().paused).is_true()\
			.override_failure_message(
				"Iteration %d: tree should be paused after disconnect (team=%d, money=%d)" % [_i, team, money])

		get_tree().paused = false
		assert_bool(get_tree().paused).is_false()\
			.override_failure_message(
				"Iteration %d: tree should be unpaused after reconnect (team=%d, money=%d)" % [_i, team, money])

	_clear_game_state()
	get_tree().paused = false

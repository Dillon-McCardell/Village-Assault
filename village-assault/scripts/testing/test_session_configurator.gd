class_name TestSessionConfigurator
extends RefCounted

const VALID_TROOP_TYPES: Array[String] = [
	"troop_brute",
	"troop_grunt",
	"troop_miner",
	"troop_ranger",
	"troop_scout",
]
const VALID_TEAMS: Array[String] = ["left", "right"]

var errors: PackedStringArray = []

func load_scenario(path: String) -> Dictionary:
	errors.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open scenario: %s" % path)
		return {}
	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	if parse_result != OK:
		errors.append(
			"Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not parser.data is Dictionary:
		errors.append("Scenario root must be a JSON object")
		return {}
	var scenario: Dictionary = parser.data
	errors = validate_scenario(scenario)
	return scenario if errors.is_empty() else {}

func validate_scenario(scenario: Dictionary) -> PackedStringArray:
	var validation_errors := PackedStringArray()
	var map_value: Variant = scenario.get("map", null)
	if not map_value is Dictionary:
		validation_errors.append("map must be an object")
		return validation_errors
	var map_config: Dictionary = map_value
	var width := int(map_config.get("width", GameState.DEFAULT_MAP_WIDTH))
	var height := int(map_config.get("height", GameState.DEFAULT_MAP_HEIGHT))
	if width <= 0:
		validation_errors.append("map.width must be greater than zero")
	if height <= 1:
		validation_errors.append("map.height must be greater than one")
	_validate_surface(map_config, width, height, validation_errors)
	_validate_edit_group(map_config.get("carve", {}), "map.carve", width, height, validation_errors)
	_validate_edit_group(map_config.get("fill", {}), "map.fill", width, height, validation_errors)
	_validate_troops(scenario.get("troops", []), width, height, validation_errors)
	_validate_camera(scenario.get("camera", {}), width, height, validation_errors)
	return validation_errors

func get_world_settings(scenario: Dictionary) -> Dictionary:
	var map_config: Dictionary = scenario.get("map", {})
	return {
		"width": int(map_config.get("width", GameState.DEFAULT_MAP_WIDTH)),
		"height": int(map_config.get("height", GameState.DEFAULT_MAP_HEIGHT)),
		"seed": int(map_config.get("seed", GameState.DEFAULT_MAP_SEED)),
	}

func apply_terrain(game: Node, scenario: Dictionary) -> bool:
	var territory := game.get_node_or_null("TerritoryManager") as TerritoryManager
	if territory == null:
		errors = PackedStringArray(["Game scene has no TerritoryManager"])
		return false
	var map_config: Dictionary = scenario.get("map", {})
	var surface_heights := _build_surface_heights(map_config, territory.grid_width)
	var carved_tiles := _collect_edit_tiles(map_config.get("carve", {}), territory)
	var filled_tiles := _collect_edit_tiles(map_config.get("fill", {}), territory)
	return territory.apply_test_terrain_layout(surface_heights, carved_tiles, filled_tiles)

func spawn_troops(game: Node, scenario: Dictionary) -> Array[int]:
	var spawned_ids: Array[int] = []
	var territory := game.get_node_or_null("TerritoryManager") as TerritoryManager
	if territory == null:
		return spawned_ids
	var unit_ids := get_troop_unit_ids(scenario)
	var troops: Array = scenario.get("troops", [])
	for index in range(troops.size()):
		var raw_troop: Variant = troops[index]
		var troop: Dictionary = raw_troop
		var item_id := String(troop.get("type", ""))
		var unit_id := unit_ids[index]
		var team := _team_from_string(String(troop.get("team", "")))
		var tile := _vector2i_from_array(troop.get("tile", []))
		var spawn_payload: Dictionary = game.call("get_troop_spawn_payload", item_id)
		var payload_overrides: Dictionary = troop.get("spawn_payload", {})
		spawn_payload.merge(payload_overrides, true)
		var initial_position := territory.troop_stand_tile_to_world_position(tile, 1)
		game.call("spawn_unit", initial_position, team, item_id, unit_id, spawn_payload)
		var unit := game.call("get_unit_by_id", unit_id) as Node2D
		if unit == null:
			continue
		var width_tiles := maxi(1, int(unit.get("_troop_occupancy_width_tiles")))
		unit.position = territory.troop_stand_tile_to_world_position(tile, width_tiles)
		if bool(troop.get("frozen", false)):
			unit.set_physics_process(false)
			unit.set_meta("test_session_frozen", true)
		spawned_ids.append(unit_id)
	return spawned_ids

func get_troop_unit_ids(scenario: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var reserved_ids: Dictionary = {}
	var troops: Array = scenario.get("troops", [])
	for raw_troop in troops:
		var troop: Dictionary = raw_troop
		if troop.has("unit_id"):
			reserved_ids[int(troop["unit_id"])] = true
	var next_automatic_id := 10001
	for raw_troop in troops:
		var troop: Dictionary = raw_troop
		if troop.has("unit_id"):
			result.append(int(troop["unit_id"]))
			continue
		while reserved_ids.has(next_automatic_id):
			next_automatic_id += 1
		result.append(next_automatic_id)
		reserved_ids[next_automatic_id] = true
		next_automatic_id += 1
	return result

func apply_camera(game: Node, scenario: Dictionary, role: String) -> void:
	var camera := game.get_node_or_null("Camera2D") as Camera2D
	var territory := game.get_node_or_null("TerritoryManager") as TerritoryManager
	if camera == null or territory == null:
		return
	var camera_root: Dictionary = scenario.get("camera", {})
	var camera_config: Dictionary = camera_root.get("default", {})
	if camera_root.get(role) is Dictionary:
		camera_config = camera_config.duplicate(true)
		camera_config.merge(camera_root.get(role), true)
	if camera_config.has("tile"):
		camera.position = territory.tile_to_world_center(_vector2i_from_array(camera_config["tile"]))
	if camera_config.has("zoom"):
		var zoom_value := float(camera_config["zoom"])
		camera.zoom = Vector2(zoom_value, zoom_value)
	if game.has_method("_update_camera_limits"):
		game.call("_update_camera_limits")

func _validate_surface(
	map_config: Dictionary,
	width: int,
	height: int,
	validation_errors: PackedStringArray
) -> void:
	if map_config.has("surface_y") and map_config.has("surface_heights"):
		validation_errors.append("map may define surface_y or surface_heights, but not both")
	if map_config.has("surface_y"):
		var surface_y := int(map_config["surface_y"])
		if surface_y < 0 or surface_y >= height:
			validation_errors.append("map.surface_y must be inside the map")
	if not map_config.has("surface_heights"):
		return
	var heights: Variant = map_config["surface_heights"]
	if not heights is Array:
		validation_errors.append("map.surface_heights must be an array")
		return
	if heights.size() != width:
		validation_errors.append("map.surface_heights must contain exactly map.width entries")
	for index in range(heights.size()):
		var surface_y := int(heights[index])
		if surface_y < 0 or surface_y >= height:
			validation_errors.append("map.surface_heights[%d] must be inside the map" % index)

func _validate_edit_group(
	raw_group: Variant,
	path: String,
	width: int,
	height: int,
	validation_errors: PackedStringArray
) -> void:
	if not raw_group is Dictionary:
		validation_errors.append("%s must be an object" % path)
		return
	var group: Dictionary = raw_group
	_validate_point_list(group.get("tiles", []), "%s.tiles" % path, width, height, validation_errors)
	var rects: Variant = group.get("rects", [])
	if not rects is Array:
		validation_errors.append("%s.rects must be an array" % path)
	else:
		for index in range(rects.size()):
			var rect: Variant = rects[index]
			if not rect is Dictionary:
				validation_errors.append("%s.rects[%d] must be an object" % [path, index])
				continue
			_validate_point(
				rect.get("position", []),
				"%s.rects[%d].position" % [path, index],
				width,
				height,
				validation_errors
			)
			var size: Variant = rect.get("size", [])
			if not _is_number_pair(size) or int(size[0]) <= 0 or int(size[1]) <= 0:
				validation_errors.append("%s.rects[%d].size must contain two positive integers" % [path, index])
			elif _is_number_pair(rect.get("position", [])):
				var position := _vector2i_from_array(rect["position"])
				if position.x + int(size[0]) > width or position.y + int(size[1]) > height:
					validation_errors.append("%s.rects[%d] must fit inside the map" % [path, index])
	var lines: Variant = group.get("lines", [])
	if not lines is Array:
		validation_errors.append("%s.lines must be an array" % path)
	else:
		for index in range(lines.size()):
			var line: Variant = lines[index]
			if not line is Dictionary:
				validation_errors.append("%s.lines[%d] must be an object" % [path, index])
				continue
			_validate_point(
				line.get("from", []),
				"%s.lines[%d].from" % [path, index],
				width,
				height,
				validation_errors
			)
			_validate_point(
				line.get("to", []),
				"%s.lines[%d].to" % [path, index],
				width,
				height,
				validation_errors
			)
			if int(line.get("thickness", 1)) <= 0:
				validation_errors.append("%s.lines[%d].thickness must be positive" % [path, index])

func _validate_troops(
	raw_troops: Variant,
	width: int,
	height: int,
	validation_errors: PackedStringArray
) -> void:
	if not raw_troops is Array:
		validation_errors.append("troops must be an array")
		return
	var unit_ids: Dictionary = {}
	for index in range(raw_troops.size()):
		var raw_troop: Variant = raw_troops[index]
		if not raw_troop is Dictionary:
			validation_errors.append("troops[%d] must be an object" % index)
			continue
		var troop: Dictionary = raw_troop
		if String(troop.get("type", "")) not in VALID_TROOP_TYPES:
			validation_errors.append("troops[%d].type is not a supported troop" % index)
		if String(troop.get("team", "")).to_lower() not in VALID_TEAMS:
			validation_errors.append("troops[%d].team must be left or right" % index)
		_validate_point(
			troop.get("tile", []),
			"troops[%d].tile" % index,
			width,
			height,
			validation_errors
		)
		if troop.has("unit_id"):
			var unit_id := int(troop["unit_id"])
			if unit_id <= 0:
				validation_errors.append("troops[%d].unit_id must be positive" % index)
			elif unit_ids.has(unit_id):
				validation_errors.append("troops[%d].unit_id duplicates %d" % [index, unit_id])
			unit_ids[unit_id] = true
		if troop.has("spawn_payload") and not troop["spawn_payload"] is Dictionary:
			validation_errors.append("troops[%d].spawn_payload must be an object" % index)

func _validate_camera(
	raw_camera: Variant,
	width: int,
	height: int,
	validation_errors: PackedStringArray
) -> void:
	if not raw_camera is Dictionary:
		validation_errors.append("camera must be an object")
		return
	var camera_root: Dictionary = raw_camera
	for role in ["default", "host", "client"]:
		if not camera_root.has(role):
			continue
		var raw_config: Variant = camera_root[role]
		if not raw_config is Dictionary:
			validation_errors.append("camera.%s must be an object" % role)
			continue
		var config: Dictionary = raw_config
		if config.has("tile"):
			_validate_point(config["tile"], "camera.%s.tile" % role, width, height, validation_errors)
		if config.has("zoom") and float(config["zoom"]) <= 0.0:
			validation_errors.append("camera.%s.zoom must be positive" % role)

func _validate_point_list(
	raw_points: Variant,
	path: String,
	width: int,
	height: int,
	validation_errors: PackedStringArray
) -> void:
	if not raw_points is Array:
		validation_errors.append("%s must be an array" % path)
		return
	for index in range(raw_points.size()):
		_validate_point(raw_points[index], "%s[%d]" % [path, index], width, height, validation_errors)

func _validate_point(
	raw_point: Variant,
	path: String,
	width: int,
	height: int,
	validation_errors: PackedStringArray
) -> void:
	if not _is_number_pair(raw_point):
		validation_errors.append("%s must contain two integers" % path)
		return
	var point := _vector2i_from_array(raw_point)
	if point.x < 0 or point.y < 0 or point.x >= width or point.y >= height:
		validation_errors.append("%s must be inside the map" % path)

func _build_surface_heights(map_config: Dictionary, width: int) -> Array[int]:
	var heights: Array[int] = []
	if map_config.has("surface_y"):
		heights.resize(width)
		heights.fill(int(map_config["surface_y"]))
	elif map_config.has("surface_heights"):
		for raw_height in map_config["surface_heights"]:
			heights.append(int(raw_height))
	return heights

func _collect_edit_tiles(raw_group: Variant, territory: TerritoryManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	if not raw_group is Dictionary:
		return result
	var group: Dictionary = raw_group
	for raw_tile in group.get("tiles", []):
		_append_tile_if_valid(_vector2i_from_array(raw_tile), territory, seen, result)
	for raw_rect in group.get("rects", []):
		var rect: Dictionary = raw_rect
		var position := _vector2i_from_array(rect.get("position", []))
		var size := _vector2i_from_array(rect.get("size", []))
		for y in range(position.y, position.y + size.y):
			for x in range(position.x, position.x + size.x):
				_append_tile_if_valid(Vector2i(x, y), territory, seen, result)
	for raw_line in group.get("lines", []):
		var line: Dictionary = raw_line
		var from := _vector2i_from_array(line.get("from", []))
		var to := _vector2i_from_array(line.get("to", []))
		var thickness := int(line.get("thickness", 1))
		var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
		for step in range(steps + 1):
			var ratio := float(step) / float(steps) if steps > 0 else 0.0
			var center := Vector2i(roundi(lerpf(from.x, to.x, ratio)), roundi(lerpf(from.y, to.y, ratio)))
			var start_offset := -int(floor((thickness - 1) / 2.0))
			for y_offset in range(start_offset, start_offset + thickness):
				for x_offset in range(start_offset, start_offset + thickness):
					_append_tile_if_valid(center + Vector2i(x_offset, y_offset), territory, seen, result)
	return result

func _append_tile_if_valid(
	tile: Vector2i,
	territory: TerritoryManager,
	seen: Dictionary,
	result: Array[Vector2i]
) -> void:
	if not territory.is_tile_in_bounds(tile) or seen.has(tile):
		return
	seen[tile] = true
	result.append(tile)

func _team_from_string(value: String) -> int:
	return GameState.Team.LEFT if value.to_lower() == "left" else GameState.Team.RIGHT

func _is_number_pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for entry in value:
		if not entry is int and not entry is float:
			return false
		if float(entry) != float(int(entry)):
			return false
	return true

func _vector2i_from_array(value: Variant) -> Vector2i:
	if not value is Array or value.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))

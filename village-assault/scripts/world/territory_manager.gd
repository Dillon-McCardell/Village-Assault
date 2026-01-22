extends Node2D
class_name TerritoryManager

@export var grid_width: int = 64
@export var grid_height: int = 20
@export var tile_size: int = 16
@export_range(0.05, 0.45, 0.05) var left_territory_ratio: float = 0.2
@export_range(0.05, 0.45, 0.05) var right_territory_ratio: float = 0.2

@export var base_flat_width: int = 10
@export var base_surface_height: int = 8
@export var min_surface_height: int = 6
@export var max_surface_height: int = 12
@export_range(0.0, 1.0, 0.05) var roughness: float = 0.6
@export var max_step: int = 2
@export var smooth_passes: int = 2
@export var terrain_seed: int = 0

@onready var tile_map: TileMap = $WorldTileMap

var _spawn_offsets: Dictionary = {
	GameState.Team.LEFT: 0,
	GameState.Team.RIGHT: 0,
}

var _heightmap: Array[int] = []

const TILE_DIRT: Vector2i = Vector2i(0, 0)
const TILE_GRASS: Vector2i = Vector2i(1, 0)

func _ready() -> void:
	GameState.world_settings_updated.connect(_on_world_settings_updated)
	_apply_world_settings()
	_ensure_tileset()
	_build_terrain()

func is_world_pos_in_team_territory(world_pos: Vector2, team: int) -> bool:
	var tile := world_to_tile(world_pos)
	if tile.x < 0 or tile.y < 0 or tile.x >= grid_width or tile.y >= grid_height:
		return false
	var bounds := _get_team_bounds(team)
	return bounds.has_point(tile)

func get_next_spawn_position_for_team(team: int) -> Vector2:
	var bounds := _get_team_bounds(team)
	if bounds.size.x <= 0:
		return Vector2.ZERO
	var offset: int = int(_spawn_offsets.get(team, 0))
	var spawn_x: int = bounds.position.x + int(offset % bounds.size.x)
	var surface_y: int = _get_surface_height(spawn_x)
	var spawn_y: int = int(clamp(surface_y - 1, 0, grid_height - 1))
	var spawn_tile := Vector2i(spawn_x, spawn_y)
	_spawn_offsets[team] = offset + 1
	return tile_to_world_center(spawn_tile)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / tile_size), floor(world_pos.y / tile_size))

func tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x + 0.5) * tile_size, (tile_pos.y + 0.5) * tile_size)

func _get_team_bounds(team: int) -> Rect2i:
	var left_width: int = int(max(1, int(round(grid_width * left_territory_ratio))))
	var right_width: int = int(max(1, int(round(grid_width * right_territory_ratio))))
	match team:
		GameState.Team.LEFT:
			return Rect2i(0, 0, left_width, grid_height)
		GameState.Team.RIGHT:
			return Rect2i(grid_width - right_width, 0, right_width, grid_height)
		_:
			return Rect2i(0, 0, 0, 0)

func _build_terrain() -> void:
	_heightmap = _generate_heightmap()
	tile_map.clear()
	for x in range(grid_width):
		var surface_y: int = _get_surface_height(x)
		for y in range(surface_y, grid_height):
			var atlas_coords := TILE_DIRT
			if y == surface_y:
				atlas_coords = TILE_GRASS
			tile_map.set_cell(0, Vector2i(x, y), 0, atlas_coords)

func _generate_heightmap() -> Array[int]:
	var heights: Array[int] = []
	heights.resize(grid_width)
	var rng := RandomNumberGenerator.new()
	if terrain_seed != 0:
		rng.seed = terrain_seed
	elif GameState.map_seed != GameState.DEFAULT_MAP_SEED:
		rng.seed = GameState.map_seed
	else:
		rng.randomize()
	var base_height: int = int(clamp(base_surface_height, min_surface_height, max_surface_height))
	var flat_width: int = _get_flat_width()
	for x in range(grid_width):
		if _is_in_flat_pad(x, flat_width):
			heights[x] = base_height
			continue
		var prev: int = heights[x - 1] if x > 0 else base_height
		var delta: int = rng.randi_range(-max_step, max_step)
		if rng.randf() > roughness:
			delta = 0
		var next_height: int = int(clamp(prev + delta, min_surface_height, max_surface_height))
		heights[x] = next_height
	var passes: int = int(max(0, smooth_passes))
	for pass_index in range(passes):
		heights = _smooth_heights(heights)
	_apply_flat_pads(heights, base_height, flat_width)
	return heights

func _smooth_heights(source: Array[int]) -> Array[int]:
	var smoothed: Array[int] = []
	smoothed.resize(grid_width)
	var flat_width: int = _get_flat_width()
	for x in range(grid_width):
		if _is_in_flat_pad(x, flat_width):
			smoothed[x] = source[x]
			continue
		var left_index: int = int(clamp(x - 1, 0, grid_width - 1))
		var right_index: int = int(clamp(x + 1, 0, grid_width - 1))
		var left: int = source[left_index]
		var center: int = source[x]
		var right: int = source[right_index]
		var avg: int = int(round((left + center + right) / 3.0))
		smoothed[x] = int(clamp(avg, min_surface_height, max_surface_height))
	return smoothed

func _get_surface_height(x: int) -> int:
	if _heightmap.is_empty():
		return int(clamp(base_surface_height, min_surface_height, max_surface_height))
	return int(clamp(_heightmap[x], min_surface_height, max_surface_height))

func _get_flat_width() -> int:
	var max_width: int = int(max(1, grid_width / 2))
	return int(clamp(base_flat_width, 1, max_width))

func _is_in_flat_pad(x: int, flat_width: int) -> bool:
	return x < flat_width or x >= grid_width - flat_width

func _apply_flat_pads(heights: Array[int], base_height: int, flat_width: int) -> void:
	for i in range(flat_width):
		var left_index: int = i
		var right_index: int = grid_width - 1 - i
		heights[left_index] = base_height
		heights[right_index] = base_height

func get_base_anchor_world(team: int) -> Vector2:
	var flat_width: int = _get_flat_width()
	var center_x: int = 0
	match team:
		GameState.Team.RIGHT:
			center_x = grid_width - 1 - int(floor(flat_width / 2.0))
		_:
			center_x = int(floor(flat_width / 2.0))
	var surface_y: int = _get_surface_height(center_x)
	var camera_tile := Vector2i(center_x, clamp(surface_y - 2, 0, grid_height - 1))
	return tile_to_world_center(camera_tile)

func get_world_pixel_rect() -> Rect2:
	var width: float = grid_width * tile_size
	var height: float = grid_height * tile_size
	return Rect2(0.0, 0.0, width, height)

func get_surface_tile_y_at_x(world_x: float) -> int:
	var tile_x: int = int(clamp(int(floor(world_x / tile_size)), 0, grid_width - 1))
	return _get_surface_height(tile_x)

func get_surface_world_y_at_x(world_x: float, unit_half_height: float) -> float:
	var surface_tile_y: int = get_surface_tile_y_at_x(world_x)
	return (surface_tile_y * tile_size) - unit_half_height

func _ensure_tileset() -> void:
	if tile_map.tile_set != null:
		return
	var image := Image.create(tile_size * 2, tile_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_fill_rect(image, Rect2i(0, 0, tile_size, tile_size), Color(0.45, 0.32, 0.18, 1))
	_fill_rect(image, Rect2i(tile_size, 0, tile_size, tile_size), Color(0.3, 0.6, 0.25, 1))
	var texture := ImageTexture.create_from_image(image)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	var _source_id := tileset.add_source(source)
	source.create_tile(TILE_DIRT)
	source.create_tile(TILE_GRASS)
	tile_map.tile_set = tileset

func _apply_world_settings() -> void:
	grid_width = GameState.map_width
	grid_height = GameState.map_height
	terrain_seed = GameState.map_seed

func _on_world_settings_updated(_map_width: int, _map_height: int, _map_seed: int) -> void:
	_apply_world_settings()
	_build_terrain()

func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			image.set_pixel(x, y, color)

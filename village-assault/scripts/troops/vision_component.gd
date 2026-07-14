extends Node
class_name VisionComponent

const VISION_SOURCE_GROUP: StringName = &"fog_vision_sources"

@export_range(0.0, 12.0, 0.25) var vision_radius_tiles: float = 3.0
@export_range(0.0, 3.0, 0.25) var wall_feather_tiles: float = 1.0
@export_range(0.0, 3.0, 0.25) var edge_feather_tiles: float = 1.0
@export_range(0.05, 1.0, 0.05) var exploration_stamp_spacing_tiles: float = 0.25
@export var enabled: bool = true

func _ready() -> void:
	var source_node := get_parent()
	if source_node != null:
		source_node.add_to_group(VISION_SOURCE_GROUP)

func configure_from_spawn_payload(payload: Dictionary) -> void:
	vision_radius_tiles = maxf(0.0, float(payload.get(
		"vision_radius_tiles",
		vision_radius_tiles
	)))
	wall_feather_tiles = maxf(0.0, float(payload.get(
		"vision_wall_feather_tiles",
		wall_feather_tiles
	)))
	edge_feather_tiles = maxf(0.0, float(payload.get(
		"vision_edge_feather_tiles",
		edge_feather_tiles
	)))
	exploration_stamp_spacing_tiles = maxf(0.05, float(payload.get(
		"vision_stamp_spacing_tiles",
		exploration_stamp_spacing_tiles
	)))

func get_vision_source() -> Dictionary:
	if not enabled or vision_radius_tiles <= 0.0:
		return {}
	var source_node := get_parent() as Node2D
	if source_node == null:
		return {}
	var height_value: Variant = source_node.get("unit_height")
	var unit_height := float(height_value) if height_value != null else 0.0
	return {
		"center": source_node.global_position - Vector2(0.0, unit_height * 0.5),
		"radius_tiles": vision_radius_tiles,
		"wall_feather_tiles": wall_feather_tiles,
		"edge_feather_tiles": edge_feather_tiles,
		"stamp_spacing_tiles": exploration_stamp_spacing_tiles,
	}

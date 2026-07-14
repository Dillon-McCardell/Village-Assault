extends Resource
class_name ShopItem

@export var id: String = ""
@export var label: String = ""
@export var price: int = 0
@export var category: String = ""
@export var health: int = 10
@export var damage: int = 0
@export var defense: int = 0
@export var tile_damage: int = 0
@export var vision_radius_tiles: float = 3.0
@export var vision_wall_feather_tiles: float = 1.0
@export var vision_edge_feather_tiles: float = 1.0
@export var vision_stamp_spacing_tiles: float = 0.25

func get_display_label() -> String:
	return "%s $%d\n%s" % [label, price, get_stats_label()]

func get_stats_label() -> String:
	return "♡ %d ⚔ %d ⛨ %d ⛏ %d" % [health, damage, defense, tile_damage]

func get_spawn_payload() -> Dictionary:
	return {
		"health": health,
		"damage": damage,
		"defense": defense,
		"tile_damage": tile_damage,
		"vision_radius_tiles": vision_radius_tiles,
		"vision_wall_feather_tiles": vision_wall_feather_tiles,
		"vision_edge_feather_tiles": vision_edge_feather_tiles,
		"vision_stamp_spacing_tiles": vision_stamp_spacing_tiles,
	}

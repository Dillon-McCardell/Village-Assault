extends Resource
class_name ShopItem

@export var id: String = ""
@export var label: String = ""
@export var price: int = 0
@export var category: String = ""
@export var health: int = 10
@export var damage: int = 0
@export var defense: int = 0

func get_display_label() -> String:
	return "%s $%d\n%s" % [label, price, get_stats_label()]

func get_stats_label() -> String:
	return "♡ %d ⚔ %d ⛨ %d" % [health, damage, defense]

func get_spawn_payload() -> Dictionary:
	# Placeholder for future spawn data.
	return {}

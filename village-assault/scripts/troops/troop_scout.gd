extends "res://scripts/test_unit.gd"

func _ready() -> void:
	super._ready()
	set_body_polygon(PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))
	body.color = Color(0.95, 0.85, 0.1, 1)

func _update_color() -> void:
	pass

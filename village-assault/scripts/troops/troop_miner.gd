extends "res://scripts/test_unit.gd"

func _ready() -> void:
	super._ready()
	set_body_polygon(PackedVector2Array([Vector2(-8, -10), Vector2(8, -10), Vector2(8, 10), Vector2(-8, 10)]))
	body.color = Color(0.85, 0.65, 0.2, 1)

func _update_color() -> void:
	pass

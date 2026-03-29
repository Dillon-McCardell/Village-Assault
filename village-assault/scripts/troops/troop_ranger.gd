extends "res://scripts/test_unit.gd"

func _ready() -> void:
	super._ready()
	set_body_polygon(PackedVector2Array([Vector2(-8, -16), Vector2(8, -16), Vector2(8, 16), Vector2(-8, 16)]))
	body.color = Color(0.2, 0.4, 0.9, 1)

func _update_color() -> void:
	pass

extends "res://scripts/test_unit.gd"

func _ready() -> void:
	super._ready()
	body.polygon = PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	body.color = Color(0.2, 0.75, 0.2, 1)

func _update_color() -> void:
	pass

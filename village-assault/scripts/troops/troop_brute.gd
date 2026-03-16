extends "res://scripts/test_unit.gd"

func _ready() -> void:
	super._ready()
	body.polygon = PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	body.color = Color(0.55, 0.35, 0.15, 1)

func _update_color() -> void:
	pass

extends Control

func _draw() -> void:
	var color = Color(0.5, 0.0, 1.0) # Purple
	var points = PackedVector2Array([
		Vector2(size.x / 2, 0),
		Vector2(size.x, size.y),
		Vector2(0, size.y)
	])
	draw_polygon(points, PackedColorArray([color]))


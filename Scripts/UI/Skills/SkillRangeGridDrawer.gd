extends Control

# Data to draw
var cells_in_scope: Array[Vector2i] = []
var active_color: Color = Color.ORANGE
var move_dir: Vector2i = Vector2i.ZERO
var cell_size: Vector2 = Vector2(12, 12)
var line_width: float = 4.0
var line_color: Color = Color.WHITE
var bg_cell_color: Color = Color(41/255.0, 45/255.0, 65/255.0, 1.0)
var center_color: Color = Color(1, 0.9, 0.2)

func setup(p_cells: Array[Vector2i], p_active_color: Color, p_move_dir: Vector2i, p_cell_size: Vector2, p_line_width: float):
	cells_in_scope = p_cells
	active_color = p_active_color
	move_dir = p_move_dir
	cell_size = p_cell_size
	line_width = p_line_width
	
	# Calculate total size
	custom_minimum_size = (cell_size + Vector2(line_width, line_width)) * 7 + Vector2(line_width, line_width)
	queue_redraw()

func _draw():
	var total_cell_step = cell_size + Vector2(line_width, line_width)
	
	# 1. Draw full white background (the grid lines)
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), line_color, true)
	
	# 2. Draw cells
	for y in range(7):
		for x in range(7):
			var pos_in_grid = Vector2i(x - 3, y - 3)
			var draw_pos = Vector2(x, y) * total_cell_step + Vector2(line_width, line_width)
			var rect = Rect2(draw_pos, cell_size)
			
			var color = bg_cell_color
			
			if cells_in_scope.has(pos_in_grid):
				color = active_color
			
			# 關鍵修正：中心點永遠標示為黃色 (標示單位位置)，即使它在範圍內
			if pos_in_grid == Vector2i.ZERO:
				color = center_color
			
			draw_rect(rect, color, true)

			# 3. Draw arrow if needed
			if pos_in_grid == move_dir and move_dir != Vector2i.ZERO:
				_draw_arrow(rect.get_center(), move_dir)

func _draw_arrow(center: Vector2, dir: Vector2i):
	var arrow_size = cell_size.x * 0.8
	var points = PackedVector2Array()
	
	# Simple triangle arrow
	points.append(Vector2(0, -arrow_size * 0.5)) # Top
	points.append(Vector2(arrow_size * 0.4, arrow_size * 0.3)) # Bottom right
	points.append(Vector2(-arrow_size * 0.4, arrow_size * 0.3)) # Bottom left
	
	# Rotate points
	var angle = atan2(dir.y, dir.x) + PI/2.0
	for i in range(points.size()):
		points[i] = points[i].rotated(angle) + center
		
	draw_colored_polygon(points, Color.WHITE)

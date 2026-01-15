extends Node2D
class_name GridLines

## 網格格線繪製器
## 繪製網格之間的格線以便查看

@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.3)  # 半透明白色
@export var line_width: float = 1.0
@export var enable_grid_lines: bool = true

var grid: Node = null

func _ready() -> void:
	# 獲取 Grid 節點
	grid = get_tree().get_first_node_in_group("grid")
	if grid == null:
		push_warning("[GridLines] Grid not found")
		return
	
	# 設置 z_index 確保格線顯示在背景之上但不會遮擋實體
	z_index = -1
	
	add_to_group("grid_lines")
	
	print("[GridLines] Initialized")

func _draw() -> void:
	if not enable_grid_lines or grid == null:
		return
	
	# 獲取 Grid 配置
	if not ("cell_size" in grid) or not ("map_width" in grid) or not ("map_height" in grid):
		return
	
	var cell_size: Vector2i = grid.cell_size
	var map_width: int = grid.map_width
	var map_height: int = grid.map_height
	
	# 計算總地圖大小
	var map_size: Vector2 = Vector2(
		map_width * cell_size.x,
		map_height * cell_size.y
	)
	
	# 繪製垂直線
	for x in range(map_width + 1):
		var x_pos = x * cell_size.x
		var start = Vector2(x_pos, 0)
		var end = Vector2(x_pos, map_size.y)
		draw_line(start, end, line_color, line_width)
	
	# 繪製水平線
	for y in range(map_height + 1):
		var y_pos = y * cell_size.y
		var start = Vector2(0, y_pos)
		var end = Vector2(map_size.x, y_pos)
		draw_line(start, end, line_color, line_width)
		
	# 繪製額外格子的線框
	if grid.has_method("get_extra_valid_cells"):
		var extra_cells = grid.get_extra_valid_cells() # Expecting Array[Vector2i] or Dictionary keys
		for cell in extra_cells:
			var rect_pos = Vector2(cell.x * cell_size.x, cell.y * cell_size.y)
			var rect = Rect2(rect_pos, Vector2(cell_size.x, cell_size.y))
			draw_rect(rect, line_color, false, line_width)

func toggle_grid_lines() -> void:
	"""切換格線顯示"""
	enable_grid_lines = not enable_grid_lines
	queue_redraw()


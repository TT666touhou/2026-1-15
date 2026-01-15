extends Resource
class_name FootprintData

## 實體佔用體積定義
## 定義實體在網格上佔用的所有格子（相對於左上角）

# 佔用的格子列表（相對於左上角的偏移）
# 例如：[(0,0), (1,0), (0,1)] 表示 L 型
@export var occupied_cells: Array[Vector2i] = [Vector2i(0, 0)]

# 顯示名稱（用於調試）
@export var display_name: String = ""

# 獲取邊界框（用於計算放置區域）
func get_bounds() -> Rect2i:
	if occupied_cells.is_empty():
		return Rect2i(0, 0, 1, 1)
	
	var min_x = occupied_cells[0].x
	var max_x = occupied_cells[0].x
	var min_y = occupied_cells[0].y
	var max_y = occupied_cells[0].y
	
	for cell in occupied_cells:
		min_x = min(min_x, cell.x)
		max_x = max(max_x, cell.x)
		min_y = min(min_y, cell.y)
		max_y = max(max_y, cell.y)
	
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

# 獲取大小（邊界框的大小）
func get_size() -> Vector2i:
	var bounds = get_bounds()
	return Vector2i(bounds.size.x, bounds.size.y)


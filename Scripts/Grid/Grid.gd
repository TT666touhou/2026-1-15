extends Node
class_name Grid

## 網格管理器
## 管理網格地圖大小、座標轉換、佔用狀態

signal cell_occupied_changed(cell: Vector2i, is_occupied: bool)
signal size_changed()

@export var cell_size: Vector2i = Vector2i(16, 16)
@export var map_width: int = 12
@export var map_height: int = 8
@export var origin_offset: Vector2 = Vector2.ZERO

# 佔用狀態：{Vector2i: Node} - 格子座標 -> 實體
var _occupied_cells: Dictionary = {}

# 陷阱層：{Vector2i: Node} - 格子座標 -> 陷阱實體
var _traps: Dictionary = {}

# 額外有效格子：{Vector2i: bool} - 用於存儲地圖範圍外的特殊有效格子
var _extra_valid_cells: Dictionary = {}

func _ready() -> void:
	add_to_group("grid")
	# 觸發初始大小更新以確保相關 UI (如 EdgeFog) 能正確初始化
	size_changed.emit()

# ============================================================================
# 額外格子管理
# ============================================================================

func set_extra_cell_valid(cell: Vector2i, valid: bool) -> void:
	if valid:
		_extra_valid_cells[cell] = true
	else:
		_extra_valid_cells.erase(cell)
		# 如果該格子上有實體，可能需要處理（目前暫不處理，只負責格子有效性）
	
	# 通知 GridLines 更新
	var grid_lines = get_tree().get_first_node_in_group("grid_lines")
	if grid_lines and grid_lines.has_method("queue_redraw"):
		grid_lines.queue_redraw()

func get_extra_valid_cells() -> Array:
	return _extra_valid_cells.keys()

func is_extra_cell(cell: Vector2i) -> bool:
	return _extra_valid_cells.has(cell)

# ============================================================================
# 座標轉換
# ============================================================================

func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""世界座標轉網格座標"""
	var local = world_pos - origin_offset
	return Vector2i(floori(local.x / float(cell_size.x)), floori(local.y / float(cell_size.y)))

func grid_to_world(cell: Vector2i) -> Vector2:
	"""網格座標轉世界座標（左上角）"""
	return origin_offset + Vector2(cell.x * cell_size.x, cell.y * cell_size.y)

func grid_to_world_center(cell: Vector2i) -> Vector2:
	"""網格座標轉世界座標（中心）"""
	var top_left = grid_to_world(cell)
	return top_left + Vector2(cell_size.x * 0.5, cell_size.y * 0.5)

func grid_to_world_center_rect(cell: Vector2i, size: Vector2i) -> Vector2:
	"""計算矩形區域的中心世界座標"""
	# 計算矩形區域的左上角和右下角
	var top_left = grid_to_world(cell)
	var bottom_right = grid_to_world(cell + size)
	# 返回中心點
	return (top_left + bottom_right) * 0.5

# ============================================================================
# 邊界檢查
# ============================================================================

func is_in_bounds(cell: Vector2i) -> bool:
	"""檢查格子是否在邊界內，或屬於額外有效格子"""
	# 1. 檢查基本矩形範圍
	if cell.x >= 0 and cell.x < map_width and cell.y >= 0 and cell.y < map_height:
		return true
		
	# 2. 檢查額外有效格子
	return _extra_valid_cells.has(cell)

# ============================================================================
# 佔用管理
# ============================================================================

func is_cell_occupied(cell: Vector2i) -> bool:
	"""檢查格子是否被佔用"""
	return _occupied_cells.has(cell)

func set_cell_occupied(cell: Vector2i, entity: Node) -> void:
	"""設置格子佔用"""
	if is_in_bounds(cell):
		_occupied_cells[cell] = entity
		cell_occupied_changed.emit(cell, true)

func clear_cell(cell: Vector2i) -> void:
	"""清除格子佔用"""
	_occupied_cells.erase(cell)
	cell_occupied_changed.emit(cell, false)

func clear_all_occupancy() -> void:
	"""清空所有格子的佔用狀態 (用於地圖切換)"""
	var old_cells = _occupied_cells.keys()
	_occupied_cells.clear()
	for cell in old_cells:
		cell_occupied_changed.emit(cell, false)
	print("[Grid] All occupancy cleared.")

func get_occupant(cell: Vector2i) -> Node:
	"""獲取佔用格子的實體"""
	var occupant = _occupied_cells.get(cell, null)
	if is_instance_valid(occupant):
		return occupant
	else:
		# 如果實體已失效，從字典中移除並返回 null
		if _occupied_cells.has(cell):
			_occupied_cells.erase(cell)
		return null

func set_trap_occupied(cell: Vector2i, trap: Node) -> void:
	"""設置陷阱佔用"""
	if is_in_bounds(cell):
		_traps[cell] = trap

func clear_trap(cell: Vector2i) -> void:
	"""清除陷阱佔用"""
	_traps.erase(cell)

func get_trap(cell: Vector2i) -> Node:
	"""獲取該格子的陷阱"""
	var trap = _traps.get(cell, null)
	if is_instance_valid(trap):
		return trap
	else:
		if _traps.has(cell):
			_traps.erase(cell)
		return null

func get_cells_in_rect(cell: Vector2i, size: Vector2i) -> Array[Vector2i]:
	"""取得矩形區域內的所有格子座標"""
	var result: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			result.append(cell + Vector2i(x, y))
	return result

func clear_cells_rect(cell: Vector2i, size: Vector2i) -> void:
	"""清除矩形區域內的所有格子佔用"""
	var cells = get_cells_in_rect(cell, size)
	for c in cells:
		_occupied_cells.erase(c)
		cell_occupied_changed.emit(c, false)

func grid_to_world_center_footprint(cell: Vector2i, footprint_data) -> Vector2:
	"""計算不規則形狀的中心世界座標"""
	if footprint_data == null:
		var result_null = grid_to_world_center(cell)
		# print("[Grid] grid_to_world_center_footprint (null footprint) | cell: ", cell, " -> world: ", result_null)
		return result_null
	
	var bounds = footprint_data.get_bounds()
	# 計算邊界框的中心
	var top_left = grid_to_world(cell + Vector2i(bounds.position.x, bounds.position.y))
	var bottom_right = grid_to_world(cell + Vector2i(bounds.position.x + bounds.size.x, bounds.position.y + bounds.size.y))
	var result = (top_left + bottom_right) * 0.5
	# print("[Grid] grid_to_world_center_footprint | cell: ", cell, " | bounds: ", bounds, " | top_left: ", top_left, " | bottom_right: ", bottom_right, " | center: ", result, " | cell_size: ", cell_size)
	return result

func clear_cells_footprint(cell: Vector2i, footprint_data) -> void:
	"""清除不規則形狀佔用的所有格子"""
	if footprint_data == null:
		clear_cell(cell)
		return
	
	for offset in footprint_data.occupied_cells:
		var c = cell + offset
		_occupied_cells.erase(c)
		cell_occupied_changed.emit(c, false)

func get_cells_in_footprint(cell: Vector2i, footprint_data) -> Array[Vector2i]:
	"""獲取不規則形狀佔用的所有格子"""
	if footprint_data == null:
		return [cell]
	
	var result: Array[Vector2i] = []
	for offset in footprint_data.occupied_cells:
		result.append(cell + offset)
	return result

func is_footprint_occupied(cell: Vector2i, footprint_data) -> bool:
	"""檢查不規則形狀是否與已佔用的格子重疊"""
	if footprint_data == null:
		return is_cell_occupied(cell)
	
	for offset in footprint_data.occupied_cells:
		var check_cell = cell + offset
		if is_cell_occupied(check_cell):
			return true
	return false

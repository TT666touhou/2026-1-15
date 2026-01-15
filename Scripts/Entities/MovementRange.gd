extends Node
class_name MovementRange

## 移動範圍組件
## 存儲並應用單位的移動範圍限制

signal movement_range_data_set(data: MovementRangeData)

var movement_range_data: MovementRangeData = null:
	set(value):
		if movement_range_data != value:
			movement_range_data = value
			if movement_range_data != null:
				movement_range_data_set.emit(movement_range_data)

var entity: GridEntity

func _ready() -> void:
	entity = get_parent() as GridEntity
	if entity == null:
		push_error("[MovementRange] Parent must be GridEntity")

# 檢查是否可以在指定方向移動指定距離
func can_move_in_direction(direction: Vector2i, distance: int) -> bool:
	if movement_range_data == null:
		return true  # 沒有限制時允許移動
	return movement_range_data.can_move_in_direction(direction, distance)

# 獲取指定方向的最大移動距離（-1 表示無限制）
func get_max_distance(direction: Vector2i) -> int:
	if movement_range_data == null:
		return -1  # 沒有限制
	return movement_range_data.get_max_distance(direction)

func is_path_valid(path: Array[Vector2i]) -> bool:
	"""檢查路徑是否符合移動範圍限制（8方向移動，直線段）"""
	if movement_range_data == null:
		return true
	
	if path.size() <= 1:
		return true
	
	var _segment_start = path[0]
	var segment_direction: Vector2i = Vector2i.ZERO
	var segment_distance = 0
	
	for i in range(1, path.size()):
		var current = path[i]
		var step_dir = current - path[i - 1]
		
		if step_dir == Vector2i.ZERO:
			continue
		
		var normalized = _normalize_direction(step_dir)
		if normalized != step_dir:
			return false
		
		if segment_direction == Vector2i.ZERO:
			segment_direction = normalized
			segment_distance = 1
			_segment_start = path[i - 1]
		elif segment_direction == normalized:
			segment_distance += 1
		else:
			if not can_move_in_direction(segment_direction, segment_distance):
				return false
			segment_direction = normalized
			segment_distance = 1
			_segment_start = path[i - 1]
		
		if not can_move_in_direction(segment_direction, segment_distance):
			return false
	
	return true

func _normalize_direction(direction: Vector2i) -> Vector2i:
	"""標準化方向向量為8個基本方向之一"""
	if direction == Vector2i.ZERO:
		return Vector2i.ZERO
	
	return Vector2i(
		sign(direction.x) if direction.x != 0 else 0,
		sign(direction.y) if direction.y != 0 else 0
	)

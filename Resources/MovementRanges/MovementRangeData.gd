extends Resource
class_name MovementRangeData

## 移動範圍數據
## 定義單位在八個方向的移動限制

enum MovementType {
	BLOCKED = 0,      # 完全不能移動
	ONE_STEP = 1,     # 能移動一格
	UNLIMITED = 2     # 能移動多格（無限制）
}

# 八個方向的移動限制
@export var north: MovementType = MovementType.UNLIMITED      # 上
@export var south: MovementType = MovementType.UNLIMITED      # 下
@export var west: MovementType = MovementType.UNLIMITED      # 左
@export var east: MovementType = MovementType.UNLIMITED      # 右
@export var northwest: MovementType = MovementType.UNLIMITED # 左上
@export var northeast: MovementType = MovementType.UNLIMITED # 右上
@export var southwest: MovementType = MovementType.UNLIMITED  # 左下
@export var southeast: MovementType = MovementType.UNLIMITED # 右下

# 顯示名稱（用於調試）
@export var display_name: String = ""

# 獲取指定方向的移動類型
func get_movement_type(direction: Vector2i) -> MovementType:
	var normalized = _normalize_direction(direction)
	return _get_movement_type_for_normalized(normalized)

# 檢查是否可以在指定方向移動指定距離
func can_move_in_direction(direction: Vector2i, distance: int) -> bool:
	var movement_type = get_movement_type(direction)
	match movement_type:
		MovementType.BLOCKED:
			return false
		MovementType.ONE_STEP:
			return distance <= 1
		MovementType.UNLIMITED:
			return true
	return false

# 獲取指定方向的最大移動距離（-1 表示無限制）
func get_max_distance(direction: Vector2i) -> int:
	var movement_type = get_movement_type(direction)
	match movement_type:
		MovementType.BLOCKED:
			return 0
		MovementType.ONE_STEP:
			return 1
		MovementType.UNLIMITED:
			return -1  # -1 表示無限制
	return 0

# 標準化方向向量（轉換為八個基本方向之一）
func _normalize_direction(direction: Vector2i) -> Vector2i:
	if direction == Vector2i.ZERO:
		return Vector2i.ZERO
	
	# 標準化為單位向量
	var normalized = Vector2i(
		sign(direction.x) if direction.x != 0 else 0,
		sign(direction.y) if direction.y != 0 else 0
	)
	return normalized

# 根據標準化方向獲取移動類型
func _get_movement_type_for_normalized(normalized: Vector2i) -> MovementType:
	if normalized == Vector2i(0, -1):      # 上
		return north
	elif normalized == Vector2i(0, 1):     # 下
		return south
	elif normalized == Vector2i(-1, 0):   # 左
		return west
	elif normalized == Vector2i(1, 0):    # 右
		return east
	elif normalized == Vector2i(-1, -1): # 左上
		return northwest
	elif normalized == Vector2i(1, -1):   # 右上
		return northeast
	elif normalized == Vector2i(-1, 1):  # 左下
		return southwest
	elif normalized == Vector2i(1, 1):   # 右下
		return southeast
	else:
		return MovementType.BLOCKED


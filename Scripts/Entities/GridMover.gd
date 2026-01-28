extends Node
class_name GridMover

## 物理座標同步組件
## 當 RigidBody 停止移動時，將其位置對齊到最近的網格

var entity: GridEntity
var grid: Node

func _ready() -> void:
	entity = get_parent() as GridEntity
	grid = get_tree().get_first_node_in_group("grid")

func _physics_process(_delta: float) -> void:
	if entity == null or grid == null: return
	
	# 已停用：物理移動時不自動同步網格座標，避免吸附感
	# if entity.linear_velocity.length() < 2.0 and entity.linear_velocity.length() > 0:
	# 	var current_cell = grid.world_to_grid(entity.global_position)
	# 	if current_cell != entity.grid_position:
	# 		entity.set_grid_position(current_cell)
	pass

func move_to(target_cell: Vector2i, _instant: bool = false, _intended_direction: Vector2i = Vector2i.ZERO) -> bool:
	if entity == null or grid == null:
		return false
	
	if entity.grid_position == target_cell:
		return false
	
	# 直接更新位置 (不播放路徑動畫)
	entity.set_grid_position(target_cell)
	return true

func is_moving() -> bool:
	return false

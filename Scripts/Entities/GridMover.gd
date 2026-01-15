extends Node
class_name GridMover

## 移動組件
## 處理實體在網格上的移動

signal movement_started(entity: GridEntity, target_cell: Vector2i)
signal movement_completed(entity: GridEntity, final_position: Vector2i)

@export var move_animation_duration: float = 0.2  # 移動動畫時間 (從 0.3 改為 0.2)

var grid: Node  # Grid 類型（使用 Node 避免循環依賴）
var pathfinder: Node  # GridPathfinder 類型（使用 Node 避免循環依賴）
var entity: GridEntity
var _is_moving: bool = false

func _ready() -> void:
	entity = get_parent() as GridEntity
	if entity == null:
		push_error("[GridMover] Parent must be GridEntity")
		return
	
	grid = get_tree().get_first_node_in_group("grid")
	pathfinder = get_tree().get_first_node_in_group("grid_pathfinder")
	
	if grid == null or pathfinder == null:
		push_warning("[GridMover] Grid or GridPathfinder not found")
		return
	
	# 驗證方法存在
	if not grid.has_method("grid_to_world_center") or not pathfinder.has_method("find_path"):
		push_warning("[GridMover] Grid or GridPathfinder missing required methods")

func move_to(target_cell: Vector2i, instant: bool = false) -> void:
	"""移動到目標格子（無移動範圍限制）"""
	if pathfinder == null or entity == null or grid == null:
		return
	
	if not pathfinder.has_method("find_path") or not grid.has_method("is_cell_occupied"):
		return
	
	# 如果目標格子已被佔用（且不是自己），則不移動
	if grid.is_cell_occupied(target_cell):
		var occupant = grid.get_occupant(target_cell)
		if occupant != entity:
			print("[GridMover] Target cell is occupied by another entity")
			return
	
	# 如果已經在目標位置，不需要移動
	if entity.grid_position == target_cell:
		print("[GridMover] Already at target cell")
		return
	
	if _is_moving:
		_cancel_movement()
	
	# 開始移動
	_is_moving = true
	movement_started.emit(entity, target_cell)
	
	if instant:
		# 瞬間移動邏輯 (跳過路徑搜尋，直接檢查佔用並移動)
		
		# 1. 檢查目標位置是否有效 (考慮 Footprint)
		var is_blocked = false
		if entity.footprint_data != null and grid.has_method("get_cells_in_footprint"):
			var target_cells = grid.get_cells_in_footprint(target_cell, entity.footprint_data)
			for cell in target_cells:
				if not grid.is_in_bounds(cell):
					is_blocked = true
					break
				if grid.is_cell_occupied(cell):
					var occupant = grid.get_occupant(cell)
					if occupant != entity: # 忽略自身的佔用
						is_blocked = true
						break
		else:
			# Fallback for 1x1 or no footprint
			if grid.is_cell_occupied(target_cell):
				var occupant = grid.get_occupant(target_cell)
				if occupant != entity:
					is_blocked = true
		
		if is_blocked:
			print("[GridMover] Instant move blocked at ", target_cell)
			_is_moving = false
			return

		# 更新位置 (set_grid_position 會處理 Footprint 註銷與註冊)
		entity.set_grid_position(target_cell)
		# 使用 grid_to_world_center_footprint 修正多格單位位置
		entity.global_position = grid.grid_to_world_center_footprint(target_cell, entity.footprint_data) if entity.footprint_data else grid.grid_to_world_center(target_cell)
		
		# 更新障礙物
		if pathfinder != null and pathfinder.has_method("update_obstacles"):
			pathfinder.update_obstacles()
			
		_is_moving = false
		movement_completed.emit(entity, target_cell)
		print("[GridMover] Instant movement completed. Final position: ", target_cell)
		return

	# 計算路徑（在移動前，暫時清除當前位置的佔用以允許路徑查找）
	# 注意：這不會真正清除 Grid 的佔用，只是為了路徑查找
	var path = pathfinder.find_path(entity.grid_position, target_cell)
	if path.is_empty():
		print("[GridMover] No path found from ", entity.grid_position, " to ", target_cell)
		_is_moving = false
		return
	
	# 移除起點（第一個點是起點，不需要移動到起點）
	if path.size() > 0:
		path.pop_front()
	
	if path.is_empty():
		print("[GridMover] Path is empty after removing start point")
		_is_moving = false
		return
	
	print("[GridMover] Moving from ", entity.grid_position, " to ", target_cell, " via path: ", path)
	
	await _move_along_path(path)
	_is_moving = false
	
	# 發送移動完成信號
	movement_completed.emit(entity, entity.grid_position)
	
	print("[GridMover] Movement completed. Final position: ", entity.grid_position)

func _move_along_path(path: Array[Vector2i]) -> void:
	"""沿路徑移動"""
	if grid == null or entity == null:
		return
	
	if not grid.has_method("grid_to_world_center") or not grid.has_method("clear_cell") or not grid.has_method("set_cell_occupied"):
		return
	
	for next_cell in path:
		# 檢查目標格子是否可達（不應該被其他實體佔用，除非是移動中的自己）
		if grid.is_cell_occupied(next_cell):
			var occupant = grid.get_occupant(next_cell)
			if occupant != entity:
				print("[GridMover] Path blocked at cell ", next_cell, " by ", occupant)
				break
		
		# 使用 grid_to_world_center_footprint 修正多格單位位置
		var target_pos = grid.grid_to_world_center_footprint(next_cell, entity.footprint_data) if entity.footprint_data else grid.grid_to_world_center(next_cell)
		
		# --- 動態計算時間 (與距離成正比) ---
		var cell_size_ref = 16.0
		if grid and "cell_size" in grid:
			cell_size_ref = float(grid.cell_size.x)
			
		var distance = entity.global_position.distance_to(target_pos)
		# 距離越長，時間越多 (例如斜向約 22.6px 會比直向 16px 慢)
		var actual_duration = (distance / cell_size_ref) * move_animation_duration
		
		# --- 進階移動動畫 (跳躍感與非等速) ---
		var tween = get_tree().create_tween()
		tween.set_parallel(true)
		
		# 1. 水平移動 (使用 actual_duration)
		tween.tween_property(entity, "global_position", target_pos, actual_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		# 2. 垂直跳躍效果 (針對 Sprite2D，時間同步縮放)
		var sprite = entity.get_node_or_null("Sprite2D")
		if sprite:
			var jump_height = 4.0
			var half_time = actual_duration * 0.5
			
			# 建立一個串聯的 Tween 來處理上下跳
			var jump_tween = get_tree().create_tween()
			jump_tween.tween_property(sprite, "position:y", -jump_height, half_time)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			jump_tween.tween_property(sprite, "position:y", 0.0, half_time)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		await tween.finished
		
		# 更新網格位置和佔用 (這會自動處理舊位置清除與新位置註冊)
		entity.set_grid_position(next_cell)
		
		# 通知 GridPathfinder 更新障礙物
		if pathfinder != null and pathfinder.has_method("update_obstacles"):
			pathfinder.update_obstacles()
		
		print("[GridMover] Moved to cell ", next_cell, ". Grid position updated.")

func is_moving() -> bool:
	"""是否正在移動"""
	return _is_moving

func _cancel_movement() -> void:
	"""取消移動"""
	var tweens = get_tree().get_processed_tweens()
	for tween in tweens:
		if tween.is_valid():
			tween.kill()
	_is_moving = false

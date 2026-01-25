extends Node
class_name GridMover

## 移動組件
## 處理實體在網格上的移動

signal movement_started(entity: GridEntity, target_cell: Vector2i)
signal movement_completed(entity: GridEntity, final_position: Vector2i)

enum MoveStyle { STEP, DASH }

@export var move_style: MoveStyle = MoveStyle.STEP
@export var move_animation_duration: float = 0.2  # 移動動畫時間 (從 0.3 改為 0.2)

var grid: Node  # Grid 類型（使用 Node 避免循環依賴）
var pathfinder: Node  # GridPathfinder 類型（使用 Node 避免循環依賴）
var entity: GridEntity
var _is_moving: bool = false
var _trail_particles: GPUParticles2D
var last_move_rammed: bool = false # 記錄最近一次移動是否觸發撞擊

func _ready() -> void:
	entity = get_parent() as GridEntity
	if entity == null:
		push_error("[GridMover] Parent must be GridEntity")
		return
	
	grid = get_tree().get_first_node_in_group("grid")
	pathfinder = get_tree().get_first_node_in_group("grid_pathfinder")
	
	# 尋找粒子節點
	_trail_particles = entity.get_node_or_null("MoveParticles")
	if _trail_particles:
		# 自動調整粒子位置到腳底
		# 1x1 單位 (size 1) 往下 8 像素，2x2 單位 (size 2) 往下 16 像素
		var footprint_size = entity.get_footprint_size()
		var y_offset = footprint_size.y * 8
		_trail_particles.position = Vector2(0, y_offset)
		print("[GridMover] Auto-positioned particles for ", entity.name, " offset Y: ", y_offset)
	
	if grid == null or pathfinder == null:
		push_warning("[GridMover] Grid or GridPathfinder not found")
		return
	
	# 驗證方法存在
	if not grid.has_method("grid_to_world_center") or not pathfinder.has_method("find_path"):
		push_warning("[GridMover] Grid or GridPathfinder missing required methods")

func move_to(target_cell: Vector2i, instant: bool = false, intended_direction: Vector2i = Vector2i.ZERO) -> bool:
	"""
	移動到目標格子（無移動範圍限制）
	回傳：是否觸發了撞擊 (Ram Attack)
	"""
	if pathfinder == null or entity == null or grid == null:
		return false
	
	if not pathfinder.has_method("find_path") or not grid.has_method("is_cell_occupied"):
		return false
	
	last_move_rammed = false # 重置狀態
	
	# 如果目標格子已被佔用（且不是自己），則不移動
	if grid.is_cell_occupied(target_cell):
		var occupant = grid.get_occupant(target_cell)
		if occupant != entity:
			# 關鍵優化：如果是同步移動的我方單位，則允許啟動移動
			# 因為 GroupMovementController 已經模擬過，保證最終落點不會重疊
			if occupant is GridEntity and occupant.faction and occupant.faction.is_controllable:
				print("[GridMover] Target cell occupied by teammate ", occupant.name, ", allowing move start.")
			else:
				print("[GridMover] Target cell is occupied by another entity: ", occupant)
				# 雖然被擋住，但仍然檢查是否可以撞擊
				if intended_direction != Vector2i.ZERO:
					last_move_rammed = await _check_and_trigger_ram(intended_direction)
					return last_move_rammed
				return false
	
	# 如果已經在目標位置，不需要移動，但可能需要觸發撞擊
	if entity.grid_position == target_cell:
		print("[GridMover] Already at target cell")
		if intended_direction != Vector2i.ZERO:
			last_move_rammed = await _check_and_trigger_ram(intended_direction)
			return last_move_rammed
		return false
	
	if _is_moving:
		_cancel_movement()
	
	# 開始移動
	_is_moving = true
	if _trail_particles:
		_trail_particles.emitting = true
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
			return false

		# 更新位置 (set_grid_position 會處理 Footprint 註銷與註冊)
		entity.set_grid_position(target_cell)
		# 使用 grid_to_world_center_footprint 修正多格單位位置
		entity.global_position = grid.grid_to_world_center_footprint(target_cell, entity.footprint_data) if entity.footprint_data else grid.grid_to_world_center(target_cell)
		
		# --- 觸發陷阱偵測 (瞬間移動) ---
		if grid.has_method("get_trap"):
			var occupied_cells = entity.get_occupied_cells()
			var triggered_traps = {} 
			for c in occupied_cells:
				var trap = grid.get_trap(c)
				if trap and trap.has_method("on_stepped_on"):
					if not triggered_traps.has(trap):
						triggered_traps[trap] = true
						trap.on_stepped_on(entity)

		# 更新障礙物
		if pathfinder != null and pathfinder.has_method("update_obstacles"):
			pathfinder.update_obstacles()
			
		_is_moving = false
		movement_completed.emit(entity, target_cell)
		print("[GridMover] Instant movement completed. Final position: ", target_cell)
		return false

	# 計算路徑（在移動前，暫時清除當前位置的佔用以允許路徑查找）
	# 注意：這不會真正清除 Grid 的佔用，只是為了路徑查找
	var path = pathfinder.find_path(entity.grid_position, target_cell)
	if path.is_empty():
		print("[GridMover] No path found from ", entity.grid_position, " to ", target_cell)
		# 雖然沒路徑，但可能前方就是敵人
		var rammed = false
		if intended_direction != Vector2i.ZERO:
			rammed = await _check_and_trigger_ram(intended_direction)
		_is_moving = false
		return rammed
	
	# 移除起點（第一個點是起點，不需要移動到起點）
	if path.size() > 0:
		path.pop_front()
	
	if path.is_empty():
		print("[GridMover] Path is empty after removing start point")
		var rammed = false
		if intended_direction != Vector2i.ZERO:
			rammed = await _check_and_trigger_ram(intended_direction)
		_is_moving = false
		return rammed
	
	print("[GridMover] Moving from ", entity.grid_position, " to ", target_cell, " via path: ", path)
	
	# 強制使用行走 (STEP) 動畫，忽略 DASH 設定
	await _move_along_path(path)
	
	# 檢查移動最後一步是否觸發撞擊
	if intended_direction != Vector2i.ZERO:
		last_move_rammed = await _check_and_trigger_ram(intended_direction)
		
	_is_moving = false
	if _trail_particles:
		_trail_particles.emitting = false
	
	# 發送移動完成信號
	movement_completed.emit(entity, entity.grid_position)
	
	print("[GridMover] Movement completed. Final position: ", entity.grid_position)
	return last_move_rammed

func _move_along_path(path: Array[Vector2i]) -> void:
	"""沿路徑移動"""
	if grid == null or entity == null:
		return
	
	if not grid.has_method("grid_to_world_center") or not grid.has_method("clear_cell") or not grid.has_method("set_cell_occupied"):
		return
	
	for next_cell in path:
		# 檢查目標格子是否可達（不應該被其他實體佔用，除非是移動中的自己或同步移動的我方單位）
		if grid.is_cell_occupied(next_cell):
			var occupant = grid.get_occupant(next_cell)
			if occupant != entity:
				# 關鍵：如果是同步移動的我方單位，則忽略佔用，避免互相卡死
				if occupant is GridEntity and occupant.faction and occupant.faction.is_controllable:
					pass # 允許穿過我方單位
				else:
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
		# 加入速度屬性影響：時間 = (距離 / 參考) * 基礎時間 / 速度倍率
		var speed_mult = _get_speed_multiplier()
		var actual_duration = (distance / cell_size_ref) * move_animation_duration / speed_mult
		
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
		
		# --- 觸發陷阱偵測 ---
		if grid.has_method("get_trap"):
			var occupied_cells = entity.get_occupied_cells()
			# 使用 Dictionary 確保同一個陷阱在一次移動步進中只觸發一次 (針對多格單位)
			var triggered_traps = {} 
			for c in occupied_cells:
				var trap = grid.get_trap(c)
				if trap and trap.has_method("on_stepped_on"):
					if not triggered_traps.has(trap):
						triggered_traps[trap] = true
						trap.on_stepped_on(entity)
		
		# 通知 GridPathfinder 更新障礙物
		if pathfinder != null and pathfinder.has_method("update_obstacles"):
			pathfinder.update_obstacles()
		
		print("[GridMover] Moved to cell ", next_cell, ". Grid position updated.")

func _move_dash(path: Array[Vector2i]) -> void:
	"""衝刺移動：直接衝向終點並帶有回彈感"""
	if path.is_empty() or grid == null or entity == null:
		return
		
	var final_cell = path[-1]
	var target_pos = grid.grid_to_world_center_footprint(final_cell, entity.footprint_data) if entity.footprint_data != null else grid.grid_to_world_center(final_cell)
	
	var distance = entity.global_position.distance_to(target_pos)
	var cell_size_ref = 16.0
	if grid and "cell_size" in grid:
		cell_size_ref = float(grid.cell_size.x)
		
	# 衝刺時間計算：使其總時間與 STEP 風格接近 (move_animation_duration)
	var actual_duration = clamp((distance / cell_size_ref) * move_animation_duration, 0.2, 1.0)
	
	var tween = get_tree().create_tween()
	# 使用 TRANS_BACK + EASE_OUT 產生衝過頭再煞車回彈的效果
	tween.tween_property(entity, "global_position", target_pos, actual_duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	
	# 更新最終邏輯位置
	entity.set_grid_position(final_cell)
	
	# 通知 GridPathfinder 更新障礙物
	if pathfinder != null and pathfinder.has_method("update_obstacles"):
		pathfinder.update_obstacles()
	
	print("[GridMover] Dash movement completed to ", final_cell)

# --- 撞擊攻擊 (Ram Attack) 相關方法 ---

func _check_and_trigger_ram(dir: Vector2i) -> bool:
	"""檢查前方是否為敵人並觸發撞擊 (限定上下左右)"""
	# 限定正交方向 (上下左右)
	if dir.x != 0 and dir.y != 0:
		return false
		
	var next_cell = entity.grid_position + dir
	
	# 1. 邊界檢查：如果出界，不觸發撞擊
	if not grid.has_method("is_in_bounds") or not grid.is_in_bounds(next_cell):
		return false
		
	# 2. 佔用檢查
	if grid.has_method("is_cell_occupied") and grid.is_cell_occupied(next_cell):
		var occupant = grid.get_occupant(next_cell)
		# 3. 實體與陣營檢查：必須是敵對實體才觸發
		if occupant is GridEntity and occupant.faction != null and entity.faction != null:
			if occupant.faction != entity.faction:
				await _execute_ram_attack(occupant, dir)
				return true
	return false

func _execute_ram_attack(target: GridEntity, dir: Vector2i) -> void:
	"""執行撞擊攻擊的視覺與傷害"""
	print("[GridMover] RAM ATTACK: ", entity.name, " -> ", target.name)
	
	# 獲取單步移動的參考時間 (受速度影響)
	var speed_mult = _get_speed_multiplier()
	var duration = move_animation_duration / speed_mult
	
	# 1. 播放攻擊動畫
	if entity.has_method("play_attack_animation_towards"):
		entity.play_attack_animation_towards(dir)
	
	# 2. 加入物理上的「撞擊感」：向目標方向稍微位移再彈回
	# 這會讓動畫時間與移動一步的節奏完全一致
	var original_pos = entity.global_position
	var grid_offset = Vector2(dir) * 4.0 # 撞擊位移量 (4像素)
	
	var tween = get_tree().create_tween()
	tween.set_parallel(false) # 序列執行：去再回
	
	# 前半段：撞向敵人
	tween.tween_property(entity, "global_position", original_pos + grid_offset, duration * 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 在撞擊最深處執行傷害邏輯
	tween.tween_callback(func():
		var damage = 1
		if entity.character_data:
			damage = entity.character_data.get_effective_attack()
		
		if target.has_method("apply_damage"):
			target.apply_damage(damage, false, false, entity)
	)
	
	# 後半段：彈回原位
	tween.tween_property(entity, "global_position", original_pos, duration * 0.7)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 等待整個 Tween 完成，這確保了攻擊總時長 = move_animation_duration
	await tween.finished

func _get_speed_multiplier() -> float:
	"""獲取當前實體的有效移動速度倍率"""
	if entity and entity.character_data:
		return entity.character_data.get_effective_movement_speed()
	return 1.0

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
	if _trail_particles:
		_trail_particles.emitting = false

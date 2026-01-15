extends Node
class_name GroupMovementController

## 群體移動輸入管理器
## 負責處理鍵盤輸入並控制所有我方單位的同步移動

const DIRECTION_MAP = {
	KEY_Q: Vector2i(-1, -1), KEY_W: Vector2i(0, -1), KEY_E: Vector2i(1, -1),
	KEY_A: Vector2i(-1, 0),                          KEY_D: Vector2i(1, 0),
	KEY_Z: Vector2i(-1, 1),  KEY_X: Vector2i(0, 1),  KEY_C: Vector2i(1, 1)
}

func _ready() -> void:
	add_to_group("group_input_manager")

func _unhandled_input(event: InputEvent) -> void:
	if not TurnManager or TurnManager.is_busy():
		return
		
	if event is InputEventKey and event.pressed and not event.is_echo():
		if DIRECTION_MAP.has(event.keycode):
			_execute_group_move(DIRECTION_MAP[event.keycode])

func _execute_group_move(direction: Vector2i) -> void:
	var entities = get_tree().get_nodes_in_group("grid_entities")
	var player_units = entities.filter(func(u): 
		return u is GridEntity and u.faction and u.faction.is_controllable
	)
	
	if player_units.is_empty():
		return
		
	await execute_faction_move(player_units, direction)

## 公用方法：執行指定單位的陣營同步移動
func execute_faction_move(units: Array, direction: Vector2i) -> void:
	if units.is_empty(): return
	
	if TurnManager: TurnManager.lock_input()
	
	var grid = units[0].grid
	if not grid: return
	
	# 1. 模擬獲取目標 (包含暫時 unregister 邏輯)
	var unit_to_target = simulate_group_movement(units, direction, grid)
	
	# 2. 啟動移動動畫
	var moved_any = false
	var active_movers = []
	for unit in units:
		if not unit_to_target.has(unit): continue
		var target = unit_to_target[unit]
		
		if target != unit.grid_position:
			var mover = unit.get_node_or_null("GridMover")
			if mover:
				moved_any = true
				active_movers.append(mover)
				_run_mover(mover, target)
			else:
				unit.set_grid_position(target)
				moved_any = true
	
	if moved_any:
		# 等待所有移動動畫完成 (平行執行)
		await _wait_for_movers(active_movers)
		
		# 結束回合 (僅在戰鬥模式且非漫遊模式下由調用者或此處判斷，此處統一由 GroupMovementController 判斷玩家輸入觸發的行為)
		# 注意：如果是 AI 調用的，TurnManager 會在調用後自己處理 advance_turn
		if TurnManager and TurnManager.is_player_turn() and not TurnManager.is_free_roam_mode:
			print("[GroupMovementController] Player moves completed, advancing turn.")
			await TurnManager.advance_turn() # 確保等待回合結算與攻擊動畫完成
		
		if TurnManager: TurnManager.unlock_input() # 最後才解鎖，確保整個流程結束
	else:
		if TurnManager: TurnManager.unlock_input()

## 公用方法：模擬群體移動落點 (核心邏輯)
func simulate_group_movement(units: Array, direction: Vector2i, grid: Node) -> Dictionary:
	var unit_to_target = {}
	var taken_cells = [] # 記錄所有單位「預計」落點，防止重疊
	
	# 複製一份 Array 進行排序，不影響原始 Array 順序
	var sorted_units = units.duplicate()
	sorted_units.sort_custom(func(a, b):
		var dot_a = a.grid_position.x * direction.x + a.grid_position.y * direction.y
		var dot_b = b.grid_position.x * direction.x + b.grid_position.y * direction.y
		return dot_a > dot_b
	)
	
	# --- 關鍵：計算前暫時清除所有參與單位的佔用，避免互卡 ---
	for unit in sorted_units:
		if unit.has_method("_unregister_cells"):
			unit._unregister_cells()
	
	# 第一階段：計算所有落點
	for unit in sorted_units:
		if not is_instance_valid(unit) or not unit.movement_range_data:
			unit_to_target[unit] = unit.grid_position
			continue
			
		var move_type = unit.movement_range_data.get_movement_type(direction)
		if move_type == MovementRangeData.MovementType.BLOCKED:
			unit_to_target[unit] = unit.grid_position
			_add_footprint_to_taken_cells(unit.grid_position, unit.footprint_data, grid, taken_cells)
			continue
			
		var target_cell = _calculate_target_for_group(unit, direction, move_type, sorted_units, taken_cells)
		unit_to_target[unit] = target_cell
		_add_footprint_to_taken_cells(target_cell, unit.footprint_data, grid, taken_cells)

	# --- 計算完畢，立即恢復原本位置的佔用 ---
	for unit in sorted_units:
		if unit.has_method("_register_cells"):
			unit._register_cells()
			
	return unit_to_target

func _run_mover(mover: GridMover, target: Vector2i) -> void:
	await mover.move_to(target)

func _wait_for_movers(movers: Array) -> void:
	# 給一點啟動時間，確保 Tween 已經開始
	await get_tree().process_frame
	
	while true:
		var still_moving = false
		for mover in movers:
			if is_instance_valid(mover) and mover.is_moving():
				still_moving = true
				break
		if not still_moving:
			break
		await get_tree().process_frame

func _calculate_target_for_group(unit: GridEntity, dir: Vector2i, type: int, group: Array, taken_cells: Array) -> Vector2i:
	var current = unit.grid_position
	var grid = unit.grid
	if not grid: return current
	
	if type == MovementRangeData.MovementType.ONE_STEP:
		var next = current + dir
		if _can_unit_fit_at_group(unit, next, group, taken_cells):
			return next
		return current
		
	elif type == MovementRangeData.MovementType.UNLIMITED:
		var last_valid = current
		var search_pos = current
		var safety_count = 0
		while safety_count < 100: # 安全計數器，防止無限循環
			var next = search_pos + dir
			if _can_unit_fit_at_group(unit, next, group, taken_cells):
				last_valid = next
				search_pos = next
				safety_count += 1
			else:
				break
		return last_valid
	
	return current

func _can_unit_fit_at_group(unit: GridEntity, cell: Vector2i, group: Array, taken_cells: Array) -> bool:
	var grid = unit.grid
	if not grid or not grid.has_method("is_in_bounds") or not grid.has_method("get_cells_in_footprint"):
		return false
		
	var cells_to_check = grid.get_cells_in_footprint(cell, unit.footprint_data)
	for c in cells_to_check:
		# 1. 邊界檢查
		if not grid.is_in_bounds(c):
			return false
			
		# 2. 檢查是否已被同組的其他單位「預訂」 (這是唯一的真實障礙物來源)
		if c in taken_cells:
			return false
			
		# 3. 檢查網格佔用 (此時參與移動的我方單位已在 simulation 前 unregister)
		if grid.is_cell_occupied(c):
			var occupant = grid.get_occupant(c)
			if occupant != unit and not occupant in group:
				return false
	return true

func _add_footprint_to_taken_cells(cell: Vector2i, footprint: Resource, grid: Node, taken_cells: Array) -> void:
	var cells = [cell]
	if footprint and grid.has_method("get_cells_in_footprint"):
		cells = grid.get_cells_in_footprint(cell, footprint)
	
	for c in cells:
		if not c in taken_cells:
			taken_cells.append(c)

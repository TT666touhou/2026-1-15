extends Node
class_name GroupMovementController

## 群體移動輸入管理器
## 負責處理鍵盤輸入並控制所有我方單位的同步移動

@export var auto_advance_on_move: bool = false # 移動後是否自動結束回合的可選項

const DIRECTION_MAP = {
	KEY_W: Vector2i(0, -1),
	KEY_A: Vector2i(-1, 0),
	KEY_S: Vector2i(0, 1),
	KEY_D: Vector2i(1, 0)
}

func _ready() -> void:
	add_to_group("group_input_manager")

func _unhandled_input(event: InputEvent) -> void:
	if not TurnManager or TurnManager.is_busy():
		return
		
	if event is InputEventKey and event.pressed:
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
	
	# 準備排序後的單位列表，確保執行順序與模擬判定順序一致 (前排優先)
	var sorted_units = units.duplicate()
	sorted_units.sort_custom(func(a, b):
		# 獲取世界座標方向以便比較
		var world_dir = Vector2(direction)
		var pos_a = Vector2(a.grid_position)
		var pos_b = Vector2(b.grid_position)
		return pos_a.dot(world_dir) > pos_b.dot(world_dir)
	)
	
	# 2. 啟動移動動畫
	var moved_any = false
	var active_movers = []
	
	# 優化：按照 sorted_units (前排優先) 的順序啟動動畫
	for unit in sorted_units:
		if not unit_to_target.has(unit): continue
		var target = unit_to_target[unit]
		
		# 無論是否真的改變網格位置，只要呼叫 mover 都要傳遞方向以便檢查前方敵人
		var mover = unit.get_node_or_null("GridMover")
		if mover:
			moved_any = true
			active_movers.append(mover)
			# 平行啟動移動，不使用引起錯誤的 Lambda 呼叫
			mover.move_to(target, false, direction)
		else:
			if target != unit.grid_position:
				unit.set_grid_position(target)
				moved_any = true
	
	if moved_any:
		# 等待所有移動動畫完成 (平行執行)
		await _wait_for_movers(active_movers)
		
		# 結束回合
		if TurnManager and TurnManager.is_player_turn() and not TurnManager.is_free_roam_mode:
			print("[GroupMovementController] Player move sequence completed, advancing turn.")
			await TurnManager.advance_turn()
		
		if TurnManager: TurnManager.unlock_input()
	else:
		if TurnManager: TurnManager.unlock_input()

## 公用方法：模擬群體移動落點 (核心邏輯：多輪同步推進 + 詳細偵錯日誌)
func simulate_group_movement(units: Array, direction: Vector2i, _grid: Node) -> Dictionary:
	var unit_to_target = {}
	var unit_finished = {} # 記錄哪些單位已停止移動
	
	print("\n[GroupMovement] === START SIMULATION dir: ", direction, " ===")
	
	# 初始化：所有單位從當前位置開始，標記為未完成
	for unit in units:
		unit_to_target[unit] = unit.grid_position
		unit_finished[unit] = false
		print("[GroupMovement] Initial Pos: ", unit.name, " at ", unit.grid_position)
	
	# --- 關鍵：計算前暫時清除所有參與單位的佔用，避免互卡 ---
	for unit in units:
		if unit.has_method("_unregister_cells"):
			unit._unregister_cells()
			print("[GroupMovement] Unregistered grid cells for: ", unit.name)
	
	# 排序：雖然現在是同步推進，但每輪內的判斷順序仍以「前方優先」較為穩定
	var sorted_units = units.duplicate()
	sorted_units.sort_custom(func(a, b):
		var dot_a = a.grid_position.x * direction.x + a.grid_position.y * direction.y
		var dot_b = b.grid_position.x * direction.x + b.grid_position.y * direction.y
		return dot_a > dot_b
	)
	
	var sort_names = []
	for u in sorted_units: sort_names.append(u.name)
	print("[GroupMovement] Sorted priority (Front to Back): ", sort_names)

	# 核心迭代：一輪一輪推進
	var moved_in_round = true
	var round_num = 0
	while moved_in_round and round_num < 100:
		moved_in_round = false
		round_num += 1
		
		# 每一輪中，每個未完成的單位嘗試走一步
		for unit in sorted_units:
			if unit_finished[unit]: continue
			
			var move_type = unit.movement_range_data.get_movement_type(direction)
			var current_pos = unit_to_target[unit]
			var next_pos = current_pos + direction
			
			# 檢查該單位是否還有移動額度 (ONE_STEP 只能走一步)
			var already_moved_dist = (current_pos - unit.grid_position).length()
			if move_type == MovementRangeData.MovementType.ONE_STEP and already_moved_dist >= 0.5:
				unit_finished[unit] = true
				print("[GroupMovement]   ", unit.name, " STOPPED: ONE_STEP limit reached at ", current_pos)
				continue
			
			if move_type == MovementRangeData.MovementType.BLOCKED:
				unit_finished[unit] = true
				print("[GroupMovement]   ", unit.name, " STOPPED: Direction blocked by config at ", current_pos)
				continue
				
			# 核心判斷：下一步是否可行
			if _can_unit_step_to(unit, next_pos, units, unit_to_target, unit_finished):
				unit_to_target[unit] = next_pos
				moved_in_round = true
			else:
				unit_finished[unit] = true
				print("[GroupMovement]   ", unit.name, " STOPPED at ", current_pos, " because next step ", next_pos, " is blocked.")

	# --- 計算完畢，立即恢復原本位置的佔用 (由執行移動的邏輯後續更新真正的位置) ---
	for unit in units:
		if unit.has_method("_register_cells"):
			unit._register_cells()
			
	print("[GroupMovement] === SIMULATION COMPLETE ===\n")
	return unit_to_target

## 內部判斷：單個步進是否可行
func _can_unit_step_to(unit: GridEntity, target_cell: Vector2i, group: Array, current_targets: Dictionary, group_finished: Dictionary) -> bool:
	var grid = unit.grid
	if not grid or not grid.has_method("is_in_bounds") or not grid.has_method("get_cells_in_footprint"):
		return false
		
	var cells_to_check = grid.get_cells_in_footprint(target_cell, unit.footprint_data)
	for c in cells_to_check:
		# 1. 邊界檢查
		if not grid.is_in_bounds(c):
			print("[GroupMovement]     ", unit.name, " block reason: OUT OF BOUNDS at ", c)
			return false
			
		# 2. 檢查是否與「已停止」的隊友重疊
		for other in group:
			if other == unit: continue
			if group_finished[other]:
				# 如果隊友已經停下來了，檢查他的最終範圍是否擋住我
				var other_final_cells = grid.get_cells_in_footprint(current_targets[other], other.footprint_data)
				if c in other_final_cells:
					print("[GroupMovement]     ", unit.name, " block reason: TEAMMATE ", other.name, " ALREADY STOPPED at ", c)
					return false
			
		# 3. 檢查網格上的靜態佔用 (非隊友的佔用)
		if grid.is_cell_occupied(c):
			var occupant = grid.get_occupant(c)
			if occupant != unit and not occupant in group:
				var occ_name = occupant.name if "name" in occupant else "Unnamed"
				print("[GroupMovement]     ", unit.name, " block reason: STATIC OCCUPANT (", occ_name, ") at ", c)
				return false
				
	return true

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

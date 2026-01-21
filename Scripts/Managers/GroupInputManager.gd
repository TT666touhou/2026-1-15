extends Node
class_name GroupMovementController

## 群體移動輸入管理器
## 負責處理鍵盤輸入並控制所有我方單位的同步移動

@export var auto_advance_on_move: bool = false # 移動後是否自動結束回合的可選項
@export var repeat_delay: float = 0.3 # 按住後的延遲
@export var repeat_interval: float = 0.05 # 重複間隔 (設短一點，主要由 mover.is_busy 控速)

var _repeat_timer: float = 0.0

const DIRECTION_MAP = {
	KEY_W: Vector2i(0, -1),
	KEY_A: Vector2i(-1, 0),
	KEY_S: Vector2i(0, 1),
	KEY_D: Vector2i(1, 0),
	KEY_Q: Vector2i(-1, -1),
	KEY_E: Vector2i(1, -1),
	KEY_Z: Vector2i(-1, 1),
	KEY_C: Vector2i(1, 1)
}

func _ready() -> void:
	add_to_group("group_input_manager")

func _unhandled_input(event: InputEvent) -> void:
	# 僅在全局忙碌（如回合切換、大招播放）時完全阻斷輸入
	if not TurnManager or TurnManager.is_busy():
		return
		
	# 第一下點擊仍然保持即時響應
	if event is InputEventKey and event.pressed and not event.is_echo():
		if DIRECTION_MAP.has(event.keycode):
			_execute_group_move(DIRECTION_MAP[event.keycode])
			_repeat_timer = -repeat_delay # 設置負值，讓 _process 延後開始重複

func _process(delta: float) -> void:
	# 僅在全局忙碌（如回合切換、大招播放）時完全阻斷輸入
	if not TurnManager or TurnManager.is_busy():
		_repeat_timer = 0
		return
		
	var dir = _get_current_input_direction()
	if dir == Vector2i.ZERO:
		_repeat_timer = 0
		return
		
	_repeat_timer += delta
	if _repeat_timer >= repeat_interval:
		# 這裡重複嘗試移動
		# 注意：_execute_group_move 內部會檢查 mover.is_busy()
		# 所以只要單位還在動，這裡就不會觸發新的移動
		if _execute_group_move(dir):
			_repeat_timer = 0 # 只有成功觸發移動（有單位可動）才重置計時器

func _get_current_input_direction() -> Vector2i:
	# 優先判定 WASD 組合出的方向
	var x = int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
	var y = int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
	
	if x != 0 or y != 0:
		return Vector2i(x, y)
		
	# 檢查其他鍵 (QEZC)
	for key in [KEY_Q, KEY_E, KEY_Z, KEY_C]:
		if Input.is_key_pressed(key):
			return DIRECTION_MAP[key]
			
	return Vector2i.ZERO

func _execute_group_move(direction: Vector2i) -> bool:
	var entities = get_tree().get_nodes_in_group("grid_entities")
	var player_units = entities.filter(func(u): 
		if not (u is GridEntity and u.faction and u.faction.is_controllable):
			return false
		# 關鍵：過濾掉正在忙碌中的單位
		var mover = u.get_node_or_null("GridMover")
		return mover == null or not mover.is_busy()
	)
	
	if player_units.is_empty():
		return false
		
	# 不再使用 await，允許連續按下按鍵
	execute_faction_move(player_units, direction)
	return true

## 公用方法：執行指定單位的陣營同步移動
func execute_faction_move(units: Array, direction: Vector2i) -> void:
	if units.is_empty(): return
	
	var grid = units[0].grid
	if not grid: return
	
	# 1. 模擬獲取目標 (包含暫時 unregister 邏輯)
	var unit_to_target = simulate_group_movement(units, direction, grid)
	
	# 準備排序後的單位列表，確保執行順序與模擬判定順序一致 (前排優先)
	var sorted_units = units.duplicate()
	sorted_units.sort_custom(func(a, b):
		var dot_a = a.grid_position.x * direction.x + a.grid_position.y * direction.y
		var dot_b = b.grid_position.x * direction.x + b.grid_position.y * direction.y
		return dot_a > dot_b
	)
	
	# 2. 啟動移動動畫
	# 注意：這裡不再 await，指令發出後立即返回
	for unit in sorted_units:
		if not unit_to_target.has(unit): continue
		var target = unit_to_target[unit]
		
		var mover = unit.get_node_or_null("GridMover")
		if mover:
			# 使用 _run_mover 包裝以便在結束時檢查回合推進
			_run_mover(mover, target, direction)
		else:
			if target != unit.grid_position:
				unit.set_grid_position(target)

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
	
	# 獲取所有我方單位，用來檢查那些「正在移動中」的單位預計落點
	var all_entities = get_tree().get_nodes_in_group("grid_entities")
	var busy_units = all_entities.filter(func(e):
		if not (e is GridEntity and e.faction and e.faction.is_controllable): return false
		var m = e.get_node_or_null("GridMover")
		return m != null and m.is_busy()
	)
	
	for c in cells_to_check:
		# 1. 邊界檢查
		if not grid.is_in_bounds(c):
			print("[GroupMovement]     ", unit.name, " block reason: OUT OF BOUNDS at ", c)
			return false
			
		# 2. 檢查是否與「當前群體移動模擬中」已停止的隊友重疊
		for other in group:
			if other == unit: continue
			if group_finished[other]:
				var other_final_cells = grid.get_cells_in_footprint(current_targets[other], other.footprint_data)
				if c in other_final_cells:
					print("[GroupMovement]     ", unit.name, " block reason: TEAMMATE ", other.name, " ALREADY STOPPED at ", c)
					return false
		
		# 3. 關鍵安全性：檢查是否與「正在執行舊移動指令」的忙碌單位目標重疊
		for busy in busy_units:
			if busy == unit: continue
			var b_mover = busy.get_node("GridMover")
			var b_target = b_mover.target_grid_position
			if b_target != Vector2i(-1, -1):
				var busy_target_cells = grid.get_cells_in_footprint(b_target, busy.footprint_data)
				if c in busy_target_cells:
					print("[GroupMovement]     ", unit.name, " block reason: BUSY UNIT ", busy.name, " moving to ", b_target)
					return false
			else:
				# 回退：檢查目前佔用
				var busy_cells = grid.get_cells_in_footprint(busy.grid_position, busy.footprint_data)
				if c in busy_cells:
					print("[GroupMovement]     ", unit.name, " block reason: BUSY UNIT ", busy.name, " occupies ", c)
					return false
			
		# 4. 檢查網格上的靜態佔用 (非隊友的佔用)
		if grid.is_cell_occupied(c):
			var occupant = grid.get_occupant(c)
			if occupant != unit and not occupant in group:
				var occ_name = "Unnamed"
				if "name" in occupant:
					occ_name = occupant.name
				print("[GroupMovement]     ", unit.name, " block reason: STATIC OCCUPANT (", occ_name, ") at ", c)
				return false
				
	return true

func _run_mover(mover: Node, target: Vector2i, direction: Vector2i) -> void:
	await mover.move_to(target, false, direction)
	# 當一個單位移動結束，檢查是否需要推進回合
	check_auto_advance()

## 檢查是否可以自動推進回合
func check_auto_advance() -> void:
	if not auto_advance_on_move: return
	if not TurnManager or not TurnManager.is_player_turn() or TurnManager.is_free_roam_mode:
		return
		
	# 檢查是否所有我方單位都已停止
	var entities = get_tree().get_nodes_in_group("grid_entities")
	var player_units = entities.filter(func(u): 
		return u is GridEntity and u.faction and u.faction.is_controllable
	)
	
	for unit in player_units:
		var mover = unit.get_node_or_null("GridMover")
		if mover and mover.is_busy():
			return # 還有單位在忙，暫不推進
			
	# 檢查最後一次操作是否有觸發撞擊 (這裡需要一點技巧，因為現在是異步的)
	# 為了簡單起見，如果在所有單位都停下時，沒有任何單位正在撞擊且 auto_advance 為真，則推進。
	# 注意：rammed_any 的判定在非同步下比較複雜，我們改為檢查目前所有單位的 last_move_rammed
	var rammed_any = false
	for unit in player_units:
		var mover = unit.get_node_or_null("GridMover")
		if mover and mover.last_move_rammed:
			rammed_any = true
			break
			
	if not rammed_any:
		print("[GroupMovementController] All units idle, advancing turn.")
		# 使用 call_deferred 避免在信號回調中直接觸發重大的狀態變更
		TurnManager.advance_turn.call_deferred()

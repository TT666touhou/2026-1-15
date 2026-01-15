extends Node
class_name StatusManager

# 負責管理單位的狀態 (Buff/Debuff)

signal status_applied(status_def: StatusDefinition, current_duration: int)
signal status_updated(status_id: String, current_duration: int)
signal status_removed(status_id: String)

# 存儲活躍狀態的內部類別
class ActiveStatus:
	var definition: StatusDefinition
	var remaining_turns: int
	var current_stack_value: float = 0.0 # 用於護盾等
	var params: Dictionary = {} # Runtime copy of params for overrides
	
	func _init(def: StatusDefinition, overrides: Dictionary = {}):
		definition = def
		remaining_turns = def.duration_turns
		params = def.params.duplicate(true) # Deep copy
		
		# Apply overrides
		if overrides.has("duration"):
			remaining_turns = overrides["duration"]
			
		if overrides.has("value"):
			# Assuming "value" is the key we want to override in params
			params["value"] = overrides["value"]
			
		# Handle other overrides if needed

# 狀態列表： { "status_id": [ActiveStatus, ActiveStatus...] }
var active_statuses: Dictionary = {}
var _parent_entity: GridEntity

func _ready() -> void:
	_parent_entity = get_parent() as GridEntity
	
	# 連接回合信號
	var turn_manager = get_node_or_null("/root/TurnManager")
	if turn_manager:
		# 修改：改為監聽回合開始，統一在玩家回合開始時結算
		turn_manager.turn_started.connect(_on_turn_started)

## 應用狀態
## overrides: { "duration": int, "value": float }
func apply_status(def: StatusDefinition, overrides: Dictionary = {}) -> void:
	if not def: return
	
	# 核心修正：抗性判定 (RES)
	if _parent_entity and _parent_entity.character_data:
		var res = _parent_entity.character_data.get_effective_resistance()
		if res > 0:
			var roll = randf()
			if roll < res:
				print("[StatusManager] Status %s RESISTED! Res: %.2f, Roll: %.2f" % [def.id, res, roll])
				if _parent_entity.has_method("show_resisted_text"):
					_parent_entity.show_resisted_text()
				return
	
	if not active_statuses.has(def.id):
		active_statuses[def.id] = []
		
	var list = active_statuses[def.id]
	var current_status: ActiveStatus = null
	var is_update = false
	
	var duration = def.duration_turns
	if overrides.has("duration") and overrides["duration"] > 0:
		duration = overrides["duration"]
	
	match def.stacking_rule:
		StatusDefinition.StackingRule.OVERRIDE:
			# 清除舊的，加入新的 (或重置時間)
			if not list.is_empty():
				current_status = list[0]
				current_status.remaining_turns = duration # Reset duration
				# Update params if override provided
				if overrides.has("value"):
					current_status.params["value"] = overrides["value"]
				is_update = true
				print("[StatusManager] OVERRIDE status duration reset: ", def.id)
			else:
				current_status = ActiveStatus.new(def, overrides)
				list.append(current_status)
				print("[StatusManager] Applied OVERRIDE status: ", def.id)
			
		StatusDefinition.StackingRule.INDEPENDENT:
			# 直接加入新的實例
			current_status = ActiveStatus.new(def, overrides)
			list.append(current_status)
			print("[StatusManager] Applied INDEPENDENT status: ", def.id)
			
		StatusDefinition.StackingRule.STACK_VALUE:
			# 堆疊數值 (如護盾)
			var add_val = def.params.get("value", 0.0)
			if overrides.has("value"):
				add_val = overrides["value"]
				
			if list.is_empty():
				current_status = ActiveStatus.new(def, overrides) # This sets initial params["value"]
				current_status.current_stack_value = add_val
				list.append(current_status)
				print("[StatusManager] Applied STACK_VALUE status: ", def.id)
			else:
				current_status = list[0]
				current_status.remaining_turns = max(current_status.remaining_turns, duration)
				current_status.current_stack_value += add_val
				is_update = true
				print("[StatusManager] Updated STACK_VALUE status: ", def.id)
			
	if is_update:
		status_updated.emit(def.id, current_status.remaining_turns)
	else:
		status_applied.emit(def, current_status.remaining_turns)

## 檢查是否有某種行為限制
func has_restriction(restriction_key: String) -> bool:
	for id in active_statuses:
		for status in active_statuses[id]:
			if status.definition.behavior_type == StatusDefinition.BehaviorType.RESTRICTION:
				# Use runtime params
				if status.params.get(restriction_key, false):
					return true
	return false

## 獲取屬性修正值 (乘數)
func get_stat_multiplier(stat_name: String) -> float:
	var multiplier = 1.0
	for id in active_statuses:
		for status in active_statuses[id]:
			if status.definition.behavior_type == StatusDefinition.BehaviorType.STAT_MODIFIER:
				# Use runtime params
				if status.params.get("stat") == stat_name:
					# 假設 params: {"stat": "attack", "value": 0.5} (增加 50%)
					# 或 {"value": -0.2} (減少 20%)
					# 這裡定義 value 為加成比例 (0.5 = +50%, -0.2 = -20%)
					var mod = status.params.get("value", 0.0)
					multiplier += mod
	return multiplier

## 獲取受傷倍率修正 (例如易傷)
func get_damage_received_multiplier() -> float:
	var multiplier = 1.0
	for id in active_statuses:
		for status in active_statuses[id]:
			if status.definition.behavior_type == StatusDefinition.BehaviorType.STAT_MODIFIER:
				# Use runtime params
				if status.params.get("stat") == "damage_received":
					# value = 0.5 代表受傷 +50%
					multiplier += status.params.get("value", 0.0)
	return multiplier

## 統一回合開始處理 (全場狀態在玩家回合開始時結算)
func _on_turn_started(faction: FactionDefinition) -> void:
	# 僅在玩家回合開始時執行全場更新
	# 假設 is_controllable 代表玩家陣營
	if not faction.is_controllable:
		return
		
	# 不再檢查 _parent_entity.faction，對所有單位統一執行
		
	# 處理 OVER_TIME 效果 (如 DOT/HOT)
	_process_over_time_effects()
	
	# 減少回合數
	var ids_to_remove = []
	var ids_updated = []
	
	for id in active_statuses:
		var list = active_statuses[id]
		var max_remaining = 0
		
		for i in range(list.size() - 1, -1, -1):
			var status = list[i]
			status.remaining_turns -= 1
			
			if status.remaining_turns > max_remaining:
				max_remaining = status.remaining_turns
				
			if status.remaining_turns <= 0:
				list.remove_at(i)
				
		if list.is_empty():
			ids_to_remove.append(id)
		else:
			ids_updated.append({"id": id, "turns": max_remaining})
			
	for id in ids_to_remove:
		active_statuses.erase(id)
		status_removed.emit(id)
	
	# 對於 INDEPENDENT 堆疊，UI 通常顯示最長的持續時間，或堆疊層數
	# 這裡簡化：通知更新，傳回最長的剩餘時間
	for data in ids_updated:
		status_updated.emit(data.id, data.turns)

## 序列化當前狀態 (保存用)
func get_save_data() -> Array:
	var data = []
	for id in active_statuses:
		for status in active_statuses[id]:
			# 只有保存了實體檔案的 Resource 才能被重新載入
			if status.definition.resource_path.is_empty():
				print("[StatusManager] Warning: Skipping unsaved resource status: ", id)
				continue
				
			data.append({
				"definition_path": status.definition.resource_path,
				"remaining_turns": status.remaining_turns,
				"stack_value": status.current_stack_value,
				"params": status.params # Save runtime params
			})
	return data

## 反序列化狀態 (讀取用)
func load_save_data(data: Array) -> void:
	# 清除現有狀態 (通常在新生成的單位上調用，所以應該是空的)
	active_statuses.clear()
	
	for item in data:
		var path = item.get("definition_path", "")
		if path == "" or not ResourceLoader.exists(path):
			print("[StatusManager] Error: Cannot load status resource: ", path)
			continue
			
		var def = load(path) as StatusDefinition
		if not def:
			continue
			
		# 重建 ActiveStatus
		# Note: We pass empty overrides here, but manually restore params below
		var new_status = ActiveStatus.new(def) 
		new_status.remaining_turns = item.get("remaining_turns", 1)
		new_status.current_stack_value = item.get("stack_value", 0.0)
		
		var saved_params = item.get("params")
		if saved_params is Dictionary:
			new_status.params = saved_params
		
		if not active_statuses.has(def.id):
			active_statuses[def.id] = []
		
		active_statuses[def.id].append(new_status)
		
		# 通知 UI 顯示狀態 (但不觸發 Apply 效果，因為這是恢復)
		# 如果需要觸發某些 Apply 效果 (如初始屬性計算)，可以考慮是否需要呼叫
		# 但通常 recalculate_stats 會由 GridEntity 在 setup_character 後統一呼叫
		
		# 這裡發送 applied 信號主要是為了讓 StatusDisplayManager 重建圖示
		status_applied.emit(def, new_status.remaining_turns)

func _process_over_time_effects() -> void:
	for id in active_statuses:
		for status in active_statuses[id]:
			if status.definition.behavior_type == StatusDefinition.BehaviorType.OVER_TIME:
				# 執行效果 - Use runtime params
				var value = status.params.get("value", 0)
				var type = status.params.get("effect_type", "damage") # default to damage
				
				if value > 0:
					if type == "heal":
						if _parent_entity.has_method("heal"):
							_parent_entity.heal(value)
							print("[StatusManager] Regen applied: ", value)
					else: # damage
						if _parent_entity.has_method("take_damage"):
							# 注意：中毒傷害通常不觸發受傷動畫或浮動文字，或者需要特殊處理
							# 這裡直接用 take_damage 簡單處理，但可能需要規避易傷加成 (視設計而定)
							_parent_entity.take_damage(value)
							print("[StatusManager] Poison applied: ", value)

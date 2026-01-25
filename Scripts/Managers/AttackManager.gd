extends Node

# Autoload name: AttackManager
# 負責處理攻擊判定、Combo 計算與傷害結算調度

signal global_combo_changed(new_count: int)

var global_combo_count: int = 0
var has_hit_this_action: bool = false

func increase_global_combo(amount: int = 1) -> void:
	global_combo_count += amount
	has_hit_this_action = true
	global_combo_changed.emit(global_combo_count)
	print("[AttackManager] Global Combo increased to: ", global_combo_count)

func mark_hit() -> void:
	has_hit_this_action = true

func reset_global_combo() -> void:
	if global_combo_count != 0:
		global_combo_count = 0
		global_combo_changed.emit(global_combo_count)
		print("[AttackManager] Global Combo RESET")

func reset_action_hit_flag() -> void:
	has_hit_this_action = false

func get_combo_damage_multiplier(scaling: float = 0.1) -> float:
	# 每個連擊提高 scaling 傷害 (預設 0.1 => 1.0, 1.1, 1.2...)
	# 核心修正：使用快照數值或當前數值，取決於呼叫時機
	return 1.0 + (global_combo_count * scaling)

# 計算預覽狀態下的 Combo
# drag_entity: 正在拖曳的實體 (可選，若為 null 則計算場上現有狀態)
# drag_target_pos: 拖曳實體的目標位置 (當 drag_entity 存在時有效)
# 返回: { TargetEntity: TotalHits }
func calculate_preview_combos(drag_entity: GridEntity = null, drag_target_pos: Vector2i = Vector2i.ZERO) -> Dictionary:
	var combos = {}
	
	# 1. 獲取所有我方單位
	# 假設玩家陣營的單位都在 "player_units" 群組，或者 "grid_entities" 中過濾
	# 為了通用性，我們先獲取所有 grid_entities，再過濾陣營
	var all_entities = get_tree().get_nodes_in_group("grid_entities")
	var player_faction = null
	
	# 嘗試獲取玩家陣營 (假設 TurnManager 有)
	if TurnManager and TurnManager.factions_order.size() > 0:
		# 這裡假設第一個陣營是玩家，或者 drag_entity 的陣營是玩家
		# 更好的做法是從 TurnManager 獲取當前行動的陣營
		player_faction = TurnManager.current_faction
		
	if player_faction == null and drag_entity != null:
		player_faction = drag_entity.faction
		
	if player_faction == null:
		return combos
		
	# 2. 遍歷所有我方單位計算攻擊
	for entity in all_entities:
		var unit = entity as GridEntity
		if not unit or unit.faction != player_faction:
			continue
			
		# 決定攻擊發起位置
		var attack_pos = unit.grid_position
		
		# 如果這個單位是正在被拖曳的單位，使用預覽位置
		if unit == drag_entity:
			attack_pos = drag_target_pos
			
		# 獲取該單位的攻擊目標
		# get_attack_results 返回 { TargetEntity: { "hits": int, "directions": Array[Vector2i] } }
		var results = unit.get_attack_results(attack_pos)
		if results.size() > 0:
			print("[AttackManager] Unit ", unit.name, " at ", attack_pos, " found targets: ", results.keys())
		
		# 累加 Hits
		for target in results:
			if not combos.has(target):
				combos[target] = 0
			
			# 獲取方向列表的長度 (即攻擊次數)
			var attack_multiplier = results[target]["hits"]
			
			# 每個方向算 1 Hit (或者是單位定義的 Hits 數)
			# 預覽時顯示保底值 (向下取整)
			var base_hits = 1
			if unit.character_data:
				base_hits = int(floor(unit.character_data.combo_count))
				
			combos[target] += base_hits * attack_multiplier
			
	return combos

# 判定單個單位的實際連擊數 (含機率)
# 此函數僅計算單次判定的結果 (舊方法，保留供單次調用)
func resolve_hit_count(attacker: GridEntity) -> int:
	var hits = 1
	if attacker.character_data:
		var count = attacker.character_data.combo_count
		hits = int(floor(count))
		if randf() < (count - hits):
			hits += 1
	return hits

# 根據箭頭數量 (arrow_count) 計算總連擊數
# 每個箭頭獨立進行機率判定，避免「全有或全無」的情況
func resolve_total_hits(attacker: GridEntity, arrow_count: int) -> int:
	var total_hits = 0
	var combo_rate = 1.0
	
	if attacker.character_data:
		combo_rate = attacker.character_data.combo_count
	elif attacker.get("base_combo_count"): # Fallback if character_data missing but property exists
		combo_rate = attacker.base_combo_count
		
	var base_per_arrow = int(floor(combo_rate))
	var chance = combo_rate - base_per_arrow
	
	for i in range(arrow_count):
		var hits = base_per_arrow
		if randf() < chance:
			hits += 1
		total_hits += hits
		
	return total_hits

# 判定是否命中
func check_hit(attacker: GridEntity, target: GridEntity) -> bool:
	if attacker.character_data == null or target.character_data == null:
		return true # 預設命中
		
	var acc = attacker.character_data.get_effective_accuracy()
	var avoid = target.character_data.get_effective_avoid()
	
	# 命中率公式：精準 - 閃避 (保底 0%，最高 100%)
	var hit_chance = clamp(acc - avoid, 0.0, 1.0)
	
	var roll = randf()
	var is_hit = roll < hit_chance
	
	if not is_hit:
		print("[AttackManager] MISS! Acc: %.2f, Avoid: %.2f, Chance: %.2f, Roll: %.2f" % [acc, avoid, hit_chance, roll])
		
	return is_hit

# 攻擊事件數據結構
class AttackEvent:
	var target: GridEntity
	var attackers: Array[GridEntity] = []
	var attack_directions: Dictionary = {} # { Attacker: Direction }
	var attacker_hit_counts: Dictionary = {} # { Attacker: int }
	# 這些值現在由 TurnManager 在 runtime 計算，這裡僅作為容器
	var total_hits: int = 0 
	var total_damage: int = 0

# 獲取戰鬥行動計畫
func get_combat_actions(attacking_faction: Resource) -> Array[AttackEvent]:
	var actions: Dictionary = {} # { TargetEntity: AttackEvent }
	
	var all_entities = get_tree().get_nodes_in_group("grid_entities")
	
	# 1. 收集所有攻擊
	for entity in all_entities:
		var attacker = entity as GridEntity
		if not attacker or attacker.faction != attacking_faction:
			continue
			
		var results = attacker.get_attack_results(attacker.grid_position)
		for target in results:
			var target_data = results[target] # { "hits": int, "directions": Array[Vector2i] }
			var directions = target_data["directions"]
			
			if not actions.has(target):
				var new_event = AttackEvent.new()
				new_event.target = target
				actions[target] = new_event
				
			var existing_event = actions[target]
			existing_event.attackers.append(attacker)
			
			# 暫存攻擊方向，用於播放動畫
			if not directions.is_empty():
				existing_event.attack_directions[attacker] = directions
			else:
				# 如果是範圍攻擊但沒有明確方向 (例如自爆)，可能為空
				existing_event.attack_directions[attacker] = []
				
			# 重要：這裡我們不再依賴 directions.size() 來計算 hits
			# 因為 get_attack_results 已經處理了 Hitbox 疊加
			# 我們需要將計算出的 hits 傳遞給 TurnManager
			
			if not existing_event.attacker_hit_counts.has(attacker):
				existing_event.attacker_hit_counts[attacker] = target_data["hits"]
			
	# 3. 排序行動 (上到下，左到右)
	var sorted_events: Array[AttackEvent] = []
	sorted_events.assign(actions.values())
	
	sorted_events.sort_custom(func(a, b):
		var pos_a = a.target.grid_position
		var pos_b = b.target.grid_position
		if pos_a.y != pos_b.y:
			return pos_a.y < pos_b.y # Y 小的在先 (上方)
		return pos_a.x < pos_b.x # X 小的在先 (左方)
	)
	
	# 排序每個事件內的攻擊者 (上到下，左到右)
	for evt in sorted_events:
		evt.attackers.sort_custom(func(a, b):
			var pos_a = a.grid_position
			var pos_b = b.grid_position
			if pos_a.y != pos_b.y:
				return pos_a.y < pos_b.y
			return pos_a.x < pos_b.x
		)
	
	return sorted_events

# 輔助：獲取所有敵方單位
func get_all_enemies(player_faction: Resource) -> Array[GridEntity]:
	var enemies: Array[GridEntity] = []
	var all_entities = get_tree().get_nodes_in_group("grid_entities")
	for entity in all_entities:
		var unit = entity as GridEntity
		if unit and unit.faction != player_faction:
			enemies.append(unit)
	return enemies

# --------------------------------------------------------------------------------
# Leader Skill (Character Trait) Calculation
# --------------------------------------------------------------------------------

# 計算單個攻擊者因 Leader Skill (Character Trait) 獲得的額外加成
# 遍歷 PartyManager 中的所有 Leader，檢查條件並累加倍率
func calculate_trait_bonus(attacker: GridEntity, target: GridEntity, current_total_hits: int) -> float:
	if PartyManager == null:
		return 1.0
		
	var total_multiplier: float = 1.0
	
	# 取得所有生效的 Trait
	var active_traits = PartyManager.get_active_traits()
	if active_traits.is_empty():
		return 1.0
		
	# 檢查攻擊者是否屬於當前行動陣營 (通常只有我方回合才觸發 PartyManager 技能，但為求通用先保留檢查)
	# 這裡假設 Leader Skill 只對 PartyManager 管理的隊伍 (Player) 生效
	# 若要讓敵人也有 Leader Skill，需擴充 PartyManager 或 AI 系統。
	# 目前先簡單檢查 attacker.faction 是否與 PartyManager 的隊伍陣營一致 (需透過 UnitCard 判斷)
	
	for trait_data in active_traits:
		for effect in trait_data.effects:
			# 僅處理攻擊時觸發的加成
			if effect.trigger_type != TraitEffect.TriggerType.ON_ATTACK:
				continue
			if effect.effect_behavior != TraitEffect.EffectBehavior.MODIFY_STAT:
				continue
			
			# 1. 檢查加成類型是否為攻擊力
			if effect.stat_type != TraitEffect.StatType.ATTACK_MULTIPLIER:
				continue
				
			# 2. 檢查目標範圍 (Target Scope)
			if not _check_trait_target(effect, attacker, target):
				continue
				
			# 3. 檢查觸發條件 (Condition)
			if not _check_trait_condition(effect, attacker, target, current_total_hits):
				continue
				
			# 4. 條件滿足，累乘倍率
			total_multiplier *= effect.value
			
	return total_multiplier

func _check_trait_target(effect: TraitEffect, _attacker: GridEntity, _target: GridEntity) -> bool:
	match effect.target_faction:
		TraitEffect.TargetFaction.SELF:
			# 嚴格來說 Leader Skill 的 Self 應該是指 Leader 本人，
			# 但這裡的 context 是「攻擊者是否受益」。
			# 若 Target 是 SELF，則只有當 Attacker == Leader 時才生效。
			# 這裡需要知道誰是 Leader，較複雜。暫時簡化：
			# 若效果是 SELF，則只有該 Trait 的擁有者攻擊時生效 (TODO: 需傳入 Leader 實體來比對)
			# 目前 PartyManager.leaders 是 Array[CharacterData]，我們可以比對 CharacterData
			return true # 暫時對所有人生效，或是略過
			
		TraitEffect.TargetFaction.ALLY:
			# 只要是己方陣營都算
			# 這裡假設 attacker 必定是執行攻擊的陣營 (TurnManager.current_faction)
			return true 
			
		TraitEffect.TargetFaction.ENEMY:
			return false # 攻擊力加成通常不會給敵人
			
		TraitEffect.TargetFaction.ALL:
			return true
			
	return false

func _check_trait_condition(effect: TraitEffect, attacker: GridEntity, _target: GridEntity, total_hits: int) -> bool:
	match effect.condition_type:
		TraitEffect.ConditionType.NONE:
			return true # 對於攻擊觸發，無條件視為成立
			
		TraitEffect.ConditionType.HP_THRESHOLD:
			if attacker.character_data == null: return false
			var hp_percent = float(attacker.character_data.current_health) / float(attacker.character_data.max_health)
			return _compare(hp_percent, effect.condition_value, effect.comparison)
			
		TraitEffect.ConditionType.COMBO_COUNT:
			return _compare(float(total_hits), effect.condition_value, effect.comparison)
			
		TraitEffect.ConditionType.FACTION_MATCH:
			# TODO: Check faction type
			return true
			
	return true

func _compare(actual: float, threshold: float, comparison: TraitEffect.Comparison) -> bool:
	match comparison:
		TraitEffect.Comparison.GREATER: return actual > threshold
		TraitEffect.Comparison.LESS: return actual < threshold
		TraitEffect.Comparison.EQUAL: return is_equal_approx(actual, threshold)
		TraitEffect.Comparison.GREATER_EQUAL: return actual >= threshold
		TraitEffect.Comparison.LESS_EQUAL: return actual <= threshold
	return false

extends Node

# [AttackManager] 攻擊結算與連擊管理器 (Autoload)
# 職責：
# 1. 統一處理所有單位的攻擊/技能結算 (resolve_combat)。
# 2. 計算傷害公式：基礎值 * Combo倍率 * 特質加成 * 暴擊 - 減傷。
# 3. 管理全域連擊數 (Global Combo)，並在回合與物理靜止時重置。

# [相關外部連動腳本]:
# - TurnManager.gd: 用於判斷當前是否為玩家回合 (is_player_turn)，決定是否套用 Combo 倍率。
# - GridEntity.gd: 受傷與死亡的實際執行者 (take_damage)。
# - SkillManager.gd: 部分技能傷害計算會調用此處的通用公式。

# --- 信號 ---
signal global_combo_changed(new_count: int)
signal unit_damaged(target: Node, attacker: Node, amount: int)

# --- 狀態變數 ---
var global_combo_count: int = 0

# ============================================================================
# Combo 系統管理
# ============================================================================

func increase_global_combo(amount: int = 1) -> void:
	global_combo_count += amount
	global_combo_changed.emit(global_combo_count)
	# print("[AttackManager] Global Combo increased to: ", global_combo_count)

func reset_global_combo() -> void:
	if global_combo_count != 0:
		global_combo_count = 0
		global_combo_changed.emit(global_combo_count)
		# print("[AttackManager] Global Combo RESET")

func get_combo_damage_multiplier(scaling: float = 0.1) -> float:
	# 核心規則：只有在玩家回合且非自由漫遊時套用 Combo 倍率
	if TurnManager and not TurnManager.is_player_turn():
		return 1.0
	return 1.0 + (global_combo_count * scaling)

# ============================================================================
# 核心戰鬥結算
# ============================================================================

## 統一戰鬥結算流 (7步結算)
## 返回: { "result": String, "damage": int, "is_crit": bool, "reflect_damage": int, "heal_amount": int, "pursuit_damage": int }
func resolve_combat(attacker: Node, target: GridEntity, base_damage: int, is_skill: bool = false, is_pursuit: bool = false) -> Dictionary:
	var report = {
		"result": "hit",
		"damage": 0,
		"is_crit": false,
		"reflect_damage": 0,
		"heal_amount": 0,
		"pursuit_damage": 0
	}
	
	if not is_instance_valid(target) or not target.character_data:
		return report

	# 獲取攻擊者數據 (支援 GridEntity 或 Projectile)
	var attacker_unit = null
	if is_instance_valid(attacker):
		# 優先檢查是否為 GridEntity，否則嘗試從投射物屬性獲取
		attacker_unit = attacker if attacker is GridEntity else \
						attacker.get("attacker_entity") if attacker.get("attacker_entity") != null else \
						attacker.get("caster")

	var a_data = attacker_unit.character_data if attacker_unit and "character_data" in attacker_unit else null
	var t_data = target.character_data
	
	# 0. 命中判定
	if not check_hit(attacker, target):
		report["result"] = "avoid"
		return report

	# --- 1. 攻擊端計算 (基礎 * Combo * 特質 * 暴擊) ---
	var current_dmg = float(base_damage)
	
	# 僅在玩家回合對玩家單位套用 Combo (技能傷害已在 SkillManager 預先計算倍率，故跳過)
	if not is_skill and TurnManager and TurnManager.is_player_turn() and attacker_unit and attacker_unit.is_in_group("player"):
		var combo_scaling = a_data.combo_damage_scaling if a_data else 0.1
		current_dmg *= get_combo_damage_multiplier(combo_scaling)
		current_dmg *= calculate_trait_bonus(attacker_unit, target, int(global_combo_count))

	# 暴擊判定
	if a_data:
		var crit_rate = a_data.get_effective_crit_rate()
		if randf() < crit_rate:
			# 基礎 1.5x 暴擊傷害，可由 character_data 擴充
			var crit_bonus = 1.5 + a_data.get_effective_crit_dmg()
			current_dmg *= crit_bonus
			report["is_crit"] = true

	# --- 2. 交互端：貫穿 vs 減傷率 (DR) ---
	var dr = t_data.get_effective_dr()
	if a_data:
		dr = max(0.0, dr - a_data.get_effective_penetration())

	# --- 3. 絕對防禦：防護罩 (Barrier) ---
	if t_data.barriers > 0:
		t_data.barriers -= 1
		t_data.barrier_triggered.emit()
		t_data.stats_changed.emit()
		report["result"] = "barrier"
		return report

	# --- 4. 隨機防禦：格擋 (Parry) ---
	if randf() < t_data.get_effective_parry():
		t_data.parry_triggered.emit()
		report["result"] = "parry"
		return report

	# --- 5. 數值削減：套用 DR 減傷 ---
	var final_dmg = int(round(current_dmg * (1.0 - dr)))
	if final_dmg <= 0: final_dmg = 1 # 保底 1 點
	
	# if TurnManager and TurnManager.is_player_turn() and attacker_unit and attacker_unit.is_in_group("player"):
	# 	print("[AttackManager] resolve_combat: %s -> %s | Base: %d | Final: %d | Combo: %d" % [
	# 		attacker_unit.name if attacker_unit else "None", 
	# 		target.name, base_damage, final_dmg, global_combo_count
	# 	])
	
	# --- 6. 生命扣除：護盾 -> HP ---
	var actual_hp_lost = t_data.take_damage(final_dmg)
	report["damage"] = final_dmg

	# 發送全域受傷信號，供實體特質系統監聽
	# print("[AttackManager] Emitting unit_damaged: Target=%s, Amount=%d" % [target.name, final_dmg])
	unit_damaged.emit(target, attacker_unit, final_dmg)

	# --- 7. 後續觸發：反射、吸血、追擊、Combo ---
	# 反射
	var ref_rate = t_data.get_effective_reflect()
	if ref_rate > 0:
		report["reflect_damage"] = int(final_dmg * ref_rate)
		if report["reflect_damage"] > 0:
			t_data.reflect_triggered.emit(a_data, report["reflect_damage"], t_data)
	
	# 吸血
	if a_data and actual_hp_lost > 0:
		var drain_rate = a_data.get_effective_drain()
		if drain_rate > 0:
			report["heal_amount"] = int(actual_hp_lost * drain_rate)
	
	# 追擊：僅限單位撞擊觸發，投射物、技能以及追擊本身不觸發
	if not is_skill and not is_pursuit and attacker is GridEntity and a_data:
		report["pursuit_damage"] = a_data.get_effective_pursuit()

	# 增加全域 Combo (僅玩家擊中敵人)
	if attacker_unit and attacker_unit.is_in_group("player") and target.is_in_group("enemy"):
		increase_global_combo(1)

	return report

# ============================================================================
# 判定輔助
# ============================================================================

func check_hit(attacker: Node, target: GridEntity) -> bool:
	var a_data = null
	if is_instance_valid(attacker):
		if attacker is GridEntity: a_data = attacker.character_data
		elif attacker.get("attacker_entity") is GridEntity: a_data = attacker.attacker_entity.character_data
	
	if a_data == null or target.character_data == null:
		return true
		
	var acc = a_data.get_effective_accuracy()
	var avoid = target.character_data.get_effective_avoid()
	var hit_chance = clamp(acc - avoid, 0.0, 1.0)
	
	return randf() < hit_chance

# ============================================================================
# 特質與加成計算
# ============================================================================

func calculate_trait_bonus(attacker: GridEntity, target: GridEntity, current_total_hits: int) -> float:
	if PartyManager == null: return 1.0
	var total_multiplier: float = 1.0
	var active_traits = PartyManager.get_active_traits()
	
	for trait_data in active_traits:
		for effect in trait_data.effects:
			if effect.trigger_type != TraitEffect.TriggerType.ON_ATTACK: continue
			if effect.effect_behavior != TraitEffect.EffectBehavior.MODIFY_STAT: continue
			if effect.stat_type != TraitEffect.StatType.ATTACK_MULTIPLIER: continue
			if not _check_trait_target(effect, attacker, target): continue
			if not _check_trait_condition(effect, attacker, target, current_total_hits): continue
			total_multiplier *= effect.value
			
	return total_multiplier

func _check_trait_target(effect: TraitEffect, _attacker: GridEntity, _target: GridEntity) -> bool:
	match effect.target_faction:
		TraitEffect.TargetFaction.SELF, TraitEffect.TargetFaction.ALLY, TraitEffect.TargetFaction.ALL: return true
		TraitEffect.TargetFaction.ENEMY: return false
	return false

func _check_trait_condition(effect: TraitEffect, attacker: GridEntity, _target: GridEntity, total_hits: int) -> bool:
	match effect.condition_type:
		TraitEffect.ConditionType.NONE: return true
		TraitEffect.ConditionType.HP_THRESHOLD:
			if attacker.character_data == null: return false
			var hp_percent = float(attacker.character_data.current_health) / float(attacker.character_data.max_health)
			return _compare(hp_percent, effect.condition_value, effect.comparison)
		TraitEffect.ConditionType.COMBO_COUNT:
			return _compare(float(total_hits), effect.condition_value, effect.comparison)
	return true

func _compare(actual: float, threshold: float, comparison: TraitEffect.Comparison) -> bool:
	match comparison:
		TraitEffect.Comparison.GREATER: return actual > threshold
		TraitEffect.Comparison.LESS: return actual < threshold
		TraitEffect.Comparison.EQUAL: return is_equal_approx(actual, threshold)
		TraitEffect.Comparison.GREATER_EQUAL: return actual >= threshold
		TraitEffect.Comparison.LESS_EQUAL: return actual <= threshold
	return false

# ============================================================================
# 預覽與 AI 輔助
# ============================================================================

func calculate_preview_combos(drag_entity: GridEntity = null, drag_target_pos: Vector2i = Vector2i.ZERO) -> Dictionary:
	var combos = {}
	var all_entities = get_tree().get_nodes_in_group("grid_entities")
	var player_faction = FACTION_PLAYER if TurnManager == null else TurnManager.current_faction
	
	if player_faction == null and drag_entity != null:
		player_faction = drag_entity.faction
		
	if player_faction == null: return combos
		
	for entity in all_entities:
		var unit = entity as GridEntity
		if not unit or unit.faction != player_faction: continue
		var attack_pos = drag_target_pos if unit == drag_entity else unit.grid_position
		var results = unit.get_attack_results(attack_pos)
		
		for target in results:
			if not combos.has(target): combos[target] = 0
			var base_hits = int(floor(unit.character_data.combo_count)) if unit.character_data else 1
			combos[target] += base_hits * results[target]["hits"]
			
	return combos

const FACTION_PLAYER = preload("res://Resources/Factions/Faction_Player.tres")

func resolve_total_hits(attacker: GridEntity, arrow_count: int) -> int:
	var total_hits = 0
	var combo_rate = attacker.character_data.combo_count if attacker.character_data else 1.0
	var base_per_arrow = int(floor(combo_rate))
	var chance = combo_rate - base_per_arrow
	
	for _i in range(arrow_count):
		total_hits += base_per_arrow + (1 if randf() < chance else 0)
	return total_hits

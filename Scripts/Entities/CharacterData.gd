class_name CharacterData extends RefCounted

# Reference to the definition
var unit_def: UnitCard
var status_manager_ref: Node = null # Reference to StatusManager

# Runtime Stats (Base)
var current_health: int
var max_health: int # Base Max HP
var attack_damage: int # Base Attack
var shield: int = 0 # 護盾 (優先扣除)
var barriers: int = 0 # 防護罩 (次數抵擋)
var base_avoid: float = 0.0 # 基礎閃避
var base_accuracy: float = 1.0 # 基礎精準
var base_dr: float = 0.0 # 基礎減傷率
var base_resistance: float = 0.0 # 基礎抗性
var base_reflect: float = 0.0 # 基礎反射率
var base_pursuit: int = 0 # 基礎追擊
var base_parry: float = 0.0 # 基礎格擋率
var base_drain: float = 0.0 # 基礎吸血率
var base_crit_dmg: float = 0.0 # 基礎額外暴擊傷害
var base_penetration: float = 0.0 # 基礎貫穿率
var base_movement_speed: float = 1.0 # 基礎移動速度
var movement_speed: Variant = 3 # 支援 int 或 String "3-6"
var combo_count: float # Base Combo
var combo_damage_scaling: float = 0.1 # 每個連擊增加的傷害倍率
var crit_rate: float
var luck: int
var character_trait: TraitData

# Persistence Data
var saved_status_data: Array = [] # Stores serialized active statuses for scene transitions

# Stat Modifiers
var stat_modifiers = {
	"attack_multiplier": 1.0,
	"hp_multiplier": 1.0,
	"combo_additive": 0.0,
	"attack_additive": 0,
	"avoid_additive": 0.0,
	"accuracy_additive": 0.0,
	"dr_additive": 0.0,
	"res_additive": 0.0,
	"ref_additive": 0.0,
	"pur_additive": 0,
	"par_additive": 0.0,
	"dra_additive": 0.0,
	"cdm_additive": 0.0,
	"pen_additive": 0.0,
	"hp_additive": 0,
	"movement_speed_multiplier": 1.0
}

# Skill System Data
var runtime_skills: Array[UnitSkillData] = []
var has_used_skill_this_turn: bool = false
var has_moved_this_turn: bool = false
var skill_cooldowns: Dictionary = {} # Mapping skill_name (String) -> remaining_turns (int)

# Equipment Slots
var weapon: Resource = null
var armor: Resource = null
var accessory: Resource = null

# Signals
@warning_ignore("unused_signal")
signal health_changed(current: int, max: int)
@warning_ignore("unused_signal")
signal combo_count_changed(new_value: float)
@warning_ignore("unused_signal")
signal crit_rate_changed(new_value: float)
@warning_ignore("unused_signal")
signal luck_changed(new_value: int)
signal stats_changed # New signal for full stat update
signal reflect_triggered(attacker: CharacterData, amount: int, reflector: CharacterData)
signal parry_triggered # 當格擋發生時觸發
signal barrier_triggered # 當防護罩抵擋時觸發
signal died

static func create(def: UnitCard) -> CharacterData:
	var instance = CharacterData.new()
	instance.unit_def = def
	# Use int casting if the definition uses float, or just direct assignment
	instance.max_health = int(def.max_health)
	instance.current_health = int(def.max_health)
	instance.attack_damage = def.attack_damage
	
	# New Stats from UnitCard
	instance.base_avoid = float(def.base_avoid) if "base_avoid" in def else 0.0
	instance.base_accuracy = float(def.base_accuracy) if "base_accuracy" in def else 1.0
	instance.base_dr = float(def.base_dr) if "base_dr" in def else 0.0
	instance.base_resistance = float(def.base_resistance) if "base_resistance" in def else 0.0
	instance.base_reflect = float(def.base_reflect) if "base_reflect" in def else 0.0
	instance.base_pursuit = int(def.base_pursuit) if "base_pursuit" in def else 0
	instance.base_parry = float(def.base_parry) if "base_parry" in def else 0.0
	instance.base_drain = float(def.base_drain) if "base_drain" in def else 0.0
	instance.base_crit_dmg = float(def.base_crit_dmg) if "base_crit_dmg" in def else 0.0
	instance.base_penetration = float(def.base_penetration) if "base_penetration" in def else 0.0
	instance.base_movement_speed = float(def.base_movement_speed) if "base_movement_speed" in def else 1.0
	instance.movement_speed = def.movement_speed if "movement_speed" in def else 3
	instance.shield = int(def.base_shield) if "base_shield" in def else 0
	instance.barriers = int(def.base_barriers) if "base_barriers" in def else 0
	
	instance.combo_count = def.base_combo_count
	instance.crit_rate = def.base_crit_rate
	instance.luck = def.base_luck
	instance.character_trait = def.character_trait
	
	# Initialize runtime skills (limit to 4)
	var skill_count = 0
	for skill in def.default_skills:
		if skill and skill_count < 4:
			instance.runtime_skills.append(skill)
			skill_count += 1
	
	return instance

func set_status_manager(manager: Node) -> void:
	status_manager_ref = manager

# --- Effective Stats Getters ---

func get_effective_attack() -> int:
	var base_mult = stat_modifiers.attack_multiplier
	if status_manager_ref and status_manager_ref.has_method("get_stat_multiplier"):
		base_mult *= status_manager_ref.get_stat_multiplier("attack")
	return int(round((attack_damage + stat_modifiers.attack_additive) * base_mult))

func get_effective_avoid() -> float:
	var total = base_avoid + stat_modifiers.avoid_additive
	# 可以加入 status_manager 修正
	return clamp(total, 0.0, 1.0)

func get_effective_accuracy() -> float:
	var total = base_accuracy + stat_modifiers.accuracy_additive
	# 可以加入 status_manager 修正
	return clamp(total, 0.0, 2.0) # 精準可以超過 1.0 以抵銷閃避

func get_effective_dr() -> float:
	var total = base_dr + stat_modifiers.dr_additive
	return clamp(total, 0.0, 0.95) # 減傷上限 95%

func get_effective_resistance() -> float:
	var total = base_resistance + stat_modifiers.res_additive
	return clamp(total, 0.0, 1.0)

func get_effective_reflect() -> float:
	var total = base_reflect + stat_modifiers.ref_additive
	return clamp(total, 0.0, 2.0) # 反射可以超過 100%

func get_effective_pursuit() -> int:
	var total = base_pursuit + stat_modifiers.pur_additive
	return max(0, total)

func get_effective_parry() -> float:
	var total = base_parry + stat_modifiers.par_additive
	return clamp(total, 0.0, 0.95) # 格擋上限 95%

func get_effective_drain() -> float:
	var total = base_drain + stat_modifiers.dra_additive
	return clamp(total, 0.0, 2.0) # 吸血可以超過 100%

func get_effective_crit_dmg() -> float:
	var total = base_crit_dmg + stat_modifiers.cdm_additive
	return max(0.0, total) # 這是額外加成

func get_effective_penetration() -> float:
	var total = base_penetration + stat_modifiers.pen_additive
	return clamp(total, 0.0, 1.0) # 貫穿上限 100%

func get_effective_movement_speed() -> float:
	var total = base_movement_speed * stat_modifiers.movement_speed_multiplier
	return max(0.1, total) # 速度保底 0.1

func get_move_distance(is_random: bool = true) -> int:
	if movement_speed is String:
		var parts = movement_speed.split("-")
		if parts.size() == 2:
			if is_random:
				return randi_range(int(parts[0]), int(parts[1]))
			else:
				# 敵人或固定距離取最大值
				return int(parts[1])
		return int(movement_speed)
	return int(movement_speed)

func get_effective_max_health() -> int:
	return int(floor((max_health + stat_modifiers.hp_additive) * stat_modifiers.hp_multiplier))

func get_effective_combo() -> float:
	return combo_count + stat_modifiers.combo_additive

# --- Stat Recalculation ---

func recalculate_stats() -> void:
	# Reset modifiers
	stat_modifiers.attack_multiplier = 1.0
	stat_modifiers.hp_multiplier = 1.0
	stat_modifiers.combo_additive = 0.0
	stat_modifiers.avoid_additive = 0.0
	stat_modifiers.accuracy_additive = 0.0
	stat_modifiers.dr_additive = 0.0
	stat_modifiers.res_additive = 0.0
	stat_modifiers.ref_additive = 0.0
	stat_modifiers.pur_additive = 0
	stat_modifiers.par_additive = 0.0
	stat_modifiers.dra_additive = 0.0
	stat_modifiers.cdm_additive = 0.0
	stat_modifiers.pen_additive = 0.0
	stat_modifiers.movement_speed_multiplier = 1.0
	# Reset additive
	stat_modifiers.attack_additive = 0
	stat_modifiers.hp_additive = 0
	
	if PartyManager:
		var active_traits = PartyManager.get_active_traits()
		for trait_data in active_traits:
			for effect in trait_data.effects:
				_apply_passive_effect(effect)
				
	# Apply Equipment Modifiers
	_apply_equipment_modifiers()
	
	stats_changed.emit()

func _apply_equipment_modifiers() -> void:
	var items = [weapon, armor, accessory]
	for item in items:
		if item == null: continue
		var mods = item.get("modifiers")
		if mods:
			for mod in mods:
				_apply_single_modifier(mod)

func _apply_single_modifier(mod: Resource) -> void:
	var m_type = mod.get("type")
	var m_value = mod.get("value")
	
	match m_type:
		ModifierData.ModifierType.ATK_ADDITIVE: stat_modifiers.attack_additive += int(m_value)
		ModifierData.ModifierType.HP_ADDITIVE: stat_modifiers.hp_additive += int(m_value)
		ModifierData.ModifierType.HP_MULTIPLIER: stat_modifiers.hp_multiplier *= m_value
		ModifierData.ModifierType.ATK_MULTIPLIER: stat_modifiers.attack_multiplier *= m_value
		ModifierData.ModifierType.DR_ADDITIVE: stat_modifiers.dr_additive += m_value
		ModifierData.ModifierType.AVOID_ADDITIVE: stat_modifiers.avoid_additive += m_value
		ModifierData.ModifierType.ACCURACY_ADDITIVE: stat_modifiers.accuracy_additive += m_value
		ModifierData.ModifierType.RES_ADDITIVE: stat_modifiers.res_additive += m_value
		ModifierData.ModifierType.REF_ADDITIVE: stat_modifiers.ref_additive += m_value
		ModifierData.ModifierType.PUR_ADDITIVE: stat_modifiers.pur_additive += int(m_value)
		ModifierData.ModifierType.PARRY_ADDITIVE: stat_modifiers.par_additive += m_value
		ModifierData.ModifierType.DRAIN_ADDITIVE: stat_modifiers.dra_additive += m_value
		ModifierData.ModifierType.CRIT_DMG_ADDITIVE: stat_modifiers.cdm_additive += m_value
		ModifierData.ModifierType.PEN_ADDITIVE: stat_modifiers.pen_additive += m_value

func _apply_passive_effect(effect: TraitEffect) -> void:
	if effect.trigger_type != TraitEffect.TriggerType.PASSIVE:
		return
		
	match effect.stat_type:
		TraitEffect.StatType.HP_MULTIPLIER:
			stat_modifiers.hp_multiplier *= effect.value
		TraitEffect.StatType.ATTACK_MULTIPLIER:
			stat_modifiers.attack_multiplier *= effect.value
		TraitEffect.StatType.COMBO_ADDITIVE:
			stat_modifiers.combo_additive += effect.value
		TraitEffect.StatType.DR_ADDITIVE:
			stat_modifiers.dr_additive += effect.value
		TraitEffect.StatType.RES_ADDITIVE:
			stat_modifiers.res_additive += effect.value
		TraitEffect.StatType.REF_ADDITIVE:
			stat_modifiers.ref_additive += effect.value
		TraitEffect.StatType.PUR_ADDITIVE:
			stat_modifiers.pur_additive += int(effect.value)
		TraitEffect.StatType.PAR_ADDITIVE:
			stat_modifiers.par_additive += effect.value
		TraitEffect.StatType.DRA_ADDITIVE:
			stat_modifiers.dra_additive += effect.value
		TraitEffect.StatType.CDM_ADDITIVE:
			stat_modifiers.cdm_additive += effect.value
		TraitEffect.StatType.PEN_ADDITIVE:
			stat_modifiers.pen_additive += effect.value

# --- Actions ---

## 防護罩增減 API (定值)
func modify_barriers(amount: int) -> void:
	barriers = max(0, barriers + amount)
	stats_changed.emit()

## 護盾增減 API (定值)
func modify_shield(amount: int) -> void:
	shield = max(0, shield + amount)
	stats_changed.emit()

## 護盾增減 API (按屬性百分比)
func add_shield_scaled(stat_name: String, ratio: float) -> void:
	var base_val = 0
	match stat_name.to_lower():
		"max_hp", "hp": base_val = get_effective_max_health()
		"attack", "str", "dex", "int", "pie": base_val = get_effective_attack()
	
	var amount = int(base_val * ratio)
	modify_shield(amount)

## 減傷率增減 API
func modify_dr_additive(amount: float) -> void:
	stat_modifiers.dr_additive += amount
	stats_changed.emit()

## 抗性增減 API
func modify_resistance_additive(amount: float) -> void:
	stat_modifiers.res_additive += amount
	stats_changed.emit()

## 反射率增減 API
func modify_reflect_additive(amount: float) -> void:
	stat_modifiers.ref_additive += amount
	stats_changed.emit()

## 追擊傷害增減 API
func modify_pursuit_additive(amount: int) -> void:
	stat_modifiers.pur_additive += amount
	stats_changed.emit()

## 格擋率增減 API
func modify_parry_additive(amount: float) -> void:
	stat_modifiers.par_additive += amount
	stats_changed.emit()

## 吸血率增減 API
func modify_drain_additive(amount: float) -> void:
	stat_modifiers.dra_additive += amount
	stats_changed.emit()

## 額外暴擊傷害增減 API
func modify_crit_dmg_additive(amount: float) -> void:
	stat_modifiers.cdm_additive += amount
	stats_changed.emit()

## 貫穿率增減 API
func modify_penetration_additive(amount: float) -> void:
	stat_modifiers.pen_additive += amount
	stats_changed.emit()

func take_damage(amount: int, ignore_barrier: bool = false, ignore_shield: bool = false, attacker: CharacterData = null) -> int:
	# 核心修復：強制停用防護罩穿透機制，確保防護罩始終有效
	var _unused_ignore_barrier = ignore_barrier # 標記為未使用以避免警告
	var effective_ignore_barrier = false
	
	# 0. 防護罩 (Barrier/防護罩) 最優先判定
	# 只要命中了且有防護罩，就必須優先扣除，不論後續傷害是否為 0
	if not effective_ignore_barrier and barriers > 0:
		barriers -= 1
		print("[CharacterData] Damage blocked by Barrier! Remaining barriers: ", barriers)
		barrier_triggered.emit()
		stats_changed.emit()
		return -1 # 回傳 -1 代表被防護罩抵擋
	
	# 1. 格擋 (Parry) 判定
	# 格擋有機率直接將傷害降為 0
	var parry_rate = get_effective_parry()
	if parry_rate > 0 and randf() < parry_rate:
		print("[CharacterData] Damage PARRIED!")
		parry_triggered.emit()
		stats_changed.emit() # 觸發 UI 更新 (例如顯示格擋文字)
		return -1 # 回傳 -1 代表被格擋
	
	# 2. 減傷率 (DR) 處理 (含貫穿 Penetration)
	var dr = get_effective_dr()
	if attacker != null:
		var pen = attacker.get_effective_penetration()
		if pen > 0:
			dr = max(0.0, dr - pen) # 貫穿直接減去目標的減傷率 (加減法邏輯)，最低為 0
			print("[CharacterData] DR reduced by Penetration (%.2f -> %.2f)" % [get_effective_dr(), dr])
			
	var damage_after_dr = int(amount * (1.0 - dr))
	var remaining_dmg = damage_after_dr
	
	# 核心修正：反射 (Reflect) 判定
	# 無論是否有防護罩或護盾，只要受到攻擊 (amount > 0) 就觸發反射
	if damage_after_dr > 0 and attacker != null:
		var ref_rate = get_effective_reflect()
		if ref_rate > 0:
			var ref_damage = int(damage_after_dr * ref_rate)
			if ref_damage > 0:
				print("[CharacterData] Reflecting %d damage! (Base: %d, Rate: %.2f)" % [ref_damage, damage_after_dr, ref_rate])
				reflect_triggered.emit(attacker, ref_damage, self)
	
	# 3. 扣除 Shield (護盾)
	if remaining_dmg > 0 and not ignore_shield and shield > 0:
		var shield_deduction = min(shield, remaining_dmg)
		shield -= shield_deduction
		remaining_dmg -= shield_deduction
		print("[CharacterData] Damage absorbed by Shield: ", shield_deduction, ". Remaining shield: ", shield)
	
	# 4. 扣除 HP (生命值)
	if remaining_dmg > 0:
		current_health = max(0, current_health - remaining_dmg)
		print("[CharacterData] Damage applied to HP: ", remaining_dmg, ". Current HP: ", current_health)
	
	health_changed.emit(current_health, get_effective_max_health())
	# 觸發 UI 更新 (為了同步護盾/防護罩顯示)
	stats_changed.emit()
	
	if current_health <= 0:
		died.emit()
	
	return damage_after_dr # 回傳減傷後的實際傷害

func _trigger_reflect(_dmg_base: int, _attacker: CharacterData) -> void:
	# 該內部函數已由 reflect_triggered 信號取代
	pass

func heal(amount: int) -> void:
	current_health = min(get_effective_max_health(), current_health + amount)
	health_changed.emit(current_health, get_effective_max_health())

# --- Skill Management ---

func equip(item: Resource) -> void:
	if item == null: return
	
	var i_slot = item.get("slot")
	match i_slot:
		0: weapon = item # WEAPON
		1: armor = item # ARMOR
		2: accessory = item # ACCESSORY
	
	recalculate_stats()

func unequip(slot_type: int) -> void:
	match slot_type:
		0: weapon = null # WEAPON
		1: armor = null # ARMOR
		2: accessory = null # ACCESSORY
	
	recalculate_stats()

func is_skill_on_cooldown(skill_name: String) -> bool:
	return skill_cooldowns.get(skill_name, 0) > 0

func set_skill_cooldown(skill_name: String, turns: int) -> void:
	if turns > 0:
		skill_cooldowns[skill_name] = turns

func decrement_cooldowns() -> void:
	var keys = skill_cooldowns.keys()
	for k in keys:
		if skill_cooldowns[k] > 0:
			skill_cooldowns[k] -= 1
		if skill_cooldowns[k] <= 0:
			skill_cooldowns.erase(k)
	has_used_skill_this_turn = false
	has_moved_this_turn = false

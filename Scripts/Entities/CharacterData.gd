class_name CharacterData extends RefCounted

## CharacterData
## 負責存儲單位的運行時數值、狀態與裝備

# --- 基礎定義 ---
var unit_def: UnitCard
var status_manager_ref: Node = null

# --- 運行時屬性 (Base) ---
var current_health: int
var max_health: int
var attack_damage: int
var shield: int = 0
var barriers: int = 0

# --- 進階屬性 ---
var base_avoid: float = 0.0
var base_accuracy: float = 1.0
var base_speed: float = 1.0
var base_dr: float = 0.0
var base_resistance: float = 0.0
var base_reflect: float = 0.0
var base_pursuit: int = 0
var base_parry: float = 0.0
var base_drain: float = 0.0
var base_crit_dmg: float = 0.0
var base_penetration: float = 0.0

# --- Combo 與 暴擊 ---
var combo_count: float
var combo_damage_scaling: float = 0.1
var crit_rate: float
var luck: int

# --- 其他狀態 ---
var character_trait: TraitData
var is_confused: bool = false
var saved_status_data: Array = []

# --- 屬性修正器 ---
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
	"crt_additive": 0.0,
	"luck_additive": 0,
	"shield_additive": 0,
	"barrier_additive": 0,
	"hp_additive": 0,
	"speed_additive": 0.0,
	"speed_multiplier": 1.0,
}

# --- 技能與物理數據 ---
var runtime_skill: UnitSkillData = null
var has_used_skill_this_turn: bool = false
var has_moved_this_turn: bool = false
var skill_cooldowns: Dictionary = {}
var accumulated_distance: float = 0.0
var is_moving_physics: bool = false

# --- 裝備欄 ---
var weapon: Resource = null
var armor: Resource = null
var accessory: Resource = null

# --- 信號 ---
@warning_ignore("unused_signal")
signal health_changed(current: int, max: int)
signal stats_changed
@warning_ignore("unused_signal")
signal reflect_triggered(attacker: CharacterData, amount: int, reflector: CharacterData)
@warning_ignore("unused_signal")
signal parry_triggered
@warning_ignore("unused_signal")
signal barrier_triggered
signal died
signal equipment_swapped(old_item: Resource, slot: int)
signal equipment_changed(new_item: Resource, slot: int)

# ============================================================================
# 初始化
# ============================================================================

static func create(def: UnitCard) -> CharacterData:
	var instance = CharacterData.new()
	instance.unit_def = def
	instance.max_health = int(def.max_health)
	instance.current_health = int(def.max_health)
	instance.attack_damage = def.attack_damage
	
	instance.base_avoid = float(def.base_avoid) if "base_avoid" in def else 0.0
	instance.base_accuracy = float(def.base_accuracy) if "base_accuracy" in def else 1.0
	instance.base_speed = float(def.base_speed) if "base_speed" in def else 1.0
	instance.base_dr = float(def.base_dr) if "base_dr" in def else 0.0
	instance.base_resistance = float(def.base_resistance) if "base_resistance" in def else 0.0
	instance.base_reflect = float(def.base_reflect) if "base_reflect" in def else 0.0
	instance.base_pursuit = int(def.base_pursuit) if "base_pursuit" in def else 0
	instance.base_parry = float(def.base_parry) if "base_parry" in def else 0.0
	instance.base_drain = float(def.base_drain) if "base_drain" in def else 0.0
	instance.base_crit_dmg = float(def.base_crit_dmg) if "base_crit_dmg" in def else 0.0
	instance.base_penetration = float(def.base_penetration) if "base_penetration" in def else 0.0
	instance.shield = int(def.base_shield) if "base_shield" in def else 0
	instance.barriers = int(def.base_barriers) if "base_barriers" in def else 0
	
	instance.combo_count = def.base_combo_count
	instance.crit_rate = def.base_crit_rate
	instance.luck = def.base_luck
	instance.character_trait = def.character_trait
	
	if def.default_skill:
		instance.runtime_skill = def.default_skill
	return instance

# ============================================================================
# 屬性獲取 (Effective Stats)
# ============================================================================

func get_effective_attack() -> int:
	var base_mult = stat_modifiers.attack_multiplier
	if status_manager_ref and status_manager_ref.has_method("get_stat_multiplier"):
		base_mult *= status_manager_ref.get_stat_multiplier("attack")
	return int(round((attack_damage + stat_modifiers.attack_additive) * base_mult))

func get_effective_avoid() -> float: return clamp(base_avoid + stat_modifiers.avoid_additive, 0.0, 1.0)
func get_effective_accuracy() -> float: return clamp(base_accuracy + stat_modifiers.accuracy_additive, 0.0, 2.0)
func get_effective_dr() -> float: return clamp(base_dr + stat_modifiers.dr_additive, 0.0, 0.95)
func get_effective_resistance() -> float: return clamp(base_resistance + stat_modifiers.res_additive, 0.0, 1.0)
func get_effective_reflect() -> float: return clamp(base_reflect + stat_modifiers.ref_additive, 0.0, 2.0)
func get_effective_pursuit() -> int: return max(0, base_pursuit + stat_modifiers.pur_additive)
func get_effective_parry() -> float: return clamp(base_parry + stat_modifiers.par_additive, 0.0, 0.95)
func get_effective_drain() -> float: return clamp(base_drain + stat_modifiers.dra_additive, 0.0, 2.0)
func get_effective_crit_dmg() -> float: return max(0.0, base_crit_dmg + stat_modifiers.cdm_additive)
func get_effective_penetration() -> float: return clamp(base_penetration + stat_modifiers.pen_additive, 0.0, 1.0)
func get_effective_crit_rate() -> float: return clamp(crit_rate + stat_modifiers.crt_additive + (float(get_effective_luck()) * 0.001), 0.0, 1.0)
func get_effective_luck() -> int: return luck + stat_modifiers.luck_additive
func get_effective_max_health() -> int: return int(floor((max_health + stat_modifiers.hp_additive) * stat_modifiers.hp_multiplier))
func get_effective_combo() -> float: return combo_count + stat_modifiers.combo_additive
func get_effective_speed() -> float: return (base_speed + stat_modifiers.speed_additive) * stat_modifiers.speed_multiplier

# ============================================================================
# 數值變更與結算
# ============================================================================

func take_damage(amount: int, _ignore_barrier: bool = false, _ignore_shield: bool = false, _attacker: CharacterData = null) -> int:
	# [已棄用] 統一由 AttackManager.resolve_combat 調度
	return take_damage_raw(amount)

func take_damage_raw(amount: int) -> int:
	"""純粹的數值扣除 API (由 AttackManager 調用)"""
	var initial_hp = current_health
	var remaining_dmg = amount
	
	if shield > 0:
		var shield_deduction = min(shield, remaining_dmg)
		shield -= shield_deduction
		remaining_dmg -= shield_deduction
	
	if remaining_dmg > 0:
		current_health = max(0, current_health - remaining_dmg)
	
	var hp_lost = initial_hp - current_health
	health_changed.emit(current_health, get_effective_max_health())
	stats_changed.emit()
	
	if current_health <= 0: died.emit()
	return hp_lost

func heal(amount: int) -> void:
	current_health = min(get_effective_max_health(), current_health + amount)
	health_changed.emit(current_health, get_effective_max_health())

# ============================================================================
# 裝備與冷卻管理
# ============================================================================

func recalculate_stats() -> void:
	# 重置所有修正器
	for key in stat_modifiers:
		if key.ends_with("_multiplier"): stat_modifiers[key] = 1.0
		else: stat_modifiers[key] = 0.0 if key.ends_with("_additive") else stat_modifiers[key]
	
	# 重新套用特質與裝備
	if PartyManager:
		# 恢復為僅獲取隊長的特質 (Leader Only)
		for trait_data in PartyManager.get_active_traits():
			for effect in trait_data.effects:
				if effect.trigger_type == TraitEffect.TriggerType.PASSIVE:
					_apply_passive_effect(effect)
	_apply_equipment_modifiers()
	stats_changed.emit()

func _apply_passive_effect(effect: TraitEffect) -> void:
	match effect.stat_type:
		TraitEffect.StatType.HP_MULTIPLIER: stat_modifiers.hp_multiplier *= effect.value
		TraitEffect.StatType.ATTACK_MULTIPLIER: stat_modifiers.attack_multiplier *= effect.value
		TraitEffect.StatType.COMBO_ADDITIVE: stat_modifiers.combo_additive += effect.value
		TraitEffect.StatType.DR_ADDITIVE: stat_modifiers.dr_additive += effect.value
		TraitEffect.StatType.RES_ADDITIVE: stat_modifiers.res_additive += effect.value
		TraitEffect.StatType.REF_ADDITIVE: stat_modifiers.ref_additive += effect.value
		TraitEffect.StatType.PUR_ADDITIVE: stat_modifiers.pur_additive += int(effect.value)
		TraitEffect.StatType.PAR_ADDITIVE: stat_modifiers.par_additive += effect.value
		TraitEffect.StatType.DRA_ADDITIVE: stat_modifiers.dra_additive += effect.value
		TraitEffect.StatType.CDM_ADDITIVE: stat_modifiers.cdm_additive += effect.value
		TraitEffect.StatType.PEN_ADDITIVE: stat_modifiers.pen_additive += effect.value

func _apply_equipment_modifiers() -> void:
	for item in [weapon, armor, accessory]:
		if item and item.get("modifiers"):
			for mod in item.modifiers:
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
		ModifierData.ModifierType.CRIT_RATE_ADDITIVE: stat_modifiers.crt_additive += m_value
		ModifierData.ModifierType.LUCK_ADDITIVE: stat_modifiers.luck_additive += int(m_value)
		ModifierData.ModifierType.SHIELD_ADDITIVE: stat_modifiers.shield_additive += int(m_value)
		ModifierData.ModifierType.BARRIER_ADDITIVE: stat_modifiers.barrier_additive += int(m_value)
		ModifierData.ModifierType.SPEED_ADDITIVE: stat_modifiers.speed_additive += m_value
		ModifierData.ModifierType.SPEED_MULTIPLIER: stat_modifiers.speed_multiplier *= m_value

func decrement_cooldowns() -> void:
	for k in skill_cooldowns.keys():
		skill_cooldowns[k] -= 1
		if skill_cooldowns[k] <= 0: skill_cooldowns.erase(k)
	has_used_skill_this_turn = false
	has_moved_this_turn = false

func equip(item: Resource) -> void:
	if item == null: return
	var i_slot = item.get("slot")
	var old_item = null
	
	match i_slot:
		0: 
			old_item = weapon
			weapon = item
		1: 
			old_item = armor
			armor = item
		2: 
			old_item = accessory
			accessory = item
			
	recalculate_stats()
	
	# 如果原本有裝備，發出信號以便在世界中噴出
	if old_item:
		equipment_swapped.emit(old_item, i_slot)
	equipment_changed.emit(item, i_slot)

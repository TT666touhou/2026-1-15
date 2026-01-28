extends Resource
class_name ModifierData

enum ModifierType {
	ATK_ADDITIVE,
	HP_ADDITIVE,
	DR_ADDITIVE,
	AVOID_ADDITIVE,
	ACCURACY_ADDITIVE,
	RES_ADDITIVE,
	REF_ADDITIVE,
	PUR_ADDITIVE,
	PARRY_ADDITIVE,
	DRAIN_ADDITIVE,
	CRIT_DMG_ADDITIVE,
	PEN_ADDITIVE,
	CRIT_RATE_ADDITIVE,
	LUCK_ADDITIVE,
	SHIELD_ADDITIVE,
	BARRIER_ADDITIVE,
	SPEED_ADDITIVE,
	SPEED_MULTIPLIER,
	ATK_MULTIPLIER,
	HP_MULTIPLIER
}

# Added a comment to force re-parse

@export var type: ModifierType
@export var value: float

# 用於調試或動態縮放的基礎資料 (不一定要導出)
var base_value: float = 0.0
var variance: float = 1.0

func get_modifier_text() -> String:
	var sign_str = "+" if value >= 0 else ""
	var val_str = ""
	var is_percent = false
	
	match type:
		ModifierType.ATK_ADDITIVE: val_str = "ATK"
		ModifierType.HP_ADDITIVE: val_str = "HP"
		ModifierType.PUR_ADDITIVE: val_str = "PUR"
		
		ModifierType.DR_ADDITIVE: 
			val_str = "DR"
			is_percent = true
		ModifierType.AVOID_ADDITIVE: 
			val_str = "AVD"
			is_percent = true
		ModifierType.ACCURACY_ADDITIVE: 
			val_str = "ACC"
			is_percent = true
		ModifierType.RES_ADDITIVE: 
			val_str = "RES"
			is_percent = true
		ModifierType.REF_ADDITIVE: 
			val_str = "REF"
			is_percent = true
		ModifierType.PARRY_ADDITIVE: 
			val_str = "PRY"
			is_percent = true
		ModifierType.DRAIN_ADDITIVE: 
			val_str = "DRN"
			is_percent = true
		ModifierType.CRIT_DMG_ADDITIVE: 
			val_str = "CDM"
			is_percent = true
		ModifierType.PEN_ADDITIVE: 
			val_str = "PEN"
			is_percent = true
		ModifierType.CRIT_RATE_ADDITIVE:
			val_str = "CRT"
			is_percent = true
		ModifierType.LUCK_ADDITIVE:
			val_str = "LUK"
		ModifierType.SHIELD_ADDITIVE:
			val_str = "SHD"
		ModifierType.BARRIER_ADDITIVE:
			val_str = "BAR"
		ModifierType.SPEED_ADDITIVE:
			val_str = "SPD"
		ModifierType.SPEED_MULTIPLIER:
			val_str = "SPD %"
			is_percent = true
			
		ModifierType.ATK_MULTIPLIER: 
			val_str = "ATK %"
			is_percent = true
		ModifierType.HP_MULTIPLIER: 
			val_str = "HP %"
			is_percent = true

	if is_percent:
		return "%s %s%d%%" % [val_str, sign_str, int(value * 100)]
	else:
		return "%s %s%d" % [val_str, sign_str, int(round(value))]


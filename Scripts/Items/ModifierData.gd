extends Resource
class_name ModifierData

enum ModifierType {
	STR_ADDITIVE,
	DEX_ADDITIVE,
	INT_ADDITIVE,
	PIE_ADDITIVE,
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
	STR_MULTIPLIER,
	DEX_MULTIPLIER,
	INT_MULTIPLIER,
	PIE_MULTIPLIER,
	HP_MULTIPLIER
}

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
		ModifierType.STR_ADDITIVE: val_str = "STR"
		ModifierType.DEX_ADDITIVE: val_str = "DEX"
		ModifierType.INT_ADDITIVE: val_str = "INT"
		ModifierType.PIE_ADDITIVE: val_str = "PIE"
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
			
		ModifierType.STR_MULTIPLIER: 
			val_str = "STR %"
			is_percent = true
		ModifierType.DEX_MULTIPLIER: 
			val_str = "DEX %"
			is_percent = true
		ModifierType.INT_MULTIPLIER: 
			val_str = "INT %"
			is_percent = true
		ModifierType.PIE_MULTIPLIER: 
			val_str = "PIE %"
			is_percent = true
		ModifierType.HP_MULTIPLIER: 
			val_str = "HP %"
			is_percent = true

	if is_percent:
		return "%s %s%d%%" % [val_str, sign_str, int(value * 100)]
	else:
		return "%s %s%d" % [val_str, sign_str, int(round(value))]


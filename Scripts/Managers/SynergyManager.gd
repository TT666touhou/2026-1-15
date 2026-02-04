extends Node

# SynergyManager.gd
# 負責管理特質（Trait）的註冊、計數與等級觸發

signal synergy_updated(trait_id: String, count: int, level: int)

var trait_definitions = {} # trait_id -> Resource/Dictionary
var trait_counts = {}      # trait_id -> int
var active_levels = {}     # trait_id -> int

func register_trait(trait_def: Variant) -> void:
	var tid = trait_def.get("trait_id")
	trait_definitions[tid] = trait_def
	if not trait_counts.has(tid):
		trait_counts[tid] = 0
		active_levels[tid] = 0

func get_count(trait_id: String) -> int:
	return trait_counts.get(trait_id, 0)

func set_debug_count(trait_id: String, count: int) -> void:
	trait_counts[trait_id] = max(0, count)
	_update_active_level(trait_id)

## 設定特質數量（裝備標籤計數用）
func set_count(trait_id: String, count: int) -> void:
	trait_counts[trait_id] = max(0, count)
	_update_active_level(trait_id)

func _update_active_level(trait_id: String) -> void:
	var def = trait_definitions.get(trait_id)
	if not def: return
	
	var count = trait_counts[trait_id]
	var thresholds = def.get("thresholds")
	var new_level = 0
	
	for i in range(thresholds.size()):
		if count >= thresholds[i]:
			new_level = i + 1
		else:
			break
			
	if active_levels.get(trait_id, -1) != new_level:
		active_levels[trait_id] = new_level
		synergy_updated.emit(trait_id, count, new_level)

## 回傳特質完整資訊供 Tooltip 使用：trait_name, thresholds, effect_descriptions, current_count, current_level
func get_trait_full_info(trait_id: String) -> Dictionary:
	var def = trait_definitions.get(trait_id)
	if not def:
		return {}
	var count = trait_counts.get(trait_id, 0)
	var th = def.get("thresholds")
	var thresholds = th if th != null else []
	var level = 0
	for i in range(thresholds.size()):
		if count >= thresholds[i]:
			level = i + 1
		else:
			break
	
	var tn = def.get("trait_name")
	var t_name = tn if tn != null else ""
	var ed = def.get("effect_descriptions")
	var effect_descriptions = ed if ed != null else []
	
	return {
		"trait_id": trait_id,
		"trait_name": t_name,
		"thresholds": thresholds,
		"effect_descriptions": effect_descriptions,
		"current_count": count,
		"current_level": level
	}

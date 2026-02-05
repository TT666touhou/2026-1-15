extends Node

# SynergyManager.gd
# 負責管理特質（Trait）的註冊、計數與等級觸發

signal synergy_updated(trait_id: String, count: int, level: int)

var trait_definitions = {} # trait_id -> Resource/Dictionary
var trait_counts = {}      # trait_id -> int
var active_levels = {}     # trait_id -> int
var effect_handlers = {}   # trait_id -> SynergyEffect instance

func register_trait(trait_def: Variant) -> void:
	var tid = trait_def.get("trait_id")
	trait_definitions[tid] = trait_def
	if not trait_counts.has(tid):
		trait_counts[tid] = 0
		active_levels[tid] = 0
	
	# 如果定義中有指定效果腳本，則實例化它
	var script = trait_def.get("effect_script")
	if script:
		effect_handlers[tid] = script.new()

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
		# 通知所有單位重新計算數值
		get_tree().call_group("grid_entities", "refresh_stats")

## 掃描全隊裝備並更新所有羈絆計數
func update_party_synergies() -> void:
	# 1. 重置計數
	for tid in trait_counts:
		trait_counts[tid] = 0
	
	# 2. 彙整所有玩家單位的標籤
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		var data = player.get("character_data") if "character_data" in player else null
		if data and data.has_method("get_all_active_traits"):
			for t_res in data.get_all_active_traits():
				var tid = t_res.get("trait_id")
				if tid and trait_counts.has(tid):
					trait_counts[tid] += 1
	
	# 3. 觸發等級更新
	for tid in trait_counts:
		_update_active_level(tid)

## 供 CharacterData 在 recalculate_stats 時調用
func apply_synergies_to_unit(data: CharacterData) -> void:
	for tid in active_levels:
		var level = active_levels[tid]
		if level > 0 and effect_handlers.has(tid):
			# 核心規則：只有身上帶有該標籤的單位會享有該等級的強化
			if data.has_method("has_trait") and data.has_trait(tid):
				effect_handlers[tid].apply_effect(data, trait_counts[tid], level)

## 觸發房間進入時的特殊羈絆效果
## [相關外部文件]: TurnManager.gd (啟動序列第五步呼叫此函式)
func trigger_room_start_synergies(members: Array) -> void:
	if members.is_empty(): return
	print("[SynergyManager] Triggering room start synergies for %d members." % members.size())
	
	for member in members:
		var data = member.get("character_data") if "character_data" in member else null
		if not data: continue
		
		for tid in active_levels:
			var level = active_levels[tid]
			if level > 0 and effect_handlers.has(tid):
				var handler = effect_handlers[tid]
				if handler.has_method("on_room_start") and data.has_method("has_trait") and data.has_trait(tid):
					handler.on_room_start(data, level)

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

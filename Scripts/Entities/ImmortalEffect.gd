extends RefCounted

## Immortal (不朽) 羈絆效果邏輯
func apply_effect(data: CharacterData, _count: int, level: int) -> void:
	var dr_bonus := 0.0
	match level:
		1: dr_bonus = 0.2  # 1件: 20% 減傷
		2: dr_bonus = 0.4  # 4件: 40% 減傷
		3: dr_bonus = 0.6  # 7件: 60% 減傷
	
	# 套用到 CharacterData 的修正器中
	data.stat_modifiers.dr_additive += dr_bonus

## 切換房間時觸發的特殊邏輯
func on_room_start(data: CharacterData, level: int) -> void:
	# 僅在 Level 3 (7件) 時觸發 50% MaxHP 護盾
	if level >= 3:
		var shield_amount = int(data.get_effective_max_health() * 0.5)
		if data.has_method("gain_shield"):
			data.gain_shield(shield_amount)
		else:
			data.shield = shield_amount
			data.stats_changed.emit()
		
		print("[ImmortalEffect] Room Start: Applied %d shield to %s" % [shield_amount, data.unit_def.display_name if data.unit_def else "Unit"])

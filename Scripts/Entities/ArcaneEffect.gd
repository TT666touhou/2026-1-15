extends RefCounted

## Arcane (奧術) 羈絆效果邏輯
func apply_effect(data: CharacterData, _count: int, level: int) -> void:
	var bonus := 0.0
	match level:
		1: bonus = 0.3  # 1件: +30%
		2: bonus = 0.6  # 3件: +60%
		3: bonus = 0.9  # 5件: +90%
		4: bonus = 3.0  # 7件: +300%
	
	# 套用到 CharacterData 的修正器中
	data.stat_modifiers.skill_damage_multiplier += bonus
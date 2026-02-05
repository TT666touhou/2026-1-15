extends RefCounted

## Crimson (緋紅) 羈絆效果邏輯
func apply_effect(data: CharacterData, _count: int, level: int) -> void:
	# 根據等級設定觸發門檻與吸血率
	# 規則：不疊加 (不使用 _count)，僅由當前 Party 達到的最高 level 決定
	match level:
		1: # 門檻 60, 吸血 1% (0.01)
			data.crimson_threshold = 60
			data.crimson_drain_rate = 0.01
		2: # 門檻 10, 吸血 1% (0.01)
			data.crimson_threshold = 10
			data.crimson_drain_rate = 0.01
		3: # 門檻 10, 吸血 1%, 數值爆發 (ATK x5, HP x10)
			data.crimson_threshold = 10
			data.crimson_drain_rate = 0.01
			data.stat_modifiers.attack_multiplier *= 5.0
			data.stat_modifiers.hp_multiplier *= 10.0

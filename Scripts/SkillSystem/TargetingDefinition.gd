extends Resource
class_name TargetingDefinition

enum ScopeType {
	SINGLE,
	AREA_CIRCLE,
	AREA_SQUARE,
	AREA_CROSS,
	GLOBAL,
	GLOBAL_CHECKER_A,
	GLOBAL_CHECKER_B,
	AREA_QUEEN,
	AREA_PATTERN,
	AREA_X
}

enum TargetFilter {
	ALLY,
	ENEMY,
	ALL,
	SELF
}

@export var scope_type: ScopeType = ScopeType.SINGLE
@export var aoe_radius: int = 0
@export var origin_is_self: bool = false # 若為 true，範圍計算的中心點強制設為施法者位置
@export var target_filter: TargetFilter = TargetFilter.ENEMY
@export var can_target_empty: bool = false

# For AREA_PATTERN: A 7x7 bitmask or array. 
@export var pattern_7x7: Array[bool] = []

func get_targeting_text(targeting_type: int) -> String:
	var scope_text = ""
	var r = aoe_radius
	
	match scope_type:
		ScopeType.SINGLE:
			scope_text = "[color=cyan]單體[/color]"
		ScopeType.AREA_CIRCLE, ScopeType.AREA_SQUARE, ScopeType.AREA_CROSS, ScopeType.AREA_QUEEN, ScopeType.AREA_X:
			if r >= 7:
				scope_text = "[color=cyan]全圖範圍[/color]"
			else:
				match scope_type:
					ScopeType.AREA_CIRCLE:
						scope_text = "[color=cyan]半徑為 %d 的圓形範圍[/color]" % r
					ScopeType.AREA_SQUARE:
						scope_text = "[color=cyan]半徑為 %d 的矩形範圍[/color]" % r
					ScopeType.AREA_CROSS:
						scope_text = "[color=cyan]半徑為 %d 的十字範圍[/color]" % r
					ScopeType.AREA_QUEEN:
						scope_text = "[color=cyan]半徑為 %d 的米字型範圍[/color]" % r
					ScopeType.AREA_X:
						scope_text = "[color=cyan]半徑為 %d 的 X 型範圍[/color]" % r
		ScopeType.GLOBAL:
			scope_text = "[color=cyan]全圖範圍[/color]"
		ScopeType.GLOBAL_CHECKER_A, ScopeType.GLOBAL_CHECKER_B:
			scope_text = "[color=cyan]全圖棋盤格範圍[/color]"
		ScopeType.AREA_PATTERN:
			scope_text = "[color=cyan]自定義形狀範圍[/color]"
		_:
			scope_text = "[color=cyan]指定範圍[/color]"
	
	var target_text = "單位"
	match target_filter:
		TargetFilter.ALLY:
			target_text = "[color=green]友軍[/color]"
		TargetFilter.ENEMY:
			target_text = "[color=red]敵人[/color]"
		TargetFilter.ALL:
			target_text = "所有單位"
		TargetFilter.SELF:
			target_text = "[color=green]自身[/color]"
	
	var origin_text = "對"
	if targeting_type == 1: # ABSOLUTE
		origin_text = "於地圖中央 "
	elif not origin_is_self:
		origin_text = "對落點 "
	else:
		origin_text = "對自身 "
	
	return origin_text + scope_text + " 內的" + target_text

func _init() -> void:
	if pattern_7x7.is_empty():
		pattern_7x7.resize(49)
		pattern_7x7.fill(false)

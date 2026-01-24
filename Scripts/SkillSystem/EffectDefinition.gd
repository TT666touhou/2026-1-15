extends Resource
class_name EffectDefinition

enum EffectType {
	HEAL,
	DAMAGE,
	ADD_STATUS,
	REMOVE_STATUS,
	MODIFY_RESOURCE,
	MOVE
}

enum ValueCalculation {
	FIXED,
	PERCENT_TARGET_ATK,
	PERCENT_TARGET_HP,
	PERCENT_TARGET_LOST_HP,
	PERCENT_CASTER_ATK,
	POKER_POINTS
}

@export var effect_type: EffectType
@export var value_calculation: ValueCalculation = ValueCalculation.FIXED
@export var base_value: float = 0.0

@export_group("Move Settings")
@export var move_direction: Vector2i = Vector2i.ZERO

@export_group("Penetration")
@export var ignore_barrier: bool = false
@export var ignore_shield: bool = false

@export_group("Status Settings")
@export var status_to_apply: StatusDefinition
## 狀態的持續回合數。設為 0 表示使用 Status Resource 的預設值。
@export var status_duration: int = 0

func get_effect_text(scaling_desc: String) -> String:
	match effect_type:
		EffectType.DAMAGE:
			var damage_label = "傷害"
			if ignore_shield:
				damage_label = "[color=cyan]穿透傷害[/color]"
			return "造成 %s %s" % [scaling_desc, damage_label]
		EffectType.HEAL:
			return "回復 %s 生命值" % [scaling_desc]
		EffectType.ADD_STATUS:
			if status_to_apply:
				var status_desc = status_to_apply.get_status_description()
				var duration = status_duration if status_duration > 0 else status_to_apply.duration_turns
				return "使目標 [[color=cyan]%s[/color]](持續 %d 回合)" % [status_desc, duration]
		EffectType.MOVE:
			var dir_name = "指定方向"
			if move_direction == Vector2i.UP: dir_name = "往上"
			elif move_direction == Vector2i.DOWN: dir_name = "往下"
			elif move_direction == Vector2i.LEFT: dir_name = "往左"
			elif move_direction == Vector2i.RIGHT: dir_name = "往右"
			return "%s移動 %s 距離" % [dir_name, scaling_desc]
	return ""

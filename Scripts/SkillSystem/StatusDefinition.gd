extends Resource
class_name StatusDefinition

enum BehaviorType {
	STAT_MODIFIER,
	RESTRICTION,
	OVER_TIME,
	TRIGGER,
	SHIELD
}

enum StackingRule {
	OVERRIDE,
	INDEPENDENT,
	STACK_VALUE
}

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var icon_scene_path: String = "" # Optional: Path to custom StatusIcon scene (e.g., "res://Scenes/UI/Status/StatusIcon_AtkUp.tscn")
@export var is_debuff: bool = false # True for negative effects, False for buffs
@export var behavior_type: BehaviorType
@export var stacking_rule: StackingRule = StackingRule.OVERRIDE
@export var duration_turns: int = 1
@export var params: Dictionary = {}

const STAT_NAMES = {
	"attack": "[color=#ff6666]力量[/color]",
	"str": "[color=#ff6666]力量[/color]",
	"dex": "[color=#66ff66]技巧[/color]",
	"int": "[color=#6666ff]智力[/color]",
	"pie": "[color=#ffff66]信仰[/color]",
	"hp": "最大生命值",
	"damage_received": "受到的傷害"
}

func get_status_description() -> String:
	if behavior_type == BehaviorType.STAT_MODIFIER:
		var stat_key = params.get("stat", "")
		var value = params.get("value", 0.0)
		var stat_display = STAT_NAMES.get(stat_key, stat_key)
		var val_abs = int(round(abs(value) * 100))
		
		if stat_key == "damage_received":
			if value > 0:
				return "%s增加 [color=red]%d%%[/color]" % [stat_display, val_abs]
			else:
				return "%s降低 [color=yellow]%d%%[/color]" % [stat_display, val_abs]
		else:
			if value > 0:
				return "%s提升 [color=yellow]%d%%[/color]" % [stat_display, val_abs]
			else:
				return "%s降低 [color=red]%d%%[/color]" % [stat_display, val_abs]

	match id:
		"poison":
			var dmg = params.get("damage", 0)
			return "每回合受到 [color=red]%d[/color] 點傷害" % dmg
		"regen":
			var val = params.get("value", 0)
			return "每回合回復 [color=green]%d[/color] 點生命值" % val
		_:
			return display_name
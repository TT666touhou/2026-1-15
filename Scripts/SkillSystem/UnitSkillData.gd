extends Resource
class_name UnitSkillData

enum ExecutionMode {
	DIRECT,        # 兩段式確認：點擊 -> 確認 -> 發動
	MOVE_TRIGGER,  # 移動後發動：點擊 -> 移動 -> 自動發動
	MOVEMENT       # 移動技能：點擊 -> 移動 -> 完成 (不結束回合)
}

enum TargetingType {
	RELATIVE,      # 相對位置：以單位為中心
	ABSOLUTE       # 絕對位置：地圖固定位置
}

@export var skill_name: String = "New Skill"
@export var description: String = ""
@export var icon: Texture2D

@export_group("Skill Logic")
@export var execution_mode: ExecutionMode = ExecutionMode.DIRECT
@export var targeting_type: TargetingType = TargetingType.RELATIVE
@export var cooldown_turns: int = 0
@export var is_accurate: bool = false # 若為 true，則跳過命中判定 (必中)

@export_group("Scaling")
@export var scaling_configs: Array[Dictionary] = [{"stat": "str", "weight": 1.0}]
@export var scaling_multiplier: float = 1.0

@export_group("Targeting & Effects")
@export var targeting: TargetingDefinition
@export var effects: Array[EffectDefinition] = []

@export_group("Movement & Action Range")
@export var is_move_skill: bool = false
@export var post_move_targeting: TargetingDefinition 
@export var post_move_effects: Array[EffectDefinition] = []

func validate_config() -> bool:
	var is_valid = true
	
	# 檢查基礎選取範圍是否為 SINGLE
	if targeting and targeting.scope_type != TargetingDefinition.ScopeType.SINGLE:
		push_error("[UnitSkillData] Skill '%s' must use SINGLE scope for 'targeting' (selection)." % skill_name)
		is_valid = false
	
	# 檢查移動技能或有效果的技能是否有定義 post_move_targeting
	if (execution_mode != ExecutionMode.MOVEMENT or not effects.is_empty()) and not post_move_targeting:
		push_error("[UnitSkillData] Skill '%s' must have 'post_move_targeting' defined for its effects." % skill_name)
		is_valid = false
	
	# 檢查絕對位置與自身中心的衝突
	if targeting_type == TargetingType.ABSOLUTE and post_move_targeting and post_move_targeting.origin_is_self:
		push_error("[UnitSkillData] Skill '%s' config error: ABSOLUTE targeting cannot use 'origin_is_self' for its effect range." % skill_name)
		is_valid = false
		
	return is_valid

func get_dynamic_description() -> String:
	var mode_prefix = ""
	var main_body = ""
	
	if execution_mode == ExecutionMode.MOVEMENT:
		# 1. 移動技能專屬：標題與核心動作
		mode_prefix = "【移動後不結束回合】"
		main_body = "移動至目標位置"
		
		# 2. 處理後續效果
		var effect_texts: Array[String] = []
		for effect in effects:
			var scaling_text = _get_formatted_scaling_text(effect.base_value)
			var txt = effect.get_effect_text(scaling_text)
			if txt != "" :
				effect_texts.append(txt)
		
		if not effect_texts.is_empty():
			# 如果有效果，顯示「接著」
			var targeting_to_use = post_move_targeting if post_move_targeting else targeting
			var target_desc = ""
			if targeting_to_use:
				target_desc = targeting_to_use.get_targeting_text(targeting_type)
			
			if target_desc != "":
				main_body += "，接著 " + target_desc + " " + "、".join(effect_texts)
			else:
				main_body += "，接著 " + "、".join(effect_texts)
	else:
		# 3. DIRECT 與 MOVE_TRIGGER 模式
		match execution_mode:
			ExecutionMode.DIRECT:
				mode_prefix = "【立刻發動】"
			ExecutionMode.MOVE_TRIGGER:
				mode_prefix = "【移動後觸發】"
		
		# 優先讀取 post_move_targeting (實際效果範圍)，若無則讀取基礎 targeting (選取範圍)
		var targeting_to_use = post_move_targeting if post_move_targeting else targeting
		var target_desc = ""
		if targeting_to_use:
			target_desc = targeting_to_use.get_targeting_text(targeting_type)
		
		var effect_texts: Array[String] = []
		for effect in effects:
			var scaling_text = _get_formatted_scaling_text(effect.base_value)
			var txt = effect.get_effect_text(scaling_text)
			if txt != "" :
				effect_texts.append(txt)
		
		if target_desc != "":
			main_body = target_desc + " " + "、".join(effect_texts)
		else:
			main_body = "、".join(effect_texts)
			
	return mode_prefix + main_body + "。"

func _get_formatted_scaling_text(base_val: float) -> String:
	if scaling_configs.is_empty():
		return "[color=red]無[/color]"
	
	var parts = []
	for config in scaling_configs:
		var s_name = _get_stat_display_name(config.get("stat", "str"))
		var weight = config.get("weight", 1.0)
		# 將 Effect 的 base_value、技能的 scaling_multiplier 以及屬性權重乘在一起
		var final_perc = int(round(base_val * scaling_multiplier * weight * 100))
		parts.append("[color=yellow]%d%%[/color] %s" % [final_perc, s_name])
	
	return " + ".join(parts)

func _get_stat_display_name(stat_key: String) -> String:
	match stat_key:
		"attack", "str": return "[color=#ff6666]力量[/color]"
		"hp": return "最大生命值"
		"luck": return "幸運"
		"dex": return "[color=#66ff66]技巧[/color]"
		"int": return "[color=#6666ff]智力[/color]"
		"pie": return "[color=#ffff66]信仰[/color]"
	return stat_key

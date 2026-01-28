extends PanelContainer
class_name SkillTooltipUI

# 基本的技能提示 UI（簡化版，用於兼容現有引用）

@onready var NameLabel: Label = %NameLabel
@onready var DescLabel: RichTextLabel = %DescLabel

func setup(skill: Resource) -> void:
	"""設置技能信息（簡化實現）"""
	if not skill:
		return
	
	if NameLabel:
		var skill_name = skill.get("skill_name") if skill.has_method("get") else "Unknown Skill"
		NameLabel.text = str(skill_name) if skill_name else "Unknown Skill"
	
	if DescLabel:
		var desc = ""
		if skill.get("manual_description") != "":
			desc = str(skill.get("manual_description"))
		elif skill.has_method("get_dynamic_description"):
			desc = skill.get_dynamic_description()
		elif skill.has("description"):
			desc = str(skill.get("description"))
		DescLabel.text = desc

extends PanelContainer
class_name SkillChargeSlot

@onready var icon_button: TextureButton = %IconButton
@onready var name_label: Label = %NameLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var charge_label: RichTextLabel = %ChargeLabel

var _skill: UnitSkillData
var _character_data: CharacterData

func setup(skill: UnitSkillData, data: CharacterData) -> void:
	_skill = skill
	_character_data = data
	
	if name_label:
		name_label.text = skill.skill_name
	if icon_button:
		icon_button.texture_normal = skill.icon
	
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	
	update_progress()

func _on_mouse_entered() -> void:
	if _skill:
		var hover_controller = get_tree().get_first_node_in_group("hover_info_controller")
		if hover_controller and hover_controller.has_method("show_skill_info"):
			hover_controller.show_skill_info(_skill, true)

func _on_mouse_exited() -> void:
	var hover_controller = get_tree().get_first_node_in_group("hover_info_controller")
	if hover_controller and hover_controller.has_method("show_skill_info"):
		hover_controller.show_skill_info(null)

func _process(_delta: float) -> void:
	update_progress()

func update_progress() -> void:
	if not _skill or not _character_data: return
	
	var current = _character_data.accumulated_distance
	var required = _skill.trigger_distance
	
	if required <= 0:
		progress_bar.max_value = 100
		progress_bar.value = 100
		charge_label.text = "[center]READY[/center]"
		return
		
	progress_bar.max_value = required
	progress_bar.value = current
	
	if current >= required:
		charge_label.text = "[center]READY[/center]"
		modulate = Color(1.2, 1.2, 1.2, 1.0) # 高亮
	else:
		charge_label.text = "[center]%d / %d[/center]" % [int(current), int(required)]
		modulate = Color.WHITE

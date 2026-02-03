extends Control
class_name DeploymentUI

@onready var left_panel: PanelContainer = $LeftPanel
@onready var member_list: VBoxContainer = $LeftPanel/Margin/VBox/ScrollContainer/MemberList
@onready var drop_indicator: ColorRect = $DropIndicator
@onready var settings_button: Button = %SettingsButton

# Leader Trait UI
@onready var leader_trait_panel: PanelContainer = %LeaderTraitPanel
@onready var trait_desc_label: Label = %TraitDescLabel

const MemberCardScene = preload("res://Scenes/UI/DeploymentMemberCard.tscn")

# Drag Ghost
var _drag_ghost: Control = null
var _current_drop_index: int = -1

func _ready() -> void:
	add_to_group("deployment_ui")
	
	# Connect to PartyManager updates
	if PartyManager:
		if not PartyManager.party_updated.is_connected(_on_party_updated):
			PartyManager.party_updated.connect(_on_party_updated)
	
	# F6 獨立運行測試
	if get_parent() == get_tree().root:
		_run_test_mode()
	
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)

func _on_settings_pressed() -> void:
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs and gs.has_method("toggle_pause"):
		gs.toggle_pause()
	else:
		# 如果 GlobalSettings 沒有 toggle_pause，嘗試直接實例化 PauseMenu (備用方案)
		var pause_scene = load("res://Scenes/UI/PauseMenu.tscn")
		if pause_scene:
			var pause_instance = pause_scene.instantiate()
			get_tree().root.add_child(pause_instance)

func _ensure_ui_refs() -> bool:
	if left_panel == null:
		left_panel = get_node_or_null("LeftPanel")
	if member_list == null:
		member_list = get_node_or_null("LeftPanel/Margin/VBox/ScrollContainer/MemberList")
	if drop_indicator == null:
		drop_indicator = get_node_or_null("DropIndicator")
	if member_list == null:
		push_warning("[DeploymentUI] MemberList not found; UI not ready yet.")
		return false
	return true

func _process(_delta: float) -> void:
	if _drag_ghost and _drag_ghost.visible:
		var mouse_pos = get_global_mouse_position()
		_drag_ghost.global_position = mouse_pos + Vector2(10, 10) # Offset
		_update_drop_indicator(mouse_pos)

func _on_party_updated() -> void:
	if PartyManager:
		initialize_party(PartyManager.get_members())

func initialize_party(members: Array[CharacterData]) -> void:
	if not _ensure_ui_refs():
		return
	# 清除現有列表
	for child in member_list.get_children():
		child.queue_free()
	
	# 隊伍為空則不處理
	if members.is_empty():
		_update_leader_trait_display(null)
		return

	# 隊長 (第一位) - 開啟高亮，放入列表
	add_member_card(members[0], member_list, true)

	# 隊員 (其餘) - 放入列表
	for i in range(1, members.size()):
		add_member_card(members[i], member_list, false)
		
	# 更新隊長特性顯示
	_update_leader_trait_display(members[0])

func _update_leader_trait_display(leader_data: CharacterData) -> void:
	if not leader_trait_panel: return
	
	if leader_data and leader_data.unit_def and leader_data.unit_def.character_trait:
		var character_trait = leader_data.unit_def.character_trait
		# 移除名稱顯示，僅顯示描述
		trait_desc_label.text = character_trait.description
		leader_trait_panel.show()
	else:
		trait_desc_label.text = "-"
		leader_trait_panel.show()

func add_member_card(data: CharacterData, parent_node: Control, is_leader: bool = false) -> void:
	var card = MemberCardScene.instantiate() as DeploymentMemberCard
	parent_node.add_child(card)
	card.setup(data)
	if is_leader:
		card.set_highlight(true)

func _update_drop_indicator(mouse_pos: Vector2) -> void:
	var found_target = false
	
	for i in range(member_list.get_child_count()):
		var child = member_list.get_child(i) as DeploymentMemberCard
		if not child: continue
		
		var rect = child.get_global_rect()
		if rect.has_point(mouse_pos):
			found_target = true
			var local_y = mouse_pos.y - rect.position.y
			var is_top = local_y < (rect.size.y / 2.0)
			
			drop_indicator.visible = true
			drop_indicator.size.x = rect.size.x
			drop_indicator.global_position.x = rect.position.x
			
			if is_top:
				drop_indicator.global_position.y = rect.position.y - 2 # Above
				_current_drop_index = i
			else:
				drop_indicator.global_position.y = rect.end.y - 2 # Below
				_current_drop_index = i + 1
			break
			
	if not found_target:
		drop_indicator.visible = false
		_current_drop_index = -1

func _run_test_mode() -> void:
	# --- 1. 初始化假資料 ---
	var u1_res = load("res://Resources/Cards/Unit_001.tres") # Soldier
	if u1_res:
		var data = CharacterData.create(u1_res)
		initialize_party([data])

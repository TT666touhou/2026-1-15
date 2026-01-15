extends Control
class_name DeploymentUI

@onready var left_panel: Panel = $LeftPanel
@onready var member_list: VBoxContainer = $LeftPanel/VBox/ScrollContainer/MemberList
@onready var drop_indicator: ColorRect = $DropIndicator

const MemberCardScene = preload("res://Scenes/UI/DeploymentMemberCard.tscn")

# Drag Ghost
var _drag_ghost: Control = null
var _drag_source_card: DeploymentMemberCard = null
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

func _process(_delta: float) -> void:
	if _drag_ghost and _drag_ghost.visible:
		var mouse_pos = get_global_mouse_position()
		_drag_ghost.global_position = mouse_pos + Vector2(10, 10) # Offset
		_update_drop_indicator(mouse_pos)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		_print_leader_skills()

func _print_leader_skills() -> void:
	if PartyManager:
		var active_traits = PartyManager.get_active_traits()
		if active_traits.is_empty():
			pass
		else:
			for i in range(active_traits.size()):
				var t = active_traits[i]
				print("Leader %d: %s - %s" % [i+1, t.trait_name, t.description])

func _on_party_updated() -> void:
	if PartyManager:
		initialize_party(PartyManager.get_members())

func initialize_party(members: Array[CharacterData]) -> void:
	# 清除現有列表
	for child in member_list.get_children():
		child.queue_free()
	
	# 隊伍為空則不處理
	if members.is_empty():
		return

	# 隊長 (第一位) - 開啟高亮，放入列表
	add_member_card(members[0], member_list, true)

	# 隊員 (其餘) - 放入列表
	for i in range(1, members.size()):
		add_member_card(members[i], member_list, false)

func add_member_card(data: CharacterData, parent_node: Control, is_leader: bool = false) -> void:
	var card = MemberCardScene.instantiate() as DeploymentMemberCard
	parent_node.add_child(card)
	card.setup(data)
	if is_leader:
		card.set_highlight(true)
		
	# Connect drag signals
	card.right_drag_started.connect(_on_card_right_drag_started)
	card.right_drag_ended.connect(_on_card_right_drag_ended)

# --- Right Drag Implementation ---

func _on_card_right_drag_started(card: DeploymentMemberCard) -> void:
	_drag_source_card = card
	
	# Create ghost
	if _drag_ghost:
		_drag_ghost.queue_free()
		
	_drag_ghost = Panel.new()
	_drag_ghost.size = Vector2(200, 50)
	_drag_ghost.modulate = Color(1, 1, 1, 0.5) # Transparent
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var label = Label.new()
	label.text = card.name_label.text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_FULL_RECT
	_drag_ghost.add_child(label)
	
	add_child(_drag_ghost)
	_drag_ghost.global_position = get_global_mouse_position()
	_drag_ghost.visible = true

func _on_card_right_drag_ended(card: DeploymentMemberCard, _end_pos: Vector2) -> void:
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null
		
	drop_indicator.visible = false
		
	if card != _drag_source_card:
		return # Should not happen
		
	# Perform Move if valid index
	if _current_drop_index != -1:
		if PartyManager:
			PartyManager.move_member(card.character_data, _current_drop_index)
			
	_drag_source_card = null
	_current_drop_index = -1

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
		# 模擬 PartyManager 在 F6 模式下不可用的情況，我們手動 populate UI
		initialize_party([data])

	# --- 2. 實例化 Unit001.tscn 以便在 F6 畫面中看到模型 ---
	var unit_scene = load("res://Scenes/Entities/Player/Unit001.tscn")
	if unit_scene:
		var unit_instance = unit_scene.instantiate()
		# 放在右側空白處
		unit_instance.global_position = Vector2(800, 400) 
		unit_instance.scale = Vector2(4, 4) # 放大以便觀察
		add_child(unit_instance)

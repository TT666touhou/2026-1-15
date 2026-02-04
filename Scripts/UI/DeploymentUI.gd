extends Control
class_name DeploymentUI

@onready var left_panel: PanelContainer = $LeftPanel
@onready var member_list: VBoxContainer = $LeftPanel/Margin/VBox/ScrollContainer/MemberList
@onready var drop_indicator: ColorRect = $DropIndicator
@onready var settings_button: Button = %SettingsButton
@onready var random_equip_button: Button = %RandomEquipButton
@onready var synergy_bookmark_list: VBoxContainer = %SynergyBookmarkList

# Leader Trait UI
@onready var leader_trait_panel: PanelContainer = %LeaderTraitPanel
@onready var trait_desc_label: Label = %TraitDescLabel

const MemberCardScene = preload("res://Scenes/UI/DeploymentMemberCard.tscn")
const SynergyItemUIScene = preload("res://Scenes/UI/Synergy/SynergyItemUI.tscn")

const TAG_DEF_PATHS = [
	"res://Resources/Equipment/Tags/Tag_Immortal.tres",
	"res://Resources/Equipment/Tags/Tag_Crimson.tres",
	"res://Resources/Equipment/Tags/Tag_SwiftWind.tres",
	"res://Resources/Equipment/Tags/Tag_Arcane.tres",
]
var _registered_trait_ids: Array[String] = []
const BOOKMARK_ALIGN_GAP := 0.0
const BOOKMARK_ALIGN_Y := 12.0

# Drag Ghost
var _drag_ghost: Control = null
var _current_drop_index: int = -1

func _ready() -> void:
	add_to_group("deployment_ui")
	var is_standalone := get_parent() == get_tree().root
	if is_standalone:
		_ensure_hover_controller()
	_register_equipment_tag_definitions()
	
	# Connect to PartyManager updates
	if PartyManager:
		if not PartyManager.party_updated.is_connected(_on_party_updated):
			PartyManager.party_updated.connect(_on_party_updated)
	
	# F6 獨立運行測試：三人隊伍
	if is_standalone:
		_run_test_mode()
	
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if random_equip_button:
		random_equip_button.pressed.connect(_on_random_equip_pressed)

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
		_refresh_equipment_tag_counts()
		refresh_synergy_bookmarks()
		return

	# 隊長 (第一位) - 開啟高亮，放入列表
	add_member_card(members[0], member_list, true)
	for data in members:
		if data.equipment_changed.is_connected(_on_member_equipment_changed):
			continue
		data.equipment_changed.connect(_on_member_equipment_changed)

	# 隊員 (其餘) - 放入列表
	for i in range(1, members.size()):
		add_member_card(members[i], member_list, false)
		
	# 更新隊長特性顯示
	_update_leader_trait_display(members[0])
	_refresh_equipment_tag_counts()
	refresh_synergy_bookmarks()

func _register_equipment_tag_definitions() -> void:
	if not SynergyManager:
		return
	_registered_trait_ids.clear()
	for path in TAG_DEF_PATHS:
		var res = load(path) as Resource
		if res and res.get("trait_id"):
			SynergyManager.register_trait(res)
			_registered_trait_ids.append(res.get("trait_id"))

func _refresh_equipment_tag_counts() -> void:
	if not SynergyManager:
		return
	var counts: Dictionary = {}
	for tid in _registered_trait_ids:
		counts[tid] = 0
	if PartyManager:
		for data in PartyManager.get_members():
			for item in [data.weapon, data.armor, data.accessory]:
				if item and item.get("traits"):
					for tag_res in item.traits:
						if tag_res and tag_res.get("trait_id"):
							var tid: String = tag_res.get("trait_id")
							if counts.has(tid):
								counts[tid] += 1
	for tid in _registered_trait_ids:
		SynergyManager.set_count(tid, counts.get(tid, 0))

func _on_member_equipment_changed(_new_item: Resource, _slot: int) -> void:
	_refresh_equipment_tag_counts()
	refresh_synergy_bookmarks()

func refresh_synergy_bookmarks() -> void:
	if not synergy_bookmark_list or not SynergyManager:
		return
	for child in synergy_bookmark_list.get_children():
		child.queue_free()
	for tid in _registered_trait_ids:
		var count: int = SynergyManager.get_count(tid)
		if count <= 0:
			continue
		var def = SynergyManager.trait_definitions.get(tid)
		if not def:
			continue
		var item = SynergyItemUIScene.instantiate()
		synergy_bookmark_list.add_child(item)
		if item.has_method("setup"):
			item.setup(def, count)
	call_deferred("_align_synergy_bookmarks_deferred")

func _align_synergy_bookmarks_deferred() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_align_synergy_bookmarks()

func _align_synergy_bookmarks() -> void:
	if not left_panel or not synergy_bookmark_list:
		return
	var panel_right = left_panel.global_position.x + left_panel.size.x
	for item in synergy_bookmark_list.get_children():
		if not (item is Control):
			continue
		var anchor = item.get_node_or_null("RightAnchor")
		if anchor and anchor is Control:
			var target_x = panel_right + BOOKMARK_ALIGN_GAP
			var delta = target_x - anchor.global_position.x
			item.global_position.x += delta
			item.global_position.y += BOOKMARK_ALIGN_Y

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

func _ensure_hover_controller() -> void:
	if get_tree().get_first_node_in_group("hover_info_controller") != null:
		return
	var HoverScript = load("res://Scripts/UI/HoverInfoController.gd")
	if HoverScript:
		var hc = Control.new()
		hc.set_script(HoverScript)
		hc.set_anchors_preset(Control.PRESET_FULL_RECT)
		hc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_tree().root.call_deferred("add_child", hc)
		get_tree().root.call_deferred("move_child", hc, 0)

func _on_random_equip_pressed() -> void:
	var members: Array[CharacterData] = []
	if PartyManager and PartyManager.get_members().size() > 0:
		members = PartyManager.get_members()
	else:
		for child in member_list.get_children() if member_list else []:
			var card = child as DeploymentMemberCard
			if card and card.character_data:
				members.append(card.character_data)
	if members.is_empty():
		return
	var data: CharacterData = members.pick_random()
	var slot_idx = randi_range(0, 2)
	var gen = get_node_or_null("/root/EquipmentGenerator")
	if not gen or not gen.has_method("generate_random_item_for_slot"):
		return
	var item = gen.generate_random_item_for_slot(5, slot_idx)
	if item:
		data.equip(item)

func _run_test_mode() -> void:
	# 三人隊伍：優先使用 PartyManager 已招募的成員（F6 時 _recruit_starters 會加 3 人）
	var members: Array[CharacterData] = []
	if PartyManager and PartyManager.get_members().size() > 0:
		members = PartyManager.get_members()
	if members.is_empty():
		var u1 = load("res://Resources/Cards/Unit_001.tres")
		var u2 = load("res://Resources/Cards/Unit_002.tres")
		var u3 = load("res://Resources/Cards/Unit_003.tres")
		if u1: members.append(CharacterData.create(u1))
		if u2: members.append(CharacterData.create(u2))
		if u3: members.append(CharacterData.create(u3))
	if members.is_empty():
		var mock = UnitCard.new()
		mock.display_name = "Debug"
		mock.max_health = 100
		mock.attack_damage = 10
		members = [CharacterData.create(mock), CharacterData.create(mock), CharacterData.create(mock)]
	initialize_party(members)

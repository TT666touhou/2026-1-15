extends PanelContainer
class_name EquipmentSlotUI

@onready var icon_rect: TextureRect = $Icon
var data: Resource = null
var hover_controller: Node = null

func _ready() -> void:
	# 調整為較大的視覺大小，48x48 在 UI 中更接近 1x1 grid 的感覺
	custom_minimum_size = Vector2(48, 48)
	size = Vector2(48, 48)
	
	# 確保 Icon 不會擋住滑鼠事件
	if has_node("Icon"):
		$Icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	hover_controller = get_tree().get_first_node_in_group("hover_info_controller")
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	
	mouse_filter = Control.MOUSE_FILTER_PASS

func _can_drop_data(_at_position: Vector2, drag_data: Variant) -> bool:
	if typeof(drag_data) != TYPE_DICTIONARY or drag_data.get("type") != "equipment":
		return false
	
	var item_resource = drag_data.get("data") as Resource
	if not item_resource: return false
	
	# 檢查裝備位類型是否匹配
	var item_slot = item_resource.get("slot")
	if name.contains("Weapon") and item_slot != 0: return false
	if name.contains("Armor") and item_slot != 1: return false
	if name.contains("Accessory") and item_slot != 2: return false
	
	return true

func _drop_data(_at_position: Vector2, drag_data: Variant) -> void:
	var item_resource = drag_data.get("data") as Resource
	var entity = drag_data.get("entity") as Node2D
	
	# 尋找所屬的 DeploymentMemberCard
	var parent_card = _find_parent_card()
	if parent_card and parent_card.has_method("equip_item"):
		if parent_card.equip_item(item_resource):
			if entity: 
				print("[EquipmentSlotUI] Freeing entity: ", entity.name)
				entity.queue_free()
				# 核心修正：同樣通知 DungeonManager
				var dungeon_mgr = Engine.get_main_loop().root.get_node_or_null("DungeonManager")
				if dungeon_mgr and dungeon_mgr.has_method("check_battle_status"):
					dungeon_mgr.call_deferred("check_battle_status")
			# 核心修正：裝備成功後，通知 DungeonManager 檢查房間狀態
			var dm = get_tree().root.get_node_or_null("DungeonManager")
			if dm and dm.has_method("check_battle_status"):
				dm.check_battle_status()

func _find_parent_card() -> DeploymentMemberCard:
	var p = get_parent()
	while p != null:
		if p is DeploymentMemberCard:
			return p
		p = p.get_parent()
	return null

func set_equipment(new_resource: Resource) -> void:
	data = new_resource
	var item_name = "NULL" if data == null else data.get("item_name")
	# print("[EquipmentSlotUI:%d] Setting data to: %s" % [get_instance_id(), item_name])
	
	if data and data.get("icon"):
		icon_rect.texture = data.icon
		icon_rect.visible = true
	else:
		icon_rect.texture = null
		icon_rect.visible = false

func _on_mouse_entered() -> void:
	var item_name = "NULL" if data == null else data.get("item_name")
	# print("[EquipmentSlotUI:%d] Mouse ENTERED. Current data: %s" % [get_instance_id(), item_name])
	if data and hover_controller and hover_controller.has_method("show_data_info"):
		hover_controller.show_data_info(data, true) # 標記為來自 UI 的懸停

func _on_mouse_exited() -> void:
	# print("[EquipmentSlotUI:%d] Mouse EXITED" % get_instance_id())
	if hover_controller and hover_controller.has_method("_hide_all"):
		hover_controller._hide_all()

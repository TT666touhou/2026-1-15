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

func set_equipment(new_data: Resource) -> void:
	data = new_data
	var item_name = "NULL" if data == null else data.get("item_name")
	print("[EquipmentSlotUI:%d] Setting data to: %s" % [get_instance_id(), item_name])
	
	if data and data.get("icon"):
		icon_rect.texture = data.icon
		icon_rect.visible = true
	else:
		icon_rect.texture = null
		icon_rect.visible = false

func _on_mouse_entered() -> void:
	var item_name = "NULL" if data == null else data.get("item_name")
	print("[EquipmentSlotUI:%d] Mouse ENTERED. Current data: %s" % [get_instance_id(), item_name])
	if data and hover_controller and hover_controller.has_method("show_data_info"):
		hover_controller.show_data_info(data, true) # 標記為來自 UI 的懸停

func _on_mouse_exited() -> void:
	print("[EquipmentSlotUI:%d] Mouse EXITED" % get_instance_id())
	if hover_controller and hover_controller.has_method("_hide_all"):
		hover_controller._hide_all()

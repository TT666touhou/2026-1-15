extends Control

# Proxy to handle drag from EquipmentEntity
var parent_entity: Node2D

func _ready() -> void:
	parent_entity = get_parent()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not parent_entity or not "equipment_data" in parent_entity:
		return null
		
	var equipment_data = parent_entity.get("equipment_data")
	if not equipment_data:
		return null
	
	# 1. 只隱藏網格上的 Sprite，不隱藏整個實體
	var grid_sprite = parent_entity.get_node_or_null("Sprite2D")
	if grid_sprite:
		grid_sprite.visible = false
	
	# 2. 建立預覽組件
	var preview = Control.new()
	preview.set_script(load("res://Scripts/UI/EquipmentDragPreview.gd"))
	
	# 獲取圖示
	var tex = equipment_data.get("icon")
	if not tex:
		# 預設戒指圖示
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://Tilesheet/colored-transparent_packed.png")
		atlas.region = Rect2(480, 288, 16, 16) # 戒指圖示
		tex = atlas
		
	# 初始化預覽
	preview.setup(tex)
	set_drag_preview(preview)
	
	return {
		"type": "equipment",
		"data": equipment_data,
		"entity": parent_entity
	}

# 處理拖拽結束 (不論成功或失敗)
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# 如果拖拽結束後 parent_entity 還存在 (代表沒被成功裝備並移除)，就恢復顯示 Sprite
		if is_instance_valid(parent_entity):
			var grid_sprite = parent_entity.get_node_or_null("Sprite2D")
			if grid_sprite:
				grid_sprite.visible = true

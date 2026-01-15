extends Node
class_name EditorGridSelector

## 編輯器專用網格選擇器
## 處理滑鼠點擊以放置或移除實體

signal cell_clicked(cell: Vector2i, button_index: int)
signal cell_hovered(cell: Vector2i)

var grid: Node
var preview_actor: Sprite2D = null
var current_card_preview: Resource = null # UnitCard

func _ready() -> void:
	grid = get_tree().get_first_node_in_group("grid")
	if grid == null:
		push_error("[EditorGridSelector] Grid not found")

func set_preview_card(card: Resource) -> void:
	current_card_preview = card
	_update_preview_visual()

func _update_preview_visual() -> void:
	if preview_actor:
		preview_actor.queue_free()
		preview_actor = null
		
	if current_card_preview == null:
		return
		
	# 根據不同類型的卡牌獲取對應的場景
	var scene = null
	if "unit_scene" in current_card_preview:
		scene = current_card_preview.get("unit_scene")
	elif "building_scene" in current_card_preview:
		scene = current_card_preview.get("building_scene")
	elif "prop_scene" in current_card_preview:
		scene = current_card_preview.get("prop_scene")
	
	if scene:
		var instance = scene.instantiate()
		var sprite = instance.get_node_or_null("Sprite2D")
		if sprite:
			preview_actor = Sprite2D.new()
			preview_actor.texture = sprite.texture
			preview_actor.region_enabled = sprite.region_enabled
			preview_actor.region_rect = sprite.region_rect
			preview_actor.hframes = sprite.hframes
			preview_actor.vframes = sprite.vframes
			preview_actor.frame = sprite.frame
			preview_actor.scale = sprite.scale
			preview_actor.modulate = Color(1, 1, 1, 0.5) # 半透明預覽
			
			# 設定為 Nearest 模式以符合像素風格
			preview_actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			
			add_child(preview_actor)
		instance.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if grid == null: return
	
	if event is InputEventMouseMotion:
		var camera = get_viewport().get_camera_2d()
		if camera:
			var world_pos = camera.get_global_mouse_position()
			var cell = grid.world_to_grid(world_pos)
			
			cell_hovered.emit(cell)
			
			if preview_actor:
				# 更新預覽位置
				# 需考慮 Footprint
				var footprint = current_card_preview.get("footprint_data")
				if footprint:
					preview_actor.global_position = grid.grid_to_world_center_footprint(cell, footprint)
				else:
					preview_actor.global_position = grid.grid_to_world_center(cell)
					
	elif event is InputEventMouseButton:
		if event.pressed:
			var camera = get_viewport().get_camera_2d()
			if camera:
				var world_pos = camera.get_global_mouse_position()
				var cell = grid.world_to_grid(world_pos)
				
				if grid.is_in_bounds(cell):
					cell_clicked.emit(cell, event.button_index)


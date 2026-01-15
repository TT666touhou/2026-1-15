extends GridEntity
class_name EquipmentEntity

@export var equipment_data: Resource

func _ready() -> void:
	# 確保有預設的 Footprint (1x1)
	if footprint_data == null:
		var fp_path = "res://Footprints/Footprint_1x1.tres"
		if ResourceLoader.exists(fp_path):
			footprint_data = load(fp_path)
		else:
			# 如果資源不存在，動態創建一個
			var fp = FootprintData.new()
			fp.occupied_cells = [Vector2i.ZERO] as Array[Vector2i]
			footprint_data = fp
			
	# 呼叫父類的 _ready 進行網格註冊
	super._ready()
	
	add_to_group("equipment_entities")
	
	# 如果沒有數據，隨機生成一個 (用於測試)
	if equipment_data == null:
		var floor_lvl = 1
		var dm = get_node_or_null("/root/DungeonManager")
		if dm and "current_floor" in dm:
			floor_lvl = dm.current_floor
			
		var gen = get_node_or_null("/root/EquipmentGenerator")
		if gen:
			equipment_data = gen.generate_random_item(floor_lvl)
			
		# 更新視覺圖示 (如果是生成的)
		_update_sprite_from_data()
	else:
		_update_sprite_from_data()

func _update_sprite_from_data() -> void:
	if equipment_data and equipment_data.get("icon"):
		var sprite = get_node_or_null("Sprite2D")
		if sprite:
			sprite.texture = equipment_data.icon
			# 裝備通常是單格 16x16，不需要 region，除非是特定的片集
			sprite.region_enabled = false 

func get_equipment_data() -> Resource:
	return equipment_data

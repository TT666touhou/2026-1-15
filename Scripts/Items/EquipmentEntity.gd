extends GridEntity
class_name EquipmentEntity

## 裝備實體
## 僅負責存儲數據與視覺更新，懸停偵測由 HoverInfoController 統一處理

@export var equipment_data: Resource

func _ready() -> void:
	# 確保有預設的 Footprint (1x1)
	if footprint_data == null:
		var fp_path = "res://Footprints/Footprint_1x1.tres"
		if ResourceLoader.exists(fp_path):
			footprint_data = load(fp_path)
			
	# 呼叫父類的 _ready 進行網格註冊
	super._ready()
	
	# 加入群組以便被控制器識別
	add_to_group("equipment_entities")
	
	# 確保滑鼠可偵測
	input_pickable = true
	
	# 延遲連結懸停信號，確保環境已穩定
	call_deferred("_setup_hover_signals")
	
	# 更新視覺
	_update_sprite_from_data()

func _setup_hover_signals() -> void:
	# 這裡我們其實不需要手動連結，因為 HoverInfoController 使用物理查詢
	# 但我們保留這個空函式以便未來擴充，並確保 input_pickable 為 true
	input_pickable = true

func _update_sprite_from_data() -> void:
	var sprite = get_node_or_null("Sprite2D")
	if not sprite: return
		
	if equipment_data:
		var tex = equipment_data.get("icon")
		if tex:
			sprite.texture = tex
			sprite.region_enabled = false 
		else:
			# Fallback: 預設戒指
			var default_atlas = load("res://Tilesheet/colored-transparent_packed.png")
			sprite.texture = default_atlas
			sprite.region_enabled = true
			sprite.region_rect = Rect2(480, 288, 16, 16)
		
		sprite.visible = true
		sprite.modulate.a = 1.0

func get_equipment_data() -> Resource:
	return equipment_data

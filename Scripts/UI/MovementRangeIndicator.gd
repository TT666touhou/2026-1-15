extends Node
class_name MovementRangeIndicatorController

## 原本的 MovementRangeIndicator 腳本 (被誤刪後恢復)
## 用於在 TileMapLayer 上繪製網格高亮

@export var indicator_layer_path: NodePath
@export var enable_debug_log: bool = false

@onready var indicator_layer: TileMapLayer = get_node_or_null(indicator_layer_path)

func _ready() -> void:
	add_to_group("movement_range_indicator")
	print("[MovementRangeIndicator] Controller ready. Path: ", indicator_layer_path)
	
	if not indicator_layer:
		# 嘗試自動尋找名為 MovementRangeIndicator 的同級節點
		indicator_layer = get_parent().get_node_or_null("MovementRangeIndicator")
		if indicator_layer:
			print("[MovementRangeIndicator] AUTO-FIX: Found indicator_layer via name search.")
		else:
			push_error("[MovementRangeIndicator] CRITICAL: No TileMapLayer found! Please assign indicator_layer_path in Inspector.")
	
	if indicator_layer:
		# 預設設置為像素過濾模式
		indicator_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _show_range_indicator(cells: Array, entity: Node) -> void:
	if not indicator_layer:
		print("[MovementRangeIndicator] CANNOT SHOW: indicator_layer is null!")
		return
		
	# 設置為不透明白色（原始顏色）
	indicator_layer.modulate = Color.WHITE
	# 確保像素風格紋理過濾
	indicator_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 保持層級在地面之上
	indicator_layer.z_index = 5
	
	var entity_name = "Unknown"
	if entity != null:
		entity_name = str(entity.name)
	print("[MovementRangeIndicator] Updating: ", entity_name, " | Cells: ", cells.size())
	
	# 清除舊的高亮
	indicator_layer.clear()
	
	if cells.is_empty():
		return
		
	# 繪製新的高亮
	for cell in cells:
		# 使用用戶指定的 (26, 14) 圖塊
		indicator_layer.set_cell(cell, 0, Vector2i(26, 14))
	
	print("[MovementRangeIndicator] Draw complete. Layer visibility: ", indicator_layer.visible, " | Modulate: ", indicator_layer.modulate, " | Z-Index: ", indicator_layer.z_index)

func clear_indicator() -> void:
	if indicator_layer:
		indicator_layer.clear()

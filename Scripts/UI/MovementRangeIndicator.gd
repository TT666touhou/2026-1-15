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
	# [需求變更] 指示器已由單位身上的 Sprite 進度箭頭取代
	pass

func clear_indicator() -> void:
	if indicator_layer:
		indicator_layer.clear()

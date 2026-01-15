extends Node2D
class_name Highlighter2D

## 高亮繪製器
## 繪製選擇框（格子/實體外框）

# Inspector 參數
@export var line_width: float = 2.0
@export var line_color: Color = Color.YELLOW
@export var fill_color: Color = Color(1.0, 1.0, 0.0, 0.1)  # 半透明填充

var _target_rect: Rect2 = Rect2()
var _is_visible: bool = false

func _ready() -> void:
	visible = false
	# 添加到 group 以便 GridSelector 可以找到
	add_to_group("selection_highlight")
	print("[Highlighter2D] Initialized and added to group")

func _draw() -> void:
	if not _is_visible:
		return
	
	# _target_rect 已經是本地座標（相對於當前節點）
	# 因為在 highlight_entity() 中已經將 global_position 設置為實體位置
	# 所以直接使用 _target_rect 繪製即可
	
	# 繪製填充矩形
	draw_rect(_target_rect, fill_color)
	
	# 繪製外框
	draw_rect(_target_rect, line_color, false, line_width)

func highlight_cell(cell: Vector2i) -> void:
	# 高亮單個格子
	var grid = get_tree().get_first_node_in_group("grid")
	if grid == null or not grid.has_method("grid_to_world"):
		push_error("[Highlighter2D] Grid not found or missing grid_to_world method")
		return
	
	var world_pos: Vector2 = grid.grid_to_world(cell)
	var cell_size: Vector2
	if "cell_size" in grid:
		cell_size = Vector2(grid.cell_size)
	else:
		cell_size = Vector2(16, 16)
	_target_rect = Rect2(world_pos, cell_size)
	_is_visible = true
	visible = true
	queue_redraw()

func highlight_rect(cell: Vector2i, size: Vector2i) -> void:
	# 高亮矩形區域（多格）
	var grid = get_tree().get_first_node_in_group("grid")
	if grid == null or not grid.has_method("grid_to_world"):
		push_error("[Highlighter2D] Grid not found or missing grid_to_world method")
		return
	
	var world_pos: Vector2 = grid.grid_to_world(cell)
	var cs: Vector2
	if "cell_size" in grid:
		cs = Vector2(grid.cell_size)
	else:
		cs = Vector2(16, 16)
	var world_size: Vector2 = Vector2(size.x * cs.x, size.y * cs.y)
	_target_rect = Rect2(world_pos, world_size)
	_is_visible = true
	visible = true
	queue_redraw()

func highlight_entity(entity: Node2D) -> void:
	# 高亮實體（使用實體的碰撞形狀或 Sprite 邊界）
	if entity == null:
		hide_highlight()
		return
	
	# 將高亮節點的位置設置為實體位置，這樣繪製時可以使用本地座標
	global_position = entity.global_position
	
	# 嘗試取得碰撞形狀
	var collision_shape: CollisionShape2D = null
	for child in entity.get_children():
		if child is CollisionShape2D:
			collision_shape = child
			break
	
	if collision_shape != null and collision_shape.shape != null:
		var shape = collision_shape.shape
		if shape is RectangleShape2D:
			var rect_shape = shape as RectangleShape2D
			# 使用本地座標（相對於實體中心）
			# CollisionShape2D 的 position 相對於實體，shape.size 是形狀大小
			var shape_offset = collision_shape.position
			var shape_size = rect_shape.size
			# 矩形從左上角開始，所以需要減去一半大小
			_target_rect = Rect2(shape_offset - shape_size * 0.5, shape_size)
		else:
			# 其他形狀，使用預設大小（本地座標）
			_target_rect = Rect2(Vector2(-8, -8), Vector2(16, 16))
	else:
		# 沒有碰撞形狀，使用 Sprite 邊界
		var sprite: Sprite2D = null
		for child in entity.get_children():
			if child is Sprite2D:
				sprite = child
				break
		
		if sprite != null:
			var sprite_rect = sprite.get_rect()
			# Sprite 的 get_rect() 返回的是相對於 Sprite 節點的本地座標矩形
			var sprite_offset = sprite.position
			_target_rect = Rect2(sprite_offset + sprite_rect.position, sprite_rect.size)
		else:
			# 預設大小（本地座標）
			_target_rect = Rect2(Vector2(-8, -8), Vector2(16, 16))
	
	_is_visible = true
	visible = true
	z_index = 100  # 確保顯示在其他實體之上
	queue_redraw()

func highlight_world_rect(rect: Rect2) -> void:
	# 直接高亮世界座標矩形
	_target_rect = rect
	_is_visible = true
	visible = true
	queue_redraw()

func hide_highlight() -> void:
	_is_visible = false
	visible = false
	queue_redraw()


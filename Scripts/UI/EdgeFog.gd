extends ColorRect

## EdgeFog 動態邊界控制
## 負責根據網格大小自動調整 Shader 的遮罩範圍，確保邊界在網格邊緣外 0.5 格

var grid: Grid
var camera: Camera2D

func _ready() -> void:
	grid = get_tree().get_first_node_in_group("grid")
	camera = get_viewport().get_camera_2d()
	
	if grid:
		if grid.has_signal("size_changed"):
			grid.size_changed.connect(update_mask)
		grid.cell_occupied_changed.connect(func(_c, _o): update_mask())
	
	# 初始更新
	call_deferred("update_mask")

func _process(_delta: float) -> void:
	# 如果相機或網格會移動，則在 _process 中更新
	update_mask()

func update_mask() -> void:
	if not grid or not camera or not material:
		return
		
	var mat = material as ShaderMaterial
	if not mat:
		return

	# 1. 獲取網格的世界座標邊界
	var grid_origin = grid.origin_offset
	var grid_size_px = Vector2(grid.map_width * grid.cell_size.x, grid.map_height * grid.cell_size.y)
	
	# 2. 往外擴充 (從 0.5 格增加到 1.0 格，讓黑霧更外擴)
	var margin = Vector2(grid.cell_size) * 1.0
	var world_min = grid_origin - margin
	var world_max = grid_origin + grid_size_px + margin
	
	# 3. 轉換為螢幕座標 (Screen Space)
	var screen_min = camera.get_canvas_transform() * world_min
	var screen_max = camera.get_canvas_transform() * world_max
	
	# 4. 轉換為標準化 UV 座標 (0.0 到 1.0)
	var viewport_size = get_viewport_rect().size
	var uv_left = screen_min.x / viewport_size.x
	var uv_top = screen_min.y / viewport_size.y
	var uv_right = screen_max.x / viewport_size.x
	var uv_bottom = screen_max.y / viewport_size.y
	
	# 5. 更新 Shader 參數
	mat.set_shader_parameter("mask_left", uv_left)
	mat.set_shader_parameter("mask_top", uv_top)
	mat.set_shader_parameter("mask_right", uv_right)
	mat.set_shader_parameter("mask_bottom", uv_bottom)
	
	# 同步更新像素解析度以維持像素感
	mat.set_shader_parameter("pixel_resolution", viewport_size)

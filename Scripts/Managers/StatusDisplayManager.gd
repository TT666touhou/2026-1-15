extends Control
class_name StatusDisplayManager

# 負責管理單位頭頂的狀態圖示顯示
# 自動定位於單位的左上角，並垂直排列

@onready var container: Container = $Container

# { status_id: StatusIcon (Control) }
var _icon_instances: Dictionary = {}

var _status_manager: StatusManager
var _parent_entity: GridEntity

# 配置參數
@export var display_scale: Vector2 = Vector2(0.25, 0.25) # 縮小顯示（減半）
@export var offset_padding: Vector2 = Vector2(0, 0) # 額外偏移
@export var rotation_interval: float = 2.0 # 輪播切換間隔（秒，不受幀率影響）
@export var max_visible_icons: int = 3 # 最多同時顯示的圖示數量

# 輪播相關變量
var _status_order: Array[String] = [] # 狀態ID的順序列表（按添加順序）
var _rotation_timer: float = 0.0 # 當前計時器
var _current_group_index: int = 0 # 當前顯示的組索引

func _ready() -> void:
	# 設置縮放
	scale = display_scale
	
	# 尋找父節點 Entity 與 StatusManager
	var parent = get_parent()
	if parent is GridEntity:
		_parent_entity = parent
		_update_position_to_top_left()
	
	if parent:
		_status_manager = parent.get_node_or_null("StatusManager")
		
	if not _status_manager:
		_status_manager = get_node_or_null("../StatusManager")
		
	if _status_manager:
		_status_manager.status_applied.connect(_on_status_applied)
		_status_manager.status_removed.connect(_on_status_removed)
		_status_manager.status_updated.connect(_on_status_updated)
	else:
		push_warning("[StatusDisplayManager] StatusManager not found!")
	
	# 初始化可見性更新
	call_deferred("_update_visible_icons")

func _update_position_to_top_left() -> void:
	if not _parent_entity: return
	
	# 獲取單位的像素大小
	# 假設標準格大小是 16x16，這應該從 Grid 獲取，這裡先 hardcode 或嘗試獲取
	var cell_size = Vector2(16, 16)
	var grid = get_tree().get_first_node_in_group("grid")
	if grid and "cell_size" in grid:
		cell_size = Vector2(grid.cell_size)
	
	var width_px = cell_size.x
	var height_px = cell_size.y
	
	# 檢查 Footprint
	if _parent_entity.footprint_data and _parent_entity.footprint_data.has_method("get_bounds"):
		var bounds = _parent_entity.footprint_data.get_bounds()
		width_px *= bounds.size.x
		height_px *= bounds.size.y
	
	# 單位中心在 (0,0) (相對於自身)
	# 左上角座標 = - (size / 2)
	# var top_left = Vector2(-width_px * 0.5, -height_px * 0.5)
	
	# 右上角座標 = (width_px / 2, -height_px / 2)
	var top_right = Vector2(width_px * 0.5, -height_px * 0.5)
	
	# 調整位置以確保圖示在格子內
	# 由於是 VBox (垂直排列)，寬度固定為一個圖示的寬度 (原始16px * 縮放比例)
	# 我們將起始點往左移一個圖示的寬度，這樣就會貼齊右邊緣但在內部
	var icon_width = 16.0 * display_scale.x
	var adjusted_pos = top_right + Vector2(-icon_width, 0)
	
	position = adjusted_pos + offset_padding

func _on_status_applied(def: StatusDefinition, duration: int) -> void:
	print("[StatusDisplayManager] Received status_applied: ", def.id, " duration: ", duration)
	if _icon_instances.has(def.id):
		var icon = _icon_instances[def.id]
		if icon.has_method("update_turns"):
			icon.update_turns(duration)
		# 更新可見性（狀態更新時也要更新顯示）
		_update_visible_icons()
		return
		
	var icon_scene = null
	if def.icon_scene_path and def.icon_scene_path != "":
		icon_scene = load(def.icon_scene_path)
		
	if not icon_scene:
		icon_scene = load("res://Scenes/UI/Status/StatusIcon.tscn")
		
	if icon_scene:
		var icon_instance = icon_scene.instantiate()
		container.add_child(icon_instance)
		_icon_instances[def.id] = icon_instance
		
		# 將新狀態ID添加到順序列表
		if not _status_order.has(def.id):
			_status_order.append(def.id)
		
		# 確保新圖示也在最上面 (如果想要由上往下堆疊，add_child 默認往後加，即往下)
		# 如果想要最新的在最上面，可以使用 move_child(icon_instance, 0)
		# container.move_child(icon_instance, 0) 
		
		if icon_instance.has_method("setup"):
			icon_instance.setup(duration)
			if def.icon and icon_instance.icon_sprite:
				icon_instance.icon_sprite.texture = def.icon
				icon_instance.icon_sprite.region_enabled = false
		
		# 如果狀態超過最大顯示數量，立即切換到最新組
		if _status_order.size() > max_visible_icons:
			# 重置計時器
			_rotation_timer = 0.0
			# 計算最新組的索引（最後一組）
			var total_groups = int(ceil(float(_status_order.size()) / float(max_visible_icons)))
			_current_group_index = total_groups - 1
		
		# 更新可見性
		_update_visible_icons() 

func _on_status_removed(status_id: String) -> void:
	if _icon_instances.has(status_id):
		var icon = _icon_instances[status_id]
		_icon_instances.erase(status_id)
		icon.queue_free()
	
	# 從順序列表中移除
	_status_order.erase(status_id)
	
	# 如果移除後狀態數量減少，重置輪播索引
	if _status_order.size() <= max_visible_icons:
		_current_group_index = 0
		_rotation_timer = 0.0
	
	# 更新可見性
	_update_visible_icons()

func _on_status_updated(status_id: String, duration: int) -> void:
	if _icon_instances.has(status_id):
		var icon = _icon_instances[status_id]
		if icon.has_method("update_turns"):
			icon.update_turns(duration)

func _process(delta: float) -> void:
	# 如果狀態數量超過最大顯示數量，則進行輪播
	if _status_order.size() > max_visible_icons:
		_rotation_timer += delta
		
		# 計算總共有多少組
		var total_groups = int(ceil(float(_status_order.size()) / float(max_visible_icons)))
		
		# 當計時器達到切換間隔時，切換到下一組
		if _rotation_timer >= rotation_interval:
			_rotation_timer = 0.0
			_current_group_index = (_current_group_index + 1) % total_groups
			_update_visible_icons()

func _update_visible_icons() -> void:
	# 如果狀態數量不超過最大顯示數量，顯示所有
	if _status_order.size() <= max_visible_icons:
		for status_id in _icon_instances:
			var icon = _icon_instances[status_id]
			if is_instance_valid(icon):
				icon.visible = true
		return
	
	# 計算當前應該顯示的狀態範圍
	var start_index = _current_group_index * max_visible_icons
	var end_index = min(start_index + max_visible_icons, _status_order.size())
	
	# 設置可見性
	for i in range(_status_order.size()):
		var status_id = _status_order[i]
		if _icon_instances.has(status_id):
			var icon = _icon_instances[status_id]
			if is_instance_valid(icon):
				# 只顯示當前組範圍內的圖示
				icon.visible = (i >= start_index and i < end_index)

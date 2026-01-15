extends Control
class_name StatusBarUI

## 統一狀態條 UI 管理器
## 在 UI 層顯示選中實體的狀態條，可以一次性改變樣式

@export var bar_width: float = 16.0
@export var bar_height: float = 2.0
@export var bar_spacing: float = 1.0
@export var offset_y: float = -12.0
@export var health_color: Color = Color.RED
# @export var hunger_color: Color = Color.ORANGE # Unused
@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.8)
@export var border_color: Color = Color.BLACK
@export var border_width: float = 1.0
@export var update_interval: float = 0.1  # 更新間隔（秒）
@export var enable_debug_log: bool = false

var _displayed_entity: Node2D = null
var _stat_script: Node = null # Optional, not always used for GridEntity
var _update_timer: float = 0.0

# 當前顯示的狀態數據
var _health_current: int = 0
var _health_max: int = 0
# var _has_hunger: bool = false # Unused

# 狀態標記
var _is_displaying: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不阻擋點擊
	visible = false
	z_index = 200  # 確保在實體上方

# 公開設定：歸零即刪除
@export var auto_free_on_dead: bool = true
@export var follow_margin_y: float = 4.0

# 對外 API：將血條掛到指定實體
func attach_to_entity(entity: Node2D) -> void:
	_displayed_entity = entity
	# 對於 Building, stat_script 可能是 BuildingStat
	_stat_script = entity.get_node_or_null("BuildingStat")
	
	_compute_offset_y(entity)
	_connect_health_signals()
	visible = true
	_is_displaying = true
	_update_display()
	_update_position()

func _process(delta: float) -> void:
	_update_timer += delta
	
	# 定期更新位置和狀態
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_display()
	
	# 更新位置（跟隨實體）
	if _displayed_entity != null and is_instance_valid(_displayed_entity):
		_update_position()
		queue_redraw()
	else:
		# 實體無效，清除顯示
		if _is_displaying:
			clear_display()

func _draw() -> void:
	if _displayed_entity == null or not is_instance_valid(_displayed_entity):
		return
	
	var y_offset: float = 0.0
	var total_height: float = 0.0
	
	# 計算總高度
	if _health_max > 0:
		total_height += bar_height
	
	# 繪製背景
	var bg_rect = Rect2(-bar_width * 0.5 - border_width, -total_height - border_width, bar_width + border_width * 2, total_height + border_width * 2)
	draw_rect(bg_rect, border_color)
	var bg_inner = Rect2(-bar_width * 0.5, -total_height, bar_width, total_height)
	draw_rect(bg_inner, background_color)
	
	# 繪製血量條
	if _health_max > 0:
		var health_percent = float(_health_current) / float(_health_max) if _health_max > 0 else 0.0
		var health_width = bar_width * health_percent
		var health_rect = Rect2(-bar_width * 0.5, y_offset - bar_height, health_width, bar_height)
		draw_rect(health_rect, health_color)
		y_offset -= bar_height

func display_entity(entity: Node2D, stat_script: Node) -> void:
	# 顯示實體狀態條
	if enable_debug_log:
		print("[StatusBarUI] display_entity called: entity=", entity, " stat_script=", stat_script)
	
	_displayed_entity = entity
	_stat_script = stat_script
	
	if entity == null:
		if enable_debug_log:
			print("[StatusBarUI] Entity is null, clearing display")
		clear_display()
		return
	
	# 連接信號並獲取初始值
	_connect_health_signals()
	
	# 如果無法獲取最大血量，則不顯示
	if _health_max <= 0:
		if enable_debug_log:
			print("[StatusBarUI] Max health is 0, hiding")
		clear_display()
		return
	
	visible = true
	_is_displaying = true
	_update_position()
	queue_redraw()
	
	if enable_debug_log:
		print("[StatusBarUI] Display entity: ", entity.name, " HP=", _health_current, "/", _health_max, " visible=", visible)

func clear_display() -> void:
	var was_displaying = _is_displaying
	_displayed_entity = null
	_stat_script = null
	visible = false
	_is_displaying = false
	queue_redraw()
	
	if enable_debug_log and was_displaying:
		print("[StatusBarUI] Clear display")

func _update_position() -> void:
	if _displayed_entity == null or not is_instance_valid(_displayed_entity):
		return
	
	var world_pos = _displayed_entity.global_position + Vector2(0, offset_y)
	global_position = world_pos

func _update_display() -> void:
	if _displayed_entity == null:
		return
	if not is_instance_valid(_displayed_entity):
		clear_display()
		return
	
	# 這裡不需要做太多事情，因為主要依賴信號更新
	# 但如果是 BuildingStat 且沒有信號（或者需要輪詢），可以在這裡更新
	queue_redraw()

# 連接 Health 訊號，並獲取初始值
func _connect_health_signals() -> void:
	if _displayed_entity == null:
		return
	
	# 1. 嘗試 GridEntity (Unit)
	var grid_entity = _displayed_entity as GridEntity
	if grid_entity != null and grid_entity.get("character_data") != null:
		var char_data = grid_entity.get("character_data") as CharacterData
		if char_data != null:
			# 連接信號
			if not char_data.health_changed.is_connected(_on_character_health_changed):
				char_data.health_changed.connect(_on_character_health_changed)
			if not char_data.died.is_connected(_on_health_died):
				char_data.died.connect(_on_health_died)
			
			# 獲取初始值
			_health_current = char_data.current_health
			_health_max = char_data.max_health
			return

	# 2. 嘗試 BuildingStat (Building)
	var building_stat = _stat_script as BuildingStat
	if building_stat == null:
		building_stat = _displayed_entity.get_node_or_null("BuildingStat") as BuildingStat
	
	if building_stat != null:
		if not building_stat.health_changed.is_connected(_on_building_health_changed):
			building_stat.health_changed.connect(_on_building_health_changed)
		# BuildingStat 有 health_depleted，但也可以用 health_changed 檢測 0
		if not building_stat.health_depleted.is_connected(_on_health_died):
			building_stat.health_depleted.connect(_on_health_died)
			
		# 獲取初始值
		_health_current = building_stat.current_health
		_health_max = building_stat.max_health
		return
		
	# 3. Fallback for Duck Typing (Legacy or simple objects)
	if _stat_script != null and _stat_script.has_method("get_info"):
		var info = _stat_script.get_info()
		_health_current = info.get("health", 0)
		_health_max = info.get("max_health", 0)
	else:
		_health_current = 0
		_health_max = 0

# Signal Callbacks

func _on_character_health_changed(current: int, max_hp: int) -> void:
	_health_current = current
	_health_max = max_hp
	queue_redraw()

func _on_building_health_changed(current: int, max_hp: int) -> void:
	_health_current = current
	_health_max = max_hp
	queue_redraw()

func _on_health_died() -> void:
	"""處理實體死亡，清除血條 UI"""
	if auto_free_on_dead:
		queue_free()
	else:
		visible = false

# 內部：根據碰撞/貼圖推算 offset_y
func _compute_offset_y(entity: Node2D) -> void:
	var top := 0.0
	# 優先 CollisionShape2D
	var cs: CollisionShape2D = entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape != null:
		if cs.shape is RectangleShape2D:
			var rs: RectangleShape2D = cs.shape as RectangleShape2D
			top = rs.size.y * 0.5
		elif cs.shape is CircleShape2D:
			var c: CircleShape2D = cs.shape as CircleShape2D
			top = c.radius
	else:
		# 回退 Sprite 高度
		var spr: Sprite2D = entity.get_node_or_null("Sprite2D") as Sprite2D
		if spr != null:
			if spr.region_enabled:
				top = spr.region_rect.size.y * 0.5
			elif spr.texture != null:
				top = spr.texture.get_height() * 0.5
	# 設定偏移（往上）
	offset_y = -(top + follow_margin_y)

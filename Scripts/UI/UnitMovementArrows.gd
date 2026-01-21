extends Node2D
class_name UnitMovementArrows

## 單位移動箭頭組件
## 現在透過 MovementArrowSettings 資源進行統一管理

# 預設資源路徑
const DEFAULT_SETTINGS_PATH = "res://Resources/UI/DefaultMovementArrowSettings.tres"
# 使用專門處理雙箭頭的 Shader
const ARROW_SHADER = preload("res://Scenes/Shared/Shaders/double_arrow.gdshader")

@export var settings: MovementArrowSettings:
	set(v):
		settings = v
		if is_inside_tree():
			_connect_settings()
			_update_visuals()
			_update_arrow_positions()
			update_display()

@onready var parent_entity: GridEntity = get_parent()
var _arrows: Dictionary = {}
var _current_attack_progress: float = 0.0

func _ready() -> void:
	if not parent_entity:
		return
	
	# 如果沒有分配資源，載入全域預設值
	if settings == null:
		if ResourceLoader.exists(DEFAULT_SETTINGS_PATH):
			settings = load(DEFAULT_SETTINGS_PATH)
		else:
			# 如果連預設檔案都沒找到，建立一個空的預設值
			settings = MovementArrowSettings.new()
	
	_setup_arrows()
	_connect_settings()
	
	# 監聽移動數據變化信號
	if parent_entity.has_signal("movement_data_changed"):
		parent_entity.movement_data_changed.connect(func():
			_update_arrow_positions()
			update_display()
		)
	
	_update_arrow_positions.call_deferred()
	update_display.call_deferred()

func _connect_settings() -> void:
	if settings and not settings.changed.is_connected(_on_settings_changed):
		settings.changed.connect(_on_settings_changed)

func _on_settings_changed() -> void:
	_update_visuals()
	_update_arrow_positions()
	update_display()

func _setup_arrows() -> void:
	var directions = {
		"north": Vector2i(0, -1),
		"south": Vector2i(0, 1),
		"west": Vector2i(-1, 0),
		"east": Vector2i(1, 0),
		"northwest": Vector2i(-1, -1),
		"northeast": Vector2i(1, -1),
		"southwest": Vector2i(-1, 1),
		"southeast": Vector2i(1, 1)
	}
	
	for dir_name in directions:
		var dir_vec = directions[dir_name]
		var sprite = Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		
		# 套用 Shader
		var mat = ShaderMaterial.new()
		mat.shader = ARROW_SHADER
		sprite.material = mat
		
		# 新增：開啟遮罩功能，並建立填充矩形
		sprite.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		
		var fill = ColorRect.new()
		fill.name = "FillProgress"
		fill.color = Color.RED
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.add_child(fill)
		
		add_child(sprite)
		_arrows[dir_name] = {
			"sprite": sprite,
			"dir": dir_vec
		}
	
	_update_visuals()

# 更新圖片、縮放與顏色 (從 settings 讀取)
func _update_visuals() -> void:
	if _arrows.is_empty() or settings == null: return
	for dir_name in _arrows:
		var data = _arrows[dir_name]
		var s = data["sprite"] as Sprite2D
		s.texture = settings.arrow_texture
		s.scale = Vector2(settings.arrow_scale, settings.arrow_scale)
		
		# 根據進度決定底層顏色
		if _current_attack_progress > 0.001:
			s.modulate = Color.WHITE # 攻擊時底層變回純白 (紅色由 FillProgress 提供)
		else:
			s.modulate = Color.WHITE # 平時維持白色
			
		s.rotation = atan2(data["dir"].y, data["dir"].x) + PI/2

func set_attack_progress(progress: float, direction: Vector2i = Vector2i.ZERO) -> void:
	"""外部介面：設置攻擊預警進度 (使用精確的像素裁剪法)"""
	_current_attack_progress = progress
	
	for dir_name in _arrows:
		var arrow_data = _arrows[dir_name]
		var sprite = arrow_data["sprite"] as Sprite2D
		var fill = sprite.get_node_or_null("FillProgress") as ColorRect
		
		# 如果指定了方向，則只有該方向會填滿
		var is_target_dir = (direction == Vector2i.ZERO or arrow_data["dir"] == direction)
		
		if fill:
			if not is_target_dir:
				fill.visible = false
				continue
				
			# 獲取實際的貼圖尺寸 (如果是 AtlasTexture 會自動處理 region)
			var rect_size = Vector2(16, 16) # 預設 fallback
			if sprite.texture:
				if sprite.texture is AtlasTexture:
					rect_size = sprite.texture.region.size
				else:
					rect_size = sprite.texture.get_size()
			
			var w = rect_size.x
			var h = rect_size.y
			
			# 根據進度計算高度 (由底部向上填滿)
			# 注意：Sprite 的中心點在 (0,0)，所以 Rect 的位置需要補償
			fill.size = Vector2(w, h * progress)
			fill.position = Vector2(-w/2, (h/2) - (h * progress))
			fill.visible = progress > 0.001
			
	# 如果有進度，強制顯示所有非 BLOCKED 箭頭
	update_display()

# 更新箭頭位置 (從 settings 讀取)
func _update_arrow_positions() -> void:
	if not parent_entity or _arrows.is_empty() or settings == null: return
	
	var footprint_size = Vector2(parent_entity.get_footprint_size())
	var cell_size = 16.0 
	
	var base_dist = (footprint_size.x * cell_size * 0.5) - settings.inset_distance
	
	for dir_name in _arrows:
		var data = _arrows[dir_name]
		var sprite = data["sprite"] as Sprite2D
		var dir_vec = Vector2(data["dir"])
		
		var dist = base_dist
		if dir_vec.x != 0 and dir_vec.y != 0:
			dist = base_dist * settings.diagonal_factor
			
		sprite.position = dir_vec * dist

# 更新顯示邏輯 (從 settings 讀取)
func update_display() -> void:
	var data: MovementRangeData = null
	if parent_entity:
		data = parent_entity.movement_range_data
		
	# 如果正在攻擊預警，強制顯示所有非 BLOCKED 的箭頭
	# 如果沒有數據 (例如砲台)，則顯示所有定義的方向
	if _current_attack_progress > 0.001:
		for dir_name in _arrows:
			var sprite = _arrows[dir_name]["sprite"]
			if data:
				var move_type = data.get(dir_name)
				sprite.visible = move_type > 0
			else:
				# 沒有數據時 (如砲台)，預設顯示所有 8 方向 (可根據需求過濾)
				sprite.visible = true
		return

	if not data or _arrows.is_empty() or settings == null:
		for arrow_data in _arrows.values():
			arrow_data["sprite"].visible = false
		return
		
	for dir_name in _arrows:
		var sprite = _arrows[dir_name]["sprite"]
		var move_type = data.get(dir_name)
		
		# 敵方單位常駐顯示攻擊範圍 (不透明)
		if parent_entity and parent_entity.faction and not parent_entity.faction.is_controllable:
			sprite.visible = move_type > 0
		else:
			# 玩家單位只在選取時顯示 (由 GridSelector 外部控制，或此處保持預設)
			sprite.visible = move_type > 0
		
		if move_type == 2: # UNLIMITED
			sprite.material.set_shader_parameter("is_unlimited", true)
			sprite.material.set_shader_parameter("offset_direction", Vector2(0, -1))
			sprite.material.set_shader_parameter("offset_distance", settings.double_arrow_offset)
			sprite.material.set_shader_parameter("duplicate_alpha", settings.double_arrow_alpha)
		else:
			sprite.material.set_shader_parameter("is_unlimited", false)

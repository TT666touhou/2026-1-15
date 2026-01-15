extends Control

# 裝備拖曳預覽控制器
# 參考自 DragPreview.gd，提供相同的物理搖擺效果

var sprite: Sprite2D
var canvas_layer: CanvasLayer # 新增 CanvasLayer 引用
var _last_screen_pos: Vector2 # 改用螢幕座標計算物理效果
var _oscillator_velocity: float = 0.0
var _oscillator_displacement: float = 0.0

# 物理參數 (與單位預覽一致)
const ROTATION_SPRING: float = 150.0
const ROTATION_DAMP: float = 10.0
const VELOCITY_MULTIPLIER: float = 1.0

func setup(texture: Texture2D) -> void:
	# 1. 設定大小為 64x64 (16x16 的 4 倍)，以符合 Grid 上的視覺大小
	size = Vector2(64, 64)
	
	# 2. 建立一個高層級的 CanvasLayer，確保它在所有 UI 之上
	# Godot 的拖放預覽預設在 Layer 0，會被自定義的 CanvasLayer (如 UI 層) 遮擋
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100 # 設為 100 確保超過普通的 UI 層
	add_child(canvas_layer)
	
	# 建立內部的 Sprite2D 以便旋轉，而不影響容器
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	# 3. 設置縮放為 4 倍，與單位預覽 (DragPreview.gd) 的縮放比例一致
	sprite.scale = Vector2(4, 4)
	sprite.centered = true
	# 將 Sprite 放在容器的中心位置 (即 32, 32)
	sprite.position = size / 2
	
	# 將 Sprite 加入到 CanvasLayer 而非直接加入 Control
	canvas_layer.add_child(sprite)
	
	# 初始化位置記錄 (使用螢幕/畫布空間座標)
	_last_screen_pos = get_global_transform_with_canvas().origin
	# 確保滑鼠不會點擊到預覽
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	# 關鍵：讓 CanvasLayer 的偏移跟隨 Control 的全域螢幕位置
	var current_screen_pos = get_global_transform_with_canvas().origin
	canvas_layer.offset = current_screen_pos
	
	if sprite == null: return

	# 計算螢幕空間的速度，這會讓物理搖擺更穩定
	var velocity = (current_screen_pos - _last_screen_pos) / delta
	_last_screen_pos = current_screen_pos
	
	if velocity.length() > 0.0:
		_oscillator_velocity += velocity.normalized().x * VELOCITY_MULTIPLIER
		
	var force = -ROTATION_SPRING * _oscillator_displacement - ROTATION_DAMP * _oscillator_velocity
	_oscillator_velocity += force * delta
	_oscillator_displacement += _oscillator_velocity * delta
	
	sprite.rotation = _oscillator_displacement


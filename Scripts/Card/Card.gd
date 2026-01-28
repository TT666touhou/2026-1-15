extends Control
class_name Card

signal selection_toggled(card)
signal request_deselect_all

# 內部設計尺寸 (高解析度基準)
# 這是 SubViewport 的固定解析度，所有內部排版(Label字體等)都以此為準
const BASE_DESIGN_SIZE = Vector2(320, 480)

@export var card_size: Vector2 = Vector2(80, 120):
	set(value):
		card_size = value
		if is_inside_tree():
			_update_size()

var card_data: RefCounted = null :
	set(value):
		if card_data != value:
			# 斷開舊數據的信號
			if card_data and card_data.has_signal("changed"):
				if card_data.is_connected("changed", _on_data_changed):
					card_data.disconnect("changed", _on_data_changed)
			
			card_data = value
			
			# 連接新數據的信號 (如果是 RuntimeCardData)
			if card_data and card_data.has_signal("changed"):
				if not card_data.is_connected("changed", _on_data_changed):
					card_data.connect("changed", _on_data_changed)
			
			if enable_debug_log:
				print("[Card] set_card_data =>", card_data)
			_update_display()

@export var interactable: bool = true # 是否可交互 (DeckView 模式下設為 false)
@export var enable_debug_log: bool = false # Force enable debug log for now
@export var return_duration: float = 0.25
@export var return_ease: int = Tween.EASE_OUT
@export var return_trans: int = Tween.TRANS_BACK
@export var fade_out_on_drag: bool = false
@export var fade_out_alpha: float = 0.0
@export var drag_threshold_px: float = 3.0
@export var hide_on_leave_hand: bool = true

# Selection State
var is_selected: bool = false
@export var selected_y_offset: float = -40.0
@export var selection_enabled: bool = true

# 3D Effect Parameters
@export var angle_x_max: float = 15.0  # Max rotation angle on X axis
@export var angle_y_max: float = 15.0  # Max rotation angle on Y axis
@export var hover_scale: float = 1.2  # Scale when hovered
@export var hover_scale_duration: float = 0.2
@export var rotation_reset_duration: float = 0.5
@export var fake_3d_enabled: bool = true # Toggle for 3D/Hover effects

# Exchange Mode State
var is_in_exchange_slot: bool = false

# Damped Oscillator Parameters
@export_category("Oscillator")
@export var enable_oscillator_rotation: bool = true
@export var oscillator_spring: float = 150.0
@export var oscillator_damp: float = 10.0
@export var oscillator_velocity_multiplier: float = 1.0

var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_started := false
var _original_global_position: Vector2
var _original_rotation: float
var _original_z: int
var _is_mouse_hovering: bool = false
var _hover_timer: Timer = null
@export var tooltip_delay: float = 0.5

# Drag State (New)
var _is_right_pressed: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _is_dragging_right: bool = false
const DRAG_THRESHOLD = 10.0

# Tweeners
var tween_rot: Tween
var tween_hover: Tween

# Oscillator variables
var _oscillator_displacement: float = 0.0
var _oscillator_velocity: float = 0.0
var _last_drag_position: Vector2 = Vector2.ZERO
var _drag_base_rotation: float = 0.0 # 拖曳時的基準旋轉角度 (會從扇形角度 Tween 到 0)

# Node References
@onready var _sub_viewport_container: SubViewportContainer = get_node_or_null("SubViewportContainer")
@onready var NameLabel: Label = get_node_or_null("SubViewportContainer/SubViewport/CardContent/MarginContainer/VBoxContainer/TopBar/NameLabel")
@onready var ImageRect: TextureRect = get_node_or_null("SubViewportContainer/SubViewport/CardContent/MarginContainer/VBoxContainer/ImageContainer/Image")
@onready var MiniRangeGrid: GridContainer = %MiniRangeGrid
@onready var _rotation_center: Node2D = get_node_or_null("RotationCenter")

func _ready() -> void:
	# print("[Card] _ready called for card: ", get_path())
	_update_size()
	
	_hover_timer = Timer.new()
	_hover_timer.wait_time = tooltip_delay
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)
	
	if _rotation_center:
		pivot_offset = _rotation_center.position
	else:
		pivot_offset = size / 2.0
	
	_update_display()
	mouse_filter = Control.MOUSE_FILTER_STOP
	
func _update_size() -> void:
	# 1. 設定自身佔位大小
	custom_minimum_size = card_size
	size = card_size
	
	# 2. 確保內部 Viewport 保持設計解析度 (清晰度來源)
	if _sub_viewport_container:
		_sub_viewport_container.z_index = 0 # 確保不影響 top_level 元素
		var viewport = _sub_viewport_container.get_node_or_null("SubViewport")
		if viewport:
			viewport.size = BASE_DESIGN_SIZE # 固定為 320x480
		
		# 3. 計算縮放比例：目標尺寸 / 設計尺寸
		# 例如：80/320 = 0.25
		_sub_viewport_container.scale = card_size / BASE_DESIGN_SIZE
		
		# 確保 Container 本身不影響佈局 (雖然它是絕對定位)
		_sub_viewport_container.size = BASE_DESIGN_SIZE # 容器大小應匹配內容
		
	# 4. 更新 Shader 參數
	_update_shader_rect_size()
	
func _on_data_changed() -> void:
	_update_display()

func set_card_data(data) -> void:
	card_data = data

func set_in_exchange_slot(enabled: bool) -> void:
	is_in_exchange_slot = enabled
	if enabled:
		set_fake_3d_enabled(false)
	else:
		set_fake_3d_enabled(true)

func set_fake_3d_enabled(enabled: bool) -> void:
	fake_3d_enabled = enabled
	if not enabled:
		# Reset any active 3D effects immediately
		if _sub_viewport_container and _sub_viewport_container.material:
			_sub_viewport_container.material.set_shader_parameter("x_rot", 0.0)
			_sub_viewport_container.material.set_shader_parameter("y_rot", 0.0)
		scale = Vector2.ONE

func _gui_input(event: InputEvent) -> void:
	if not interactable:
		# 如果不可交互，僅處理 Hover 事件以顯示 3D 效果，忽略點擊拖曳
		if event is InputEventMouseMotion:
			_handle_mouse_hover_rotation(event)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_start_pos = event.position
				_drag_started = false
				
				_original_global_position = global_position
				_original_rotation = rotation
				_original_z = z_index
				
				var card_center_offset: Vector2
				if _rotation_center:
					card_center_offset = _rotation_center.position
				else:
					card_center_offset = size / 2.0
				_drag_offset = card_center_offset
				
				_last_drag_position = global_position
				_oscillator_displacement = 0.0
				_oscillator_velocity = 0.0
				_drag_base_rotation = rotation
			else:
				if _is_dragging_right:
					# right_drag_ended.emit(self, get_global_mouse_position()) # Signal not defined here
					_is_dragging_right = false
				elif _dragging:
					_finish_drag(get_global_mouse_position())
				else:
					# This was a simple click (no significant drag)
					if selection_enabled:
						selection_toggled.emit(self)
				
				_is_right_pressed = false
				_dragging = false
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if selection_enabled:
					request_deselect_all.emit()
					return
				_is_right_pressed = true
				_drag_start_pos = event.position
		else:
			_is_right_pressed = false
			_is_dragging_right = false
	
	elif event is InputEventMouseMotion:
		if _dragging:
			accept_event()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _drag_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				_dragging = true
				set_process(true)
				var hand = get_parent()
				if hand and hand.has_method("begin_drag"):
					hand.begin_drag(self)
		elif _is_right_pressed and not _is_dragging_right:
			if _drag_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				_is_dragging_right = true
				# right_drag_started.emit(self) # Signal not defined here
		else:
			_handle_mouse_hover_rotation(event)

func kill_tweens() -> void:
	if tween_rot and tween_rot.is_running(): tween_rot.kill()
	if tween_hover and tween_hover.is_running(): tween_hover.kill()

var _debug_timer := 0.0

func _process(delta: float) -> void:
	# DEBUG: 每秒監測一次狀態
	_debug_timer += delta
#	if _debug_timer >= 1.0:
#		_debug_timer = 0.0
#		print("[Card Debug] Path: %s | Visible: %s | InTree: %s | Pos: %s | Scale: %s | Z: %d | Mod: %s" % [
#			get_path(),
#			visible,
#			is_visible_in_tree(),
#			global_position,
#			scale,
#			z_index,
#			modulate
#		])

	if _dragging:
		var mouse := get_global_mouse_position()
		
		if not _drag_started and _original_global_position.distance_to(mouse) > drag_threshold_px:
			_drag_started = true
			z_index = 1000
			if fade_out_on_drag:
				modulate.a = fade_out_alpha
		
		# If selected, let Hand.gd handle ALL positioning and rotation to avoid fighting
		if is_selected:
			# COMPLETELY DELEGATE TO HAND
			var h = get_parent()
			if h and h.has_method("on_drag_move"):
				h.on_drag_move(mouse)
			return 
			
		global_position = mouse - _drag_offset
		if _drag_started and enable_oscillator_rotation:
			_update_oscillator_rotation(delta)
		
		var hand = get_parent()
		if hand and hand.has_method("on_drag_move"):
			hand.on_drag_move(mouse)
	else:
		if _is_mouse_hovering and not _dragging:
			_handle_mouse_hover_rotation_continuous()

	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_drag(get_global_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
		_finish_drag((event as InputEventMouseButton).position)

func _finish_drag(_mouse_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	
	set_process(false)
	
	if _drag_started:
		var tween_reset = create_tween()
		tween_reset.tween_property(self, "rotation", _original_rotation, 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		_oscillator_displacement = 0.0
		_oscillator_velocity = 0.0
	
	var hand = get_parent()
	if hand and hand.has_method("end_drag"):
		hand.end_drag()
	
	if hand and hand.has_method("hide_hand_border"):
		hand.hide_hand_border()

func _update_display() -> void:
	# print("[Card] _update_display called. card_data: ", card_data)
	var nm := "BLANK"
	var img: Texture2D = null
	
	if card_data:
		if card_data.has_method("get_display_name"):
			nm = card_data.get_display_name()
		elif card_data.has_method("get"):
			var dn = card_data.get("display_name")
			if dn != null and String(dn) != "":
				nm = String(dn)
			else:
				var cn = card_data.get("card_name")
				if cn != null:
					nm = String(cn)
		
		if card_data.has_method("get_card_image"):
			img = card_data.get_card_image()
		elif "image" in card_data: # Fallback property check
			img = card_data.get("image")
	
	if NameLabel:
		NameLabel.text = nm
	
	if ImageRect:
		ImageRect.texture = img
		if img:
			ImageRect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	# 確保基礎卡片背景可見 (如果沒有特別隱藏的話)
	var bg = get_node_or_null("SubViewportContainer/SubViewport/CardContent/Sprite0001")
	if bg:
		bg.visible = true
	
	# 確保 TopBar 可見，否則看不到名字
	var top_bar = get_node_or_null("SubViewportContainer/SubViewport/CardContent/MarginContainer/VBoxContainer/TopBar")
	if top_bar:
		top_bar.visible = true
	
	# --- 技能 UI 鑲嵌邏輯（簡化版：只顯示名稱，不渲染網格）---
	if card_data:
		var skill_card = null
		if card_data.has_method("get_skill_card"):
			skill_card = card_data.get_skill_card()
		elif card_data is SkillCard:
			skill_card = card_data
			
		if skill_card:
			# 將技能名稱填入卡片頂部的名稱標籤
			if NameLabel:
				NameLabel.text = skill_card.skill_name if "skill_name" in skill_card else "Unknown Skill"
			
			# 隱藏範圍網格（grid-based 技能系統已移除）
			if MiniRangeGrid:
				MiniRangeGrid.visible = false
		else:
			# 如果不是技能卡，隱藏網格
			if MiniRangeGrid:
				MiniRangeGrid.visible = false
	else:
		if MiniRangeGrid:
			MiniRangeGrid.visible = false

func return_to_hand(animated := true) -> void:
	var hand = get_parent()
	var target: Vector2 = _original_global_position
	if hand and hand.has_method("get_card_home_global_position"):
		target = hand.get_card_home_global_position(self)
	var done := func():
		modulate.a = 1.0
		z_index = _original_z
		rotation = _original_rotation
		if hand and hand.has_method("arrange") and hand.reflow_on_release:
			hand.arrange()
	if not animated:
		global_position = target
		done.call()
		return
	visible = true
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, return_duration).set_trans(return_trans).set_ease(return_ease)
	tw.parallel().tween_property(self, "rotation", _original_rotation, return_duration).set_trans(return_trans).set_ease(return_ease)
	tw.parallel().tween_property(self, "modulate:a", 1.0, return_duration * 0.8).set_trans(return_trans).set_ease(return_ease)
	tw.finished.connect(done)

func _update_oscillator_rotation(delta: float) -> void:
	if delta <= 0.0:
		return
	var current_velocity: Vector2 = (global_position - _last_drag_position) / delta
	_last_drag_position = global_position
	if current_velocity.length() > 0.0:
		_oscillator_velocity += current_velocity.normalized().x * oscillator_velocity_multiplier
	var force = -oscillator_spring * _oscillator_displacement - oscillator_damp * _oscillator_velocity
	_oscillator_velocity += force * delta
	_oscillator_displacement += _oscillator_velocity * delta
	
	# 最終旋轉 = 當前基準角度 (逐漸變直) + 物理擺動
	rotation = _drag_base_rotation + _oscillator_displacement

# ========== 3D Effect (Shader) ==========

func _update_shader_rect_size() -> void:
	# Update shader's rect_size to match the High-Res viewport size
	if _sub_viewport_container and _sub_viewport_container.material:
		_sub_viewport_container.material.set_shader_parameter("rect_size", BASE_DESIGN_SIZE)

func _handle_mouse_hover_rotation(_event: InputEventMouseMotion) -> void:
	_handle_mouse_hover_rotation_continuous()

func _handle_mouse_hover_rotation_continuous() -> void:
	if not fake_3d_enabled: return # Check flag
	if not _sub_viewport_container or not _sub_viewport_container.material:
		return
	
	var mouse_pos: Vector2 = get_local_mouse_position()
	
	var lerp_val_x: float = remap(mouse_pos.x, 0.0, size.x, 0.0, 1.0)
	var lerp_val_y: float = remap(mouse_pos.y, 0.0, size.y, 0.0, 1.0)
	
	var rot_x: float = lerp_angle(deg_to_rad(-angle_x_max), deg_to_rad(angle_x_max), lerp_val_x)
	var rot_y: float = lerp_angle(deg_to_rad(angle_y_max), deg_to_rad(-angle_y_max), lerp_val_y)
	
	_sub_viewport_container.material.set_shader_parameter("x_rot", rad_to_deg(rot_y))
	_sub_viewport_container.material.set_shader_parameter("y_rot", rad_to_deg(rot_x))

func _on_mouse_entered() -> void:
	# If any card is being dragged, or this card is being dragged, skip hover effects
	var hand = get_parent()
	if _dragging or (hand and hand.has_method("is_dragging") and hand.call("is_dragging")):
		return
		
	_is_mouse_hovering = true
	
	if _hover_timer:
		_hover_timer.start()
	
	# 提升 Z-Index (100) 以便觀察
	if not _dragging:
		z_index = 100
	
	if not fake_3d_enabled: return # Check flag
	
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", Vector2(hover_scale, hover_scale), hover_scale_duration)

func _on_mouse_exited() -> void:
	_is_mouse_hovering = false
	
	if _hover_timer:
		_hover_timer.stop()
		
	var controller = get_tree().get_first_node_in_group("hover_info_controller")
	if controller and controller.has_method("_hide_all"):
		controller.call("_hide_all")
	
	# 還原 Z-Index
	if not _dragging:
		z_index = _original_z
	
	# Reset Rotation (Always reset regardless of flag, to ensure cleanup)
	if tween_rot and tween_rot.is_running():
		tween_rot.kill()
	if _sub_viewport_container and _sub_viewport_container.material:
		tween_rot = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_parallel(true)
		tween_rot.tween_property(_sub_viewport_container.material, "shader_parameter/x_rot", 0.0, rotation_reset_duration)
		tween_rot.tween_property(_sub_viewport_container.material, "shader_parameter/y_rot", 0.0, rotation_reset_duration)
	
	# Reset Scale
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", Vector2.ONE, hover_scale_duration * 1.1)

func _on_hover_timer_timeout() -> void:
	if not _is_mouse_hovering or _dragging:
		return
		
	var skill_card = null
	if card_data:
		if card_data.has_method("get_skill_card"):
			skill_card = card_data.get_skill_card()
		elif card_data is SkillCard:
			skill_card = card_data
			
	if skill_card:
		var controller = get_tree().get_first_node_in_group("hover_info_controller")
		if controller and controller.has_method("show_skill_info"):
			controller.show_skill_info(skill_card, true)

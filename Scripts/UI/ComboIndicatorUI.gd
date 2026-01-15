extends Control
class_name ComboIndicatorUI

@onready var panel_container: PanelContainer = $PanelContainer
@onready var value_label: Label = $PanelContainer/HBoxContainer/ValueLabel

var _tween: Tween

func _ready() -> void:
	visible = false
	# Ensure correct positioning relative to parent if needed
	# Default pivot to bottom-center for pop-up animation
	panel_container.pivot_offset = Vector2(panel_container.size.x / 2, panel_container.size.y)
	panel_container.position.x = -panel_container.size.x / 2.0
	
	# Debug: Add Camera if running standalone
	if get_tree().current_scene == self:
		var cam = Camera2D.new()
		cam.zoom = Vector2(4, 4)
		add_child(cam)
		print("[ComboUI] Debug Camera added")
		# Show a test combo so it's visible immediately
		show_combo(2)

func show_combo(count: int) -> void:
	if count <= 0:
		hide_combo()
		return
		
	var old_text = value_label.text
	value_label.text = str(count)
	
	# 強制容器更新尺寸以獲得正確的中心點
	panel_container.reset_size()
	panel_container.pivot_offset = Vector2(panel_container.size.x / 2, panel_container.size.y)
	# 核心修正：將面板向左偏移自身寬度的一半，達成水平居中
	panel_container.position.x = -panel_container.size.x / 2.0
	
	if not visible:
		visible = true
		_play_pop_in_animation()
	elif old_text != str(count):
		# 只有數字真的變動時才播放彈跳動畫，避免每幀重設 scale
		_play_bounce_animation()

func hide_combo() -> void:
	visible = false

func force_hide() -> void:
	visible = false
	if _tween and _tween.is_valid():
		_tween.kill()

func _play_pop_in_animation() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	panel_container.scale = Vector2.ZERO
	_tween.tween_property(panel_container, "scale", Vector2.ONE, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _play_bounce_animation() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	# Bounce scale up and down
	_tween.tween_property(panel_container, "scale", Vector2(1.2, 1.2), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_property(panel_container, "scale", Vector2.ONE, 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _unhandled_input(event: InputEvent) -> void:
	# Debug functionality: Shift + 1-9 to test combo display
	if not OS.is_debug_build():
		return
		
	# Only enable if running this scene standalone OR if explicitly enabled
	# Checking if parent is root (standalone) or if we are just testing
	if get_tree().current_scene == self or get_parent() == get_tree().current_scene:
		if event is InputEventKey and event.pressed and event.shift_pressed:
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				var combo = event.keycode - KEY_0
				show_combo(combo)
				print("[ComboUI] Debug show: ", combo)
			elif event.keycode == KEY_0:
				hide_combo()
				print("[ComboUI] Debug hide")


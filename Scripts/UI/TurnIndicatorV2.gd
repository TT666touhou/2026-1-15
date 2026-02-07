extends CanvasLayer

signal animation_finished

@onready var container = $Control/CenterContainer
@onready var panel = $Control/CenterContainer/PanelContainer
@onready var label = $Control/CenterContainer/PanelContainer/MarginContainer/Label
@onready var control = $Control

var _tween: Tween

func _ready() -> void:
	add_to_group("turn_indicator")
	control.visible = false
	
	if TurnManager:
		TurnManager.turn_started.connect(_on_turn_started)
		
	# 如果是獨立執行場景，保留測試功能
	if get_tree().current_scene == self:
		await get_tree().create_timer(1.0).timeout
		show_indicator("PLAYER TURN")
		await animation_finished
		await get_tree().create_timer(1.0).timeout
		show_indicator("ENEMY TURN")

func _on_turn_started(faction: FactionDefinition) -> void:
	if not faction: return
	
	if faction.is_controllable:
		show_indicator("PLAYER TURN")
	else:
		show_indicator("ENEMY TURN")

func show_indicator(text: String) -> void:
	label.text = text
	
	# 使用統一的中性風格 (米色邊框)
	var border_color = Color(0.71, 0.61, 0.56, 1.0)
	var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = border_color
	panel.add_theme_stylebox_override("panel", style)
	
	# Update text color/outline
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	
	await _play_animation()

func _play_animation() -> void:
	if _tween:
		_tween.kill()
	
	# Keep logic, but don't change visibility or visuals
	_tween = create_tween()
	
	# 1. ENTER phase duration (approx 0.5s total including interval)
	_tween.tween_interval(0.5)
	
	# 2. SUSTAIN: Static Hold (1.5s) for synchronization
	var sustain_time = 1.5
	_tween.tween_interval(sustain_time)
	
	# 等待模擬的動畫時長結束
	await _tween.finished
	
	# 3. EXIT phase duration (approx 0.2s)
	await get_tree().create_timer(0.2).timeout
	
	# Emit finished signal for local listeners
	animation_finished.emit()
	
	# Report to TurnManager to proceed with turns
	if TurnManager:
		TurnManager.report_turn_visuals_finished()
	
	if TurnManager:
		TurnManager.report_turn_visuals_finished()

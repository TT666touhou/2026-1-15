extends CanvasLayer

signal animation_finished

@onready var container = $CenterContainer
@onready var panel = $CenterContainer/PanelContainer
@onready var label = $CenterContainer/PanelContainer/MarginContainer/Label

var _tween: Tween

func _ready() -> void:
	add_to_group("turn_indicator_ui")
	visible = false
	# ## [相關外部文件]: TurnManager.gd (現在統一由 TurnManager 手動呼叫 display_wait，避免雙重觸發)

## 回合提示 UI
## [相關外部文件]: TurnManager.gd (主要控制者)
func _on_turn_started(faction: FactionDefinition) -> void:
	if not faction: return
	display_wait(faction)

## 顯示回合提示並等待動畫結束 (異步 Coroutine API)
## [相關外部文件]: TurnManager.gd (await 此函式)
func display_wait(faction: FactionDefinition) -> void:
	if not faction: return
	
	# 設定文字與色彩
	label.text = faction.faction_name + " Turn"
	
	var border_color = Color(0.71, 0.61, 0.56, 1.0)
	var bg_color = Color(0.05, 0.05, 0.05, 0.9)
	
	if faction.is_controllable:
		border_color = Color(0.4, 1.0, 0.4, 0.8)
	else:
		border_color = Color(1.0, 0.4, 0.4, 0.8)
		
	var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = bg_color
	style.border_color = border_color
	panel.add_theme_stylebox_override("panel", style)
	
	await _play_animation_async()

func _play_animation_async() -> void:
	if _tween: _tween.kill()
	
	container.pivot_offset = container.size / 2.0
	visible = true
	container.modulate.a = 0.0
	container.scale = Vector2(0.8, 0.8)
	
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 1. 登場
	_tween.tween_property(container, "modulate:a", 1.0, 0.3)
	_tween.tween_property(container, "scale", Vector2.ONE, 0.3)
	
	# 2. 停留
	_tween.set_parallel(false)
	_tween.tween_interval(1.0)
	
	# 3. 離場
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(container, "modulate:a", 0.0, 0.2)
	_tween.tween_property(container, "scale", Vector2(1.2, 1.2), 0.2)
	
	await _tween.finished
	visible = false
	animation_finished.emit()
	if TurnManager and TurnManager.has_method("on_turn_indicator_finished"):
		TurnManager.on_turn_indicator_finished()

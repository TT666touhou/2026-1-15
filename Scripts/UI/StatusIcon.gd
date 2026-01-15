extends Control
class_name StatusIcon

# 狀態圖示控制器
# 負責顯示單個狀態的圖示與剩餘回合數

@onready var icon_sprite: Sprite2D = $Icon
@onready var turn_label: Label = $TurnLabel
# @onready var anim_player: AnimationPlayer = $AnimationPlayer # Removed

@export var test_mode: bool = false # F6 測試用開關
@export var default_turns: int = 3

var _tween: Tween
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	# 設定樞軸點為中心 (假設 icon 是 16x16)
	pivot_offset = size / 2
	_base_scale = scale
	
	if test_mode and get_tree().current_scene == self:
		_start_test_loop()

func setup(turns: int, color: Color = Color.WHITE) -> void:
	# icon_texture 由場景預設決定，這裡只更新數值與顏色
	if icon_sprite:
		icon_sprite.modulate = color
	update_turns(turns)

func update_turns(turns: int) -> void:
	if turn_label:
		turn_label.text = str(turns)
	
	_play_pulse_animation()

func _play_pulse_animation() -> void:
	# 使用 Tween 替代 AnimationPlayer
	if _tween and _tween.is_valid():
		_tween.kill()
		
	# 重置狀態
	scale = _base_scale
	
	_tween = create_tween()
	# 瞬間放大 1.2 倍，然後彈回原始大小
	_tween.tween_property(self, "scale", _base_scale * 1.3, 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", _base_scale, 0.2)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _start_test_loop() -> void:
	# 簡單的測試迴圈：每秒減少回合數
	print("[StatusIcon] Test loop started. Initial: ", default_turns)
	update_turns(default_turns)
	
	await get_tree().create_timer(1.0).timeout
	update_turns(default_turns - 1)
	print("[StatusIcon] Turns: ", default_turns - 1)
	
	await get_tree().create_timer(1.0).timeout
	update_turns(default_turns - 2)
	print("[StatusIcon] Turns: ", default_turns - 2)
	
	await get_tree().create_timer(1.0).timeout
	update_turns(0)
	print("[StatusIcon] Turns: 0 (Expired)")
	
	# 重啟循環
	await get_tree().create_timer(1.0).timeout
	_start_test_loop()

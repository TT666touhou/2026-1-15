extends Marker2D
class_name HealText

@onready var label: Label = $Label

var _tween: Tween
var _base_scale: Vector2 = Vector2(0.0625, 0.0625)

func _ready() -> void:
	_base_scale = scale
	visible = false

func popup_heal(amount: int) -> void:
	_reset_state()
	
	# 設定文字與樣式
	label.text = "+" + str(abs(amount))
	
	# 嘗試載入專用的治療設定
	var settings = load("res://Scenes/UI/FloatingTextSettings_Heal.tres")
	if settings:
		label.label_settings = settings
	else:
		label.modulate = Color.GREEN
	
	_play_float_up_animation()

func _reset_state() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	
	visible = true
	scale = _base_scale
	position = Vector2.ZERO
	modulate.a = 1.0
	rotation = 0.0

func _play_float_up_animation() -> void:
	_tween = create_tween()
	_tween.set_parallel(true) # 並行執行
	
	# 1. 緩慢上浮 (Float Up)
	var float_distance = -15.0 # 向上移動 15 像素
	var float_duration = 0.4 # 上浮總時間 (原 0.8 的一半)
	
	_tween.tween_property(self, "position:y", float_distance, float_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	# 2. 初始放大彈出 (Pop In) - 加快
	scale = Vector2.ZERO
	_tween.tween_property(self, "scale", _base_scale * 1.2, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 3. 恢復正常大小
	_tween.chain().tween_property(self, "scale", _base_scale, 0.1)
	
	# 4. 停留一小段時間後淡出
	_tween.chain().tween_interval(0.1)
	_tween.chain().tween_property(self, "modulate:a", 0.0, 0.1)
	
	# 5. 結束銷毀
	_tween.tween_callback(queue_free)

extends Control
class_name HandBorder

@export var hand_bottom_offset: float = 140.0
@export var border_thickness: float = 4.0
@export var border_color: Color = Color(1, 1, 0, 0.85)
@export var fade_in_duration: float = 0.12
@export var fade_out_duration: float = 0.12
@export var pad_left_right: float = 8.0

var _hand: Control = null

func _ready() -> void:
	visible = false
	modulate.a = 0.0
	_update_visual()
	_update_layout(get_viewport().get_visible_rect())

func configure_from_hand(hand) -> void:
	_hand = hand
	if hand:
		var v = hand.get("hand_bottom_offset")
		if v != null:
			hand_bottom_offset = float(v)
	# 佈局由外部（Hand）在已確定 viewport 時呼叫 update_layout()

func update_layout(_viewport_rect: Rect2) -> void:
	_update_layout(_viewport_rect)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_update_layout(get_viewport().get_visible_rect())

func _update_visual() -> void:
	# 使用 Panel + StyleBoxFlat 畫出矩形邊框（透明底）
	var panel := get_node_or_null("BorderPanel") as Panel
	if panel == null:
		panel = Panel.new()
		panel.name = "BorderPanel"
		add_child(panel)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = border_color
	sb.set_border_width_all(int(round(border_thickness)))
	panel.add_theme_stylebox_override("panel", sb)
	# 讓 Panel 充滿自身 Control 區域
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0

func _update_layout(_viewport_rect: Rect2) -> void:
	# 讓邊框直接對齊 Hand 的 global_rect，而不是用 parent-bottom 的 anchor 計算
	if _hand == null:
		return
	var rect: Rect2 = _hand.get_global_rect()
	rect.position.x += pad_left_right
	rect.size.x -= pad_left_right * 2.0
	# 重設 anchors，以 offset/position 直接指定
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	global_position = rect.position
	size = rect.size

func show_border() -> void:
	visible = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, fade_in_duration)

func hide_border() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	tw.finished.connect(func(): visible = false)

func debug_dump() -> void:
	var rect: Rect2 = get_global_rect()
	print("[HandLayout] border global_rect=", rect)

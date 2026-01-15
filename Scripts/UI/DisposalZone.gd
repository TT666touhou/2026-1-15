extends PanelContainer

signal card_disposed(card_data)

@onready var style_box: StyleBoxFlat = get_theme_stylebox("panel").duplicate()

var _hover_tween: Tween

enum EffectType {
	SPIN_AND_SHRINK,
	DISSOLVE_ONLY
}

@export var effect_type: EffectType = EffectType.DISSOLVE_ONLY

# Shader resources
const DISSOLVE_SHADER = preload("res://Shaders/Dissolve.gdshader")
var _noise_texture: NoiseTexture2D

func _ready() -> void:
	add_to_group("disposal_zone")
	if DeckManager:
		DeckManager.register_discard_ui(self)
		
	# 使用獨立的 StyleBox 實例以便修改顏色
	add_theme_stylebox_override("panel", style_box)
	
	# Prepare noise texture
	var noise = FastNoiseLite.new()
	noise.frequency = 0.1
	_noise_texture = NoiseTexture2D.new()
	_noise_texture.noise = noise
	_noise_texture.width = 64
	_noise_texture.height = 64

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# 檢查拖曳的數據是否為 Card
	if data is Card or (data is Dictionary and data.has("type") and data.type == "card"):
		return true
	# 兼容這專案的 Card.gd 拖曳邏輯 (Card.gd 可能直接傳遞 self)
	if typeof(data) == TYPE_OBJECT and data.has_method("get_card_data"):
		return true
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# 處理卡牌銷毀
	var card = data
	if typeof(data) == TYPE_OBJECT and data is Card:
		card = data
	
	if card:
		dispose_card(card)
		# 這裡手動 detach，因為通常 drop 是由 Control 系統觸發，
		# 但我們混合了 custom drag，所以 Hand 可能不知道這裡發生了什麼，
		# 除非我們從這裡通知 Hand。
		# 在本系統中，如果是透過 request_dispose 調用，則 Hand 已經做了 detach。
		# 如果是透過 Godot 的 _drop_data，我們需要通知 Hand。
		var hand = card.get_parent()
		if hand and hand.has_method("detach_card"):
			hand.detach_card(card)
		elif hand and hand.has_method("remove_card"):
			# 如果沒有 detach_card (後備)，只能 remove
			hand.remove_card(card)

func dispose_card(card: Card) -> void:
	print("[DisposalZone] Disposing card: ", card.name)
	
	# 禁用交互
	card.interactable = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_process(false) # 停止內部邏輯，防止 shader 參數衝突
	
	# 重定父節點到 UI 層 (DisposalZone 的父節點)，確保維持在 Screen Space 且可見
	# 不要 reparent 到 current_scene (Node2D)，因為那會導致 Control 的座標系變換為 World Space，
	# 且可能被 UI 層遮擋或跑出視野。
	var ui_layer = get_parent()
	if ui_layer:
		card.reparent(ui_layer, true)
	else:
		# Fallback
		card.reparent(get_tree().current_scene, true)
	
	# 確保在最上層
	card.z_index = 100
	
	# 嘗試應用 Dissolve Shader
	var container = card.get_node_or_null("SubViewportContainer")
	if container:
		var mat = ShaderMaterial.new()
		mat.shader = DISSOLVE_SHADER
		# 確保 NoiseTexture 有數據 (通常 _ready 之後已經有了，但為了保險可以用 await)
		if not _noise_texture.get_image():
			await _noise_texture.changed
		mat.set_shader_parameter("noise_texture", _noise_texture)
		mat.set_shader_parameter("dissolve_value", 0.0)
		container.material = mat
	
	# 1. 觸發視覺特效 (溶解/縮小)
	var tween = create_tween()
	
	match effect_type:
		EffectType.SPIN_AND_SHRINK:
			# 縮小 + 旋轉
			tween.tween_property(card, "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(card, "rotation_degrees", 360.0, 0.5).as_relative()
		EffectType.DISSOLVE_ONLY:
			# 僅溶解模式：不改變 scale 和 rotation，僅靠下方 shader 效果
			pass
	
	# 如果有 Shader，同時播放 Dissolve
	if container and container.material:
		tween.parallel().tween_property(container.material, "shader_parameter/dissolve_value", 1.0, 0.5)
	else:
		# 後備：透明度漸變
		tween.parallel().tween_property(card, "modulate:a", 0.0, 0.5)
	
	# 3. 等待動畫結束後真正銷毀
	await tween.finished
	
	emit_signal("card_disposed", card.card_data)
	
	# 通知 DeckManager 進行棄牌處理 (false = Discard, true = Exhaust)
	# 根據規劃，DisposalZone 的行為是 Discard
	if DeckManager:
		DeckManager.on_card_played(card.card_data, false)
	
	if is_instance_valid(card):
		card.queue_free()

# --- 視覺回饋 (Hover) ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open_discard_view()

func _open_discard_view() -> void:
	# 嘗試尋找 DeckView
	var deck_view = get_tree().get_first_node_in_group("deck_view")
	if not deck_view:
		# 後備：嘗試從 UI 根節點查找
		var ui = get_tree().root.find_child("UI", true, false)
		if ui:
			deck_view = ui.find_child("DeckView", true, false)
	
	if deck_view and deck_view.has_method("show_deck"):
		deck_view.show_deck("discard")
		print("[DisposalZone] Opened discard view")
	else:
		print("[DisposalZone] Error: DeckView not found")

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			# 當開始拖曳時，如果拖曳的是卡牌，可以高亮顯示垃圾桶 (可選)
			pass
		NOTIFICATION_DRAG_END:
			_reset_visuals()

func _mouse_entered() -> void:
	# 當滑鼠進入且正在拖曳時
	if get_viewport().gui_get_drag_data():
		_highlight_zone(true)

func _mouse_exited() -> void:
	_highlight_zone(false)

func _highlight_zone(active: bool) -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_hover_tween = create_tween()
	
	if active:
		_hover_tween.tween_property(style_box, "border_color", Color(1.0, 0.2, 0.2, 1.0), 0.2)
		_hover_tween.parallel().tween_property(self, "scale", Vector2(1.1, 1.1), 0.2)
	else:
		_reset_visuals()

func _reset_visuals() -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(style_box, "border_color", Color(0.5, 0.2, 0.2, 1.0), 0.2)
	_hover_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.2)

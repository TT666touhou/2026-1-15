extends Button
class_name DeckPileUI

@export var hand_reference: Hand
@export var margin_bottom_right: Vector2 = Vector2(20, 20)
@export var deck_view_path: NodePath

var _deck_view_node: Node = null

func _ready() -> void:
	# 設定佈局屬性以確保自適應
	_setup_layout()
	
	# 嘗試自動尋找 Hand 節點
	if not hand_reference:
		# 嘗試在父節點中尋找
		hand_reference = get_parent().get_node_or_null("Hand")
		# 如果找不到，嘗試全域搜尋
		if not hand_reference:
			hand_reference = get_tree().get_first_node_in_group("hand_layer") as Hand
	
	# 獲取 DeckView 引用
	if not deck_view_path.is_empty():
		_deck_view_node = get_node_or_null(deck_view_path)
	
	# 連接信號
	if DeckManager:
		if not DeckManager.deck_changed.is_connected(_on_deck_changed):
			DeckManager.deck_changed.connect(_on_deck_changed)
		DeckManager.register_deck_ui(self)
			
	# 初始更新
	call_deferred("update_appearance")

func _setup_layout() -> void:
	# 強制設定 Anchor 為右下角
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# 設定增長方向為向左上
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	
func update_appearance() -> void:
	# 更新尺寸
	if hand_reference:
		# 同步手牌大小
		custom_minimum_size = hand_reference.hand_card_size
		size = hand_reference.hand_card_size # 強制刷新
		
		# 確保軸心點在中心
		pivot_offset = size / 2.0
		
		# 強制計算 Offsets 以確保貼齊右下角
		# 因為 set_anchors_preset 可能會重置 Offsets，這裡明確設定四個邊界
		offset_right = -margin_bottom_right.x
		offset_bottom = -margin_bottom_right.y
		offset_left = offset_right - size.x
		offset_top = offset_bottom - size.y
	
	# 更新文字與狀態
	_update_text()

func _update_text() -> void:
	if DeckManager:
		var count = DeckManager.draw_pile.size()
		text = "DECK\n%d" % count
		
		# 如果牌庫空了，可以改變樣式（可選）
		disabled = count == 0

func _on_deck_changed() -> void:
	_update_text()

# 處理 GUI 輸入 (包含右鍵點擊)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_open_deck_view()
			accept_event()

# 左鍵點擊 (Button 預設行為)
func _pressed() -> void:
	# 檢查 DeckManager 是否存在且牌庫有牌
	if DeckManager and DeckManager.draw_pile.size() > 0:
		# 計算按鈕中心點作為動畫起點
		var start_pos = global_position + size / 2.0
		
		# 呼叫 DeckManager 抽牌
		DeckManager.draw_card(start_pos)
	elif DeckManager and DeckManager.draw_pile.size() == 0:
		print("[DeckPileUI] No cards left in draw pile!")

func _open_deck_view() -> void:
	if _deck_view_node and _deck_view_node.has_method("show_deck"):
		_deck_view_node.call("show_deck", "draw")
	else:
		print("[DeckPileUI] DeckView node not assigned or found!")

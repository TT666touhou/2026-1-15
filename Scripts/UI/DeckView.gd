extends Control
class_name DeckView

@onready var card_grid: GridContainer = $ContentPanel/Margin/VBox/ScrollContainer/MarginContainer/CardGrid
@onready var count_label: Label = $ContentPanel/Margin/VBox/Header/CountLabel
@onready var btn_remaining: Button = $ContentPanel/Margin/VBox/Header/ModeSwitch/BtnRemaining
@onready var btn_all: Button = $ContentPanel/Margin/VBox/Header/ModeSwitch/BtnAll

# 新增導出變數，預設為 160x240 (比手牌大)
@export var view_card_size: Vector2 = Vector2(160, 240)

const CardScene = preload("res://Scenes/Card/card.tscn")
const MODE_DRAW = "draw"
const MODE_MASTER = "master"
const MODE_DISCARD = "discard"

var _current_mode: String = MODE_MASTER

func _ready() -> void:
	# 加入群組以便查找
	add_to_group("deck_view")
	
	# 強制設定高層級以覆蓋手牌
	z_index = 1000
	
	# 監聽 ESC 關閉
	set_process_input(true)
	
	# 綁定按鈕事件
	btn_remaining.pressed.connect(func(): _set_mode(MODE_DRAW))
	btn_all.pressed.connect(func(): _set_mode(MODE_MASTER))
	
	# 監聽牌組變動，若開啟狀態則即時更新
	if DeckManager:
		DeckManager.deck_changed.connect(_on_deck_changed)
	
	# 檢查是否為獨立運行 (Standalone Mode)
	if get_parent() == get_tree().root:
		print("[DeckView] Running in standalone mode")
		_setup_standalone_test()
	else:
		# 作為子節點時預設隱藏，等待調用
		if visible:
			hide()

func _setup_standalone_test() -> void:
	# 確保 DeckManager 有數據
	if DeckManager:
		if DeckManager.get_all_cards().is_empty():
			# No starter deck loading here for now
			print("[DeckView] No cards in deck.")
	
	show_deck("master")

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()

func show_deck(mode: String = MODE_MASTER) -> void:
	_set_mode(mode)
	
	# 確保 DeckView 在最上層 (處理輸入優先級)
	# Godot 的 Control 輸入順序取決於 Tree Order (後面的先處理)
	# 雖然有 z_index = 1000，但若 DeploymentUI 是後添加的，仍可能攔截輸入
	if get_parent():
		move_to_front()
		
	show()

func _set_mode(mode: String) -> void:
	_current_mode = mode
	
	# 更新按鈕狀態 (視覺反饋)
	btn_remaining.set_pressed_no_signal(mode == MODE_DRAW)
	btn_all.set_pressed_no_signal(mode == MODE_MASTER)
	
	# 如果需要禁用當前選中的按鈕防止重複點擊
	btn_remaining.disabled = (mode == MODE_DRAW)
	btn_all.disabled = (mode == MODE_MASTER)
	
	# 特殊模式處理：Discard 模式隱藏切換按鈕，其他模式顯示
	var show_switches = (mode == MODE_DRAW or mode == MODE_MASTER)
	if btn_remaining.get_parent():
		btn_remaining.get_parent().visible = show_switches
		
	# 確保標題 Label 可見 (如果有隱藏邏輯的話，這裡強制顯示或根據設計調整)
	# 這裡假設 TitleLabel 預設是隱藏的，我們根據模式決定是否顯示
	var header = btn_remaining.get_parent().get_parent()
	if header:
		var title_label = header.get_node_or_null("TitleLabel")
		if title_label:
			title_label.visible = true
	
	refresh()

func close() -> void:
	hide()
	# get_tree().paused = false
	
	if get_parent() == get_tree().root:
		print("[DeckView] Closed in standalone mode")

func refresh() -> void:
	if not DeckManager:
		return
	
	# 清空現有卡牌
	for child in card_grid.get_children():
		child.queue_free()
	
	# 獲取數據 (RuntimeCardData 列表)
	var cards = DeckManager.get_all_cards(_current_mode)
	
	# 更新標題與計數
	var total_count = DeckManager.get_all_cards(_current_mode).size()
	var title_text = ""
	
	if _current_mode == MODE_DRAW:
		title_text = "DRAW PILE"
		count_label.text = "%d" % total_count # 右側已有計數，標題從簡
	elif _current_mode == MODE_MASTER:
		title_text = "DECK LIBRARY"
		count_label.text = "%d" % total_count
	elif _current_mode == MODE_DISCARD:
		title_text = "DISCARD PILE"
		count_label.text = "%d" % total_count
	else:
		count_label.text = "%d" % total_count

	# 嘗試更新 TitleLabel (如果存在)
	var header = btn_remaining.get_parent().get_parent() # VBox/Header
	if header:
		var title_label = header.get_node_or_null("TitleLabel")
		if title_label:
			title_label.text = title_text
			title_label.visible = not title_text.is_empty()
	
	# 兼容舊邏輯：如果 TitleLabel 不存在或不可見，將標題資訊整合到 CountLabel
	if header and header.get_node_or_null("TitleLabel") == null:
		if _current_mode == MODE_DRAW:
			count_label.text = "Draw Pile: %d" % total_count
		elif _current_mode == MODE_MASTER:
			count_label.text = "Total Cards: %d" % total_count
		elif _current_mode == MODE_DISCARD:
			count_label.text = "Discard Pile: %d" % total_count
	
	# 填充 Grid
	for card_data in cards:
		# 1. 創建 Wrapper (CenterContainer)
		# 目的：隔離 GridContainer 的 Layout 影響，確保 Card 保持原始尺寸 (80x120)
		# 並避免 SubViewportContainer 被強制拉伸導致內部座標錯亂
		var wrapper = CenterContainer.new()
		
		# 2. 創建 Card 實例
		var card = CardScene.instantiate()
		# 覆寫尺寸為檢視器專用大小
		card.card_size = view_card_size
		wrapper.add_child(card)
		
		# 設置 Wrapper 大小以適配卡牌
		wrapper.custom_minimum_size = view_card_size
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
		card_grid.add_child(wrapper)
		
		# 3. 設定數據與互動
		card.set_card_data(card_data)
		card.interactable = false # 禁止拖曳
		
		# 這裡不需要額外的 process_mode 設置，因為我們沒有暫停遊戲
		# SubViewport 會自動開始渲染

func _on_deck_changed() -> void:
	if visible:
		refresh()

func _on_close_button_pressed() -> void:
	close()

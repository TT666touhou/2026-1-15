extends Node

# 全域信號
signal deck_initialized
signal deck_changed # 任何牌組內容變動（增刪改）時觸發
signal card_drawn(card: RuntimeCardData)
signal card_discarded(card: RuntimeCardData)

# 核心數據：Master Deck (玩家擁有的所有卡牌實例)
var _master_deck: Array[RuntimeCardData] = []

# 戰鬥時的動態狀態
var draw_pile: Array[RuntimeCardData] = []
var discard_pile: Array[RuntimeCardData] = []
var hand_pile: Array[RuntimeCardData] = []
var exhaust_pile: Array[RuntimeCardData] = []

# 配置
var max_hand_size: int = 10
var max_deck_size: int = -1 # -1 表示無上限

# 引用
var _hand_ref: Control = null # 戰鬥場景中的 Hand 節點引用
var _deck_ui_ref: Control = null
var _discard_ui_ref: Control = null
const CardScene = preload("res://Scenes/Card/card.tscn")

func _ready() -> void:
	print("[DeckSystem] Initialized as Autoload")
	
	# Poker Deck auto-loading removed. 
	# Decks should be initialized via initialize_deck() by game logic.
	
	reset_for_combat()

# --- 初始化與設置 ---

func register_hand(hand: Control) -> void:
	_hand_ref = hand
	print("[DeckSystem] Hand registered: ", hand)

func register_deck_ui(node: Control) -> void:
	_deck_ui_ref = node

func register_discard_ui(node: Control) -> void:
	_discard_ui_ref = node

func initialize_deck(deck_def: Resource) -> void:
	_master_deck.clear()
	if deck_def and deck_def.get("cards"):
		var raw_cards = deck_def.get("cards")
		for raw_card in raw_cards:
			var runtime_card = RuntimeCardData.create(raw_card)
			_master_deck.append(runtime_card)
	
	print("[DeckSystem] Master Deck initialized with %d cards" % _master_deck.size())
	deck_initialized.emit()
	reset_for_combat() # 預設進入戰鬥準備狀態

func reset_for_combat() -> void:
	draw_pile = _master_deck.duplicate()
	discard_pile.clear()
	hand_pile.clear()
	exhaust_pile.clear()
	
	shuffle_draw_pile()
	print("[DeckSystem] Combat reset. Draw pile: %d" % draw_pile.size())
	deck_changed.emit()

func shuffle_draw_pile() -> void:
	draw_pile.shuffle()

# --- 戰鬥邏輯 ---

func draw_card(target_position: Vector2 = Vector2.ZERO) -> RuntimeCardData:
	# 檢查手牌上限
	if _hand_ref and _hand_ref.has_method("get_card_count"):
		if _hand_ref.get_card_count() >= max_hand_size:
			print("[DeckSystem] Cannot draw: Hand is full")
			return null
	
	# 檢查牌堆
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			print("[DeckSystem] Cannot draw: No cards left")
			return null
		_recycle_discard()
	
	var card = draw_pile.pop_back()
	hand_pile.append(card)
	
	# 通知 Hand 節點生成視覺實例
	if _hand_ref and _hand_ref.has_method("add_card"):
		_hand_ref.add_card(card, target_position)
	
	print("[DeckSystem] Drew card: ", card.get_display_name())
	card_drawn.emit(card)
	deck_changed.emit()
	return card

func _recycle_discard() -> void:
	_play_reshuffle_animation()
	
	print("[DeckSystem] Recycling discard pile...")
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	shuffle_draw_pile()
	deck_changed.emit()

func _play_reshuffle_animation(count_override: int = -1) -> void:
	if not _deck_ui_ref or not _discard_ui_ref:
		return
		
	var target_size = Vector2(80, 120)
	if _hand_ref and _hand_ref.get("hand_card_size"):
		target_size = _hand_ref.hand_card_size
		
	var start_center = _discard_ui_ref.global_position + _discard_ui_ref.size / 2.0
	var end_center = _deck_ui_ref.global_position + _deck_ui_ref.size / 2.0
	
	var card_offset = target_size / 2.0
	var start_pos = start_center - card_offset
	var end_pos = end_center - card_offset
	
	var count = 0
	if count_override > 0:
		count = count_override
	else:
		count = min(discard_pile.size(), 5)
		if count <= 0: count = 3
	
	var parent = _hand_ref.get_parent() if _hand_ref else get_tree().root
	
	var mid_x = (start_center.x + end_center.x) / 2.0
	var peak_height = 450.0 
	var control_point_center = Vector2(mid_x, min(start_center.y, end_center.y) - peak_height)
	var control_point = control_point_center - card_offset
	
	var noise = FastNoiseLite.new()
	noise.frequency = 0.1
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 64
	noise_tex.height = 64
	
	var spawn_timeline = create_tween()
	for i in range(count):
		spawn_timeline.tween_callback(_spawn_single_recycle_card.bind(parent, target_size, start_pos, control_point, end_pos, noise_tex))
		spawn_timeline.tween_interval(0.05)

func _spawn_single_recycle_card(parent: Node, target_size: Vector2, start_pos: Vector2, control_point: Vector2, end_pos: Vector2, noise_tex: Texture2D) -> void:
	var card = CardScene.instantiate()
	parent.add_child(card)
	
	if card.get("card_size") != null:
		card.card_size = target_size
		
	card.global_position = start_pos
	card.scale = Vector2.ONE
	card.rotation = randf_range(-0.5, 0.5)
	card.z_index = 2000
	card.interactable = false
	
	var container = card.get_node_or_null("SubViewportContainer")
	if container:
		var mat = ShaderMaterial.new()
		var shader = load("res://Shaders/Dissolve.gdshader")
		if shader:
			mat.shader = shader
			if noise_tex and not noise_tex.get_image():
				await noise_tex.changed
			mat.set_shader_parameter("noise_texture", noise_tex)
			mat.set_shader_parameter("dissolve_value", 1.0)
			container.material = mat
	
	var tween = create_tween()
	var duration = 0.8
	
	tween.tween_method(
		_update_card_bezier_pos.bind(card, start_pos, control_point, end_pos),
		0.0, 1.0, duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	if container and container.material:
		tween.parallel().tween_property(container.material, "shader_parameter/dissolve_value", 0.0, duration * 0.4)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		card.modulate.a = 0.0
		tween.parallel().tween_property(card, "modulate:a", 1.0, duration * 0.4)
	
	tween.parallel().tween_property(card, "scale", Vector2(0.3, 0.3), duration)
	tween.parallel().tween_property(card, "rotation", randf_range(-PI, PI), duration)
	
	tween.parallel().tween_property(card, "modulate:a", 0.0, 0.2).set_delay(duration - 0.2)
	
	tween.finished.connect(card.queue_free)

func _update_card_bezier_pos(t: float, card: Node, p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	if not is_instance_valid(card): return
	var q0 = p0.lerp(p1, t)
	var q1 = p1.lerp(p2, t)
	card.global_position = q0.lerp(q1, t)

func on_card_played(card: RuntimeCardData, exhaust: bool = false) -> void:
	if card in hand_pile:
		hand_pile.erase(card)
	
	if exhaust:
		exhaust_pile.append(card)
		print("[DeckSystem] Card exhausted: ", card.get_display_name())
	else:
		discard_pile.append(card)
		card_discarded.emit(card)
		print("[DeckSystem] Card discarded: ", card.get_display_name())
	
	deck_changed.emit()
	
	if hand_pile.is_empty() and draw_pile.is_empty() and not discard_pile.is_empty():
		print("[DeckSystem] Hand and Draw pile empty, auto-recycling discard...")
		_recycle_discard()

func on_card_played_by_data(card: Resource) -> void:
	var r_card = card
	if card is Resource and not card is RuntimeCardData:
		for rc in hand_pile:
			if rc.get_base_data() == card:
				r_card = rc
				break
	
	if r_card is RuntimeCardData:
		on_card_played(r_card)

func on_card_node_played(card_node: Node, exhaust: bool = false) -> void:
	var data = card_node.get("card_data")
	if data is RuntimeCardData:
		on_card_played(data, exhaust)

func get_master_deck() -> Array[RuntimeCardData]:
	return _master_deck

func get_all_cards(mode: String = "master") -> Array[RuntimeCardData]:
	match mode:
		"master": return _master_deck
		"draw": return draw_pile
		"discard": return discard_pile
		"hand": return hand_pile
		"exhaust": return exhaust_pile
	return _master_deck

func add_card_to_master_deck(base_data: Resource) -> bool:
	if max_deck_size != -1 and _master_deck.size() >= max_deck_size:
		print("[DeckSystem] Cannot add card: Max deck size reached")
		return false
	
	var new_card = RuntimeCardData.create(base_data)
	_master_deck.append(new_card)
	deck_changed.emit()
	return true

func remove_card_from_master_deck(card: RuntimeCardData) -> bool:
	if card in _master_deck:
		_master_deck.erase(card)
		deck_changed.emit()
		return true
	return false

func get_deck_count_str() -> String:
	if max_deck_size == -1:
		return "%d" % _master_deck.size()
	return "%d / %d" % [_master_deck.size(), max_deck_size]

func debug_add_card_to_hand(base_data: Resource) -> void:
	var new_card = RuntimeCardData.create(base_data)
	hand_pile.append(new_card)
	if _hand_ref and _hand_ref.has_method("add_card"):
		_hand_ref.add_card(new_card)
	deck_changed.emit()

func debug_test_recycle_animation() -> void:
	var count = randi_range(12, 20)
	print("[DeckSystem] Playing debug recycle animation with %d cards" % count)
	_play_reshuffle_animation(count)

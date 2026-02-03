extends HBoxContainer

var turn_label: Label
var phase_label: Label

func _ready() -> void:
	# Layout Settings
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = SIZE_SHRINK_END
	size_flags_vertical = SIZE_SHRINK_CENTER
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 20)
	
	# 創建 Turn Label
	turn_label = Label.new()
	turn_label.text = "Turn: 1"
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", 20)
	turn_label.modulate = Color.YELLOW
	add_child(turn_label)
	
	# 創建 Phase Label
	phase_label = Label.new()
	phase_label.text = "Phase: Player"
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 16)
	add_child(phase_label)
	
	# 連接信號
	if TurnManager:
		TurnManager.turn_changed.connect(_on_turn_changed)
		TurnManager.turn_count_changed.connect(_on_turn_count_changed)
		if TurnManager.has_signal("free_roam_mode_changed"):
			TurnManager.free_roam_mode_changed.connect(_on_free_roam_mode_changed)
		
		_update_display()

func _on_turn_changed(_faction: FactionDefinition) -> void:
	_update_display()

func _on_turn_count_changed(_count: int) -> void:
	_update_display()

func _on_free_roam_mode_changed(_enabled: bool) -> void:
	_update_display()

func _process(_delta: float) -> void:
	# 持續更新以反應 RESOLVING 等瞬時狀態
	_update_display()

func _update_display() -> void:
	if not TurnManager: return
	
	# 1. 優先權：搜刮模式 (State.LOOT_PHASE = 6)
	if TurnManager.current_state == TurnManager.State.LOOT_PHASE:
		phase_label.text = "LOOT PHASE"
		phase_label.modulate = Color.CYAN
		turn_label.text = "Turn: --"
		return

	# 2. 優先權：漫遊模式
	if TurnManager.is_free_roam_mode:
		phase_label.text = "ROAMING MODE"
		phase_label.modulate = Color(0.2, 1.0, 0.4) # Light Green
		turn_label.text = "Turn: --"
		return

	# 3. 一般回合顯示
	turn_label.text = "Turn: %d" % TurnManager.turn_count
	
	var faction = TurnManager.current_faction
	if faction:
		var state_name = TurnManager.State.keys()[TurnManager.current_state]
		phase_label.text = "Phase: %s (%s)" % [faction.faction_name, state_name]
		phase_label.modulate = faction.color
	else:
		phase_label.text = "Phase: None"
		phase_label.modulate = Color.WHITE

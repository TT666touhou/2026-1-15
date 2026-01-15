extends HBoxContainer

var turn_label: Label
var phase_label: Label
# End Turn Button moved to independent scene

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
		
		# 初始化顯示
		if TurnManager.get("is_free_roam_mode"):
			_on_free_roam_mode_changed(true)
		else:
			_update_ui(TurnManager.current_faction, TurnManager.turn_count)

func _on_turn_changed(faction: FactionDefinition) -> void:
	_update_ui(faction, TurnManager.turn_count)

func _on_turn_count_changed(count: int) -> void:
	# 如果在漫遊模式，不更新回合數顯示
	if TurnManager and TurnManager.get("is_free_roam_mode"):
		return
	turn_label.text = "Turn: %d" % count

func _on_free_roam_mode_changed(enabled: bool) -> void:
	if enabled:
		phase_label.text = "ROAMING MODE"
		phase_label.modulate = Color(0.2, 1.0, 0.4) # Light Green
		turn_label.text = "Turn: --"
	else:
		_update_ui(TurnManager.current_faction, TurnManager.turn_count)

func _update_ui(faction: FactionDefinition, count: int) -> void:
	# 再次檢查是否處於漫遊模式 (防止競態條件)
	if TurnManager and TurnManager.get("is_free_roam_mode"):
		phase_label.text = "ROAMING MODE"
		phase_label.modulate = Color(0.2, 1.0, 0.4)
		turn_label.text = "Turn: --"
		return

	turn_label.text = "Turn: %d" % count
	
	if faction:
		phase_label.text = "Phase: %s" % faction.faction_name
		phase_label.modulate = faction.color
	else:
		phase_label.text = "Phase: None"
		phase_label.modulate = Color.WHITE

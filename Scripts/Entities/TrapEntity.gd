extends GridEntity
class_name TrapEntity

var trap_atk: int = 10
var trap_resource: TrapCard = null

func _ready() -> void:
	# 陷阱通常不需要 Combo Indicator 或血條 (除非可破壞)
	super._ready()
	z_index = 1
	add_to_group("traps")

func setup_trap(card: TrapCard) -> void:
	"""從卡片初始化陷阱"""
	trap_resource = card
	trap_atk = card.attack_damage
	if card.faction:
		faction = card.faction
	if card.footprint_data:
		footprint_data = card.footprint_data

func should_register_combo() -> bool:
	"""陷阱不列入連擊計數"""
	return false

func play_preview_animation() -> void:
	"""僅播放視覺效果，不造成傷害"""
	_play_trigger_visuals()

func _register_cells() -> void:
	if grid == null or footprint_data == null:
		return
	if not grid.has_method("get_cells_in_footprint"):
		return
		
	var cells = grid.get_cells_in_footprint(grid_position, footprint_data)
	for cell in cells:
		if grid.has_method("set_trap_occupied"):
			grid.set_trap_occupied(cell, self)
		# 注意：陷阱不調用 set_cell_occupied，因此不會阻擋移動或路徑搜尋

func _unregister_cells() -> void:
	if grid == null or footprint_data == null:
		return
	var cells = grid.get_cells_in_footprint(grid_position, footprint_data)
	for cell in cells:
		if grid.has_method("clear_trap"):
			grid.clear_trap(cell)

func apply_overrides(overrides: Dictionary) -> void:
	super.apply_overrides(overrides)
	if overrides.has("attack_damage"):
		trap_atk = int(overrides["attack_damage"])
	elif overrides.has("atk"): # 兼容舊名稱或簡寫
		trap_atk = int(overrides["atk"])

func on_stepped_on(stepper: GridEntity) -> void:
	"""當單位踩上陷阱時觸發"""
	if stepper and stepper.has_method("take_damage"):
		print("[TrapEntity] Triggered on ", stepper.name, " for ", trap_atk, " damage")
		# 注意：take_damage 可能是非同步的
		_call_take_damage_async(stepper)
		_play_trigger_visuals()

func _call_take_damage_async(stepper: GridEntity) -> void:
	await stepper.take_damage(trap_atk)

func _play_trigger_visuals() -> void:
	# 播放尖刺彈出動畫
	var anim_player = get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.play("trigger")
		anim_player.queue("idle") # 動畫結束後回到縮回狀態
	
	# 同時播放抖動與粒子
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_damage_animation"):
		visuals.play_damage_animation()

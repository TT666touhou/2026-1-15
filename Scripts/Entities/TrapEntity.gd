extends GridEntity
class_name TrapEntity

## TrapEntity
## 負責管理陷阱的邏輯、網格佔用與觸發效果

# --- 屬性 ---
var trap_atk: int = 10
var trap_resource: TrapCard = null

# ============================================================================
# 初始化
# ============================================================================

func _ready() -> void:
	# 陷阱通常不需要 Combo Indicator 或血條 (除非可破壞)
	super._ready()
	z_index = 1
	add_to_group("traps")

func setup_trap(card: TrapCard) -> void:
	"""從卡片資源初始化陷阱"""
	trap_resource = card
	trap_atk = card.attack_damage
	if card.faction:
		faction = card.faction
	if card.footprint_data:
		footprint_data = card.footprint_data

func apply_overrides(overrides) -> void:
	"""應用編輯器覆蓋數值"""
	# 核心修正：手動執行基類邏輯以避開 super 解析問題
	if overrides is Dictionary:
		if overrides.has("move_limit"):
			move_limit = int(overrides["move_limit"])
		
		if overrides.has("attack_damage"):
			trap_atk = int(overrides["attack_damage"])
		elif overrides.has("atk"):
			trap_atk = int(overrides["atk"])

# ============================================================================
# 網格與觸發
# ============================================================================

func _register_cells() -> void:
	if not grid or not footprint_data: return
	if not grid.has_method("get_cells_in_footprint"): return
		
	var cells = grid.get_cells_in_footprint(grid_position, footprint_data)
	for cell in cells:
		if grid.has_method("set_trap_occupied"):
			grid.set_trap_occupied(cell, self)

func _unregister_cells() -> void:
	if not grid or not footprint_data: return
	var cells = grid.get_cells_in_footprint(grid_position, footprint_data)
	for cell in cells:
		if grid.has_method("clear_trap"):
			grid.clear_trap(cell)

func on_stepped_on(stepper: GridEntity) -> void:
	"""當單位踩上陷阱時觸發傷害"""
	if stepper and stepper.has_method("take_damage"):
		print("[TrapEntity] Triggered on ", stepper.name, " for ", trap_atk, " damage")
		stepper.take_damage(trap_atk)
		_play_trigger_visuals()

# ============================================================================
# 視覺表現
# ============================================================================

func play_preview_animation() -> void:
	_play_trigger_visuals()

func _play_trigger_visuals() -> void:
	var anim_player = get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.play("trigger")
		anim_player.queue("idle")
	
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_damage_animation"):
		visuals.play_damage_animation()

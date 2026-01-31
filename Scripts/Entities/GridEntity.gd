extends RigidBody2D
class_name GridEntity

## GridEntity
## 網格實體基類，管理物理、網格定位、戰鬥結算與視覺表現

# --- 基礎屬性 ---
var grid: Node
var grid_position: Vector2i = Vector2i.ZERO
@export var footprint_data: Resource
@export var faction: FactionDefinition
@export var is_player: bool = false
@export var enable_debug_log: bool = true
var is_selected: bool = false
var character_data: CharacterData
var movement_range_data: MovementRangeData
var move_limit: int = -1
var is_boss: bool = false

# --- 物理參數 ---
@export var friction: float = 0.0
@export var linear_damp_value: float = 1.0
@export var angular_damp_value: float = 0.0
var last_position: Vector2 = Vector2.ZERO
var _last_trap_cell: Vector2i = Vector2i(-1, -1)
var _init_frames: int = 5
var _collision_cooldowns: Dictionary = {}
var is_dying: bool = false # 標記單位是否正在執行死亡流程
var last_trait_trigger_time: int = 0 # 上次觸發特質的時間 (ms)

const LootCollectorComponentScript = preload("res://Scripts/Components/LootCollectorComponent.gd")
var loot_collector: Node2D = null # 搜刮組件

# --- Shader 與 視覺 ---
var combined_shader = preload("res://Shaders/UnitCombined.gdshader")
var _combined_material: ShaderMaterial

# --- 信號 ---
@warning_ignore("unused_signal")
signal movement_data_changed
@warning_ignore("unused_signal")
signal entry_animation_finished

# ============================================================================
# 公開配置 API
# ============================================================================

func apply_overrides(overrides) -> void:
	"""應用來自編輯器或模板的數值覆蓋"""
	if not overrides is Dictionary or overrides.is_empty(): return
		
	if overrides.has("move_limit"):
		move_limit = int(overrides["move_limit"])
		
	if overrides.has("movement") and movement_range_data:
		var move_dict = overrides["movement"]
		var new_data = movement_range_data.duplicate()
		for key in move_dict:
			new_data.set(key, int(move_dict[key]))
		movement_range_data = new_data
		movement_data_changed.emit()
	elif overrides.has("move_limit"):
		movement_data_changed.emit()
		
	if character_data:
		if overrides.has("max_health"):
			character_data.max_health = int(overrides["max_health"])
			character_data.current_health = character_data.max_health
			
		if overrides.has("attack_damage"):
			character_data.attack_damage = int(overrides["attack_damage"])

		if overrides.has("base_shield"):
			character_data.shield = int(overrides["base_shield"])
		if overrides.has("base_barriers"):
			character_data.barriers = int(overrides["base_barriers"])
		if overrides.has("base_dr"):
			character_data.base_dr = float(overrides["base_dr"])
		
		if overrides.has("is_boss"):
			is_boss = bool(overrides["is_boss"])
		
		character_data.recalculate_stats()
		character_data.stats_changed.emit()

func initialize_runtime(data: CharacterData, faction_group: String, is_player_unit: bool) -> void:
	"""運行時統一初始化介面"""
	is_player = is_player_unit
	
	# 核心修正：支援多種陣營初始化
	if faction_group == "player":
		faction = load("res://Resources/Factions/Faction_Player.tres")
	elif faction_group == "neutral":
		# 嘗試載入中立陣營，若無則預設為敵人
		var neutral_path = "res://Resources/Factions/Faction_Neutral.tres"
		if ResourceLoader.exists(neutral_path):
			faction = load(neutral_path)
		else:
			faction = load("res://Resources/Factions/Faction_Enemy.tres")
	else:
		faction = load("res://Resources/Factions/Faction_Enemy.tres")
		
	if data: setup_character(data)
	
	input_pickable = true
	
	# 核心修正：僅對 GridEntity 子類且非物理拾取物的對象進行物理層級覆寫
	# 這樣可以保護裝備、金幣等在 Scene 中已經設定好的物理設定
	var is_loot = false
	if self.has_method("is_in_group"):
		is_loot = is_in_group("loot") or is_in_group("physical_coins") or is_in_group("equipment_entities")
	
	if not is_loot:
		if collision_layer == 1:
			collision_layer = 1
			# 玩家不再物理撞擊戰利品層 (128)，改由 LootCollectorComponent 的 Area2D 偵測
			collision_mask = (1 | 2 | 4) if faction_group == "player" else (1 | 2)
	
	if not is_in_group(faction_group): add_to_group(faction_group)
	if not is_in_group("grid_entities"): add_to_group("grid_entities")

func setup_character(data: CharacterData) -> void:
	character_data = data
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		_combined_material = ShaderMaterial.new()
		_combined_material.shader = combined_shader
		sprite.material = _combined_material
	
	_connect_data_signals()
	_update_shader_health()
	
	# 監聽裝備替換信號
	if not character_data.equipment_swapped.is_connected(_on_equipment_swapped):
		character_data.equipment_swapped.connect(_on_equipment_swapped)

func _on_equipment_swapped(old_item: Resource, _slot: int) -> void:
	# 當手動替換裝備時，將舊裝備噴飛出來
	var equip_scene = load("res://Scenes/Entities/EquipmentEntity.tscn")
	if not equip_scene: return
	
	var drop = equip_scene.instantiate()
	drop.set("equipment_data", old_item)
	
	# 加入場景 (通常是 UnitsLayer 或 Parent)
	var units_layer = get_parent()
	units_layer.add_child(drop)
	drop.global_position = global_position
	
	# 給予隨機衝量噴出
	var random_dir = Vector2.RIGHT.rotated(randf_range(0, TAU))
	var force = randf_range(150.0, 300.0)
	drop.apply_central_impulse(random_dir * force)
	
	# 確保視覺更新
	if drop.has_method("_update_sprite_from_data"):
		drop.call("_update_sprite_from_data")
	
	print("[GridEntity] Spat out old equipment: ", old_item.get("item_name"))

# ============================================================================
# 生命週期與內部初始化
# ============================================================================

func _ready() -> void:
	z_index = 5
	_setup_groups()
	_setup_physics_base()
	_setup_grid_reference()
	_register_cells()
	_initialize_components()
	
	contact_monitor = true
	max_contacts_reported = 4
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
		
	# 連接全域受傷信號，用於觸發特質
	if AttackManager:
		if not AttackManager.unit_damaged.is_connected(_on_global_unit_damaged):
			AttackManager.unit_damaged.connect(_on_global_unit_damaged)

func _setup_groups() -> void:
	add_to_group("grid_entities")
	if is_player or (faction and faction.is_controllable):
		add_to_group("player")
	else:
		add_to_group("enemy")

func _setup_physics_base() -> void:
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = linear_damp_value
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = angular_damp_value
	lock_rotation = true
	can_sleep = true

func _setup_grid_reference() -> void:
	grid = get_tree().get_first_node_in_group("grid")
	if grid_position == Vector2i.ZERO and grid:
		grid_position = grid.world_to_grid(global_position)

func _connect_data_signals() -> void:
	if not character_data: return
	character_data.health_changed.connect(_on_health_changed)
	character_data.died.connect(_on_died)
	character_data.reflect_triggered.connect(_on_reflect_triggered)
	character_data.parry_triggered.connect(_on_parry_triggered)
	character_data.barrier_triggered.connect(_on_barrier_triggered)

# ============================================================================
# 戰鬥結算與傷害
# ============================================================================

func apply_damage(amount: int, _ignore_barrier: bool = false, _ignore_shield: bool = false, attacker: GridEntity = null, is_pursuit: bool = false) -> int:
	if not AttackManager: return 0
	var report = AttackManager.resolve_combat(attacker, self, amount, false)
	
	match report["result"]:
		"avoid": show_avoid_text()
		"barrier": show_barrier_text()
		"parry": show_parry_text()
		"hit":
			var dmg = report["damage"]
			if dmg > 0:
				_apply_damage_visuals(dmg, is_pursuit)
				if report["reflect_damage"] > 0 and attacker:
					attacker.apply_damage(report["reflect_damage"], true, true, self)
				if report["heal_amount"] > 0 and attacker:
					attacker.heal(report["heal_amount"])
				if report["pursuit_damage"] > 0:
					apply_damage(report["pursuit_damage"], false, false, attacker, true)
			return dmg
	return 0

func _apply_damage_visuals(dmg: int, is_pursuit: bool) -> void:
	if is_pursuit: show_pursuit_number(dmg)
	else: show_damage_number(dmg)
	
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_damage_animation"):
		visuals.play_damage_animation()

# ============================================================================
# 物理控制 API
# ============================================================================

func lock_physics() -> void:
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_deferred("freeze", true)
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	input_pickable = true
	if character_data: character_data.is_moving_physics = false

func unlock_physics() -> void:
	set_deferred("freeze", false)
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	can_sleep = false
	sleeping = false

# ============================================================================
# 碰撞與觸發邏輯
# ============================================================================

func _initialize_components() -> void:
	# 只有玩家單位需要搜刮組件
	if is_in_group("player"):
		loot_collector = LootCollectorComponentScript.new()
		add_child(loot_collector)

func _physics_process(_delta: float) -> void:
	if not character_data: return
	
	if _init_frames > 0:
		_init_frames -= 1
		last_position = global_position
		return
		
	var current_velocity = linear_velocity.length()
	if current_velocity > 5.0:
		if not character_data.is_moving_physics:
			character_data.is_moving_physics = true
			last_position = global_position
	elif current_velocity < 2.0 and character_data.is_moving_physics:
		character_data.is_moving_physics = false

	var distance_moved = global_position.distance_to(last_position)
	if distance_moved > 0.1:
		character_data.accumulated_distance += distance_moved
		last_position = global_position
		
		if grid:
			var current_cell = grid.world_to_grid(global_position)
			if current_cell != grid_position:
				grid_position = current_cell
				
			if grid.has_method("get_trap") and current_cell != _last_trap_cell:
				_last_trap_cell = current_cell
				var trap = grid.get_trap(current_cell)
				if trap and trap.has_method("on_stepped_on"):
					trap.on_stepped_on(self)
		
		_check_distance_skill_trigger()

func _check_distance_skill_trigger() -> void:
	var skill = character_data.runtime_skill
	if skill and skill.trigger_distance > 0.0:
		if character_data.accumulated_distance >= skill.trigger_distance:
			character_data.accumulated_distance = 0.0
			if SkillManager:
				SkillManager.execute_skill(self, skill, grid_position)

func _on_body_entered(body: Node) -> void:
	# if enable_debug_log:
	# 	print("[GridEntity] _on_body_entered with: ", body.name, " (Groups: ", body.get_groups(), ")")
	
	# 播放單位碰撞音效
	if body is GridEntity:
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_sfx_2d("unit_collision", global_position, 0.0)
	
	# 1. 環境碰撞
	if body.is_in_group("wall") or (body is StaticBody2D and body.collision_layer & 2):
		var state = PhysicsServer2D.body_get_direct_state(get_rid())
		var normal = Vector2.ZERO
		if state.get_contact_count() > 0:
			normal = state.get_contact_local_normal(0)
		_handle_wall_collision(normal)
		return

	# 2. 掉落物碰撞 (Loot)
	if body.is_in_group("loot") and is_in_group("player"):
		_handle_loot_collision(body)
		return

	# 3. 單位碰撞
	var target = body as GridEntity
	if target:
		if _is_hostile_to(target):
			_handle_hostile_collision(target)
		elif _is_friendly_to(target):
			_handle_friendly_collision(target)

func _is_hostile_to(other: GridEntity) -> bool:
	return is_in_group("player") != other.is_in_group("player")

func _is_friendly_to(other: GridEntity) -> bool:
	return is_in_group("player") == other.is_in_group("player")

func _handle_loot_collision(loot: Node) -> void:
	if loot_collector and loot_collector.has_method("handle_loot_collision"):
		loot_collector.handle_loot_collision(loot)

func _handle_hostile_collision(target: GridEntity) -> void:
	# 核心修正：極其嚴格的轉場與狀態判定
	var dm = get_tree().root.get_node_or_null("DungeonManager")
	if dm and dm.get("_is_transitioning"):
		return

	if TurnManager:
		if TurnManager.current_state == TurnManager.State.DEPLOYMENT or TurnManager.current_state == TurnManager.State.WAITING:
			return

	var tid = target.get_instance_id()
	if _collision_cooldowns.get(tid, 0) > Time.get_ticks_msec() - 500: return
	_collision_cooldowns[tid] = Time.get_ticks_msec()
	
	var is_resolving = TurnManager and TurnManager.current_state == TurnManager.State.RESOLVING
	var is_free_roam = TurnManager and TurnManager.is_free_roam_mode
	
	if TurnManager and (TurnManager.is_enemy_turn() or is_resolving or is_free_roam):
		if is_in_group("enemy") and target.is_in_group("player"):
			var dmg = character_data.attack_damage if character_data else 10
			target.apply_damage(dmg, false, false, self, false)
	
	if TurnManager and (TurnManager.is_player_turn() or is_resolving or is_free_roam):
		if is_in_group("player") and target.is_in_group("enemy"):
			var dmg = character_data.attack_damage if character_data else 10
			target.apply_damage(dmg, false, false, self, false)

func _handle_wall_collision(normal: Vector2 = Vector2.ZERO) -> void:
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_wall_collision_fx"):
		visuals.play_wall_collision_fx(normal)
	
	if character_data and character_data.runtime_skill:
		var s_name = character_data.runtime_skill.skill_name
		if s_name.contains("迴旋飛斧"):
			SkillManager.call_deferred("execute_skill", self, character_data.runtime_skill, grid_position)

func _handle_friendly_collision(target: GridEntity) -> void:
	# 法師 (Unit003) 撞擊隊友時觸發連鎖閃電
	if name.contains("Unit003") or (character_data and character_data.unit_def and character_data.unit_def.resource_path.contains("Unit_003")):
		if SkillManager and SkillManager.has_method("create_lightning_chain"):
			var base_atk: float = 10.0
			if character_data: base_atk = character_data.get_effective_attack()
			var combo_mult: float = 1.0
			if AttackManager:
				var scaling: float = 0.1
				if character_data: scaling = character_data.combo_damage_scaling
				combo_mult = AttackManager.get_combo_damage_multiplier(scaling)
			var final_dmg: int = int(round(base_atk * combo_mult))
			SkillManager.create_lightning_chain(self, target, final_dmg)
	
	linear_velocity *= 1.03

# ============================================================================
# 視覺輔助與信號
# ============================================================================

func _on_health_changed(_c: int, _m: int) -> void: _update_shader_health()
func _update_shader_health() -> void:
	if _combined_material and character_data:
		var hp_p = float(character_data.current_health) / float(character_data.get_effective_max_health())
		_combined_material.set_shader_parameter("health_percent", hp_p)

func _on_died() -> void: _handle_death()
func _on_reflect_triggered(_a: CharacterData, _amt: int, _r: CharacterData) -> void: pass
func _on_parry_triggered() -> void: show_parry_text()
func _on_barrier_triggered() -> void: show_barrier_text()

func _spawn_text(text: String, color: Color = Color.WHITE) -> void:
	var scn = load("res://Scenes/UI/FloatingText.tscn")
	if scn:
		var inst = scn.instantiate()
		inst.global_position = global_position + Vector2(0, -16)
		inst.top_level = true
		get_tree().current_scene.add_child(inst)
		if inst.has_method("popup_text"): inst.popup_text(text, color)

func show_damage_number(amt: int) -> void: _spawn_text(str(amt), Color.WHITE)
func show_avoid_text() -> void: _spawn_text("AVOID", Color.WHITE)
func show_parry_text() -> void: _spawn_text("PARRY", Color.WHITE)
func show_barrier_text() -> void: _spawn_text("BARRIER", Color.WHITE)
func show_pursuit_number(amt: int) -> void: _spawn_text(str(amt), Color.WHITE)

# ============================================================================
# 網格定位與生命週期
# ============================================================================

func on_selected() -> void:
	is_selected = true

func on_deselected() -> void:
	is_selected = false

func set_grid_position(cell: Vector2i) -> void:
	if character_data and character_data.is_moving_physics:
		grid_position = cell
		return
	_unregister_cells()
	grid_position = cell
	_register_cells()
	if grid: global_position = grid.grid_to_world_center_footprint(cell, footprint_data)

func _register_cells() -> void:
	if grid and footprint_data:
		for c in grid.get_cells_in_footprint(grid_position, footprint_data):
			grid.set_cell_occupied(c, self)

func _unregister_cells() -> void:
	if grid and footprint_data:
		grid.clear_cells_footprint(grid_position, footprint_data)

func _handle_death() -> void:
	if is_dying: return
	is_dying = true
	
	lock_physics()
	collision_layer = 0
	collision_mask = 0
	
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_death_animation"):
		visuals.play_death_animation()
		await get_tree().create_timer(0.5).timeout
	
	if BoardManager:
		BoardManager.unregister_entity(self)
	
	call_deferred("queue_free")

func prepare_for_entry() -> void:
	var sprite = get_node_or_null("Sprite2D")
	if sprite: sprite.modulate.a = 0.0

func play_entry_animation(delay: float = 0.0) -> void:
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_spawn_animation"):
		visuals.play_spawn_animation(2)
		if not visuals.spawn_animation_finished.is_connected(_on_entry_animation_finished):
			visuals.spawn_animation_finished.connect(_on_entry_animation_finished, CONNECT_ONE_SHOT)
	else:
		var sprite = get_node_or_null("Sprite2D")
		if sprite: sprite.modulate.a = 1.0
		_on_entry_animation_finished()

func _on_entry_animation_finished() -> void:
	entry_animation_finished.emit()

# ============================================================================
# 特質監聽與執行
# ============================================================================

func _on_global_unit_damaged(target: Node, attacker: Node, _amount: int) -> void:
	if is_dying or character_data == null or character_data.character_trait == null:
		return
		
	var trait_data = character_data.character_trait
	for effect in trait_data.effects:
		if effect.trigger_type != TraitEffect.TriggerType.ON_DAMAGED:
			continue
			
		if not _is_trait_trigger_valid(effect, target, attacker):
			continue
			
		var now = Time.get_ticks_msec()
		if now - last_trait_trigger_time < 200:
			continue
		last_trait_trigger_time = now
		_execute_trait_effect(effect, target)
	
	_execute_global_gold_passive(target)

func _execute_global_gold_passive(target: Node) -> void:
	if target == self and is_in_group("player"):
		gain_coin(1)

func _is_trait_trigger_valid(effect: TraitEffect, target: Node, _attacker: Node) -> bool:
	match effect.target_faction:
		TraitEffect.TargetFaction.SELF: return target == self
		TraitEffect.TargetFaction.ALLY: return target.is_in_group("player")
		TraitEffect.TargetFaction.ENEMY: return target.is_in_group("enemy")
		TraitEffect.TargetFaction.ALL: return true
	return false

func _execute_trait_effect(effect: TraitEffect, _target: Node) -> void:
	if effect.effect_behavior == TraitEffect.EffectBehavior.GRANT_RESOURCE:
		if effect.resource_key == "coin":
			gain_coin(int(effect.resource_amount))

func gain_coin(amount: int, show_floating_text: bool = false) -> void:
	var ledger = get_tree().get_first_node_in_group("ledger")
	if ledger:
		ledger.add_resource("coin", amount)
		if show_floating_text:
			_spawn_text("+%d Coin" % amount, Color.YELLOW)

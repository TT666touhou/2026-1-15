extends GridEntity
class_name TurretEntity

var trap_atk: int = 15
var trap_resource: TurretCard = null
var arrow_scene = preload("res://Scenes/Shared/ArrowProjectile.tscn")

func _ready() -> void:
	super._ready()
	z_index = 1
	add_to_group("turrets")

func setup_turret(card: TurretCard) -> void:
	"""從卡片初始化砲台"""
	trap_resource = card
	trap_atk = card.attack_damage
	if card.footprint_data:
		footprint_data = card.footprint_data

func should_register_combo() -> bool:
	"""砲台不列入連擊計數"""
	return false

func take_damage(amount: int, ignore_barrier: bool = false, ignore_shield: bool = false, attacker: CharacterData = null, is_pursuit: bool = false) -> int:
	"""覆寫受傷邏輯，當被撞擊時向反方向發射箭矢"""
	print("[TurretEntity] take_damage called! Amount: ", amount, " Attacker: ", attacker)
	var actual_damage = await super.take_damage(amount, ignore_barrier, ignore_shield, attacker, is_pursuit)
	
	# 偵測撞擊來源方向
	if attacker and attacker.status_manager_ref:
		var attacker_node = attacker.status_manager_ref.get_parent()
		print("[TurretEntity] Attacker node found: ", attacker_node.name if attacker_node else "null")
		if attacker_node is GridEntity:
			# 計算撞擊方向 (從攻擊者到砲台)
			var diff = grid_position - attacker_node.grid_position
			var ram_dir = Vector2i(
				clampi(diff.x, -1, 1),
				clampi(diff.y, -1, 1)
			)
			print("[TurretEntity] Impact direction: ", ram_dir, " (Diff: ", diff, ")")
			
			if ram_dir != Vector2i.ZERO:
				# 往反方向射擊 (增加短暫閃紅預警)
				if has_method("update_attack_indicators"):
					var arrow_tween = create_tween()
					arrow_tween.tween_method(update_attack_indicators, 0.0, 1.0, 0.15)
					await arrow_tween.finished
					update_attack_indicators(0.0)
				_fire_arrow(ram_dir)
	else:
		print("[TurretEntity] No attacker or status_manager_ref found in take_damage.")
				
	return actual_damage

func _fire_arrow(direction: Vector2i) -> void:
	"""在指定方向生成箭矢"""
	if arrow_scene:
		var arrow = arrow_scene.instantiate()
		get_parent().add_child(arrow)
		
		# 砲台發射位置為砲台中心
		# setup(start_grid_pos, dir, dmg, speed, attacker)
		arrow.setup(grid_position, direction, trap_atk, 0.1, self)
		print("[TurretEntity] Fired arrow in direction: ", direction)

func apply_overrides(overrides: Dictionary) -> void:
	super.apply_overrides(overrides)
	if overrides.has("attack_damage"):
		trap_atk = int(overrides["attack_damage"])
	elif overrides.has("atk"):
		trap_atk = int(overrides["atk"])

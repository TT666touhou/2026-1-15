extends EnemyProjectile
class_name ArrowProjectile

## 箭矢子彈實體
## 繼承 EnemyProjectile，但碰撞邏輯更廣泛 (傷害撞擊者的敵對單位)

func _check_collision() -> bool:
	if not grid or not grid.has_method("get_occupant"):
		return false
		
	var occupant = grid.get_occupant(grid_position)
	if occupant is GridEntity and occupant != attacker_entity:
		# 箭矢特殊邏輯：傷害除了發射者(砲台)以外的任何實體
		# 或者可以根據需求設定陣營
		if occupant.has_method("apply_damage"):
			print("[ArrowProjectile] Hit: ", occupant.name, " for ", damage, " damage.")
			# apply_damage 現在是非同步的
			var do_damage = func(): await occupant.apply_damage(damage, false, false, attacker_entity)
			do_damage.call()
		return true
	return false

extends Node
class_name EnemyAIController

## 敵方 AI 控制器
## 負責評估單位的最佳移動方案

## 計算單一單位的最佳移動方案
static func calculate_best_move_for_unit(tree: SceneTree, unit: GridEntity) -> Dictionary:
	if not is_instance_valid(unit): return {}
	
	var entities = tree.get_nodes_in_group("grid_entities")
	var player_units = entities.filter(func(e):
		return e is GridEntity and e.faction and e.faction.is_controllable
	)
	
	var reachable = unit.get_reachable_cells()
	if not reachable.has(unit.grid_position):
		reachable.append(unit.grid_position)
		
	var best_move = {}
	var max_score = -999999.0
	
	for cell in reachable:
		var score = _evaluate_move(unit, cell, player_units)
		if best_move.is_empty() or score > max_score:
			max_score = score
			best_move = {"unit": unit, "cell": cell}
			
	return best_move

static func _evaluate_move(unit: GridEntity, target_cell: Vector2i, players: Array) -> float:
	var total_hits = 0
	var dist_reduction = 0.0
	
	# 1. 評分：即時攻擊潛力 (權重最高)
	var attack_results = unit.get_attack_results(target_cell)
	for target in attack_results:
		if target in players:
			total_hits += attack_results[target].get("hits", 0)
			
	# 2. 評分：長遠規劃 (Greedy 距離縮減)
	if not players.is_empty():
		var old_min_dist = _get_min_dist_to_group(unit.grid_position, players)
		var new_min_dist = _get_min_dist_to_group(target_cell, players)
		dist_reduction = float(old_min_dist - new_min_dist)
		
	# 最終評分公式
	# Hits * 1000 + 距離縮減 * 10
	var score = (total_hits * 1000.0) + (dist_reduction * 10.0)
	
	# 加入微小隨機值避免平分時行為死板，並優先考慮靠左上的位置 (傳統)
	score += randf() * 0.1
	score -= (target_cell.y * 0.01 + target_cell.x * 0.001)
	
	return score

static func _get_min_dist_to_group(pos: Vector2i, group: Array) -> int:
	var min_dist = 9999
	for member in group:
		if is_instance_valid(member):
			# 曼哈頓距離
			var dist = abs(pos.x - member.grid_position.x) + abs(pos.y - member.grid_position.y)
			if dist < min_dist:
				min_dist = dist
	return min_dist

## 兼容性保留
static func get_best_faction_direction(_tree: SceneTree, _faction: FactionDefinition) -> Vector2i:
	return Vector2i.ZERO

extends Node
class_name EnemyAIController

## 敵方 AI 控制器
## 負責評估整個陣營的最佳行動方案

class MoveScore:
	var unit: GridEntity
	var cell: Vector2i
	var total_hits: int = 0
	var max_combo: int = 0
	
	func _init(u: GridEntity, c: Vector2i, hits_data: Dictionary):
		unit = u
		cell = c
		for target in hits_data:
			var hits = hits_data[target].get("hits", 0)
			total_hits += hits
			if hits > max_combo:
				max_combo = hits

	static func is_better_than(a: MoveScore, b: MoveScore) -> bool:
		# 1. 優先考慮總攻擊次數 (Total Hits)
		if a.total_hits != b.total_hits:
			return a.total_hits > b.total_hits
		
		# 2. 總次數相同時，考慮單體最高連擊 (Max Combo)
		if a.max_combo != b.max_combo:
			return a.max_combo > b.max_combo
		
		# 3. 戰術價值相同時，優先選擇靠上方的 (Smallest Y)
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		
		# 4. 靠左側的 (Smallest X)
		return a.cell.x < b.cell.x

## 計算指定陣營當前的最佳移動
## 返回: { "unit": GridEntity, "cell": Vector2i } 或空字典
static func calculate_best_move(tree: SceneTree, faction: FactionDefinition) -> Dictionary:
	var entities = tree.get_nodes_in_group("grid_entities")
	var faction_units = entities.filter(func(e): 
		return e is GridEntity and e.faction == faction and not e.is_boss
	)
	
	# 如果有 Boss，Boss 也要考慮 (除非需求說 Boss 不動，但通常 Boss 也要參與評價)
	var bosses = entities.filter(func(e): 
		return e is GridEntity and e.faction == faction and e.is_boss
	)
	faction_units.append_array(bosses)

	var best_score: MoveScore = null
	
	for unit in faction_units:
		if not is_instance_valid(unit): continue
		
		# 獲取該單位所有可到達的格子
		var reachable = unit.get_reachable_cells()
		
		# 必須包含原地，因為「不移動」也是一種選擇
		if not reachable.has(unit.grid_position):
			reachable.append(unit.grid_position)
			
		for cell in reachable:
			# 模擬在該格子時的攻擊結果
			var hits_data = unit.get_attack_results(cell)
			var score = MoveScore.new(unit, cell, hits_data)
			
			if best_score == null or MoveScore.is_better_than(score, best_score):
				best_score = score
				
	if best_score:
		print("[EnemyAI] Best move found: ", best_score.unit.name, " to ", best_score.cell, 
			" (Hits: ", best_score.total_hits, ", Combo: ", best_score.max_combo, ")")
		return {"unit": best_score.unit, "cell": best_score.cell}
		
	return {}

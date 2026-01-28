extends Node
class_name EnemyAttackComponent

## 敵人攻擊組件基類
## 負責定義敵人的攻擊行為與目標搜尋

@onready var parent_entity: GridEntity = get_parent()

func _ready() -> void:
	pass

func perform_attack() -> void:
	"""執行攻擊的入口，由 TurnManager 調用"""
	pass

func _get_nearest_player() -> GridEntity:
	var players = get_tree().get_nodes_in_group("player")
	var nearest: GridEntity = null
	var min_dist = INF
	
	for p in players:
		if p is GridEntity:
			var d = parent_entity.global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				nearest = p
	return nearest

func _get_all_players() -> Array:
	return get_tree().get_nodes_in_group("player")

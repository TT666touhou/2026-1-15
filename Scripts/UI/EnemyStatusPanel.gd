extends PanelContainer

@export var enemy_card_scene: PackedScene
@onready var list_container: VBoxContainer = $MarginContainer/VBox/ScrollContainer/EnemyList

var enemy_cards = {} # Dictionary[GridEntity, Control]

func _ready() -> void:
	# 初始載入時，尋找現有敵人
	_refresh_all()
	
	# 監聽節點添加，以自動發現新敵人
	# 注意：這是一個比較全局的監聽，性能上可能需要優化，或者改由 BoardManager 發送信號
	get_tree().node_added.connect(_on_node_added)

func _refresh_all() -> void:
	# 清空當前列表
	for child in list_container.get_children():
		child.queue_free()
	enemy_cards.clear()
	
	# 尋找所有 GridEntity
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for entity in entities:
		if entity is GridEntity:
			_check_and_add_enemy(entity)

func _on_node_added(node: Node) -> void:
	if node is GridEntity:
		# 等待一幀以確保屬性已初始化 (如 faction)
		await get_tree().process_frame
		if is_instance_valid(node):
			_check_and_add_enemy(node)

func _check_and_add_enemy(entity: GridEntity) -> void:
	# 檢查是否為敵人 (陣營不同於玩家)
	
	# 如果已經在列表中，跳過
	if enemy_cards.has(entity):
		return
		
	var is_enemy = false
	var player_faction = TurnManager.current_faction 
	
	if entity.faction:
		if player_faction:
			if entity.faction != player_faction:
				is_enemy = true
		elif entity.faction.resource_path.to_lower().contains("enemy"):
			is_enemy = true
	
	if is_enemy:
		_add_enemy_card(entity)

func _add_enemy_card(entity: GridEntity) -> void:
	if enemy_card_scene == null:
		return
		
	var card = enemy_card_scene.instantiate()
	list_container.add_child(card)
	card.update_info(entity)
	enemy_cards[entity] = card
	
	# 監聽實體移除 (死亡)
	entity.tree_exiting.connect(func(): _remove_enemy_card(entity))

func _remove_enemy_card(entity: GridEntity) -> void:
	if enemy_cards.has(entity):
		var card = enemy_cards[entity]
		if is_instance_valid(card):
			card.queue_free()
		enemy_cards.erase(entity)

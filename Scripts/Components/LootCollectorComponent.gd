extends Node2D
class_name LootCollectorComponent

## LootCollectorComponent
## 負責管理玩家單位的戰利品收集邏輯，包含磁鐵範圍與裝備替換

# --- 屬性 ---
@export var magnet_radius: float = 20.0
@export var collection_threshold: float = 2.0 # 速度低於此值時執行裝備替換

var _parent_entity: GridEntity = null
var _magnet_area: Area2D = null

func _ready() -> void:
	_parent_entity = get_parent() as GridEntity
	if not _parent_entity:
		push_error("[LootCollectorComponent] Parent is not a GridEntity!")
		return
		
	if _parent_entity.is_in_group("player"):
		_setup_coin_magnet()

func _physics_process(_delta: float) -> void:
	pass # 裝備拾取邏輯已移除，回歸手動拖拽

func _setup_coin_magnet() -> void:
	# print("[LootCollector] Setting up magnet for: ", _parent_entity.name)
	# 建立磁鐵區域
	_magnet_area = Area2D.new()
	_magnet_area.name = "CoinMagnetArea"
	_magnet_area.collision_layer = 0
	_magnet_area.collision_mask = 128 # Layer 8: Loot
	_magnet_area.monitorable = false # 不被別人偵測
	_magnet_area.monitoring = true   # 主動偵測
	
	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = magnet_radius
	collision.shape = circle
	
	_magnet_area.add_child(collision)
	add_child(_magnet_area)
	
	_magnet_area.body_entered.connect(_on_magnet_body_entered)
	# print("[LootCollector] Area2D created. Radius: ", magnet_radius, " Mask: ", _magnet_area.collision_mask)

func _on_magnet_body_entered(body: Node) -> void:
	if not _parent_entity or _parent_entity.is_dying: return
	
	# 處理金幣 (僅保留金幣吸附)
	if body.is_in_group("physical_coins"):
		if body.has_method("collect_to_node"):
			body.collect_to_node(_parent_entity)
			# print("[LootCollector] Magnetized coin to: ", _parent_entity.name)

## 公開接口：由父實體轉發碰撞事件
func handle_loot_collision(loot: Node) -> void:
	if loot.is_in_group("physical_coins"):
		if loot.has_method("collect_to_node"):
			loot.collect_to_node(_parent_entity)

# 移除所有裝備替換邏輯與動畫演出

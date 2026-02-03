extends RigidBody2D
class_name EquipmentEntity

## 裝備實體 (物理掉落物)
## 負責存儲數據、視覺更新，並在被玩家撞擊時觸發拾取

@export var equipment_data: Resource
var is_collectible: bool = false # 標記是否可以被拾取 (下一回合才開啟)

func _ready() -> void:
	# 加入群組以便被識別
	add_to_group("loot")
	add_to_group("equipment_entities")
	
	# 初始狀態：物理活躍但不可拾取
	freeze = false
	lock_rotation = true
	gravity_scale = 0.0
	linear_damp = 5.0
	angular_damp = 5.0
	is_collectible = false # 預設關閉拾取
	
	# 確保滑鼠可偵測 (用於顯示資訊)
	input_pickable = true
	
	# 更新視覺
	_update_sprite_from_data()
	
	# 監聽解鎖信號
	if TurnManager:
		TurnManager.loot_unlocked.connect(enable_collection)
		# 如果生成時已經是可以行動的階段，直接解鎖
		if TurnManager.is_player_turn():
			enable_collection()

func enable_collection() -> void:
	if is_collectible: return
	is_collectible = true
	# print("[EquipmentEntity:%d] UNLOCKED: is_collectible set to TRUE" % get_instance_id())
	
	# 斷開信號
	if TurnManager and TurnManager.loot_unlocked.is_connected(enable_collection):
		TurnManager.loot_unlocked.disconnect(enable_collection)

func _on_turn_started(_faction: FactionDefinition) -> void:
	pass # 舊邏輯移除，統一由信號處理

func collect_to_node(_target: Node2D) -> void:
	# [相容性介面] 裝備目前不使用磁鐵吸附，由 LootCollectorComponent 精確碰撞處理
	pass

func _update_sprite_from_data() -> void:
	var sprite = get_node_or_null("Sprite2D")
	if not sprite: return
		
	if equipment_data:
		var tex = equipment_data.get("icon")
		if tex:
			sprite.texture = tex
			sprite.region_enabled = false 
		else:
			# Fallback: 預設戒指
			var default_atlas = load("res://Tilesheet/colored-transparent_packed.png")
			sprite.texture = default_atlas
			sprite.region_enabled = true
			sprite.region_rect = Rect2(480, 288, 16, 16)
		
		sprite.visible = true
		sprite.modulate.a = 1.0

func get_equipment_data() -> Resource:
	return equipment_data

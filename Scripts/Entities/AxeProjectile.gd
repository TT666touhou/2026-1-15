extends Area2D
class_name AxeProjectile

var direction: Vector2 = Vector2.ZERO
var speed: float = 300.0
var damage: int = 0
var caster: GridEntity = null
var lifetime: float = 5.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# 設置碰撞遮罩
	collision_layer = 0
	add_to_group("projectiles")
	# 同時偵測 Layer 1 (Player/Enemy) 與 Layer 3 (Enemy/Props)
	# 由於目前專案中敵人與玩家可能都混在 Layer 1，我們透過 faction 判斷
	collision_mask = 1 | 4 
	
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# 自動清理
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func setup(pos: Vector2, dir: Vector2, dmg: int, spd: float, source: GridEntity) -> void:
	global_position = pos
	direction = dir.normalized()
	damage = dmg
	speed = spd
	caster = source
	
	# 確保 Area2D 的物理同步
	if sprite:
		sprite.rotation = direction.angle()
	print("[AxeProjectile] Setup complete: Pos: ", global_position, " | Dir: ", direction, " | Damage: ", damage)

func _physics_process(delta: float) -> void:
	# 移動
	global_position += direction * speed * delta
	
	# 旋轉效果
	if sprite:
		sprite.rotation += 15.0 * delta # 快速旋轉

func _on_body_entered(body: Node) -> void:
	if is_instance_valid(caster) and body == caster:
		return
		
	if body is GridEntity:
		var target = body as GridEntity
		
		# 陣營檢查：僅攻擊不同陣營的單位
		if is_instance_valid(caster) and caster.faction and target.faction:
			if caster.faction == target.faction:
				return # 相同陣營，不造成傷害
		
		# 核心修正：投射物傷害現在統一透過 AttackManager 結算
		var attacker = caster if is_instance_valid(caster) else null
		target.apply_damage(damage, false, false, attacker)
		# 飛斧穿透，不銷毀

func _on_area_entered(_area: Area2D) -> void:
	# 如果敵人是用 Area2D 實作的碰撞
	pass

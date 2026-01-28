extends CharacterBody2D
class_name ArrowProjectile

## 玩家箭矢投射物
## 負責在場景中直線飛行、反彈並對敵方單位造成傷害

@onready var sprite: Sprite2D = $Sprite2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 100.0
var damage: int = 1
var attacker_entity: GridEntity = null
var _is_active: bool = false
var _lifetime: float = 0.0
var _bounce_count: int = 0
const MAX_BOUNCES: int = 5 # 限制反彈次數，防止永久彈跳

func _ready() -> void:
	_is_active = true
	add_to_group("projectiles")
	# 設定初始旋轉
	rotation = direction.angle()

func setup(pos: Vector2, dir: Vector2, dmg: int, atk_speed: float, attacker: GridEntity) -> void:
	global_position = pos
	direction = dir.normalized()
	velocity = direction * atk_speed
	damage = dmg
	speed = atk_speed
	attacker_entity = attacker
	
	rotation = direction.angle()
	print("[ArrowProjectile] Setup complete (CharacterBody2D): Pos: ", global_position, " | Dir: ", direction, " | Speed: ", speed)

func _physics_process(delta: float) -> void:
	if not _is_active: return
	
	_lifetime += delta
	if _lifetime > 10.0: # 壽命延長一點點因為速度慢
		_destroy()
		return

	# 使用 move_and_collide 處理物理碰撞與反彈
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		var collider = collision.get_collider()
		
		# 1. 檢查是否撞到 GridEntity
		if collider is GridEntity and collider != attacker_entity:
			var target = collider as GridEntity
			# 陣營檢查
			if is_instance_valid(attacker_entity) and attacker_entity.faction and target.faction:
				if attacker_entity.faction != target.faction:
					_apply_hit(target)
					return
			elif target.is_in_group("enemy"):
				_apply_hit(target)
				return
		
		# 2. 處理反彈 (撞到牆壁或非敵對單位)
		var normal = collision.get_normal()
		velocity = velocity.bounce(normal)
		direction = velocity.normalized()
		
		# 更新箭頭方向
		rotation = direction.angle()
		
		_bounce_count += 1
		print("[ArrowProjectile] Bounced! Normal: ", normal, " | New Dir: ", direction, " | Count: ", _bounce_count)
		
		if _bounce_count > MAX_BOUNCES:
			_destroy()

func _apply_hit(target: GridEntity) -> void:
	if target.has_method("apply_damage"):
		# 核心修正：投射物傷害現在統一透過 AttackManager 結算
		# 注意：這裡傳入的是 attacker_entity (GridEntity)，符合 apply_damage 的參數類型要求
		# 如果發動者已死亡 (previously freed)，則傳入 null
		var attacker = attacker_entity if is_instance_valid(attacker_entity) else null
		target.apply_damage(damage, false, false, attacker, false)
	
	_destroy()

func _destroy() -> void:
	_is_active = false
	queue_free()

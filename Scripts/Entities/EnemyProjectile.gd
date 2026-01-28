extends CharacterBody2D
class_name EnemyProjectile

## 敵方通用子彈投射物
## 負責在場景中直線飛行、反彈並對玩家單位造成傷害

@onready var sprite: Sprite2D = $Sprite2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 150.0
var damage: int = 1
var attacker_entity: GridEntity = null
var _is_active: bool = false
var _lifetime: float = 0.0
var _bounce_count: int = 0
const MAX_BOUNCES: int = 3 # 敵方子彈反彈次數較少

# 穿透屬性
var is_piercing: bool = false
var _hit_cooldowns: Dictionary = {}
const HIT_INTERVAL_MS: int = 500

# 輔助偵測器 (僅穿透模式使用)
var _detection_area: Area2D = null

func _ready() -> void:
	_is_active = true
	add_to_group("projectiles")
	# 設定初始旋轉
	rotation = direction.angle()
	
	# 如果是穿透型，初始化 Area2D 偵測器
	if is_piercing:
		_setup_piercing_physics()

func setup(pos: Vector2, dir: Vector2, dmg: int, atk_speed: float, attacker: GridEntity) -> void:
	global_position = pos
	direction = dir.normalized()
	velocity = direction * atk_speed
	damage = dmg
	speed = atk_speed
	attacker_entity = attacker
	
	rotation = direction.angle()
	
	# 自動判定穿透 (如果貼圖是魔球)
	# 注意：這是在 _ready 之前調用的，所以 _ready 會根據這個值進行設置
	print("[EnemyProjectile] Setup complete: Pos: ", global_position, " | Dir: ", direction, " | Piercing: ", is_piercing)

func _setup_piercing_physics() -> void:
	# 1. 調整本體的物理遮罩：只偵測環境層 (Layer 2)，不偵測單位層 (Layer 1)
	# 這樣 move_and_collide 就只會對牆壁產生反彈，而會直接穿過單位
	collision_mask = 2 
	
	# 2. 建立 Area2D 用於偵測單位重疊
	_detection_area = Area2D.new()
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 1 | 4 # 偵測單位層與敵人層 (實現全穿透)
	add_child(_detection_area)
	
	# 建立與本體形狀一致的碰撞形狀
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node:
		var new_shape = CollisionShape2D.new()
		new_shape.shape = shape_node.shape.duplicate()
		_detection_area.add_child(new_shape)
	
	_detection_area.body_entered.connect(_on_detection_body_entered)
	print("[EnemyProjectile] Piercing physics setup complete for: ", name)

func set_texture(tex: Texture2D) -> void:
	if sprite:
		sprite.texture = tex
		# 如果貼圖包含 magicorb，自動開啟穿透 (備援判定)
		if tex.resource_path.contains("magicorb"):
			is_piercing = true
			if is_inside_tree() and _detection_area == null:
				_setup_piercing_physics()

func _physics_process(delta: float) -> void:
	if not _is_active: return
	
	_lifetime += delta
	if _lifetime > 8.0:
		_destroy()
		return

	# 使用 move_and_collide 處理物理碰撞與反彈
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		var collider = collision.get_collider()
		
		# 非穿透模式下的單位碰撞處理
		if not is_piercing:
			if collider is GridEntity and collider.is_in_group("player"):
				_apply_hit(collider)
				_destroy()
				return
		
		# 牆壁反彈 (不論是否穿透都會執行，因為穿透模式下 collision_mask 只包含牆壁)
		var normal = collision.get_normal()
		velocity = velocity.bounce(normal)
		direction = velocity.normalized()
		rotation = direction.angle()
		
		_bounce_count += 1
		var max_b = 10 if is_piercing else MAX_BOUNCES
		if _bounce_count > max_b:
			_destroy()

func _on_detection_body_entered(body: Node) -> void:
	if not is_piercing: return
	if body is GridEntity and body != attacker_entity:
		# 核心修正：檢查目標是否為敵對陣營
		var is_target_player = body.is_in_group("player")
		var is_attacker_player = attacker_entity.is_in_group("player") if attacker_entity else false
		
		# 只有當陣營不同時才造成傷害
		if is_target_player != is_attacker_player:
			_apply_hit(body)

func _apply_hit(target: GridEntity) -> void:
	if not target.has_method("apply_damage"): return
	
	var target_id = target.get_instance_id()
	var current_time = Time.get_ticks_msec()
	
	if _hit_cooldowns.has(target_id):
		if current_time - _hit_cooldowns[target_id] < HIT_INTERVAL_MS:
			return
	
	_hit_cooldowns[target_id] = current_time
	print("[EnemyProjectile] Piercing hit on: ", target.name)
	
	# 如果發動者已死亡 (previously freed)，則傳入 null
	var attacker = attacker_entity if is_instance_valid(attacker_entity) else null
	target.apply_damage(damage, false, false, attacker)

func _destroy() -> void:
	_is_active = false
	queue_free()

extends Node
class_name UnitMovementController

## Unit 移動控制器
## 管理移動邏輯（使用狀態機和 NavigationAgent）

# Inspector 參數
@export var move_speed: float = 100.0  # 基礎移動速度（可被 CardProvider 覆蓋）
@export var rotation_speed: float = 5.0  # 旋轉速度
@export var path_update_interval: float = 0.1  # 路徑更新間隔（秒）
@export var base_position: Vector2i = Vector2i(-1, -1)
@export var card_provider_path: NodePath = ^"CardProvider"

# 調試選項
@export var enable_debug_log: bool = false

# 節點引用
var _parent: CharacterBody2D = null
# var _unit_team: UnitTeam = null (Removed)
var _detection_area = null
var _card_provider = null

# 移動狀態
var _moved_this_frame: bool = false

# 服務引用（未來階段會使用）
var _dynamic_obstacle_manager: Node = null
var _resource_map: Node = null

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D
	if _parent == null:
		push_error("[UnitMovementController] Parent must be CharacterBody2D")
		return
	
	# 查找子節點
	# _unit_team = _parent.get_node_or_null("UnitTeam") as UnitTeam (Removed)
	_detection_area = _parent.get_node_or_null("UnitDetectionArea")
	
	# 嘗試獲取 CardProvider（可選）
	_card_provider = _parent.get_node_or_null(card_provider_path)
	
	# 查找服務（未來階段會使用，目前先設為 null）
	_find_services()
	
	if enable_debug_log:
		print("[UnitMovementController] Initialized for ", _parent.name)

func _physics_process(_delta: float) -> void:
	# 如果這幀沒有移動，逐漸減速
	if not _moved_this_frame:
		_parent.velocity = lerp(_parent.velocity, Vector2.ZERO, 0.5)
		_parent.move_and_slide()
	_moved_this_frame = false

## 移動方法（供狀態機調用）
func move(velocity: Vector2) -> void:
	_parent.velocity = lerp(_parent.velocity, velocity, 0.2)
	_parent.move_and_slide()
	_moved_this_frame = true

## 設置基礎移動速度（CardProvider 可調用）
func set_base_speed(speed: float) -> void:
	move_speed = speed

## 取消移動
func cancel_movement() -> void:
	if enable_debug_log:
		print("[UnitMovementController] Canceled movement")

	# 停止移動（用於狀態機）
	_parent.velocity = Vector2.ZERO

## 移動到世界座標位置（用於玩家命令，狀態機調用）
func move_to_world_position(target_pos: Vector2) -> void:
	# 這個方法由狀態機調用，不依賴 Blackboard
	# 狀態機會處理實際的移動邏輯
	if enable_debug_log:
		print("[UnitMovementController] Move command received: ", target_pos)


## 查找服務（未來階段會使用）
func _find_services() -> void:
	# 查找 World 節點中的服務
	var world = get_tree().current_scene
	if world == null:
		return
	
	# 查找 DynamicObstacleManager（未來階段）
	_dynamic_obstacle_manager = world.get_node_or_null("DynamicObstacleManager")
	
	# 查找 ResourceMap（未來階段）
	_resource_map = world.get_node_or_null("ResourceMap")
	
	# 查找 Grid（不再需要 GridPlacer）
	if enable_debug_log:
		print("[UnitMovementController] Found services:")
		print("  DynamicObstacleManager: ", _dynamic_obstacle_manager != null)
		print("  ResourceMap: ", _resource_map != null)

func set_base_position(cell: Vector2i) -> void:
	base_position = cell

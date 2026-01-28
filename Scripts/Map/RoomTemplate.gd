extends Resource
class_name RoomTemplate

enum RoomDifficulty {
	TUTORIAL,
	EASY,
	NORMAL,
	HARD,
	ELITE,
	BOSS
}

@export var room_name: String = "New Room"
@export var difficulty: RoomDifficulty = RoomDifficulty.EASY
@export var width: int = 12
@export var height: int = 8
@export_multiline var description: String = ""

# 存儲實體配置
# 每個 Dictionary 包含:
# {
#   "pos": Vector2i,           # 網格座標 (左上角)
#   "card_path": String,       # UnitCard 資源路徑
#   "overrides": Dictionary    # (可選) 數值覆蓋: { "max_health": int, "attack_damage": int, "move_limit": int }
# }
@export var entities: Array[Dictionary] = []

# 存儲玩家出生點座標 (有序)
# Index 0 = Player 1 (Leader), Index 1 = Player 2, etc.
@export var player_spawn_points: Array[Vector2i] = []

func add_room_entity(pos: Vector2i, card_path: String, overrides: Dictionary = {}) -> void:
	entities.append({
		"pos": pos,
		"card_path": card_path,
		"overrides": overrides
	})

func clear_entities() -> void:
	entities.clear()

func clear_spawn_points() -> void:
	player_spawn_points.clear()

extends Resource
class_name BaseCard

# 與舊版卡片相容的欄位（供 UI/生成系統使用）
@export var card_id: String = ""
@export var card_name: String = ""   # 與舊版 UI 相容
@export var description: String = ""
@export var cost: Dictionary = {}    # 例如 {"wood":10}

# 新系統共用欄位
@export var display_name: String = ""   # 若為空，UI可回退使用 card_name
@export var max_playable_count: int = 0 # 可選：牌組限制
@export var max_health: float = 100.0

func get_cost_dict() -> Dictionary:
	return cost.duplicate()

func get_card_image() -> Texture2D:
	# 可於子類覆寫；若保留 null 則 UI應該容忍
	return null

class_name CardInstance extends RefCounted

# 原始靜態數據 (只讀，用於重置或參考)
var base_data: SkillCard

# 動態執行時數據 (可修改)
var current_soul_cost: int
var current_targeting: TargetingDefinition
var current_effects: Array[EffectDefinition] = []

# 唯一識別符 (用於除錯或追蹤)
var instance_id: int

func _init(data: SkillCard):
	base_data = data
	instance_id = get_instance_id()
	
	# 初始化動態屬性
	current_soul_cost = data.soul_cost
	
	# 深拷貝 Targeting (因為我們可能會修改範圍或條件)
	if data.targeting:
		current_targeting = data.targeting.duplicate(true)
	
	# 深拷貝 Effects (因為我們可能會修改數值)
	for effect in data.effects:
		current_effects.append(effect.duplicate(true))

# --- 輔助方法 ---

func get_card_id() -> String:
	return base_data.card_id

func get_card_name() -> String:
	return base_data.card_name

func get_description() -> String:
	return base_data.description

func get_icon() -> Texture2D:
	return base_data.get_card_icon()

func get_exclusive_unit_id() -> String:
	return base_data.exclusive_unit_id

# 用於檢查這張卡是否為某個 Resource 的實例
func is_instance_of(resource: Resource) -> bool:
	return base_data == resource

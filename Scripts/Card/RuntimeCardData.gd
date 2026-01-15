extends Resource
class_name RuntimeCardData

# 繼承自 Resource，因為 CardProvider 需要 Resource 類型
# 這樣可以同時兼容編輯器配置和運行時數據

# 原始數據引用
var _base_data: Resource

# 運行時修改屬性
var custom_modifiers: Dictionary = {}
var temp_modifiers: Dictionary = {} # 用於戰鬥內暫時修改

# SkillCard 專屬運行時數據
var runtime_targeting: TargetingDefinition = null
var runtime_effects: Array[EffectDefinition] = []
var runtime_exclusive_unit_id: String = ""

# Movement Skill Runtime Data
var runtime_is_move_skill: bool = false
var runtime_post_move_targeting: TargetingDefinition = null
var runtime_post_move_effects: Array[EffectDefinition] = []

# 建構函式
func _init(base_data: Resource = null) -> void:
	if base_data:
		_base_data = base_data
		_init_skill_data()

func _init_skill_data() -> void:
	if _base_data and _base_data.get_script().resource_path.contains("SkillCard"):
		runtime_exclusive_unit_id = _base_data.get("exclusive_unit_id")
		
		var base_targeting = _base_data.get("targeting")
		if base_targeting:
			runtime_targeting = base_targeting.duplicate(true)
			
		var base_effects = _base_data.get("effects")
		if base_effects:
			for eff in base_effects:
				if eff:
					runtime_effects.append(eff.duplicate(true))

		# Copy Movement Skill Data
		runtime_is_move_skill = _base_data.get("is_move_skill")
		var base_post_targeting = _base_data.get("post_move_targeting")
		if base_post_targeting:
			runtime_post_move_targeting = base_post_targeting.duplicate(true)
			
		var base_post_effects = _base_data.get("post_move_effects")
		if base_post_effects:
			for eff in base_post_effects:
				if eff:
					runtime_post_move_effects.append(eff.duplicate(true))

# 靜態工廠方法
static func create(base_data: Resource) -> RuntimeCardData:
	return RuntimeCardData.new(base_data)

# --- 屬性存取介面 (Proxy) ---

func get_display_name() -> String:
	if not _base_data: return "Unknown"
	if custom_modifiers.has("display_name"):
		return custom_modifiers["display_name"]
	
	if _base_data.has_method("get_display_name"):
		return _base_data.get_display_name()
	if _base_data.get("display_name"):
		return _base_data.get("display_name")
	if _base_data.get("card_name"):
		return _base_data.get("card_name")
	return "Unknown"

func get_cost_dict() -> Dictionary:
	if not _base_data: return {}
	
	var cost = {}
	if _base_data.has_method("get_cost_dict"):
		cost = _base_data.get_cost_dict().duplicate()
	elif _base_data.get("cost") is Dictionary:
		cost = _base_data.get("cost").duplicate()
	elif _base_data.get("cost") is int:
		cost = {"soul": _base_data.get("cost")}
	
	if _base_data.get("soul_cost") != null:
		var sc = int(_base_data.get("soul_cost"))
		if sc > 0:
			cost["soul"] = sc

	if custom_modifiers.has("cost_mod_all"):
		var add = custom_modifiers["cost_mod_all"]
		for k in cost.keys():
			cost[k] = max(0, cost[k] + add)
			
	for k in cost.keys():
		var mod_key = "cost_mod_" + str(k)
		if custom_modifiers.has(mod_key):
			cost[k] = max(0, cost[k] + custom_modifiers[mod_key])
			
	return cost

func get_card_image() -> Texture2D:
	if not _base_data: return null
	if _base_data.has_method("get_card_image"):
		return _base_data.get_card_image()
	if _base_data.get("icon"):
		return _base_data.get("icon")
	if _base_data.get("texture"):
		return _base_data.get("texture")
	return null

func _get(property: StringName):
	match property:
		"display_name", "card_name":
			return get_display_name()
		"cost":
			return get_cost_dict()
		"soul_cost":
			return get_cost_dict().get("soul", 0)
		"base_data":
			return _base_data
		"targeting":
			return runtime_targeting
		"effects":
			return runtime_effects
		"exclusive_unit_id":
			return runtime_exclusive_unit_id
		"is_move_skill": return runtime_is_move_skill
		"post_move_targeting": return runtime_post_move_targeting
		"post_move_effects": return runtime_post_move_effects
	
	if _base_data:
		return _base_data.get(property)
	return null

func get_base_data() -> Resource:
	return _base_data

func is_skill_card() -> bool:
	return _base_data is SkillCard

func get_skill_card() -> SkillCard:
	if _base_data is SkillCard:
		return _base_data as SkillCard
	return null

func add_modifier(key: String, value) -> void:
	custom_modifiers[key] = value
	emit_changed()

func remove_modifier(key: String) -> void:
	if custom_modifiers.has(key):
		custom_modifiers.erase(key)
		emit_changed()

func clear_modifiers() -> void:
	custom_modifiers.clear()
	emit_changed()

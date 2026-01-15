extends Resource
class_name BaseCardData

@export var card_id: String = ""
@export var card_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var image_path: String = ""
@export var cost: Dictionary = {}

func get_card_icon() -> Texture2D:
	if icon_path != "":
		var t = load(icon_path)
		if t:
			return t as Texture2D
	return null

func get_card_image() -> Texture2D:
	if image_path != "":
		var t = load(image_path)
		if t:
			return t as Texture2D
	return get_card_icon()

func get_cost_dict() -> Dictionary:
	var result: Dictionary = {}
	for key in cost.keys():
		var amount := int(cost[key])
		if amount > 0:
			result[StringName(key)] = amount
	return result

func set_cost_value(resource: StringName, amount: int) -> void:
	var key := StringName(resource)
	if amount <= 0:
		cost.erase(key)
	else:
		cost[key] = int(amount)

func clear_cost() -> void:
	cost.clear()

extends Resource
class_name EquipmentData

enum SlotType { WEAPON, ARMOR, ACCESSORY }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY, RELIC }

@export var item_name: String = "New Item"
@export var slot: SlotType = SlotType.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var item_level: int = 1
@export var icon: Texture2D

@export var traits: Array[Resource] = []

@export var modifiers: Array[ModifierData] = []

const RARITY_CONFIG = {
	Rarity.COMMON: {"color": "white", "text": "普通"},
	Rarity.RARE: {"color": "cyan", "text": "稀有"},
	Rarity.EPIC: {"color": "purple", "text": "史詩"},
	Rarity.LEGENDARY: {"color": "orange", "text": "傳說"},
	Rarity.RELIC: {"color": "red", "text": "神物"}
}

func get_rarity_color() -> String:
	return RARITY_CONFIG.get(rarity, {}).get("color", "white")

func get_equipment_text() -> String:
	var lines = []
	lines.append("[b]%s[/b] (Lv.%d)" % [item_name, item_level])
	
	var config = RARITY_CONFIG.get(rarity, {"color": "white", "text": "未知"})
	lines.append("[color=%s]%s[/color]" % [config["color"], config["text"]])
	lines.append("")
	
	for mod in modifiers:
		lines.append(mod.get_modifier_text())
		
	return "\n".join(lines)

func get_modifiers_text() -> String:
	var lines = []
	for mod in modifiers:
		lines.append(mod.get_modifier_text())
	return "\n".join(lines)

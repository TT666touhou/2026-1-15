extends Resource
class_name EquipmentData

enum SlotType { WEAPON, ARMOR, ACCESSORY }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY, RELIC }

@export var item_name: String = "New Item"
@export var slot: SlotType = SlotType.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var item_level: int = 1
@export var icon: Texture2D

@export var modifiers: Array[ModifierData] = []

func get_equipment_text() -> String:
	var lines = []
	lines.append("[b]%s[/b] (Lv.%d)" % [item_name, item_level])
	
	var rarity_text = ""
	var rarity_color = "white"
	match rarity:
		Rarity.COMMON: 
			rarity_text = "普通"
			rarity_color = "white"
		Rarity.RARE: 
			rarity_text = "稀有"
			rarity_color = "cyan"
		Rarity.EPIC: 
			rarity_text = "史詩"
			rarity_color = "purple"
		Rarity.LEGENDARY: 
			rarity_text = "傳說"
			rarity_color = "orange"
		Rarity.RELIC: 
			rarity_text = "神物"
			rarity_color = "red"
	
	lines.append("[color=%s]%s[/color]" % [rarity_color, rarity_text])
	lines.append("")
	
	for mod in modifiers:
		lines.append(mod.get_modifier_text())
		
	return "\n".join(lines)

func get_modifiers_text() -> String:
	var lines = []
	for mod in modifiers:
		lines.append(mod.get_modifier_text())
	return "\n".join(lines)

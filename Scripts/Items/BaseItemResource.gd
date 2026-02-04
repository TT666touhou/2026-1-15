extends Resource
class_name BaseItemResource

@export var item_names: Array[String] = ["New Item"]
@export var slot: EquipmentData.SlotType = EquipmentData.SlotType.WEAPON
@export var visual_icons: Array[Texture2D] = []
@export var affix_pool: Array[AffixDefinition] = []
@export var tag_pool: Array[Resource] = []
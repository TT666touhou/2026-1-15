extends Node

# EquipmentGenerator (Autoload 建議)

@export var database: Resource # 改用 Resource 避免類型解析錯誤

const RARITY_WEIGHTS = {
	EquipmentData.Rarity.COMMON: 700,
	EquipmentData.Rarity.RARE: 220,
	EquipmentData.Rarity.EPIC: 60,
	EquipmentData.Rarity.LEGENDARY: 19,
	EquipmentData.Rarity.RELIC: 1
}

## 稀有度 -> 標籤數量（上限 3），可集中調整
const RARITY_TAG_COUNT = {
	EquipmentData.Rarity.COMMON: 1,
	EquipmentData.Rarity.RARE: 1,
	EquipmentData.Rarity.EPIC: 2,
	EquipmentData.Rarity.LEGENDARY: 2,
	EquipmentData.Rarity.RELIC: 3
}
const MAX_TAGS_PER_ITEM = 3

# 詞條定義池 (已改為由各 BaseItemResource 獨立提供)
# var affix_pool: Array[AffixDefinition] = []

func _ready() -> void:
	if database == null:
		var default_path = "res://Resources/Equipment/MainEquipmentDatabase.tres"
		if ResourceLoader.exists(default_path):
			database = load(default_path)
	
	# 初始化邏輯已移除，詞條池現在位於各個 BaseItemResource 中

## 依指定槽位生成隨機裝備（武器 0 / 防具 1 / 飾品 2）
func generate_random_item_for_slot(ilvl: int, slot: int) -> EquipmentData:
	var base_item: Resource = null
	if database:
		var pool: Array = []
		match slot:
			0: pool = database.get("weapons") if database.get("weapons") else []
			1: pool = database.get("armors") if database.get("armors") else []
			2: pool = database.get("accessories") if database.get("accessories") else []
			_: pool = []
		if not pool.is_empty():
			base_item = pool.pick_random()
	var item = _generate_from_base(ilvl, base_item)
	if item:
		item.slot = slot
	return item

func generate_random_item(ilvl: int) -> EquipmentData:
	var base_item: Resource = null
	if database:
		var all_bases = []
		all_bases.append_array(database.weapons)
		all_bases.append_array(database.armors)
		all_bases.append_array(database.accessories)
		if not all_bases.is_empty():
			base_item = all_bases.pick_random()
	return _generate_from_base(ilvl, base_item)

func _generate_from_base(ilvl: int, base_item: Resource) -> EquipmentData:
	var item = EquipmentData.new()
	item.item_level = ilvl
	item.rarity = _roll_rarity()
	
	if base_item:
		item.slot = base_item.get("slot")
		item.item_name = base_item.get("item_names").pick_random()
		var icons = base_item.get("visual_icons")
		if icons and not icons.is_empty():
			item.icon = icons.pick_random()
	else:
		item.slot = [EquipmentData.SlotType.WEAPON, EquipmentData.SlotType.ARMOR, EquipmentData.SlotType.ACCESSORY].pick_random()
		match item.slot:
			EquipmentData.SlotType.WEAPON: item.item_name = "劍"
			EquipmentData.SlotType.ARMOR: item.item_name = "甲冑"
			EquipmentData.SlotType.ACCESSORY: item.item_name = "護符"
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://Tilesheet/colored-transparent_packed.png")
		match item.slot:
			EquipmentData.SlotType.WEAPON: atlas.region = Rect2(480, 272, 16, 16)
			EquipmentData.SlotType.ARMOR: atlas.region = Rect2(496, 0, 16, 16)
			EquipmentData.SlotType.ACCESSORY: atlas.region = Rect2(528, 176, 16, 16)
		item.icon = atlas
	
	# 3. 根據稀有度決定詞條數量
	var affix_count = 1
	match item.rarity:
		EquipmentData.Rarity.COMMON: affix_count = randi_range(1, 2)
		EquipmentData.Rarity.RARE: affix_count = 2
		EquipmentData.Rarity.EPIC: affix_count = randi_range(2, 3)
		EquipmentData.Rarity.LEGENDARY: affix_count = randi_range(3, 4)
		EquipmentData.Rarity.RELIC: affix_count = randi_range(4, 6)
	
	# 4. 抽取詞條
	var pool = []
	if base_item and "affix_pool" in base_item:
		pool = base_item.affix_pool
	
	if not pool.is_empty():
		var available_affixes = pool.filter(func(a): return a.min_ilvl <= ilvl)
		if available_affixes.is_empty():
			available_affixes = [pool[0]] # Fallback
		for i in range(affix_count):
			var def = _pick_weighted_affix(available_affixes)
			var mod = ModifierData.new()
			mod.type = def.stat_type
			mod.base_value = def.base_value # 存入基礎值
			var v_min = 0.8
			var v_max = 1.2
			match item.rarity:
				EquipmentData.Rarity.COMMON:    v_min = 0.80; v_max = 1.53
				EquipmentData.Rarity.RARE:      v_min = 1.17; v_max = 1.90
				EquipmentData.Rarity.EPIC:      v_min = 1.53; v_max = 2.27
				EquipmentData.Rarity.LEGENDARY: v_min = 1.90; v_max = 2.63
				EquipmentData.Rarity.RELIC:     v_min = 2.27; v_max = 3.00
			mod.variance = randf_range(v_min, v_max)
			var scaling = 1.0 + (0.2 * float(ilvl))
			mod.value = mod.base_value * scaling * mod.variance
			if not _is_percent_stat(mod.type):
				mod.value = round(mod.value)
			item.modifiers.append(mod)
	
	# 5. 從 tag_pool 抽取不重複標籤（依稀有度數量，上限 3）
	var tag_count = RARITY_TAG_COUNT.get(item.rarity, 0)
	tag_count = mini(tag_count, MAX_TAGS_PER_ITEM)
	var tag_pool_arr: Array = []
	if base_item and "tag_pool" in base_item:
		tag_pool_arr = base_item.tag_pool
	if not tag_pool_arr.is_empty() and tag_count > 0:
		var pool_copy = tag_pool_arr.duplicate()
		pool_copy.shuffle()
		for i in range(mini(tag_count, pool_copy.size())):
			item.traits.append(pool_copy[i])
		
	return item

func _roll_rarity() -> EquipmentData.Rarity:
	var total_weight = 0
	for w in RARITY_WEIGHTS.values():
		total_weight += w
		
	var roll = randi() % total_weight
	var current = 0
	for r in RARITY_WEIGHTS.keys():
		current += RARITY_WEIGHTS[r]
		if roll < current:
			return r
	return EquipmentData.Rarity.COMMON

func _pick_weighted_affix(pool: Array[AffixDefinition]) -> AffixDefinition:
	var total = 0.0
	for a in pool: total += a.weight
	var roll = randf() * total
	var current = 0.0
	for a in pool:
		current += a.weight
		if roll < current:
			return a
	return pool[0]

func _is_percent_stat(type: ModifierData.ModifierType) -> bool:
	return type >= ModifierData.ModifierType.DR_ADDITIVE


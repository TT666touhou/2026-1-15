extends Node

# EquipmentGenerator (Autoload)
# 簡約穩定的裝備生成器：負責生成隨機裝備與測試資料。

@export var database: Resource

const RARITY_WEIGHTS = {
	EquipmentData.Rarity.COMMON: 700,
	EquipmentData.Rarity.RARE: 220,
	EquipmentData.Rarity.EPIC: 60,
	EquipmentData.Rarity.LEGENDARY: 19,
	EquipmentData.Rarity.RELIC: 1
}

const RARITY_TAG_COUNT = {
	EquipmentData.Rarity.COMMON: 1,
	EquipmentData.Rarity.RARE: 1,
	EquipmentData.Rarity.EPIC: 2,
	EquipmentData.Rarity.LEGENDARY: 2,
	EquipmentData.Rarity.RELIC: 3
}

func _ready() -> void:
	if not database:
		var p = "res://Resources/Equipment/MainEquipmentDatabase.tres"
		if ResourceLoader.exists(p):
			database = load(p)

## 為指定槽位或隨機槽位生成裝備
func generate_random_item(ilvl: int = 1, slot: int = -1) -> EquipmentData:
	var base_item: Resource = null
	
	if database:
		var pool := []
		# 獲取基礎池
		var ws = database.get("weapons")
		var ar = database.get("armors")
		var ac = database.get("accessories")
		
		match slot:
			0: pool = ws if ws else []
			1: pool = ar if ar else []
			2: pool = ac if ac else []
			_:
				if ws: pool.append_array(ws)
				if ar: pool.append_array(ar)
				if ac: pool.append_array(ac)
		
		if not pool.is_empty():
			base_item = pool.pick_random()
	
	return _generate_from_base(ilvl, base_item)

## 生成帶有特定標籤的測試裝備
func create_test_item(tag_ids: Array = [], ilvl: int = 1, slot: int = -1) -> EquipmentData:
	var item = generate_random_item(ilvl, slot)
	if not item: return null
	
	if not tag_ids.is_empty():
		item.traits.clear()
		for tid in tag_ids:
			var res = _load_tag_resource(tid)
			if res: item.traits.append(res)
	
	item.item_name = "[Test] " + item.item_name
	return item

## 為全隊穿上測試裝備
func equip_party_test_set(tag_ids: Array) -> void:
	var pm = get_node_or_null("/root/PartyManager")
	if not pm: return
	for m in pm.get_members():
		for s in range(3):
			var item = create_test_item(tag_ids, 10, s)
			if item: m.equip(item)

# --- 內部邏輯 ---

func _generate_from_base(ilvl: int, base: Resource) -> EquipmentData:
	var item = EquipmentData.new()
	item.item_level = ilvl
	item.rarity = _roll_rarity()
	
	if base:
		item.slot = base.get("slot")
		var names = base.get("item_names")
		item.item_name = names.pick_random() if names else "Unknown Item"
		var icons = base.get("visual_icons")
		if icons and not icons.is_empty():
			item.icon = icons.pick_random()
	else:
		# Fallback: 隨機填充基本資訊
		item.slot = randi() % 3
		item.item_name = ["生鏽長劍", "皮甲布衣", "簡陋護符"][item.slot]
	
	_add_affixes(item, base, ilvl)
	_add_tags(item, base)
	return item

func _add_affixes(item: EquipmentData, base: Resource, ilvl: int) -> void:
	var count = 1
	match item.rarity:
		EquipmentData.Rarity.RARE: count = 2
		EquipmentData.Rarity.EPIC: count = randi_range(2, 3)
		EquipmentData.Rarity.LEGENDARY: count = randi_range(3, 4)
		EquipmentData.Rarity.RELIC: count = randi_range(4, 6)
	
	var pool = base.get("affix_pool") if base and "affix_pool" in base else []
	if pool.is_empty(): return
	
	var available = pool.filter(func(a): 
		var val = a.get("min_ilvl")
		return (int(val) if val != null else 0) <= ilvl
	)
	if available.is_empty(): available = [pool[0]]
	
	for i in range(count):
		var def = _pick_weighted(available)
		var mod = ModifierData.new()
		mod.type = def.get("stat_type")
		mod.base_value = def.get("base_value")
		
		# 稀有度加成係數
		var mult = 1.0 + (float(item.rarity) * 0.4)
		var scaling = 1.0 + (float(ilvl) * 0.1)
		mod.value = mod.base_value * scaling * mult * randf_range(0.9, 1.1)
		
		if not mod.is_percentage():
			mod.value = round(mod.value)
		item.modifiers.append(mod)

func _add_tags(item: EquipmentData, base: Resource) -> void:
	if not item.traits.is_empty(): return
	var count = mini(RARITY_TAG_COUNT.get(item.rarity, 0), 3)
	var pool = base.get("tag_pool") if base and "tag_pool" in base else []
	if pool.is_empty() or count <= 0: return
	
	var copy = pool.duplicate()
	copy.shuffle()
	for i in range(mini(count, copy.size())):
		item.traits.append(copy[i])

func _roll_rarity() -> int:
	var total = 0
	for w in RARITY_WEIGHTS.values(): total += w
	var roll = randi() % total
	var curr = 0
	for r in RARITY_WEIGHTS:
		curr += RARITY_WEIGHTS[r]
		if roll < curr: return r
	return 0

func _pick_weighted(pool: Array) -> Resource:
	var total = 0.0
	for a in pool: 
		var w = a.get("weight")
		total += float(w) if w != null else 1.0
	var roll = randf() * total
	var curr = 0.0
	for a in pool:
		var w = a.get("weight")
		curr += float(w) if w != null else 1.0
		if roll < curr: return a
	return pool[0]

func _load_tag_resource(tid: String) -> Resource:
	var paths = [
		"res://Resources/Equipment/Tags/Tag_%s.tres" % tid.capitalize(),
		"res://Resources/Equipment/Tags/Tag_%s.tres" % tid
	]
	for p in paths:
		if ResourceLoader.exists(p): return load(p)
	return null

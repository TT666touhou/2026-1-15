extends Node
class_name SynergyTester

## SynergyTester
## 負責在遊戲初始化時執行邏輯驗證，確保加成與門檻邏輯正確。

static func run_all_tests() -> void:
	print("\n[SynergyTester] === STARTING IN-GAME LOGIC TESTS ===")
	run_crimson_test()
	run_arcane_test()
	run_immortal_test()
	print("[SynergyTester] === ALL TESTS COMPLETED ===\n")

static func run_immortal_test() -> void:
	print("[SynergyTester] Running Immortal Logic Test...")
	
	var ImmortalEffect = load("res://Scripts/Entities/ImmortalEffect.gd").new()
	var card = UnitCard.new()
	card.max_health = 200.0
	var data = CharacterData.create(card)
	
	# 測試一：Level 1 (20% 減傷)
	ImmortalEffect.apply_effect(data, 1, 1)
	if abs(data.get_effective_dr() - 0.2) < 0.001:
		print("[PASS] Immortal Lvl 1: DR is 0.2")
	else:
		print("[FAIL] Immortal Lvl 1: Expected 0.2, got %.2f" % data.get_effective_dr())
		
	# 測試二：Level 3 (60% 減傷 + 進場護盾)
	data.recalculate_stats() # 重置
	ImmortalEffect.apply_effect(data, 7, 3)
	if abs(data.get_effective_dr() - 0.6) < 0.001:
		print("[PASS] Immortal Lvl 3: DR is 0.6")
	else:
		print("[FAIL] Immortal Lvl 3: Expected 0.6, got %.2f" % data.get_effective_dr())
		
	# 模擬進場
	ImmortalEffect.on_room_start(data, 3)
	if data.shield == 100: # 200 * 0.5
		print("[PASS] Immortal Lvl 3: Room Entry Shield is 100")
	else:
		print("[FAIL] Immortal Lvl 3: Shield Mismatch, got %d" % data.shield)

static func run_arcane_test() -> void:
	print("[SynergyTester] Running Arcane Logic Test...")
	
	var ArcaneEffect = load("res://Scripts/Entities/ArcaneEffect.gd").new()
	var card = UnitCard.new()
	var data = CharacterData.create(card)
	
	# 測試一：Level 1 (+30%)
	ArcaneEffect.apply_effect(data, 1, 1)
	if abs(data.stat_modifiers.skill_damage_multiplier - 1.3) < 0.001:
		print("[PASS] Arcane Lvl 1: Mult is 1.3")
	else:
		print("[FAIL] Arcane Lvl 1: Expected 1.3, got %.2f" % data.stat_modifiers.skill_damage_multiplier)
		
	# 測試二：Level 4 (+300%)
	data.stat_modifiers.skill_damage_multiplier = 1.0 # 重置
	ArcaneEffect.apply_effect(data, 7, 4)
	if abs(data.stat_modifiers.skill_damage_multiplier - 4.0) < 0.001:
		print("[PASS] Arcane Lvl 4: Mult is 4.0")
	else:
		print("[FAIL] Arcane Lvl 4: Expected 4.0, got %.2f" % data.stat_modifiers.skill_damage_multiplier)

static func run_crimson_test() -> void:
	print("[SynergyTester] Running Crimson Logic Test...")
	
	# 準備模擬數據
	var CrimsonEffect = load("res://Scripts/Entities/CrimsonEffect.gd").new()
	var card = UnitCard.new()
	card.max_health = 100.0
	card.attack_damage = 20
	
	var data = CharacterData.create(card)
	
	# 測試一：Level 1 (門檻 60)
	CrimsonEffect.apply_effect(data, 1, 1)
	if data.crimson_threshold == 60:
		print("[PASS] Crimson Lvl 1: Threshold is 60")
	else:
		print("[FAIL] Crimson Lvl 1: Expected 60, got %d" % data.crimson_threshold)
		
	# 測試二：Level 3 (數值爆發)
	data.recalculate_stats() # 重置
	CrimsonEffect.apply_effect(data, 9, 3)
	if data.get_effective_attack() == 100: # 20 * 5
		print("[PASS] Crimson Lvl 3: ATK Boosted x5 (20 -> 100)")
	else:
		print("[FAIL] Crimson Lvl 3: ATK Mismatch, got %d" % data.get_effective_attack())
		
	if data.get_effective_max_health() == 1000: # 100 * 10
		print("[PASS] Crimson Lvl 3: HP Boosted x10 (100 -> 1000)")
	else:
		print("[FAIL] Crimson Lvl 3: HP Mismatch, got %d" % data.get_effective_max_health())

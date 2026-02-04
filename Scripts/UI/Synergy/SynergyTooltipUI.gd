extends PanelContainer
class_name SynergyTooltipUI

## 特質說明 Tooltip：列出所有里程碑效果，已啟用者高亮顯示

@onready var name_label: Label = %NameLabel
@onready var effects_list: VBoxContainer = %EffectsList

const COLOR_ACTIVE := Color(1.0, 1.0, 1.0)
const COLOR_INACTIVE := Color(0.298, 0.329, 0.427)

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

## 使用 SynergyManager 的 trait_id 與當前數量顯示
func setup_by_trait_id(trait_id: String) -> void:
	print("[SynergyTooltipUI] setup_by_trait_id trait_id=%s" % trait_id)
	if not SynergyManager:
		print("[SynergyTooltipUI] SKIP: SynergyManager is null")
		return
	var info = SynergyManager.get_trait_full_info(trait_id)
	if info.is_empty():
		print("[SynergyTooltipUI] SKIP: get_trait_full_info returned empty (trait not registered?)")
	else:
		print("[SynergyTooltipUI] Showing tooltip for %s level=%d" % [info.get("trait_name", ""), info.get("current_level", 0)])
	setup(info)

## 直接傳入 get_trait_full_info 的 Dictionary
func setup(info: Dictionary) -> void:
	if info.is_empty():
		visible = false
		return

	for child in effects_list.get_children():
		child.queue_free()

	name_label.text = info.get("trait_name", "")
	var thresholds: Array = info.get("thresholds", [])
	var descriptions: Array = info.get("effect_descriptions", [])
	var current_level: int = info.get("current_level", 0)

	for i in range(descriptions.size()):
		var thresh = thresholds[i] if i < thresholds.size() else 0
		var tier_name = _tier_name(i + 1)
		var line = str(thresh) + " 階級 " + tier_name + "：" + str(descriptions[i])
		var label = Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 11)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 250
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if current_level >= i + 1:
			label.modulate = COLOR_ACTIVE
		else:
			label.modulate = COLOR_INACTIVE
		effects_list.add_child(label)

	# 高度隨內容自適應
	custom_minimum_size = Vector2(280, 0)
	visible = true

func _tier_name(tier: int) -> String:
	match tier:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
		_: return str(tier)

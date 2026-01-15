extends Panel
class_name InspectPanel

## 檢查面板
## 顯示選中對象的信息（英文粗體大字）

@export var title_label_path: NodePath = NodePath("VBox/TitleLabel")
@export var content_label_path: NodePath = NodePath("VBox/ContentLabel")

var _title_label: Label
var _content_label: Label

func _ready() -> void:
	_title_label = get_node_or_null(title_label_path)
	_content_label = get_node_or_null(content_label_path)
	
	if _title_label != null:
		_title_label.add_theme_font_size_override("font_size", 24)
		_title_label.add_theme_color_override("font_color", Color.WHITE)
		_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_title_label.add_theme_constant_override("outline_size", 2)
	
	if _content_label != null:
		_content_label.add_theme_font_size_override("font_size", 18)
		_content_label.add_theme_color_override("font_color", Color.WHITE)
		_content_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_content_label.add_theme_constant_override("outline_size", 1)
	
	visible = false

func display_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		hide_panel()
		return
	
	visible = true
	
	var title_text := "SELECTED"
	var content_text := ""
	
	# 根據 payload 類型構建顯示內容
	if payload.has("type"):
		match payload.type:
			"entity":
				title_text = "ENTITY"
				content_text = _format_entity_payload(payload)
			"resource_tile":
				title_text = "RESOURCE"
				content_text = _format_resource_tile_payload(payload)
			"ground_tile":
				title_text = "TILE"
				content_text = _format_ground_tile_payload(payload)
			"multi_selection":
				title_text = "SELECTED"
				content_text = payload.get("content", "")
			_:
				title_text = "UNKNOWN"
				content_text = _format_generic_payload(payload)
	else:
		content_text = _format_generic_payload(payload)
	
	if _title_label != null:
		_title_label.text = title_text
	
	if _content_label != null:
		_content_label.text = content_text

func _format_entity_payload(payload: Dictionary) -> String:
	var lines: Array[String] = []
	
	if payload.has("entity_name"):
		lines.append("NAME: " + str(payload.entity_name))
	
	if payload.has("cell"):
		var cell = payload.cell
		lines.append("CELL: (" + str(cell.x) + ", " + str(cell.y) + ")")
	
	if payload.has("position"):
		var pos = payload.position
		lines.append("POS: (" + str(int(pos.x)) + ", " + str(int(pos.y)) + ")")
	
	# 顯示狀態信息
	if payload.has("info"):
		var info = payload.info
		if info is Dictionary:
			if info.has("health") and info.has("max_health"):
				lines.append("HP: " + str(info.health) + "/" + str(info.max_health))
			if info.has("hunger") and info.has("max_hunger"):
				lines.append("HUNGER: " + str(int(info.hunger)) + "/" + str(info.max_hunger))
			# 顯示其他信息
			for key in info:
				if key != "health" and key != "max_health" and key != "hunger" and key != "max_hunger" and key != "health_percent" and key != "hunger_percent":
					lines.append(str(key).to_upper() + ": " + str(info[key]))
	
	return "\n".join(lines)

func _format_resource_tile_payload(payload: Dictionary) -> String:
	var lines: Array[String] = []
	
	if payload.has("cell"):
		var cell = payload.cell
		lines.append("CELL: (" + str(cell.x) + ", " + str(cell.y) + ")")
	
	if payload.has("tile_type"):
		lines.append("TYPE: " + str(payload.tile_type).to_upper())
	
	if payload.has("current_amount"):
		lines.append("AMOUNT: " + str(payload.current_amount))
	elif payload.has("base_amount"):
		lines.append("BASE: " + str(payload.base_amount))
	
	if payload.has("resource_type"):
		lines.append("RESOURCE: " + str(payload.resource_type).to_upper())
	
	return "\n".join(lines)

func _format_ground_tile_payload(payload: Dictionary) -> String:
	var lines: Array[String] = []
	
	if payload.has("cell"):
		var cell = payload.cell
		lines.append("CELL: (" + str(cell.x) + ", " + str(cell.y) + ")")
	
	if payload.has("world_pos"):
		var pos = payload.world_pos
		lines.append("POS: (" + str(int(pos.x)) + ", " + str(int(pos.y)) + ")")
	
	return "\n".join(lines)

func _format_generic_payload(payload: Dictionary) -> String:
	var lines: Array[String] = []
	
	for key in payload:
		if key == "type" or key == "entity" or key == "cell":
			continue
		lines.append(str(key).to_upper() + ": " + str(payload[key]))
	
	return "\n".join(lines)

func hide_panel() -> void:
	visible = false

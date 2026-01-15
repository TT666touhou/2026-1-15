extends HBoxContainer

@export var ledger_path: NodePath = NodePath("") # 留空以使用自動搜尋
@export var font_theme: Font = null

# 資源圖示設定 - 使用 AtlasTexture 讓用戶可以在 Inspector 直接選取區域
@export var texture_soul: AtlasTexture
@export var texture_gold: AtlasTexture

var _ledger: Node = null
var _entries: Dictionary = {} # resource_name -> HBoxContainer
var _blink_tweens: Dictionary = {} # resource_name -> Tween (for blinking)
var _jump_tweens: Dictionary = {} # resource_name -> Tween (for jump/pop)

func _ready() -> void:
	# Layout settings
	size_flags_horizontal = SIZE_SHRINK_BEGIN
	size_flags_vertical = SIZE_SHRINK_CENTER
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 24)
	
	# Setup defaults if not assigned in Inspector
	_setup_defaults()
	
	_connect_ledger()
	_update_all()

func _setup_defaults() -> void:
	var default_atlas = load("res://Tilesheet/colored-transparent_packed.png")
	
	if texture_soul == null:
		texture_soul = AtlasTexture.new()
		texture_soul.atlas = default_atlas
		texture_soul.region = Rect2(432, 0, 16, 16) # Ghost
		
	if texture_gold == null:
		texture_gold = AtlasTexture.new()
		texture_gold.atlas = default_atlas
		texture_gold.region = Rect2(688, 112, 16, 16) # Coins

func _connect_ledger() -> void:
	# 直接使用 Autoload 路徑，簡單可靠
	_ledger = get_node_or_null("/root/PlayerResourceLedger")
		
	if _ledger == null:
		push_warning("ResourceHUD: PlayerResourceLedger not found; HUD disabled.")
		set_process(false)
		return
		
	# 斷開舊連接以防重複
	if _ledger.ledger_reset.is_connected(_on_ledger_reset):
		_ledger.ledger_reset.disconnect(_on_ledger_reset)
	if _ledger.resource_changed.is_connected(_on_resource_changed):
		_ledger.resource_changed.disconnect(_on_resource_changed)
		
	_ledger.ledger_reset.connect(_on_ledger_reset)
	_ledger.resource_changed.connect(_on_resource_changed)

func _update_all() -> void:
	if _ledger == null:
		return
	var data: Dictionary = _ledger.call("get_all")
	for resource in data.keys():
		_update_entry(resource, int(data[resource]))

func _update_entry(resource: String, value: int) -> void:
	var entry := _get_or_create_entry(resource)
	
	# Update Text
	var label := entry.get_node("ValueContainer/TextMargin/Label") as Label
	label.text = str(value)
	
	# Check Limits & Tooltip
	var limit: int = 999999
	var caps = _ledger.get("capacity_limits")
	if caps is Dictionary:
		limit = int(caps.get(resource, 999999))
	
	var is_capped := (value >= limit)
	
	# Tooltip logic
	if limit < 99999: # 假設大於此數為無上限
		entry.tooltip_text = "%s: %d / %d" % [resource.capitalize(), value, limit]
	else:
		entry.tooltip_text = "%s: %d" % [resource.capitalize(), value]
	
	# Handle Capped Effect (Soul only, or generic if desired)
	if resource == "soul":
		_set_blinking_state(resource, entry.get_node("ValueContainer/Border"), is_capped)

func _get_or_create_entry(resource: String) -> HBoxContainer:
	if _entries.has(resource):
		return _entries[resource]
	
	# Create Main Container
	var entry = HBoxContainer.new()
	entry.name = "%sEntry" % resource.capitalize()
	entry.alignment = BoxContainer.ALIGNMENT_CENTER
	entry.add_theme_constant_override("separation", 4)
	entry.tooltip_text = resource.capitalize()
	entry.mouse_filter = Control.MOUSE_FILTER_PASS # Allow tooltip
	
	# 1. Icon
	var icon_rect = TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = Vector2(24, 24)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var tex: Texture2D = null
	if resource == "soul":
		tex = texture_soul
	elif resource == "gold":
		tex = texture_gold
	
	icon_rect.texture = tex
	entry.add_child(icon_rect)
	
	# 2. Value Container (Holds Label + Border)
	var val_container = MarginContainer.new()
	val_container.name = "ValueContainer"
	
	# Border (ReferenceRect or Panel for blinking)
	# 使用 ReferenceRect 做外框比較輕量，或者用 PanelContainer 
	var border = ReferenceRect.new()
	border.name = "Border"
	border.border_color = Color.WHITE
	border.border_width = 2.0
	border.editor_only = false
	border.visible = false # Default hidden
	val_container.add_child(border)
	
	# Label
	var label = Label.new()
	label.name = "Label"
	label.text = "0"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font_theme != null:
		label.add_theme_font_override("font", font_theme)
	label.add_theme_font_size_override("font_size", 20)
	
	# Add some margin for the text so border doesn't overlap tightly
	var text_margin = MarginContainer.new()
	text_margin.name = "TextMargin"
	text_margin.add_theme_constant_override("margin_left", 4)
	text_margin.add_theme_constant_override("margin_right", 4)
	text_margin.add_child(label)
	
	val_container.add_child(text_margin)
	entry.add_child(val_container)
	
	add_child(entry)
	_entries[resource] = entry
	return entry

func _set_blinking_state(resource: String, border_node: Control, is_blinking: bool) -> void:
	# Check if state changed to avoid restarting tween unnecessarily
	var current_tween = _blink_tweens.get(resource)
	var is_running = (current_tween != null and current_tween.is_running())
	
	if is_blinking:
		if not border_node.visible:
			border_node.visible = true
			
		if not is_running:
			var tw = create_tween().set_loops()
			tw.tween_property(border_node, "modulate:a", 0.2, 0.5).set_trans(Tween.TRANS_SINE)
			tw.tween_property(border_node, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
			_blink_tweens[resource] = tw
	else:
		border_node.visible = false
		border_node.modulate.a = 1.0
		if current_tween:
			current_tween.kill()
			_blink_tweens.erase(resource)

func _animate_resource_gain(resource: String) -> void:
	if not _entries.has(resource): return
	
	var entry = _entries[resource]
	var icon = entry.get_node("Icon")
	var val_container = entry.get_node("ValueContainer")
	
	# Ensure pivots are centered for scaling (Requires size to be non-zero)
	# If size is (0,0), pivot_offset won't work well, but layout usually updates quickly.
	# We set pivot relative to current size
	icon.pivot_offset = icon.size / 2.0
	val_container.pivot_offset = val_container.size / 2.0
	
	# Kill existing jump tween for this resource if any
	if _jump_tweens.has(resource) and _jump_tweens[resource]:
		_jump_tweens[resource].kill()
	
	var tw = create_tween().set_parallel(true)
	_jump_tweens[resource] = tw
	
	# Pop animation: Scale UP -> Scale Normal
	var pop_scale = Vector2(1.5, 1.5)
	
	# Step 1: Pop Up
	tw.tween_property(icon, "scale", pop_scale, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(val_container, "scale", pop_scale, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Step 2: Return to Normal (Chained)
	tw.chain().tween_property(icon, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(val_container, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _format_label(_resource: String, value: int) -> String:
	return str(value)

func _on_ledger_reset(current: Dictionary) -> void:
	# Clear old entries to ensure clean slate (optional, but safer for drastic changes)
	for child in get_children():
		child.queue_free()
	_entries.clear()
	_blink_tweens.clear() # Clear tweens
	_jump_tweens.clear()
	
	for key in current.keys():
		_update_entry(key, int(current[key]))

func _on_resource_changed(resource: String, new_value: int, delta: int) -> void:
	_update_entry(resource, new_value)
	if delta > 0:
		_animate_resource_gain(resource)

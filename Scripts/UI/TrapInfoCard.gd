extends PanelContainer

@onready var icon_rect: TextureRect = $MarginContainer/HBox/Icon
@onready var name_label: Label = $MarginContainer/HBox/InfoBox/NameLabel
@onready var atk_label: Label = $MarginContainer/HBox/InfoBox/StatsGrid/AtkLabel

var _trap_entity: TrapEntity = null

func _ready() -> void:
	# 列表項目默認顯示，但由 HoverInfoController 控制
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

func update_info(entity: GridEntity) -> void:
	# 兼容 GridEntity 但預期是 TrapEntity
	if not entity is TrapEntity:
		print("[TrapInfoCard] Entity is NOT a TrapEntity: ", entity.name if entity else "null")
		visible = false
		return
		
	_trap_entity = entity as TrapEntity
	# print("[TrapInfoCard] Updating info for: ", _trap_entity.name, " ATK: ", _trap_entity.trap_atk)
	visible = true
	
	# 1. 更新頭像
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite and sprite is Sprite2D:
		var atlas_tex = AtlasTexture.new()
		atlas_tex.atlas = sprite.texture
		
		if sprite.hframes > 1 or sprite.vframes > 1:
			var w = sprite.texture.get_width() / sprite.hframes
			var h = sprite.texture.get_height() / sprite.vframes
			atlas_tex.region = Rect2(0, 0, w, h)
		else:
			atlas_tex.region = Rect2(0, 0, sprite.texture.get_width(), sprite.texture.get_height())
			
		icon_rect.texture = atlas_tex
	
	# 2. 更新名稱與 ATK
	if _trap_entity.trap_resource:
		var res = _trap_entity.trap_resource
		name_label.text = res.display_name if (res.has_method("get") and res.get("display_name")) else res.card_name
	else:
		name_label.text = "陷阱"
		
	atk_label.text = "ATK: %d" % _trap_entity.trap_atk

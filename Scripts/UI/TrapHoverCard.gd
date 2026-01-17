extends PanelContainer

@onready var icon_rect: TextureRect = $HBox/Icon
@onready var name_label: Label = $HBox/VBox/NameLabel
@onready var atk_label: Label = $HBox/VBox/AtkLabel

var _trap_entity: TrapEntity = null

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)

func update_info(entity: TrapEntity) -> void:
	_trap_entity = entity
	
	if not entity:
		visible = false
		return
		
	visible = true
	
	# 1. 更新頭像 (裁切 spikes.png 第一幀)
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
	if entity.trap_resource:
		name_label.text = entity.trap_resource.display_name if entity.trap_resource.display_name else entity.trap_resource.card_name
	else:
		name_label.text = "陷阱"
		
	atk_label.text = "ATK: %d" % entity.trap_atk

func _on_mouse_entered() -> void:
	if is_instance_valid(_trap_entity) and _trap_entity.has_method("play_preview_animation"):
		_trap_entity.play_preview_animation()

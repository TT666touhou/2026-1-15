extends Resource
class_name MovementArrowSettings

@export_group("圖示設定")
@export var arrow_texture: Texture2D = preload("res://Tilesheet/kenney_cursor-pack/PNG/Outline/Default/arrow_n.png"):
	set(v):
		arrow_texture = v
		emit_changed()
@export var arrow_scale: float = 0.098:
	set(v):
		arrow_scale = v
		emit_changed()
@export var arrow_color: Color = Color.CYAN:
	set(v):
		arrow_color = v
		emit_changed()

@export_group("位置設定")
@export var inset_distance: float = 1.5:
	set(v):
		inset_distance = v
		emit_changed()
@export var diagonal_factor: float = 0.95:
	set(v):
		diagonal_factor = v
		emit_changed()

@export_group("雙箭頭效果 (無限移動)")
@export var double_arrow_offset: float = 0.3:
	set(v):
		double_arrow_offset = v
		emit_changed()
@export var double_arrow_alpha: float = 1.0:
	set(v):
		double_arrow_alpha = v
		emit_changed()

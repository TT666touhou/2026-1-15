extends Node
class_name GridSelector

## 極簡化選取器：只負責點擊選中，不參與任何移動或拖拽

signal entity_selected(entity: GridEntity)
signal selection_cleared()

@export var selection_layer_path: NodePath
@export var enable_debug_log: bool = false

var grid: Node
var selected_entity: GridEntity = null
var selection_highlight: Node2D = null

func _ready() -> void:
	grid = get_tree().get_first_node_in_group("grid")
	if selection_layer_path != NodePath():
		selection_highlight = get_node_or_null(selection_layer_path)
	add_to_group("grid_selector")

func _unhandled_input(event: InputEvent) -> void:
	# 只處理單純的點擊選取
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_selection()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			clear_selection()

func _handle_selection() -> void:
	var camera = get_viewport().get_camera_2d()
	if camera == null or grid == null: return
	
	var world_pos = camera.get_global_mouse_position()
	var cell = grid.world_to_grid(world_pos)
	var entity = grid.get_occupant(cell)
	
	if entity is GridEntity:
		select_entity(entity)
	else:
		clear_selection()

func select_entity(entity: GridEntity) -> void:
	if selected_entity: selected_entity.on_deselected()
	selected_entity = entity
	selected_entity.on_selected()
	_update_highlight()
	entity_selected.emit(entity)

func clear_selection() -> void:
	if selected_entity:
		selected_entity.on_deselected()
		selected_entity = null
	_update_highlight()
	selection_cleared.emit()

func _update_highlight() -> void:
	if selection_highlight and selected_entity:
		selection_highlight.global_position = grid.grid_to_world_center(selected_entity.grid_position)
		selection_highlight.visible = true
	elif selection_highlight:
		selection_highlight.visible = false

extends Node2D
class_name SkillPreviewController

@export var preview_color: Color = Color(1, 0.6, 0.2, 0.4) # 橘色預覽
@export var border_color: Color = Color(1, 0.6, 0.2, 0.8)

var affected_cells: Array[Vector2i] = []
var grid: Node = null

func _ready() -> void:
	add_to_group("skill_preview_controller")
	grid = get_tree().get_first_node_in_group("grid")
	z_index = 50 

## 根據技能與目標點更新預覽
func update_preview(unit: GridEntity, skill: Resource, target_cell: Vector2i) -> void:
	affected_cells.clear()
	if not skill:
		queue_redraw()
		return
		
	var targeting = skill.get("targeting")
	var post_targeting = skill.get("post_move_targeting")
	var targeting_type = skill.get("targeting_type")
	
	# 核心規則：預覽必須與執行引擎同步，強制使用 post_move_targeting 作為效果預覽
	var effective_target = post_targeting if post_targeting != null else targeting
	
	# 決定「效果中心點」
	var origin = target_cell
	
	if targeting_type == UnitSkillData.TargetingType.ABSOLUTE:
		origin = SkillManager._get_grid_center()
	else:
		# RELATIVE 模式
		if skill.get("execution_mode") == UnitSkillData.ExecutionMode.DIRECT:
			origin = unit.grid_position if unit else target_cell
		else:
			origin = target_cell # MOVE_TRIGGER 類使用移動落點
			
	affected_cells = SkillManager.get_cells_in_scope(effective_target, origin)
	queue_redraw()

func clear_preview() -> void:
	affected_cells.clear()
	queue_redraw()

func _draw() -> void:
	if affected_cells.is_empty() or not grid or not grid.has_method("grid_to_world"):
		return
		
	var cs = Vector2(16, 16)
	if "cell_size" in grid:
		cs = Vector2(grid.cell_size)
		
	for cell in affected_cells:
		var world_pos = grid.grid_to_world(cell)
		var local_pos = to_local(world_pos)
		draw_rect(Rect2(local_pos, cs), preview_color, true)
		draw_rect(Rect2(local_pos, cs), border_color, false, 1.0)

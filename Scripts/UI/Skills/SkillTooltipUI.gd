extends PanelContainer
class_name SkillTooltipUI

@onready var name_label: Label = %NameLabel
@onready var desc_label: RichTextLabel = %DescLabel
@onready var targeting_type_label: Label = %TargetingTypeLabel
@onready var execution_mode_label: Label = %ExecutionModeLabel
@onready var range_grid: GridContainer = %RangeGrid
@onready var effect_grid: GridContainer = %EffectGrid
@onready var selection_container: Control = %SelectionContainer
@onready var effect_container: Control = %EffectContainer

func setup(skill: Resource) -> void:
	name_label.text = skill.skill_name
	
	# 使用動態生成描述，支援 BBCode 標籤 (顏色、粗體)
	desc_label.text = skill.get_dynamic_description()
	
	# 更新標籤 (中文)
	if targeting_type_label:
		targeting_type_label.visible = false
	
	if execution_mode_label:
		execution_mode_label.visible = false
	
	_update_range_display(skill)

func _update_range_display(skill: Resource) -> void:
	# 核心修正：只有當標註為「移動技能」(is_move_skill) 且有後續效果時，才顯示兩段式 (目前僅限影襲)
	var is_two_stage = skill.is_move_skill and skill.post_move_targeting != null
	var selection_label = selection_container.get_node("Label")
	
	# 尋找移動效果方向
	var move_dir = Vector2i.ZERO
	for effect in skill.effects:
		if effect.effect_type == EffectDefinition.EffectType.MOVE:
			move_dir = effect.move_direction
			break
	
	if is_two_stage:
		# 兩段式顯示：中心點(黃色) + 橘色效果
		selection_container.visible = true
		effect_container.visible = true
		selection_label.text = "Selection"
		render_skill_grid(range_grid, skill.targeting, Color(1, 0.9, 0.2), true, Vector2(12, 12), move_dir) # 僅中心點 + 箭頭
		render_skill_grid(effect_grid, skill.post_move_targeting, Color(1.0, 0.4, 0.1), false, Vector2(12, 12)) # 橘色：效果範圍
	else:
		# 單段式顯示
		selection_container.visible = true
		effect_container.visible = false
		
		# 核心修正：強制展示 post_move_targeting 作為效果範圍
		var target_to_show = skill.post_move_targeting if skill.post_move_targeting != null else skill.targeting
		
		# 根據模式決定標題與顏色
		if skill.execution_mode == UnitSkillData.ExecutionMode.MOVEMENT:
			selection_label.text = "Selection"
			# 純移動：僅顯示黃色選取中心點
			render_skill_grid(range_grid, target_to_show, Color(1, 0.9, 0.2), true, Vector2(12, 12), move_dir)
		else:
			selection_label.text = "Effect"
			# 一般/大範圍技能 (如末日、虛空)：顯示完整橘色形狀
			render_skill_grid(range_grid, target_to_show, Color(1.0, 0.4, 0.1), false, Vector2(12, 12), move_dir)

## 靜態工具函數：供所有 UI 組件共用渲染邏輯
static func render_skill_grid(grid: GridContainer, targeting: Resource, active_color: Color, force_dot_only: bool = false, cell_size: Vector2 = Vector2(12, 12), move_dir: Vector2i = Vector2i.ZERO, p_line_width: float = 4.0) -> void:
	# 清除舊內容
	for child in grid.get_children():
		child.free()
	
	if not targeting and move_dir == Vector2i.ZERO:
		return
		
	# 強制設定列數為 1，因為我們現在使用單一向量繪製節點
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	
	var radius = 0
	if targeting:
		radius = targeting.aoe_radius
		if radius == null: radius = 0
	
	var cells_in_scope: Array[Vector2i] = []
	var center = Vector2i.ZERO
	
	if targeting:
		pass # print("[SkillPreview] Rendering grid...")
	
	if force_dot_only:
		cells_in_scope.append(center)
	elif targeting:
		# 使用 Enum 名稱進行判斷，避免硬編碼索引錯誤
		match targeting.scope_type:
			TargetingDefinition.ScopeType.SINGLE:
				cells_in_scope.append(center)
			TargetingDefinition.ScopeType.AREA_CIRCLE:
				for x in range(-radius, radius + 1):
					for y in range(-radius, radius + 1):
						if abs(x) + abs(y) <= radius:
							cells_in_scope.append(center + Vector2i(x, y))
			TargetingDefinition.ScopeType.AREA_SQUARE:
				for x in range(-radius, radius + 1):
					for y in range(-radius, radius + 1):
						cells_in_scope.append(center + Vector2i(x, y))
			TargetingDefinition.ScopeType.AREA_CROSS:
				cells_in_scope.append(center)
				for i in range(1, radius + 1):
					cells_in_scope.append(center + Vector2i(i, 0))
					cells_in_scope.append(center + Vector2i(-i, 0))
					cells_in_scope.append(center + Vector2i(0, i))
					cells_in_scope.append(center + Vector2i(0, -i))
			TargetingDefinition.ScopeType.GLOBAL:
				for x in range(-3, 4):
					for y in range(-3, 4):
						cells_in_scope.append(Vector2i(x, y))
			TargetingDefinition.ScopeType.GLOBAL_CHECKER_A:
				for x in range(-3, 4):
					for y in range(-3, 4):
						if abs(x + y) % 2 == 0:
							cells_in_scope.append(Vector2i(x, y))
			TargetingDefinition.ScopeType.GLOBAL_CHECKER_B:
				for x in range(-3, 4):
					for y in range(-3, 4):
						if abs(x + y) % 2 != 0:
							cells_in_scope.append(Vector2i(x, y))
			TargetingDefinition.ScopeType.AREA_PATTERN:
				var pattern_data = targeting.get("pattern_7x7")
				if pattern_data and pattern_data.size() == 49:
					for p_idx in range(49):
						if pattern_data[p_idx]:
							var dx = (p_idx % 7) - 3
							var dy = floori(float(p_idx) / 7.0) - 3
							cells_in_scope.append(center + Vector2i(dx, dy))
			TargetingDefinition.ScopeType.AREA_X:
				cells_in_scope.append(center)
				for i in range(1, radius + 1):
					cells_in_scope.append(center + Vector2i(i, i))
					cells_in_scope.append(center + Vector2i(-i, -i))
					cells_in_scope.append(center + Vector2i(i, -i))
					cells_in_scope.append(center + Vector2i(-i, i))
			TargetingDefinition.ScopeType.AREA_QUEEN:
				cells_in_scope.append(center)
				for i in range(1, radius + 1):
					cells_in_scope.append(center + Vector2i(i, 0))
					cells_in_scope.append(center + Vector2i(-i, 0))
					cells_in_scope.append(center + Vector2i(0, i))
					cells_in_scope.append(center + Vector2i(0, -i))
					cells_in_scope.append(center + Vector2i(i, i))
					cells_in_scope.append(center + Vector2i(-i, -i))
					cells_in_scope.append(center + Vector2i(i, -i))
					cells_in_scope.append(center + Vector2i(-i, i))
	
	# 建立向量繪製器
	var drawer_script = load("res://Scripts/UI/Skills/SkillRangeGridDrawer.gd")
	var drawer = Control.new()
	drawer.set_script(drawer_script)
	grid.add_child(drawer)
	
	# 設置數據
	drawer.setup(cells_in_scope, active_color, move_dir, cell_size, p_line_width)

func show_at(pos: Vector2) -> void:
	if pos != Vector2.ZERO:
		global_position = pos
	
	visible = true
	modulate.a = 0.0
	var tw = create_tween()
	if tw:
		tw.tween_property(self, "modulate:a", 1.0, 0.2)

func hide_tooltip() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.finished.connect(func(): visible = false)

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

func setup(skill: UnitSkillData) -> void:
	name_label.text = skill.skill_name
	
	# 使用動態生成描述，支援 BBCode 標籤 (顏色、粗體)
	desc_label.text = skill.get_dynamic_description()
	
	# 更新標籤 (中文)
	var target_type_str = "相對位置 (以單位為中心)" if skill.targeting_type == UnitSkillData.TargetingType.RELATIVE else "絕對位置 (地圖固定位置)"
	targeting_type_label.text = "瞄準：" + target_type_str
	
	var mode_str = "立刻發動"
	match skill.execution_mode:
		UnitSkillData.ExecutionMode.DIRECT: mode_str = "立刻發動"
		UnitSkillData.ExecutionMode.MOVE_TRIGGER: mode_str = "移動後自動觸發"
		UnitSkillData.ExecutionMode.MOVEMENT: mode_str = "移動技能 (不結束回合)"
	execution_mode_label.text = "模式：" + mode_str
	
	_update_range_display(skill)

func _update_range_display(skill: UnitSkillData) -> void:
	# 核心修正：只有當標註為「移動技能」(is_move_skill) 且有後續效果時，才顯示兩段式 (目前僅限影襲)
	var is_two_stage = skill.is_move_skill and skill.post_move_targeting != null
	var selection_label = selection_container.get_node("Label")
	
	if is_two_stage:
		# 兩段式顯示：中心點(黃色) + 橘色效果
		selection_container.visible = true
		effect_container.visible = true
		selection_label.text = "Selection"
		render_skill_grid(range_grid, skill.targeting, Color(1, 0.9, 0.2), true) # 僅中心點
		render_skill_grid(effect_grid, skill.post_move_targeting, Color(1.0, 0.4, 0.1)) # 橘色：效果範圍
	else:
		# 單段式顯示
		selection_container.visible = true
		effect_container.visible = false
		
		# 核心修正：強制展示 post_move_targeting 作為效果範圍
		var target_to_show = skill.post_move_targeting if skill.post_move_targeting else skill.targeting
		
		# 根據模式決定標題與顏色
		if skill.execution_mode == UnitSkillData.ExecutionMode.MOVEMENT:
			selection_label.text = "Selection"
			# 純移動：僅顯示黃色選取中心點
			render_skill_grid(range_grid, target_to_show, Color(1, 0.9, 0.2), true)
		else:
			selection_label.text = "Effect"
			# 一般/大範圍技能 (如末日、虛空)：顯示完整橘色形狀
			render_skill_grid(range_grid, target_to_show, Color(1.0, 0.4, 0.1), false)

## 靜態工具函數：供所有 UI 組件共用渲染邏輯
static func render_skill_grid(grid: GridContainer, targeting: TargetingDefinition, active_color: Color, force_dot_only: bool = false, cell_size: Vector2 = Vector2(12, 12)) -> void:
	# 清除舊內容
	for child in grid.get_children():
		child.free()
	
	if not targeting:
		return
		
	# 強制設定列數為 7，確保預覽正確
	grid.columns = 7
	
	var radius = targeting.aoe_radius
	if radius == null: radius = 0
	var cells_in_scope: Array[Vector2i] = []
	var center = Vector2i.ZERO
	
	print("[SkillPreview] Rendering grid. ScopeType: %s, Radius: %d" % [TargetingDefinition.ScopeType.keys()[targeting.scope_type], radius])
	
	if force_dot_only:
		cells_in_scope.append(center)
	else:
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
				var pattern = targeting.get("pattern_7x7")
				if pattern and pattern.size() == 49:
					for i in range(49):
						if pattern[i]:
							var dx = (i % 7) - 3
							var dy: int = int(floor(i / 7.0)) - 3
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

	# 繪製 7x7 網格
	for y in range(-3, 4):
		for x in range(-3, 4):
			var rect = ColorRect.new()
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # 確保預覽圖示不阻擋按鈕點擊
			rect.custom_minimum_size = cell_size
			
			var pos = Vector2i(x, y)
			if pos == Vector2i.ZERO:
				rect.color = Color(1, 0.9, 0.2) # 中心：黃色
			elif cells_in_scope.has(pos):
				rect.color = active_color
			else:
				rect.color = Color(0.2, 0.2, 0.2, 0.6) # 背景
			
			grid.add_child(rect)

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


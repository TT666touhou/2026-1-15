extends Control
class_name StatBar

@export var back_bar: TextureProgressBar
@export var front_bar: TextureProgressBar

@export var is_health: bool = true
@export var low_hp_pulse: bool = true
@export var damage_shake: bool = true
@export var hide_on_zero: bool = false

@export var min_width: float = 24.0
@export var min_height: float = 4.0
@export var height_scale: float = 0.25 # Percent of cell height to use for bar height
@export var vertical_padding: float = 6.0 # Extra pixels above the unit
@export var default_max_value: float = 100.0
@export var default_current_value: float = 100.0

var current_pct: float = 1.0
var front_tween: Tween
var back_tween: Tween
var pulse_tween: Tween = null
var shake_tween: Tween = null

var _bar_width: float = 24.0
var _bar_height: float = 4.0
var _bottom_offset: float = 16.0 # Distance from center to bottom edge
var _base_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	if not back_bar:
		back_bar = get_node_or_null("BackBar")
	if not front_bar:
		front_bar = get_node_or_null("FrontBar")
	
	_ensure_bars()
	_apply_layout()
	update_bar(default_current_value, default_max_value)

func _ensure_bars() -> bool:
	if back_bar == null:
		back_bar = get_node_or_null("BackBar")
	if front_bar == null:
		front_bar = get_node_or_null("FrontBar")
	return back_bar != null and front_bar != null

func _input(event):
	if event is InputEventKey:
		if event.is_pressed() and event.keycode == KEY_SPACE:
			if back_bar:
				update_bar(back_bar.value - 10, back_bar.max_value)

func configure_from_grid(cell_size: Vector2i, width_cells: int, height_cells: int) -> void:
	# Width: Match entity width minus some padding (optional)
	_bar_width = float(cell_size.x * width_cells)
	
	# Height: Fixed or scaled? User said "width limited by entity size", didn't specify height change.
	# Using fixed min_height or scaled. Defaulting to min_height for consistency.
	_bar_height = min_height 
	
	# Bottom Offset: Calculate distance from center to bottom edge
	# Entity Height / 2
	_bottom_offset = float(cell_size.y * height_cells) * 0.5
	
	_apply_layout()

func set_health(current: float, max_hp: float) -> void:
	update_bar(current, max_hp)

func on_damage(_amount: float, projected_hp: float, max_hp: float) -> void:
	update_bar(projected_hp, max_hp)

func update_bar(current: float, max_value: float):
	if not _ensure_bars():
		return

	var safe_max = max(1.0, max_value)
	var pct = clamp(current / safe_max, 0.0, 1.0)
	
	front_bar.max_value = safe_max
	back_bar.max_value = safe_max
	
	var is_damage = pct < current_pct
	var is_heal   = pct > current_pct
	
	if is_damage:
		if front_tween and front_tween.is_running():
			front_tween.kill()
		if back_tween and back_tween.is_running():
			back_tween.kill()
		
		front_bar.value = current
		
		back_tween = create_tween()
		back_tween.tween_property(back_bar, "value", current, 0.45)
		_on_damage()
	
	elif is_heal:
		if front_tween and front_tween.is_running():
			front_tween.kill()
		if back_tween and back_tween.is_running():
			back_tween.kill()
		
		front_tween = create_tween().set_parallel()
		front_tween.tween_property(front_bar, "value", current, 0.25)
		front_tween.tween_property(back_bar, "value",  current, 0.25)
		_on_heal()
	else:
		# Initialize / Sync
		front_bar.value = current
		
		# Only snap back_bar if NO tween is running to avoid interrupting damage animation
		if not (back_tween and back_tween.is_running()):
			back_bar.value = current
	
	current_pct = pct
	
	if hide_on_zero:
		visible = pct > 0.0
	
	if is_health:
		_check_low_hp_pulse(pct)

func _shake():
	if shake_tween and shake_tween.is_running():
		shake_tween.kill()
		# Reset to base position before shaking again
		position = _base_position
		
	shake_tween = create_tween()
	shake_tween.tween_property(self, "position", _base_position + Vector2(2, 0), 0.05)
	shake_tween.tween_property(self, "position", _base_position - Vector2(2, 0), 0.05)
	shake_tween.tween_property(self, "position", _base_position, 0.05)

func _flash(flash_color: Color):
	modulate = flash_color
	var t = create_tween()
	t.tween_property(self, "modulate", Color(1,1,1), 0.25)

func _on_damage():
	_flash(Color(1, 0.3, 0.3))
	if damage_shake:
		_shake()

func _on_heal():
	_flash(Color(0.3, 1, 0.3))

func _check_low_hp_pulse(pct: float) -> void:
	if not low_hp_pulse:
		return

	if pct < 0.25:
		if pulse_tween == null or not pulse_tween.is_running():
			if pulse_tween:
				pulse_tween.kill()

			pulse_tween = create_tween()
			pulse_tween.set_loops()
			pulse_tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.2)
			pulse_tween.tween_property(self, "scale", Vector2(1.00, 1.00), 0.2)
	else:
		scale = Vector2.ONE
		
		if pulse_tween and pulse_tween.is_running():
			pulse_tween.kill()
			pulse_tween = null

func _apply_layout() -> void:
	var bar_size := Vector2(_bar_width, _bar_height)
	# Position: Center horizontally, Bottom aligned vertically
	# Assuming Parent (Entity) origin is Center.
	# X = -width/2
	# Y = bottom_offset - height (to place it *inside* the bottom edge)
	# Or Y = bottom_offset (to place it *below*)
	# Based on image, it looks like it's overlapping the bottom tiles, so it's inside the entity bounds?
	# Image: Red box is at the bottom of the sprite/tile.
	# So Y should be: (EntityHeight/2) - BarHeight
	
	var bar_position := Vector2(-bar_size.x * 0.5, _bottom_offset - bar_size.y)
	
	custom_minimum_size = bar_size
	size = bar_size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = bar_position
	_base_position = bar_position
	pivot_offset = bar_size / 2 # Center pivot for scaling
	
	# Children (BackBar, FrontBar) are set to Full Rect anchors in the scene,
	# so they will automatically resize to match this control.

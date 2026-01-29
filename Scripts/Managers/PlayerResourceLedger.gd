extends Node

@export var default_resources := {
	"coin": 0,
}
@export var capacity_limits := {
}
@export var debug_mode: bool = false

signal resource_changed(resource: String, new_value: int, delta: int)
signal ledger_reset(current: Dictionary)

var _resources: Dictionary = {}
var _is_initialized: bool = false

func _ready() -> void:
	add_to_group("ledger")
	_initialize_resources()

func _initialize_resources() -> void:
	if _is_initialized:
		return
	_resources.clear()
	for key in default_resources.keys():
		var value: int = int(default_resources[key])
		var limit: int = int(capacity_limits.get(key, 999999999))
		_resources[key] = clampi(value, 0, limit)
	for key in capacity_limits.keys():
		if not _resources.has(key):
			_resources[key] = 0
			if debug_mode:
				print("[Ledger] init fill missing resource: ", key)
	_is_initialized = true
	ledger_reset.emit(_resources.duplicate())
	if debug_mode:
		print("[Ledger] initialized: ", _resources)

func reset(resources: Dictionary = default_resources) -> void:
	default_resources = resources.duplicate()
	_is_initialized = false
	_initialize_resources()

func get_amount(resource: String) -> int:
	return _resources.get(resource, 0)

func get_all() -> Dictionary:
	return _resources.duplicate()

func can_afford(cost: Dictionary) -> bool:
	for key in cost.keys():
		if get_amount(key) < int(cost[key]):
			return false
	return true

func add_resource(resource: String, amount: int) -> int:
	var current: int = get_amount(resource)
	var limit: int = int(capacity_limits.get(resource, 999999999))
	var new_value := clampi(current + int(amount), 0, limit)
	_resources[resource] = new_value
	var delta := new_value - current
	if delta != 0:
		resource_changed.emit(resource, new_value, delta)
		if debug_mode:
			print("[Ledger] add ", resource, " delta=", delta, " total=", new_value)
	return delta

func spend_resource(cost: Dictionary) -> bool:
	if not can_afford(cost):
		if debug_mode:
			print("[Ledger] spend failed: ", cost)
		return false
	for key in cost.keys():
		add_resource(key, -int(cost[key]))
	return true

func set_amount(resource: String, value: int) -> void:
	var limit: int = int(capacity_limits.get(resource, 999999999))
	var new_value := clampi(int(value), 0, limit)
	var current: int = get_amount(resource)
	_resources[resource] = new_value
	var delta := new_value - current
	if delta != 0:
		resource_changed.emit(resource, new_value, delta)

func print_summary() -> void:
	print("[Ledger] summary: ", _resources)

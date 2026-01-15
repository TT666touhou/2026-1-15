extends Node
class_name TraitService

# Helper to apply trait effects based on trigger events

static func apply_trigger(trigger_type: TraitEffect.TriggerType, context: Dictionary) -> void:
	if PartyManager == null:
		return
	var active_traits = PartyManager.get_active_traits()
	if active_traits.is_empty():
		return
	
	var tree: SceneTree = Engine.get_main_loop()
	if tree == null:
		return
	
	# Precollect entities for target filtering
	var all_entities: Array = tree.get_nodes_in_group("grid_entities")
	
	for trait_data in active_traits:
		for effect in trait_data.effects:
			if effect.trigger_type != trigger_type:
				continue
			
			var targets: Array = []
			if trigger_type == TraitEffect.TriggerType.ON_KILL:
				targets = _get_on_kill_targets(effect, all_entities)
			else:
				targets = _get_targets_for_effect(effect, all_entities, context)
			for entity in targets:
				_apply_effect(effect, entity, context, trigger_type)


static func _get_targets_for_effect(effect: TraitEffect, entities: Array, context: Dictionary) -> Array:
	var result: Array = []
	
	# Reference faction/entity for comparison
	var ref_entity: GridEntity = null
	if context.has("attacker"):
		ref_entity = context["attacker"]
	elif context.has("damaged_entity"):
		ref_entity = context["damaged_entity"]
	elif context.has("killed_entity"):
		ref_entity = context["killed_entity"]
	
	var ref_faction = null
	if ref_entity and ref_entity.has_method("get"):
		ref_faction = ref_entity.get("faction")
	elif context.has("faction"):
		ref_faction = context["faction"]
	
	for e in entities:
		var ge = e as GridEntity
		if ge == null:
			continue
		if _match_target(effect.target_faction, ge, ref_entity, ref_faction):
			result.append(ge)
	
	return result


static func _match_target(target_faction: TraitEffect.TargetFaction, candidate: GridEntity, ref_entity: GridEntity, ref_faction) -> bool:
	match target_faction:
		TraitEffect.TargetFaction.SELF:
			return ref_entity != null and candidate == ref_entity
		TraitEffect.TargetFaction.ALLY:
			if ref_entity and ref_entity.faction:
				return candidate.faction == ref_entity.faction
			if ref_faction:
				return candidate.faction == ref_faction
			return false
		TraitEffect.TargetFaction.ENEMY:
			if ref_entity and ref_entity.faction:
				return candidate.faction != ref_entity.faction
			if ref_faction:
				return candidate.faction != ref_faction
			return false
		TraitEffect.TargetFaction.ALL:
			return true
	return false


static func _apply_effect(effect: TraitEffect, target: GridEntity, _context: Dictionary, trigger_type: TraitEffect.TriggerType) -> void:
	match effect.effect_behavior:
		TraitEffect.EffectBehavior.MODIFY_STAT:
			# 防禦性編程：如果被標記為 MODIFY_STAT 但看起來像資源效果 (有 key 且 trigger 是 ON_KILL/TURN_START/ON_DAMAGED)
			if effect.resource_key != "" and (trigger_type == TraitEffect.TriggerType.ON_KILL or trigger_type == TraitEffect.TriggerType.TURN_START or trigger_type == TraitEffect.TriggerType.ON_DAMAGED):
				_apply_grant_resource(effect, target)
			else:
				_apply_modify_stat(effect, target)
		TraitEffect.EffectBehavior.GRANT_RESOURCE:
			_apply_grant_resource(effect, target)
		TraitEffect.EffectBehavior.APPLY_STATUS:
			_apply_status(effect, target)
		_:
			pass


static func _apply_modify_stat(effect: TraitEffect, target: GridEntity) -> void:
	if target == null or target.character_data == null:
		return
	var cd = target.character_data
	match effect.stat_type:
		TraitEffect.StatType.ATTACK_MULTIPLIER:
			cd.stat_modifiers.attack_multiplier *= effect.value
		TraitEffect.StatType.HP_MULTIPLIER:
			cd.stat_modifiers.hp_multiplier *= effect.value
		TraitEffect.StatType.COMBO_ADDITIVE:
			cd.stat_modifiers.combo_additive += effect.value
		_:
			return
	
	# Clamp HP to new max
	var eff_max_hp = cd.get_effective_max_health()
	cd.current_health = min(cd.current_health, eff_max_hp)
	cd.stats_changed.emit()
	cd.health_changed.emit(cd.current_health, eff_max_hp)
	cd.combo_count_changed.emit(cd.get_effective_combo())


static func _apply_grant_resource(effect: TraitEffect, target: GridEntity = null) -> void:
	if PlayerResourceLedger == null:
		return
	if effect.resource_key == "":
		return
	# 限制只加給可控制陣營（我方）
	if target and target.faction and not target.faction.is_controllable:
		return
	var delta = int(effect.resource_amount)
	PlayerResourceLedger.add_resource(effect.resource_key, delta)


static func _apply_status(effect: TraitEffect, target: GridEntity) -> void:
	if effect.status_resource == null:
		return
	if target == null:
		return
	var sm = target.get_node_or_null("StatusManager")
	if sm and sm.has_method("apply_status"):
		sm.apply_status(effect.status_resource)


static func _get_on_kill_targets(effect: TraitEffect, entities: Array) -> Array:
	var result: Array = []
	for e in entities:
		var ge = e as GridEntity
		if ge == null:
			continue
		match effect.target_faction:
			TraitEffect.TargetFaction.ALLY:
				if ge.faction and ge.faction.is_controllable:
					result.append(ge)
			TraitEffect.TargetFaction.ENEMY:
				if ge.faction and not ge.faction.is_controllable:
					result.append(ge)
			TraitEffect.TargetFaction.ALL:
				result.append(ge)
			_:
				# SELF 或其他未處理的情況在 ON_KILL 不適用
				pass
	return result

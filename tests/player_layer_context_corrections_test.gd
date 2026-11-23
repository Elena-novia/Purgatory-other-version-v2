extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")

var world: Node2D
var player: PlayerController
var context: LayerContext
var box: PushBox
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = MAIN.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	context = player.layer_context
	box = world.get_node("Box")
	await _check_layer_notifications()
	await _check_coplanar_support()
	await _check_owner_exit()
	for route in ["physical", "sanity", "void", "lethal void"]:
		await _check_return(route)
	world.queue_free()
	await _frames(2)
	quit(1 if failed else 0)

func _check_layer_notifications() -> void:
	await _place(2, Vector2(895, 482))
	player.magic_orb.toggle_release_or_retrieve()
	_expect(player.magic_orb.stored_receiver == box, "Production orb is stored in the Middle box")
	await _transition_case([], [], ["C3", "L3"],
		"Middle to Back emits context then layer, once each")
	await _transition_case([-1], [], ["C3", "L3", "C2", "L2"],
		"Context observer's Back to Middle request follows both Back notifications")
	await _transition_case([-1, 1], [-1], ["C3", "L3", "C2", "L2", "C3", "L3", "C2", "L2"],
		"Several requests from both signals are processed in their original FIFO order")
	await _transition_case([0, 1, -1], [], ["C3", "L3", "C2", "L2"],
		"Invalid directions and out-of-range destinations publish nothing and preserve the next valid request")
	player.magic_orb.toggle_release_or_retrieve()
	await _frames(12)

func _transition_case(on_context: Array[int], on_layer: Array[int], expected: Array[String], message: String) -> void:
	if player.current_layer == 3:
		player.try_change_layer(-1)
	await _place(2, Vector2(500, 482))
	var steps_from_context := on_context.duplicate()
	var steps_from_layer := on_layer.duplicate()
	var trace: Array[String] = []
	var consistent: Array[bool] = []
	var velocity_at_start := player.velocity
	var inspect_context := func():
		var index := context.logical_layer
		trace.append("C%d" % index)
		while not steps_from_context.is_empty():
			player.try_change_layer(steps_from_context.pop_front())
		consistent.append(context.logical_layer == index and _transition_state(index, velocity_at_start))
	var inspect_layer := func(index: int):
		trace.append("L%d" % index)
		while not steps_from_layer.is_empty():
			player.try_change_layer(steps_from_layer.pop_front())
		consistent.append(_transition_state(index, velocity_at_start))
	context.context_changed.connect(inspect_context)
	player.layer_changed.connect(inspect_layer)
	player.try_change_layer(1)
	context.context_changed.disconnect(inspect_context)
	player.layer_changed.disconnect(inspect_layer)
	_expect(trace == expected, "%s (observed %s)" % [message, str(trace)])
	_expect(consistent.size() == expected.size() and not consistent.has(false),
		"Each observer sees stable positions, velocities, indices, solids, profiles and stored orb")

func _transition_state(index: int, before_velocity: Vector2) -> bool:
	var profile: GameplayLayer = world.get_depth_profiles()[index - 1]
	var bit := GameplayLayer.solid_collision_bit(index)
	return context.logical_layer == index and player.current_layer == index and _has_solid(index) \
		and player.global_position.is_equal_approx(Vector2(500, 520 - 38 * (index - 1))) \
		and player.velocity.is_equal_approx(before_velocity) and context.gameplay_layer == null \
		and context.depth_profile == profile and player.depth_visuals.get("_active_profile") == profile \
		and box.current_layer == index and box.collision_layer == bit and box.collision_mask == bit \
		and box.global_position.is_equal_approx(Vector2(945, 504 - 38 * (index - 1))) \
		and box.depth_visuals.get("_active_profile") == profile \
		and player.magic_orb.current_layer == index and player.magic_orb.get_parent() == box \
		and player.magic_orb.stored_receiver == box \
		and player.magic_orb.global_position.is_equal_approx(box.orb_anchor.global_position) \
		and player.magic_orb.depth_visuals.get("_depth_source") == box.depth_visuals

func _check_coplanar_support() -> void:
	var section_a := _add_flat_section("CoincidentA")
	var section_b := _add_flat_section("CoincidentB")
	await _frames(2)
	await _place(1, Vector2(5000, 480), 25)
	_expect(player.is_on_floor() and _has_solid(1) and context.gameplay_layer == null,
		"Two coplanar floors support Front without selecting an owner on initial landing")
	_expect(_floor_without(section_a) == section_b and _floor_without(section_b) == section_a,
		"At the identical world pose each coplanar section independently supports the player")

	var assigned: Array[GameplayLayer] = []
	var layer_events: Array[int] = []
	var observe_owner := func():
		if context.gameplay_layer != null:
			assigned.append(context.gameplay_layer)
	var observe_layer := func(index: int): layer_events.append(index)
	# Exact audit setup: restore half a pixel above the same two floors so the
	# next move snaps to the floor without recording a slide.
	player.set_checkpoint(Vector2(5000, 499.5), 1)
	player.restore_checkpoint()
	context.context_changed.connect(observe_owner)
	player.layer_changed.connect(observe_layer)
	await _frames(1)
	_expect(player.is_on_floor() and player.get_slide_collision_count() == 0
		and absf(player.global_position.y - 500.0) < 0.1 and _has_solid(1),
		"The checkpoint reproduction really snapped with zero slide contacts and correct Front solids")
	_expect(context.gameplay_layer == null and assigned.is_empty() and context.owner_path.is_empty(),
		"The ambiguous snap publishes no arbitrary owner")
	await _frames(3)
	_expect(context.gameplay_layer == null and assigned.is_empty(), "Ambiguity stays unresolved on later frames")

	section_b.position.y = 3.0
	await _frames(12)
	_expect(context.gameplay_layer == section_a and assigned == [section_a] and _has_solid(1),
		"With the second floor three pixels below, the unique supporting section is published")
	world.remove_child(section_a)
	_expect(context.gameplay_layer == null and _has_solid(1), "Ordinary section removal clears ownership immediately")
	await _frames(12)
	_expect(context.gameplay_layer == section_b and assigned == [section_a, section_b] and _has_solid(1),
		"Landing on the second floor resolves a new owner on the same logical layer")
	_expect(layer_events.is_empty(), "All of the owner-only changes leave layer_changed silent")
	context.context_changed.disconnect(observe_owner)
	player.layer_changed.disconnect(observe_layer)
	section_a.free()
	section_b.queue_free()
	await _frames(2)

func _check_owner_exit() -> void:
	var section := _add_flat_section("ExitProbe")
	await _place(1, Vector2(5000, 480), 25)
	_expect(context.gameplay_layer == section, "A live section is accepted as the confirmed owner")
	var exit_observations: Array[bool] = []
	var attempt_rebind := func():
		if context.gameplay_layer == null:
			exit_observations.append(section.is_inside_tree() and context.owner_path.is_empty()
				and context.set_dynamic_layer(1, section) and context.gameplay_layer == null)
	context.context_changed.connect(attempt_rebind)
	player.set_physics_process(false)
	world.remove_child(section)
	context.context_changed.disconnect(attempt_rebind)
	_expect(exit_observations == [true],
		"The original context_changed observer cannot rebind its exiting section while Godot still reports it in-tree")
	_expect(not section.is_inside_tree() and context.gameplay_layer == null and _has_solid(1),
		"After removal no reference survives and the Front solids remain active")

	var early_observations: Array[bool] = []
	var attempt_before_context_handler := func():
		early_observations.append(section.is_inside_tree() and context.gameplay_layer == null
			and context.owner_path.is_empty() and context.set_dynamic_layer(1, section)
			and context.gameplay_layer == null)
	# Attach this listener before the context reattaches its own tree_exiting listener.
	section.tree_exiting.connect(attempt_before_context_handler)
	world.add_child(section)
	_expect(context.set_dynamic_layer(1, section) and context.gameplay_layer == section,
		"The same section is available for normal assignment after reentry")
	world.remove_child(section)
	_expect(early_observations == [true] and context.gameplay_layer == null and _has_solid(1),
		"An earlier tree_exiting observer also sees no departing owner and cannot register it")
	section.tree_exiting.disconnect(attempt_before_context_handler)
	world.add_child(section)
	player.set_physics_process(true)
	await _place(1, Vector2(5000, 480), 25)
	_expect(context.gameplay_layer == section, "Real contact establishes the reentered section again")
	section.queue_free()
	await _frames(2)

func _check_return(route: String) -> void:
	# The production box remains in Middle. Store the orb there so each route
	# also exercises the actual retrieval rule before publishing Back.
	await _place(2, Vector2(895, 482), 18)
	player.magic_orb.toggle_release_or_retrieve()
	_expect(player.magic_orb.stored_receiver == box, "%s starts with the orb stored in the box" % route)
	await _place(2, Vector2(160, 482))
	player.set_checkpoint(Vector2(160, 412), 3)
	player.vitals.health = 0.75 if route != "lethal void" else 0.05
	player.vitals.sanity = 0.4
	var box_position := box.global_position
	var expected_health := player.vitals.health - player.vitals.damage_per_hit if route == "void" \
		else player.vitals.max_health
	var checkpoint_notifications: Array[bool] = []
	var visual_notifications: Array[bool] = []
	var vital_notifications: Array[bool] = []
	var layer_events: Array[int] = []
	var observe_context := func():
		if context.logical_layer == 3 and context.gameplay_layer == null:
			checkpoint_notifications.append(_return_state(expected_health, box_position))
	var observe_visual := func():
		if context.logical_layer == 3 and context.gameplay_layer == null:
			visual_notifications.append(_return_state(expected_health, box_position))
	var observe_vitals := func(health: float, sanity: float):
		if context.logical_layer == 3 and player.global_position == player.checkpoint_position:
			vital_notifications.append(is_equal_approx(health, expected_health)
				and is_equal_approx(sanity, player.vitals.max_sanity)
				and _return_state(expected_health, box_position))
	var observe_layer := func(index: int): layer_events.append(index)
	context.context_changed.connect(observe_context)
	player.depth_visuals.appearance_changed.connect(observe_visual)
	player.vitals.values_changed.connect(observe_vitals)
	player.layer_changed.connect(observe_layer)
	match route:
		"physical":
			player.vitals.take_damage(player.vitals.max_health)
		"sanity":
			player.vitals.sanity = 0.0
			player.vitals._emit_values()
			player.vitals._check_death()
		_:
			player.global_position.y = PlayerController.VOID_Y + 15
			player.fall_into_void()
	if route == "lethal void":
		_expect(world.get("_respawn_in_progress") and checkpoint_notifications.is_empty(),
			"A lethal fall leaves checkpoint publication to the active physical-death sequence")
	if route != "void":
		for _frame in range(420):
			await physics_frame
			if not world.get("_respawn_in_progress"):
				break
		_expect(not world.get("_respawn_in_progress"), "%s completes the existing death effect" % route)
	context.context_changed.disconnect(observe_context)
	player.depth_visuals.appearance_changed.disconnect(observe_visual)
	player.vitals.values_changed.disconnect(observe_vitals)
	player.layer_changed.disconnect(observe_layer)
	_expect(checkpoint_notifications == [true], "%s context callback sees the complete checkpoint state once" % route)
	_expect(visual_notifications == [true], "%s appearance callback sees the immediate scale and restored state" % route)
	_expect(not vital_notifications.is_empty() and not vital_notifications.has(false),
		"%s checkpoint vital callbacks see the restored layer, visual profile and vitals" % route)
	_expect(layer_events.is_empty(), "%s checkpoint return preserves layer_changed silence" % route)
	_expect(_return_state(expected_health, box_position), "%s final checkpoint state matches the published state" % route)
	await _frames(30)
	_expect(context.gameplay_layer == world.get_node("BackLayer"), "%s reacquires ownership only after landing" % route)

func _return_state(health: float, box_position: Vector2) -> bool:
	var back: GameplayLayer = world.get_node("BackLayer")
	return _has_solid(3) and context.gameplay_layer == null and context.depth_profile == back \
		and player.global_position == player.checkpoint_position and player.velocity == Vector2.ZERO \
		and not player._intentional_jump and not player._damage_landing_pending \
		and player.depth_visuals.scale.is_equal_approx(Vector2.ONE * back.depth_scale) \
		and player.depth_visuals.modulate.is_equal_approx(back.depth_modulation()) \
		and is_equal_approx(player.vitals.health, health) and is_equal_approx(player.vitals.sanity, player.vitals.max_sanity) \
		and box.current_layer == 2 and box.collision_mask == 2 and box.global_position.is_equal_approx(box_position) \
		and player.magic_orb.stored_receiver == null and player.magic_orb.get_parent() == player \
		and not player.vitals.orb_is_away

func _floor_without(excluded: GameplayLayer) -> Object:
	var hit := KinematicCollision2D.new()
	player.add_collision_exception_with(excluded)
	var supported := player.test_move(player.global_transform, Vector2.DOWN, hit, player.safe_margin, true)
	player.remove_collision_exception_with(excluded)
	return hit.get_collider() if supported else null

func _add_flat_section(label: String) -> GameplayLayer:
	var section := GameplayLayer.new()
	section.name = label
	var decoration := Node2D.new()
	decoration.name = "ParallaxDecoration"
	var details := Node2D.new()
	details.name = "DepthDetails"
	decoration.add_child(details)
	section.add_child(decoration)
	var polygon := CollisionPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(4900, 500), Vector2(5100, 500), Vector2(5100, 580), Vector2(4900, 580)])
	section.add_child(polygon)
	world.add_child(section)
	return section

func _has_solid(index: int) -> bool:
	var bit := GameplayLayer.solid_collision_bit(index)
	return player.current_layer == index and context.logical_layer == index \
		and player.collision_layer == bit and player.collision_mask == bit

func _place(index: int, point: Vector2, frames := 4) -> void:
	player.cancel_damage_reaction()
	player.set_checkpoint(point, index)
	player.restore_checkpoint()
	await _frames(frames)

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		print("FAIL: ", message)
		failed += 1

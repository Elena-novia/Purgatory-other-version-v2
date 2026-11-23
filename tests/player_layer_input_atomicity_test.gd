extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const STEP_LIMIT := PlayerController.LAYER_STEPS_PER_PHYSICS_FRAME
const CAPACITY := PlayerController.MAX_PENDING_LAYER_STEPS

var world: Node2D
var player: PlayerController
var ctx: LayerContext
var box: PushBox
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = MAIN.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	ctx = player.layer_context
	box = world.get_node("Box")
	await _check_player_publications()
	await _check_owner_removal()
	await _check_standalone_owner_writes()
	for route in ["physical", "sanity", "lethal void"]:
		await _check_respawn(route)
	await _check_keyboard()
	world.queue_free()
	await _frames(2)
	quit(1 if failed else 0)

func _check_player_publications() -> void:
	await _place(2, Vector2(895, 482), 8)
	player.magic_orb.toggle_release_or_retrieve()
	await _place(2, Vector2(500, 482))
	_expect(player.magic_orb.stored_receiver == box, "Production box stores the orb before the coordinated transition")
	var trace: Array[String] = []
	var stable: Array[bool] = []
	var context_requested: Array[bool] = [false]
	var layer_requested: Array[bool] = [false]
	var admissions: Array[bool] = []
	var a := func():
		var index := ctx.logical_layer
		trace.append("C%d:A" % index)
		if not context_requested[0]:
			context_requested[0] = true
			admissions.append(ctx.set_dynamic_layer(2))
			admissions.append(not ctx.set_dynamic_layer(0))
			admissions.append(not ctx.set_dynamic_layer(2, world.get_node("MiddleLayer")))
		stable.append(_stored_state(index))
	var b := func():
		trace.append("C%d:B" % ctx.logical_layer)
		stable.append(_stored_state(ctx.logical_layer))
	var l_a := func(index: int):
		trace.append("L%d:A" % index)
		if not layer_requested[0]:
			layer_requested[0] = true
			admissions.append(ctx.set_dynamic_layer(3))
			admissions.append(ctx.set_dynamic_layer(2))
		stable.append(_stored_state(index))
	var l_b := func(index: int):
		trace.append("L%d:B" % index)
		stable.append(_stored_state(index))
	ctx.context_changed.connect(a)
	ctx.context_changed.connect(b)
	player.layer_changed.connect(l_a)
	player.layer_changed.connect(l_b)
	player.try_change_layer(1)
	ctx.context_changed.disconnect(a)
	ctx.context_changed.disconnect(b)
	player.layer_changed.disconnect(l_a)
	player.layer_changed.disconnect(l_b)
	var expected: Array[String] = []
	for index in [3, 2, 3, 2]:
		expected.append_array(["C%d:A" % index, "C%d:B" % index, "L%d:A" % index, "L%d:B" % index])
	_expect(admissions == [true, true, true, true, true],
		"Supported direct index requests are admitted and invalid index or cross-layer owner writes are rejected")
	_expect(trace == expected and stable.size() == expected.size() and not stable.has(false),
		"Direct writes from both signals wait for both observers and execute as full movements in absolute FIFO order")
	_expect(_stored_state(2) and _pending() == 0, "The final absolute request leaves the player, box, orb and profile together in Middle")
	print("DIRECT_WRITES_TRACE ", trace, " accepted=", admissions, " stable=", stable)
	player.magic_orb.toggle_release_or_retrieve()

func _stored_state(index: int) -> bool:
	var bit := 1 << (index - 1)
	var profile: GameplayLayer = world.get_depth_profiles()[index - 1]
	return _bits(index) and ctx.gameplay_layer == null and ctx.depth_profile == profile \
		and player.depth_visuals.get("_active_profile") == profile and box.depth_visuals.get("_active_profile") == profile \
		and player.global_position.is_equal_approx(Vector2(500, 520 - 38 * (index - 1))) \
		and box.global_position.is_equal_approx(Vector2(945, 504 - 38 * (index - 1))) \
		and box.current_layer == index and box.collision_layer == bit and box.collision_mask == bit \
		and player.magic_orb.current_layer == index and player.magic_orb.get_parent() == box \
		and player.magic_orb.global_position.is_equal_approx(box.orb_anchor.global_position)

func _check_owner_removal() -> void:
	var section := _front_section("RemovedDuringSignal")
	var terrain := CollisionPolygon2D.new()
	terrain.polygon = PackedVector2Array([Vector2(4100, 500), Vector2(4300, 500), Vector2(4300, 590), Vector2(4100, 590)])
	section.add_child(terrain)
	await _place(1, Vector2(4200, 450), 0)
	var trace: Array[String] = []
	var paths: Array[String] = []
	var layer_events: Array[int] = []
	var a := func():
		trace.append("A:" + _owner_name(ctx))
		paths.append(ctx.owner_path)
		if ctx.gameplay_layer == section and section.is_inside_tree():
			world.remove_child(section)
	var b := func():
		trace.append("B:" + _owner_name(ctx))
		paths.append(ctx.owner_path)
	var l := func(index: int): layer_events.append(index)
	ctx.context_changed.connect(a)
	ctx.context_changed.connect(b)
	player.layer_changed.connect(l)
	await _frames(24)
	ctx.context_changed.disconnect(a)
	ctx.context_changed.disconnect(b)
	player.layer_changed.disconnect(l)
	_expect(trace == ["A:RemovedDuringSignal", "B:RemovedDuringSignal", "A:null", "B:null"]
		and paths.size() == 4 and not paths[0].is_empty() and paths[0] == paths[1],
		"Detaching the owner keeps the current snapshot for both callbacks before one separate clear")
	_expect(ctx.gameplay_layer == null and not section.is_inside_tree() and _bits(1) and layer_events.is_empty(),
		"Removal leaves no owner reference and publishes no logical transition")
	print("OWNER_REMOVAL_TRACE ", trace)
	section.free()

func _check_standalone_owner_writes() -> void:
	var one := _front_section("StandaloneA")
	var two := _front_section("StandaloneB")
	var context := LayerContext.new()
	context.mode = LayerContext.Mode.DYNAMIC
	world.add_child(context)
	var trace: Array[String] = []
	var accepted: Array[bool] = []
	var a := func():
		trace.append("A:" + _owner_name(context))
		if accepted.is_empty() and context.gameplay_layer == one:
			accepted.append(context.set_dynamic_layer(1, two))
			accepted.append(not context.set_dynamic_layer(4, two))
			accepted.append(context.set_dynamic_layer(1, one))
	var b := func(): trace.append("B:" + _owner_name(context))
	context.context_changed.connect(a)
	context.context_changed.connect(b)
	_expect(context.set_dynamic_layer(1, one) and trace == ["A:StandaloneA", "B:StandaloneA"],
		"Standalone context keeps compatibility and defers nested owner writes")
	await _frames(3)
	_expect(accepted == [true, true, true] and context.gameplay_layer == one
		and trace == ["A:StandaloneA", "B:StandaloneA", "A:StandaloneB", "B:StandaloneB", "A:StandaloneA", "B:StandaloneA"],
		"Valid owner writes publish in order and the invalid nested write has no effect")
	print("STANDALONE_OWNER_TRACE ", trace)
	context.queue_free()
	one.queue_free()
	two.queue_free()

func _check_respawn(route: String) -> void:
	await _place(1, Vector2(160, 520))
	var destination := 3 if route == "sanity" else 2
	player.set_checkpoint(Vector2(160, 520 - 38 * (destination - 1)), destination)
	for _i in range(STEP_LIMIT):
		player.request_layer_step(-1)
	player.request_layer_step(1)
	if route == "sanity":
		player.request_layer_step(-1)
	var trace: Array[String] = []
	var layer_events: Array[int] = []
	var phase_states: Array[bool] = []
	var observed_restore: Array[bool] = [false]
	var a := func():
		if world.get("_respawn_in_progress") and ctx.logical_layer == destination and not observed_restore[0]:
			trace.append("appearance:%d:%d" % [ctx.logical_layer, _pending()])
			if route == "physical":
				player.request_layer_step(-1)
				_tap(KEY_W)
			phase_states.append(_restore_snapshot(destination))
	var c := func():
		if world.get("_respawn_in_progress") and ctx.logical_layer == destination and not observed_restore[0]:
			trace.append("context:%d:%d" % [ctx.logical_layer, _pending()])
			phase_states.append(_restore_snapshot(destination))
	var v := func(health: float, sanity: float):
		if world.get("_respawn_in_progress") and not observed_restore[0] and health == player.vitals.max_health \
				and sanity == player.vitals.max_sanity and ctx.logical_layer == destination:
			observed_restore[0] = true
			trace.append("vitals:%d:%d" % [ctx.logical_layer, _pending()])
			if route == "physical":
				player.request_layer_step(-1)
			phase_states.append(_restore_snapshot(destination))
	var l := func(index: int):
		trace.append("L%d:respawn=%s:physics=%s" % [index, world.get("_respawn_in_progress"), player.is_physics_processing()])
		layer_events.append(index)
		phase_states.append(not world.get("_respawn_in_progress") and player.is_physics_processing() and _bits(index))
	player.depth_visuals.appearance_changed.connect(a)
	ctx.context_changed.connect(c)
	player.vitals.values_changed.connect(v)
	player.layer_changed.connect(l)
	match route:
		"physical":
			player.vitals.take_damage(player.vitals.max_health)
			_tap(KEY_S)
		"sanity":
			player.vitals.sanity = 0.0
			player.vitals._check_death()
		_:
			player.global_position.y = PlayerController.VOID_Y + 20
			player.vitals.health = 0.05
			player.fall_into_void()
	await _frames(4)
	_expect(world.get("_respawn_in_progress") and not player.is_physics_processing()
		and _pending() == (1 if route == "lethal void" else 2) and layer_events.is_empty(),
		"%s preserves admitted requests during the death overlay" % route)
	for _i in range(420):
		await physics_frame
		if not world.get("_respawn_in_progress"):
			break
	await _frames(4)
	player.depth_visuals.appearance_changed.disconnect(a)
	ctx.context_changed.disconnect(c)
	player.vitals.values_changed.disconnect(v)
	player.layer_changed.disconnect(l)
	var expected: Array[int] = []
	expected.assign([3, 2, 1, 2, 1] if route == "physical" else ([2] if route == "sanity" else [3]))
	_expect(observed_restore[0] and not phase_states.has(false) and phase_states.size() == 3 + expected.size(),
		"%s publishes a complete checkpoint and every queued transition waits for active gameplay" % route)
	_expect(layer_events == expected and _pending() == 0 and _bits(expected.back()),
		"%s resumes requests in FIFO order, revalidates them, and drains without duplicates" % route)
	print("RESPAWN_TRACE ", route, " ", trace)

func _restore_snapshot(index: int) -> bool:
	return _bits(index) and ctx.gameplay_layer == null and player.global_position == player.checkpoint_position \
		and player.velocity == Vector2.ZERO and not player.is_physics_processing() and world.get("_respawn_in_progress") \
		and is_equal_approx(player.depth_visuals.scale.x, ctx.depth_profile.depth_scale) \
		and player.vitals.health == player.vitals.max_health and player.vitals.sanity == player.vitals.max_sanity

func _check_keyboard() -> void:
	await _place(1, Vector2(160, 520))
	_tap(KEY_W)
	_expect(_bits(2), "An ordinary W still advances one layer immediately")
	_tap(KEY_S)
	_expect(_bits(1), "An ordinary S still returns one layer immediately")

	await _place(1, Vector2(160, 520))
	_fill_queue(-1, CAPACITY - 1)
	_tap(KEY_W)
	_expect(_pending() == CAPACITY and _buffered() == 0, "W occupies the last admitted slot when 63 requests are pending")
	await _frames(8)
	_expect(_bits(2) and _pending() == 0, "The W admitted at 63 executes after the earlier entries")

	await _place(1, Vector2(160, 520))
	_fill_queue(-1, CAPACITY)
	var indices: Array[int] = []
	var l := func(index: int): indices.append(index)
	player.layer_changed.connect(l)
	_tap(KEY_W)
	_tap(KEY_W, true)
	_tap(KEY_S)
	_tap(KEY_W)
	_expect(_pending() == CAPACITY and _buffered() == 3 and indices.is_empty(),
		"Full queue retains W, S, W without counting keyboard echo or giving them an early turn")
	_expect(not player.request_layer_step(-1), "Script requests cannot pass the buffered keyboard entries")
	await _frames(9)
	player.layer_changed.disconnect(l)
	_expect(indices == [2, 1, 2] and _pending() == 0 and _buffered() == 0,
		"All three buffered presses enter when capacity frees and execute exactly once in order")
	print("KEYBOARD_TRACE full_queue indices=", indices)

	await _place(3, Vector2(160, 444))
	_fill_queue(1, CAPACITY)
	_tap(KEY_W)
	await _frames(8)
	_expect(_bits(3) and _pending() == 0 and _buffered() == 0,
		"Buffered W at Back is revalidated and discarded without a change")
	_tap(KEY_S)
	_expect(_bits(2), "Keyboard remains responsive following a rejected buffer entry")

	await _place(1, Vector2(160, 520))
	player.take_hit(0.1, player.global_position - Vector2(20, 0))
	await _frames(4)
	var velocity := player.velocity
	_tap(KEY_W)
	_expect(_bits(2) and player.velocity == velocity and player._damage_landing_pending,
		"Real W during knockback preserves the airborne reaction")

	await _place(1, Vector2(160, 520))
	_fill_queue(-1, CAPACITY)
	for _i in range(PlayerController.MAX_BUFFERED_KEYBOARD_STEPS + 1):
		_tap(KEY_W)
	var notice: Label = world.get_node("HUD/LayerInputNotice")
	_expect(_pending() == CAPACITY and _buffered() == PlayerController.MAX_BUFFERED_KEYBOARD_STEPS
		and notice.is_visible_in_tree() and notice.get_viewport_rect().has_point(notice.get_global_rect().get_center()),
		"The bounded keyboard backlog reports an unretained press in the visible HUD")
	await _frames(10)
	_expect(_pending() == 0 and _buffered() == 0, "Maximum backlog drains without exceeding the admitted capacity")

func _fill_queue(direction: int, pending: int) -> void:
	for _i in range(STEP_LIMIT + pending):
		player.request_layer_step(direction)

func _bits(index: int) -> bool:
	var bit := GameplayLayer.solid_collision_bit(index)
	return ctx.logical_layer == index and player.current_layer == index and player.collision_layer == bit and player.collision_mask == bit

func _front_section(label: String) -> GameplayLayer:
	var section := GameplayLayer.new()
	section.name = label
	var art := Node2D.new()
	art.name = "ParallaxDecoration"
	var details := Node2D.new()
	details.name = "DepthDetails"
	art.add_child(details)
	section.add_child(art)
	world.add_child(section)
	return section

func _owner_name(context: LayerContext) -> String:
	return str(context.gameplay_layer.name) if context.gameplay_layer != null else "null"

func _pending() -> int:
	return player.get("_pending_layer_steps").size()

func _buffered() -> int:
	return player.get("_buffered_keyboard_steps").size()

func _tap(code: Key, echo := false) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	press.echo = echo
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	release.echo = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func _place(index: int, at: Vector2, count := 6) -> void:
	player.cancel_damage_reaction()
	player.set_checkpoint(at, index)
	player.restore_checkpoint()
	await _frames(count)

func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame

func _expect(passed: bool, msg: String) -> void:
	print("PASS: " if passed else "FAIL: ", msg)
	if not passed:
		failed += 1

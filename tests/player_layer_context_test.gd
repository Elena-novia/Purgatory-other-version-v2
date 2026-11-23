extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const TERRAIN := preload("res://scripts/world/terrain_polygon.gd")

var world: Node2D
var player: PlayerController
var context: LayerContext
var front: GameplayLayer
var front_two: GameplayLayer
var middle: GameplayLayer
var back: GameplayLayer
var box: PushBox
var failed := 0
var layer_events: Array[int] = []
var context_events := 0
var context_masks_consistent := true
var inspect_box_event := false
var box_event_consistent := false
var box_context_consistent := false
var expected_restore_layer := 0
var restore_event_consistent := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = MAIN.instantiate()
	player = world.get_node("Player")
	context = player.layer_context
	front = world.get_node("FrontLayer")
	front_two = world.get_node("FrontLayer2")
	middle = world.get_node("MiddleLayer")
	back = world.get_node("BackLayer")
	box = world.get_node("Box")
	_expect(context.logical_layer == 0 and player.current_layer == 1,
		"Detached player has an unresolved context and a configured Front index")
	player.current_layer = 4
	_expect(player.current_layer == 3 and context.logical_layer == 0,
		"Detached assignments clamp and store the index in LayerContext")
	player.current_layer = 0
	context.context_changed.connect(_on_context_changed)
	player.layer_changed.connect(_on_layer_changed)
	root.add_child(world)
	_expect(context.mode == LayerContext.Mode.DYNAMIC and _has_layer(1)
		and context.gameplay_layer == null and player.get_parent() == world,
		"Player starts in Dynamic Front under Main with no previous ground owner")
	await _wait_frames(4)
	_expect(player.is_on_floor() and context.gameplay_layer == front,
		"Direct Front terrain contact establishes the owner")
	await _check_ownership()
	await _check_manual_switching()
	await _check_natural_falling()
	await _check_interactions()
	await _check_restoration()
	world.remove_child(player)
	_expect(context.logical_layer == 0 and context.gameplay_layer == null and player.current_layer == 1,
		"Leaving the tree clears the resolved state but keeps the configured logical index")
	world.add_child(player)
	_expect(_has_layer(1) and context.gameplay_layer == null,
		"Reentering the tree restores Front solids without restoring the old owner")
	await _wait_frames(4)
	_expect(context.gameplay_layer == front, "Physical contact reestablishes Front ownership after reentry")
	_expect(context_masks_consistent, "Context listeners always observe the matching solid bits")
	world.queue_free()
	await _wait_frames(2)
	quit(1 if failed > 0 else 0)

func _check_ownership() -> void:
	_tap(KEY_SPACE)
	await _wait_frames(4)
	_expect(player.velocity.y < 0.0 and _has_layer(1) and context.gameplay_layer == null,
		"Jump immediately loses the owner and retains Front solids and support index")
	await _wait_frames(64)
	_expect(player.is_on_floor() and context.gameplay_layer == front,
		"Landing from a normal jump reacquires the grounded section")

	_add_floor(front, Vector2(3700, 520), 200)
	_add_floor(front_two, Vector2(3920, 520), 200)
	front_two.depth_scale = 0.53
	front_two.tint_strength = 0.8
	await _place(1, Vector2(3880, 520))
	var transitions := layer_events.size()
	var contexts := context_events
	Input.action_press("move_right")
	await _wait_frames(24)
	Input.action_release("move_right")
	await _wait_frames(2)
	_expect(player.position.x > 3950.0 and _has_layer(1) and context.gameplay_layer == front_two,
		"Walking across the gap establishes the second Front section without changing logical layer")
	_expect(layer_events.size() == transitions and context_events > contexts,
		"Owner changes publish context changes without a layer transition signal")
	_expect(context.depth_profile == front and _has_visual(front)
		and player.scale == Vector2.ONE and player.body_shape.global_scale == Vector2.ONE
		and player.body_shape.shape.get_rect().size == Vector2(24, 48)
		and player.camera.scale == Vector2.ONE,
		"Scaled secondary terrain with its own tint leaves the independent player's profile and physics unchanged")
	Input.action_press("move_left")
	await _wait_frames(24)
	Input.action_release("move_left")
	await _wait_frames(2)
	_expect(context.gameplay_layer == front and _has_layer(1),
		"Crossing back discards the previous section reference")
	await _place(1, Vector2(3980, 520))
	_expect(context.gameplay_layer == front_two, "Second Front section can be reacquired after another contact")
	_add_floor(front, Vector2(3940, 523), 100)
	await _wait_frames(3)
	_expect(context.gameplay_layer == front_two,
		"An overlapping section below the actual contact does not take physical ownership")
	front_two.current_layer = 2
	_expect(context.gameplay_layer == null and _has_layer(1) and context.depth_profile == front,
		"Reclassifying the confirmed owner clears it without switching the player")
	front_two.current_layer = 1
	_expect(context.gameplay_layer == null, "Restoring the section index does not infer contact")
	await _wait_frames(3)
	_expect(context.gameplay_layer == front_two, "Physical contact reacquires the reclassified section")
	world.remove_child(front_two)
	_expect(context.gameplay_layer == null and _has_layer(1) and context.owner_path.is_empty(),
		"Removing the supporting section immediately clears the owner without losing solids")
	front_two.queue_free()
	await _wait_frames(12)
	_expect(context.gameplay_layer == front,
		"Ownership changes only after the player lands on the previously overlapping section")

	var anonymous := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(120, 24)
	shape.shape = rectangle
	anonymous.position = Vector2(4310, 532)
	anonymous.add_child(shape)
	world.add_child(anonymous)
	await _place(1, Vector2(4310, 520))
	_expect(player.is_on_floor() and _has_layer(1) and context.gameplay_layer == null,
		"A valid unowned solid floor does not invent a GameplayLayer owner")

func _check_manual_switching() -> void:
	await _place(1, Vector2(160, 520))
	var events := layer_events.size()
	_tap(KEY_W)
	_expect(_has_layer(2) and context.gameplay_layer == null,
		"Grounded W switches to Middle and waits for actual destination contact")
	var transition: Tween = player.depth_visuals.get("_tween")
	_tap(KEY_W, true)
	_expect(_has_layer(2) and layer_events.size() == events + 1,
		"A repeated W event emits no transition")
	await _wait_frames(3)
	_expect(transition != null and player.depth_visuals.get("_tween") == transition
		and context.gameplay_layer == middle, "Acquiring Middle ownership does not restart the active depth tween")
	await _wait_frames(13)
	_expect(context.gameplay_layer == middle and _has_visual(middle),
		"The Middle landing sets its physical owner and interpolates to the canonical profile")
	_tap(KEY_S)
	await _wait_frames(3)
	_expect(_has_layer(1) and context.gameplay_layer == front, "Grounded S returns to Front")

	Input.action_press("move_right")
	_tap(KEY_SPACE)
	await _wait_frames(8)
	var before := player.velocity
	var x := player.position.x
	_tap(KEY_W)
	_expect(_has_layer(2) and before.y < 0.0 and player.velocity == before and context.gameplay_layer == null,
		"Airborne W preserves upward and horizontal velocities with no ground owner")
	await _wait_frames(3)
	before = player.velocity
	_tap(KEY_S)
	_expect(_has_layer(1) and player.velocity == before and player.position.x > x
		and context.gameplay_layer == null,
		"Airborne S preserves the moving jump in the other direction")
	Input.action_release("move_right")

	await _place(1, Vector2(3830, 520))
	_tap(KEY_SPACE)
	await _wait_frames(5)
	_expect_rejected(KEY_W, "An airborne destination lacking support leaves the jump intact")

	_add_floor(middle, Vector2(3760, 482), 140)
	_add_solid(middle, Vector2(3820, 425), Vector2(20, 57))
	await _place(1, Vector2(3830, 520))
	_expect_rejected(KEY_W, "A destination obstacle blocks W even with valid authored support")

	_add_floor(middle, Vector2(4380, 970), 120)
	_add_floor(front, Vector2(4380, 1008), 120)
	await _place(2, Vector2(4440, 970))
	_expect(player.is_on_floor() and context.gameplay_layer == middle,
		"Void test starts on confirmed terrain just above the boundary")
	_expect_rejected(KEY_S, "A destination below the void boundary is rejected despite having support")

	await _place(2, Vector2(895, 482))
	_tap(KEY_E)
	_expect(player.magic_orb.stored_receiver == box, "E stores the orb in the production PushBox")
	await _place(2, Vector2(500, 482))
	inspect_box_event = true
	_tap(KEY_W)
	inspect_box_event = false
	_expect(_has_layer(3) and box_event_consistent and box_context_consistent,
		"Context and layer_changed observers see both bodies and the orb already in the Back destination")
	await _wait_frames(18)
	_expect(context.gameplay_layer == back and _has_visual(back),
		"Back retains its correct physical support and canonical visual profile")
	var wall := _add_solid(middle, Vector2(box.position.x - 18.0, 435), Vector2(36, 47))
	await _wait_frames(2)
	var box_transform := box.global_transform
	var box_velocity := box.linear_velocity
	_expect_rejected(KEY_S, "An obstructed box destination rejects the entire transaction")
	_expect(box.global_transform == box_transform and box.linear_velocity == box_velocity
		and box.current_layer == 3 and box.collision_mask == 4 and player.magic_orb.stored_receiver == box,
		"Rejected synchronized S preserves the box transform, velocity, solids, and stored orb")
	wall.queue_free()
	_tap(KEY_E)
	_expect(player.magic_orb.stored_receiver == null and box.current_layer == 3,
		"E retrieves the orb and leaves the box in its current layer")

func _check_natural_falling() -> void:
	_add_floor(front, Vector2(4520, 610), 100)
	_add_floor(middle, Vector2(4520, 540), 100)
	await _place(1, Vector2(4570, 452), 46)
	_expect(_has_layer(1) and context.gameplay_layer == front and absf(player.position.y - 610.0) < 1.0,
		"Lower current-layer ground takes priority over a closer foreign platform")

	_add_floor(middle, Vector2(4660, 500), 100)
	_add_floor(back, Vector2(4660, 580), 100)
	await _place(1, Vector2(4710, 445), 30)
	_expect(_has_layer(2) and context.gameplay_layer == middle and layer_events.back() == 2,
		"A confirmed generated one-way contact selects the first eligible foreign layer and its owner")

	_add_solid(middle, Vector2(4702, 450), Vector2(16, 50))
	var prior_events := layer_events.size()
	await _place(1, Vector2(4710, 435), 0)
	var restored_each_frame := true
	for frame in range(44):
		await _wait_frames(1)
		restored_each_frame = restored_each_frame and player.collision_mask == context.solid_bit
	_expect(restored_each_frame and _has_layer(3) and context.gameplay_layer == back
		and layer_events.slice(prior_events) == [3],
		"An obstructed foreign landing never commits Middle or leaks its temporary support bit")

	_add_floor(front, Vector2(4880, 520), 120)
	_add_floor(middle, Vector2(5000, 570), 320)
	await _place(1, Vector2(4975, 520))
	prior_events = layer_events.size()
	Input.action_press("move_right")
	_tap(KEY_SPACE)
	for frame in range(72):
		await _wait_frames(1)
		if player.position.y > 570.0:
			break
	Input.action_release("move_right")
	_expect(player.position.x > 5100.0 and player.position.y > 570.0
		and _has_layer(1) and context.gameplay_layer == null and layer_events.size() == prior_events,
		"An intentional jump past a foreign platform retains its layer and solid mask")

func _check_interactions() -> void:
	var plate := world.get_node("FrontLayer/PressurePlate") as PressurePlate
	await _place(1, plate.detection_area.global_position)
	_expect(plate.is_pressed and context.gameplay_layer == front,
		"An actor with a confirmed Dynamic layer activates the production PressurePlate")
	await _place(2, plate.detection_area.global_position - Vector2(0, 38))
	_expect(not plate.is_pressed, "PressurePlate releases when the player stands on another layer")

	var pedestal := world.get_node("Pedestal") as OrbReceiver
	await _place(1, Vector2(583, 520), 12)
	_tap(KEY_E)
	_expect(pedestal.has_orb and player.magic_orb.stored_receiver == pedestal,
		"The same-layer pedestal stores the orb with Dynamic player identity")
	_tap(KEY_E)

	var checkpoint := world.get_node("Checkpoint") as Checkpoint
	await _place(2, Vector2(checkpoint.position.x, 482))
	_expect(player.checkpoint_layer == 2
		and player.checkpoint_position == checkpoint.global_position + checkpoint.respawn_offset,
		"The production checkpoint records the compatible layer and authored respawn point")

	var enemy := world.get_node("Enemy") as EnemyHazard
	var hp := player.vitals.health
	await _place(1, Vector2(enemy.global_position.x, 520))
	_expect(player.vitals.health == hp, "A foreign-layer enemy cannot damage the player")
	await _place(2, Vector2(enemy.global_position.x, 482), 8)
	_expect(player.vitals.health < hp and player._damage_landing_pending and _has_layer(2)
		and context.gameplay_layer == null,
		"The compatible enemy damages and knocks the player airborne without clearing logical solids")

	await _place(1, Vector2(160, 520))
	var landings: Array[int] = []
	player.damage_landed.connect(func(): landings.append(player.current_layer))
	player.take_hit(0.1, player.global_position - Vector2(40, 0))
	await _wait_frames(5)
	var before := player.velocity
	_tap(KEY_W)
	_expect(_has_layer(2) and player.velocity == before and player._damage_landing_pending,
		"W preserves the active knockback instead of interrupting or relaunching the player")
	await _wait_frames(64)
	_expect(landings == [2] and context.gameplay_layer == middle,
		"Landing after the knockback transition confirms Middle and emits one damage landing")

func _check_restoration() -> void:
	await _place(1, Vector2(160, 520))
	player.set_checkpoint(Vector2(160, 412), 3)
	_tap(KEY_SPACE)
	await _wait_frames(5)
	_expect(not player.is_on_floor(), "Physical death is tested during an active jump")
	_expected_restore(3)
	player.vitals.take_damage(player.vitals.max_health)
	await _wait_for_respawn()
	_expect(restore_event_consistent and _has_layer(3) and _has_visual(back)
		and player.vitals.health == player.vitals.max_health,
		"Physical death restores Back position, solids, and immediate profile before reconfirming support")
	await _wait_frames(26)
	_expect(context.gameplay_layer == back, "Physical respawn confirms Back owner only upon landing")

	player.set_checkpoint(Vector2(160, 450), 2)
	_expected_restore(2)
	player.vitals.sanity = 0.0
	player.vitals._emit_values()
	player.vitals._check_death()
	await _wait_for_respawn()
	_expect(restore_event_consistent and _has_layer(2) and _has_visual(middle)
		and player.vitals.sanity == player.vitals.max_sanity,
		"Sanity death discards the previous Back owner and restores Middle vitals and visuals")
	await _wait_frames(26)
	_expect(context.gameplay_layer == middle, "Sanity respawn confirms Middle owner only upon landing")

	player.set_checkpoint(Vector2(160, 493), 1)
	var previous_health := player.vitals.health
	player.vitals.sanity = 0.5
	player.position.y = PlayerController.VOID_Y + 1.0
	_expected_restore(1)
	player.fall_into_void()
	_expect(restore_event_consistent and _has_layer(1) and _has_visual(front)
		and player.vitals.health < previous_health and player.vitals.sanity == player.vitals.max_sanity,
		"Void fall retains its damage and sanity behaviour while restoring position, layer, and visuals")
	await _wait_frames(24)
	_expect(context.gameplay_layer == front, "Void return confirms Front contact without retaining Middle")

func _expected_restore(layer: int) -> void:
	expected_restore_layer = layer
	restore_event_consistent = false

func _on_context_changed() -> void:
	context_events += 1
	if context.logical_layer != 0:
		context_masks_consistent = context_masks_consistent and _has_layer(context.logical_layer)
	if inspect_box_event and context.logical_layer == 3:
		box_context_consistent = _matches_stored_box_destination()
	if expected_restore_layer != 0 and context.logical_layer == expected_restore_layer:
		restore_event_consistent = context.gameplay_layer == null and player.velocity == Vector2.ZERO \
			and player.global_position == player.checkpoint_position
		expected_restore_layer = 0

func _on_layer_changed(layer: int) -> void:
	layer_events.append(layer)
	if inspect_box_event:
		box_event_consistent = _matches_stored_box_destination()

func _matches_stored_box_destination() -> bool:
	return _has_layer(3) and player.position.is_equal_approx(Vector2(500, 444)) \
		and box.current_layer == 3 and box.collision_layer == 4 and box.collision_mask == 4 \
		and absf(box.global_position.y - 428.0) < 1.0 \
		and player.magic_orb.get_parent() == box \
		and player.magic_orb.global_position.is_equal_approx(box.orb_anchor.global_position) \
		and context.depth_profile == back and player.depth_visuals.get("_active_profile") == back

func _expect_rejected(key: Key, message: String) -> void:
	var layer := player.current_layer
	var position := player.global_position
	var old_velocity := player.velocity
	var owner := context.gameplay_layer
	var events := layer_events.size()
	var contexts := context_events
	_tap(key)
	_expect(_has_layer(layer) and player.global_position == position and player.velocity == old_velocity
		and context.gameplay_layer == owner and layer_events.size() == events and context_events == contexts, message)

func _has_layer(layer: int) -> bool:
	var solid := GameplayLayer.solid_collision_bit(layer)
	return player.current_layer == layer and context.logical_layer == layer and context.solid_bit == solid \
		and context.ground_support_bit == GameplayLayer.landing_surface_bit(layer) \
		and player.collision_layer == solid and player.collision_mask == solid

func _has_visual(profile: GameplayLayer) -> bool:
	return context.depth_profile == profile \
		and player.depth_visuals.scale.is_equal_approx(Vector2.ONE * profile.depth_scale) \
		and player.depth_visuals.modulate.is_equal_approx(profile.depth_modulation())

func _place(layer: int, point: Vector2, frames := 4) -> void:
	player.cancel_damage_reaction()
	player.set_checkpoint(point, layer)
	player.restore_checkpoint()
	if frames > 0:
		await _wait_frames(frames)

func _add_floor(section: GameplayLayer, point: Vector2, width: float) -> void:
	var polygon := _make_polygon(section, point, Vector2(width, 90))
	polygon.set_script(TERRAIN)
	polygon.set("supports_other_layers", true)
	section.add_child(polygon)

func _add_solid(section: GameplayLayer, point: Vector2, size: Vector2) -> CollisionPolygon2D:
	var polygon := _make_polygon(section, point, size)
	section.add_child(polygon)
	return polygon

func _make_polygon(section: GameplayLayer, point: Vector2, size: Vector2) -> CollisionPolygon2D:
	var polygon := CollisionPolygon2D.new()
	polygon.position = section.to_local(point)
	var points := PackedVector2Array()
	for offset in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		points.append(section.to_local(point + offset) - polygon.position)
	polygon.polygon = points
	return polygon

func _tap(key: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _wait_for_respawn() -> void:
	for frame in range(420):
		await physics_frame
		if not world.get("_respawn_in_progress") and player.vitals.sanity > 0.0:
			return

func _wait_frames(count: int) -> void:
	for frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failed += 1
		push_error("FAIL: " + message)

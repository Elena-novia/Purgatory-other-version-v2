extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const TERRAIN_SCRIPT := preload("res://scripts/world/terrain_polygon.gd")
const TEST_X := 4200.0

var player: PlayerController
var box: PushBox
var layers: Array[GameplayLayer]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	box = main.get_node("Box")
	layers = [main.get_node("FrontLayer"), main.get_node("MiddleLayer"), main.get_node("BackLayer")]
	await _wait_frames(4)

	await _check_jump_with_motion(KEY_W, 1, 2, Vector2(150, 520), 482.0, KEY_D, 10)
	await _check_jump_with_motion(KEY_S, 2, 1, Vector2(570, 482), 520.0, KEY_A, 34)
	await _check_simultaneous_jump(KEY_W, 1, 2, Vector2(160, 520), 482.0)
	await _check_simultaneous_jump(KEY_S, 2, 1, Vector2(160, 482), 520.0)
	await _check_uneven_layers()
	await _check_airborne_rejection()
	await _check_falling_transition()
	await _check_orb_sync()

	if failures.is_empty():
		print("Airborne layer transitions: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_jump_with_motion(key: Key, from_layer: int, target: int, point: Vector2,
		floor_y: float, movement: Key, jump_frames: int) -> void:
	await _place_on(from_layer, point)
	_key_event(movement, true)
	await _jump(jump_frames)
	var phase := "ascending" if key == KEY_W else "descending"
	_expect(not player.is_on_floor() and (player.velocity.y < 0.0) == (key == KEY_W)
		and not is_zero_approx(player.velocity.x), "Space and A/D are active while %s" % phase)
	var before := player.global_position
	var velocity_before := player.velocity
	var label := "W" if key == KEY_W else "S"
	_key_event(key, true)
	Input.flush_buffered_events()
	_expect(_has_layer(target), "%s changes exactly one layer while %s" % [label, phase])
	_expect(player.velocity == velocity_before, "%s preserves the full velocity vector" % label)
	_expect(player.global_position.is_equal_approx(before + Vector2(0, floor_y - point.y)),
		"%s keeps the player's height relative to the matching floor" % label)
	_key_event(key, true, true)
	_key_event(key, false)
	Input.flush_buffered_events()
	_expect(_has_layer(target), "Holding %s does not trigger a second transition" % label)
	var shifted := player.global_position
	await _wait_frames(4)
	_expect(not player.is_on_floor() and (player.global_position.x - shifted.x) * velocity_before.x > 0.0,
		"A/D remains responsive after changing layers")
	var gravity_step := player.get_gravity().y * 4.0 / Engine.physics_ticks_per_second
	_expect(absf(player.velocity.y - (velocity_before.y + gravity_step)) < 0.05,
		"The same gravity continues advancing the jump")
	_key_event(movement, false)
	Input.flush_buffered_events()
	await _expect_landing(target, floor_y, "The jump lands on the selected layer")

func _check_simultaneous_jump(key: Key, from_layer: int, target: int, point: Vector2, floor_y: float) -> void:
	await _place_on(from_layer, point)
	_key_event(KEY_SPACE, true)
	_key_event(key, true)
	_key_event(key, false)
	_key_event(KEY_SPACE, false)
	Input.flush_buffered_events()
	await _wait_frames(5)
	var label := "W" if key == KEY_W else "S"
	_expect(_has_layer(target) and not player.is_on_floor() and player.velocity.y < 0.0,
		"Space and %s pressed in the same frame start a jump on layer %d" % [label, target])
	await _expect_landing(target, floor_y, "The simultaneous jump finishes on layer %d" % target)

func _check_uneven_layers() -> void:
	var source := _add_floor(1, Vector2(TEST_X, 556), 400.0)
	var target := _add_floor(2, Vector2(TEST_X, 504), 400.0)
	await _wait_frames(2)
	await _place_on(1, Vector2(TEST_X + 100.0, 556))
	_tap(KEY_SPACE)
	for _i in range(4):
		await physics_frame
		if not player.is_on_floor() and player.velocity.y < 0.0:
			break
	var before := player.global_position
	var velocity_before := player.velocity
	_tap(KEY_W)
	_expect(_has_layer(2) and player.velocity == velocity_before and player.velocity.y < 0.0
		and absf(player.global_position.y - (before.y - 52.0)) < 0.05,
		"An early airborne W keeps the jump height when the platforms are 52 px apart (%s to %s)" % [
			before, player.global_position
		])
	await _expect_landing(2, 504.0, "The shifted jump ends on the edited middle platform")
	source.queue_free()
	target.queue_free()
	await _wait_frames(2)

func _check_airborne_rejection() -> void:
	var source := _add_floor(1, Vector2(TEST_X, 520), 400.0)
	await _wait_frames(2)
	await _place_on(1, Vector2(TEST_X + 100.0, 520))
	await _jump(10)
	_expect_blocked(KEY_W, 1, "An airborne W into a gap preserves layer, position and velocity")
	var far_floor := _add_floor(2, Vector2(TEST_X, 670), 400.0)
	await _wait_frames(2)
	_expect_blocked(KEY_W, 1, "An airborne W rejects support outside the landing range")
	far_floor.queue_free()

	var destination := _add_floor(2, Vector2(TEST_X, 482), 400.0)
	var wall := _add_wall(2, Vector2(TEST_X + 84.0, 320.0), Vector2(32, 162))
	await _wait_frames(2)
	_expect_blocked(KEY_W, 1, "An obstacle covering the airborne destination still blocks W")
	await _expect_landing(1, 520.0, "Rejections let the original jump finish")
	source.queue_free()
	destination.queue_free()
	wall.queue_free()
	await _wait_frames(2)

func _check_falling_transition() -> void:
	var source := _add_floor(1, Vector2(TEST_X, 520), 120.0)
	var destination := _add_floor(2, Vector2(TEST_X + 130.0, 560), 420.0)
	await _wait_frames(2)
	await _place_on(1, Vector2(TEST_X + 100.0, 520))
	Input.action_press("move_right")
	for _i in range(24):
		await physics_frame
		if player.global_position.x > TEST_X + 143.0 and not player.is_on_floor():
			break
	var before := player.global_position
	var velocity_before := player.velocity
	_tap(KEY_W)
	_expect(velocity_before.y > 0.0 and _has_layer(2) and player.velocity == velocity_before
		and absf(player.global_position.y - before.y + player.layer_transition_offset) < 0.05,
		"W preserves downward motion when only the destination has ground beneath the player")
	Input.action_release("move_right")
	await _expect_landing(2, 560.0, "The player finishes the fall on the chosen destination platform")
	source.queue_free()
	destination.queue_free()
	await _wait_frames(2)

func _check_orb_sync() -> void:
	await _place_on(2, Vector2(895, 482))
	_tap(KEY_E)
	_expect(box.stored_orb and player.magic_orb.get_parent() == box, "E stores the orb in the production box")
	await _place_on(2, Vector2(500, 482))
	await _jump(10)
	var box_x := box.global_position.x
	var velocity_before := player.velocity
	_tap(KEY_W)
	_expect(_has_layer(3) and box.current_layer == 3 and box.collision_mask == 4
		and is_equal_approx(box.global_position.x, box_x) and player.velocity == velocity_before,
		"An airborne W synchronizes the distant box without changing player velocity")
	_expect(player.magic_orb.get_parent() == box
		and player.magic_orb.global_position.is_equal_approx(box.orb_anchor.global_position),
		"The orb stays on its anchor through the airborne transition")
	var blocker := _add_wall(2, Vector2(box_x - 20.0, 435.0), Vector2(40, 46))
	await _wait_frames(2)
	_expect_blocked(KEY_S, 3, "An invalid box destination blocks both shifts and preserves the jump")
	blocker.queue_free()
	await _wait_frames(2)

	var box_transform := box.global_transform
	box_transform.origin.x = 4800.0
	box.global_transform = box_transform
	PhysicsServer2D.body_set_state(box.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, box_transform)
	await _wait_frames(2)
	_expect_blocked(KEY_S, 3, "An airborne S is also atomic when only the box lacks ground")
	box_transform.origin.x = box_x
	box.global_transform = box_transform
	PhysicsServer2D.body_set_state(box.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, box_transform)
	await _wait_frames(2)
	velocity_before = player.velocity
	_tap(KEY_S)
	_expect(_has_layer(2) and box.current_layer == 2 and box.collision_mask == 2
		and player.velocity == velocity_before and player.magic_orb.get_parent() == box,
		"An airborne S succeeds once both destinations are valid")
	await _expect_landing(2, 482.0, "The player lands with the orb still stored in the synchronized box")

func _has_layer(expected: int) -> bool:
	var bit := 1 << (expected - 1)
	return player.current_layer == expected and player.collision_layer == bit and player.collision_mask == bit

func _expect_landing(layer: int, floor_y: float, message: String) -> void:
	for _i in range(60):
		await physics_frame
		if player.is_on_floor():
			break
	_expect(_has_layer(layer) and player.is_on_floor()
		and absf(player.global_position.y - floor_y) < 0.5, message)

func _expect_blocked(key: Key, layer: int, message: String) -> void:
	var point := player.global_position
	var speed := player.velocity
	var box_point := box.global_position
	var box_layer := box.current_layer
	_tap(key)
	_expect(not player.is_on_floor() and _has_layer(layer) and player.global_position == point
		and player.velocity == speed and box.current_layer == box_layer and box.global_position == box_point, message)

func _place_on(layer: int, point: Vector2) -> void:
	player.current_layer = layer
	player._apply_layer_mask()
	player.global_position = point
	player.velocity = Vector2.ZERO
	await _wait_frames(4)
	_expect(player.is_on_floor(), "Starts supported on layer %d" % layer)

func _jump(frames: int) -> void:
	_tap(KEY_SPACE)
	await _wait_frames(frames)

func _tap(key: Key) -> void:
	_key_event(key, true)
	_key_event(key, false)
	Input.flush_buffered_events()

func _key_event(key: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _add_floor(layer: int, point: Vector2, width: float) -> CollisionPolygon2D:
	var ground := _make_polygon(layer, point, Vector2(width, 100))
	ground.set_script(TERRAIN_SCRIPT)
	ground.set("supports_other_layers", true)
	ground.set("fill_color", Color("51475e"))
	layers[layer - 1].add_child(ground)
	return ground

func _add_wall(layer: int, point: Vector2, dimensions: Vector2) -> CollisionPolygon2D:
	var wall := _make_polygon(layer, point, dimensions)
	layers[layer - 1].add_child(wall)
	return wall

func _make_polygon(layer: int, point: Vector2, size: Vector2) -> CollisionPolygon2D:
	var polygon := CollisionPolygon2D.new()
	polygon.position = layers[layer - 1].to_local(point)
	polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	return polygon

func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

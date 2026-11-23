extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const TERRAIN_SCRIPT := preload("res://scripts/world/terrain_polygon.gd")
const START_X := 4200.0
const LANDING_X := START_X + 145.0
const FALLBACK_Y := 595.0

var failures: Array[String] = []
var player: PlayerController
var layers: Array[GameplayLayer]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	layers = [main.get_node("FrontLayer"), main.get_node("MiddleLayer"), main.get_node("BackLayer")]
	var box: PushBox = main.get_node("Box")
	await _wait_frames(5)

	await _check_normal_jump(1)
	await _check_normal_jump(2)
	await _check_knockback_with_ground()
	await _check_uneven_ground_transitions()
	await _check_foreign_wall()
	await _check_drop(1, 2)
	await _check_drop(1, 3)
	await _check_drop(2, 3, true)

	_spawn_on(2, Vector2(900, 482))
	await _wait_frames(4)
	_press_key(KEY_E)
	await _wait_frames(2)
	_expect(box.stored_orb_instance == player.magic_orb, "E stores the orb in the production box")
	var box_x := box.global_position.x
	_press_key(KEY_W)
	await _wait_frames(3)
	_expect(player.current_layer == 3 and box.current_layer == 3, "W moves player and stored box together")
	_press_key(KEY_S)
	await _wait_frames(3)
	_expect(player.current_layer == 2 and box.current_layer == 2, "S moves player and stored box together")

	var landing_floor := await _check_drop(2, 3, false, true)
	_expect(box.current_layer == 3 and is_equal_approx(box.global_position.x, box_x)
		and player.magic_orb.get_parent() == box,
		"A distant stored box follows the completed fall and keeps its own X position and orb")
	var return_floor := _add_platform(2, Vector2(LANDING_X, FALLBACK_Y + player.layer_transition_offset), 450.0)
	await _wait_frames(2)
	_press_key(KEY_S)
	await _wait_frames(2)
	_expect(player.current_layer == 2 and box.current_layer == 2,
		"S still works after a synchronized fall when the destination has ground")
	landing_floor.queue_free()
	return_floor.queue_free()

	await _check_blocked_box_fallback(box)
	await _check_void()

	if failures.is_empty():
		print("Conditional cross-layer ground: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_normal_jump(layer_number: int) -> void:
	var floor_y := layers[layer_number - 1].position.y
	_spawn_on(layer_number, Vector2(150, floor_y))
	await _wait_frames(3)
	_press_key(KEY_SPACE)
	await _wait_frames(8)
	_expect(not player.is_on_floor() and player.global_position.y < floor_y - 15.0,
		"Space starts a normal jump on layer %d" % layer_number)
	await _wait_frames(65)
	_expect(player.is_on_floor() and player.current_layer == layer_number
		and absf(player.global_position.y - floor_y) < 0.5,
		"Overlapping foreign ground does not catch a layer %d jump" % layer_number)

func _check_knockback_with_ground() -> void:
	_spawn_on(1, Vector2(270, 520))
	await _wait_frames(4)
	player.take_hit(0.1, player.global_position - Vector2(40, 0))
	await _wait_frames(8)
	_expect(not player.is_on_floor() and player.global_position.y < 500.0,
		"Damage launches the player with the existing knockback")
	await _wait_frames(65)
	_expect(player.is_on_floor() and player.current_layer == 1 and absf(player.global_position.y - 520.0) < 0.5,
		"Ordinary knockback lands on the current layer through overlapping foreign floors")

func _check_uneven_ground_transitions() -> void:
	var front := _add_platform(1, Vector2(START_X, 556), 400.0)
	var middle := _add_platform(2, Vector2(START_X, 504), 400.0)
	var back := _add_platform(3, Vector2(START_X, 467), 400.0)
	await _wait_frames(2)
	_spawn_on(1, Vector2(START_X + 100.0, 556))
	await _wait_frames(4)
	for step in [Vector3i(KEY_S, 1, 556), Vector3i(KEY_W, 2, 504), Vector3i(KEY_W, 3, 467),
		Vector3i(KEY_W, 3, 467), Vector3i(KEY_S, 2, 504), Vector3i(KEY_S, 1, 556)]:
		_press_key(step.x)
		_press_key(step.x, true)
		await _wait_frames(3)
		_expect(player.current_layer == step.y and player.collision_mask == (1 << (step.y - 1))
			and absf(player.global_position.y - step.z) < 0.5,
			"W/S obeys single-step input and authored terrain height on layer %d at Y=%d" % [step.y, step.z])
	front.queue_free()
	middle.queue_free()
	back.queue_free()
	await _wait_frames(2)

func _check_drop(from_layer: int, to_layer: int, knockback := false, keep_landing_floor := false) -> CollisionPolygon2D:
	var source_y := layers[from_layer - 1].position.y
	var source := _add_platform(from_layer, Vector2(START_X, source_y), 120.0)
	var destination := _add_platform(to_layer, Vector2(LANDING_X, FALLBACK_Y), 450.0)
	await _wait_frames(2)
	_spawn_on(from_layer, Vector2(START_X + 103.0, source_y))
	await _wait_frames(4)
	_expect(player.is_on_floor(), "Starts supported before falling off layer %d" % from_layer)
	if knockback:
		player.take_hit(0.1, player.global_position - Vector2(40, 0))
	else:
		Input.action_press("move_right")
	var saw_fall := false
	for _frame in range(85):
		await physics_frame
		saw_fall = saw_fall or (not player.is_on_floor() and player.velocity.y > 0.0)
		if player.current_layer == to_layer:
			break
	Input.action_release("move_right")
	await _wait_frames(5)
	_expect(saw_fall and player.is_on_floor() and player.current_layer == to_layer
		and absf(player.global_position.y - FALLBACK_Y) < 0.5
		and player.collision_layer == (1 << (to_layer - 1)) and player.collision_mask == player.collision_layer,
		"%s from layer %d lands on layer %d and adopts its identity at %s" % [
			"Knockback over a gap" if knockback else "Walking off an edge", from_layer, to_layer, player.global_position])
	source.queue_free()
	if keep_landing_floor:
		return destination
	destination.queue_free()
	await _wait_frames(2)
	return null

func _check_blocked_box_fallback(box: PushBox) -> void:
	var source := _add_platform(2, Vector2(START_X, 482), 120.0)
	var destination := _add_platform(3, Vector2(LANDING_X, FALLBACK_Y), 450.0)
	var blocker := _add_wall(3, Vector2(box.global_position.x - 18.0, 395.0), Vector2(36, 50))
	await _wait_frames(2)
	_spawn_on(2, Vector2(START_X + 103.0, 482))
	await _wait_frames(4)
	var starting_health := player.vitals.health
	Input.action_press("move_right")
	var reached_fallback := false
	for _frame in range(95):
		await physics_frame
		reached_fallback = reached_fallback or player.current_layer == 3 or box.current_layer == 3
		if player.vitals.health < starting_health:
			break
	Input.action_release("move_right")
	_expect(not reached_fallback and box.current_layer == 2 and player.vitals.health < starting_health
		and player.global_position.is_equal_approx(player.checkpoint_position)
		and not box.stored_orb and player.magic_orb.get_parent() == player,
		"Blocked box skips the fallback without a partial shift and retrieves the orb on checkpoint return")
	source.queue_free()
	destination.queue_free()
	blocker.queue_free()
	await _wait_frames(2)

func _check_void() -> void:
	var source := _add_platform(1, Vector2(START_X, 520), 120.0)
	await _wait_frames(2)
	_spawn_on(1, Vector2(START_X + 103.0, 520))
	await _wait_frames(4)
	_expect(player.is_on_floor(), "Starts on solid ground before walking into the void")
	var starting_health := player.vitals.health
	Input.action_press("move_right")
	for _frame in range(95):
		await physics_frame
		if player.vitals.health < starting_health:
			break
	Input.action_release("move_right")
	_expect(player.vitals.health < starting_health
		and player.global_position.is_equal_approx(player.checkpoint_position),
		"Walking off an edge with no lower ground still applies void damage and returns the player to the checkpoint")
	source.queue_free()

func _check_foreign_wall() -> void:
	var front_floor := _add_platform(1, Vector2(START_X, 520), 400.0)
	var middle_floor := _add_platform(2, Vector2(START_X, 480), 400.0)
	var wall := _add_wall(2, Vector2(START_X + 60.0, 380.0), Vector2(30, 100))
	await _wait_frames(2)
	_spawn_on(1, Vector2(START_X + 75.0, 520))
	await _wait_frames(3)
	_press_key(KEY_W)
	await _wait_frames(2)
	_expect(player.current_layer == 1, "W rejects a wall even when the destination has an authored floor")
	_spawn_on(1, Vector2(START_X + 25.0, 520))
	await _wait_frames(3)
	Input.action_press("move_right")
	await _wait_frames(35)
	Input.action_release("move_right")
	_expect(player.global_position.x > START_X + 100.0 and player.current_layer == 1,
		"The middle-layer wall does not obstruct a FrontLayer player")
	front_floor.queue_free()
	middle_floor.queue_free()
	wall.queue_free()
	await _wait_frames(2)

func _add_platform(layer_number: int, point: Vector2, width: float) -> CollisionPolygon2D:
	var ground := _make_polygon(layer_number, point, Vector2(width, 100))
	ground.set_script(TERRAIN_SCRIPT)
	ground.set("supports_other_layers", true)
	ground.set("fill_color", Color("51475e"))
	layers[layer_number - 1].add_child(ground)
	return ground

func _add_wall(layer_number: int, point: Vector2, size: Vector2) -> CollisionPolygon2D:
	var wall := _make_polygon(layer_number, point, size)
	layers[layer_number - 1].add_child(wall)
	return wall

func _make_polygon(layer_number: int, point: Vector2, size: Vector2) -> CollisionPolygon2D:
	var polygon := CollisionPolygon2D.new()
	polygon.position = layers[layer_number - 1].to_local(point)
	polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	return polygon

func _spawn_on(layer_number: int, point: Vector2) -> void:
	player.cancel_damage_reaction()
	player.current_layer = layer_number
	player._apply_layer_mask()
	player.global_position = point
	player.velocity = Vector2.ZERO

func _press_key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)

func _wait_frames(frames: int) -> void:
	for _frame in range(frames):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

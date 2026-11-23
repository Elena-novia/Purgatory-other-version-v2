extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const TERRAIN_SCRIPT := preload("res://scripts/world/terrain_polygon.gd")
const PLATFORM_X := 4200.0
const PLAYER_X := 4300.0
const BOX_X := 4650.0
const FRONT_Y := 538.0
const MIDDLE_Y := 500.0
const BACK_Y := 462.0

var failures: Array[String] = []
var player: PlayerController
var box: PushBox
var layers: Array[GameplayLayer]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	box = main.get_node("Box")
	layers = [main.get_node("FrontLayer"), main.get_node("MiddleLayer"), main.get_node("BackLayer")]
	_add_platform(2, Vector2(PLATFORM_X, MIDDLE_Y), 600.0)
	await _wait_frames(3)

	_spawn_on(2, Vector2(PLAYER_X, MIDDLE_Y))
	await _wait_frames(4)
	var starting_health := player.vitals.health
	await _expect_blocked(KEY_W, "W rejects a gap in the back layer")
	await _expect_blocked(KEY_S, "S rejects a gap in the front layer")
	await _wait_frames(75)
	_expect(player.is_on_floor() and player.current_layer == 2 and player.vitals.health == starting_health,
		"Rejected transitions leave the player safely on the source floor")

	var low_source := _add_platform(2, Vector2(PLATFORM_X, 980.0), 400.0)
	var floor_below_void := _add_platform(1, Vector2(PLATFORM_X, 1018.0), 400.0)
	await _wait_frames(2)
	_spawn_on(2, Vector2(PLAYER_X, 980.0))
	await _wait_frames(4)
	await _expect_blocked(KEY_S, "Ground beyond the void boundary is not a safe destination")
	low_source.queue_free()
	floor_below_void.queue_free()
	_spawn_on(2, Vector2(PLAYER_X, MIDDLE_Y))
	await _wait_frames(2)

	var invalid_floor := _add_platform(3, Vector2(PLAYER_X - 2.0, BACK_Y), 4.0)
	await _wait_frames(2)
	await _expect_blocked(KEY_W, "Ground below the center alone is too narrow for the player's footprint")
	invalid_floor.queue_free()
	invalid_floor = _add_platform(3, Vector2(PLATFORM_X, BACK_Y + 140.0), 400.0)
	await _wait_frames(2)
	await _expect_blocked(KEY_W, "A platform far below the intended landing position is rejected")
	invalid_floor.queue_free()

	var obstacle := CollisionPolygon2D.new()
	obstacle.position = layers[2].to_local(Vector2(PLAYER_X - 24.0, BACK_Y))
	obstacle.polygon = PackedVector2Array([Vector2.ZERO, Vector2(48, 0), Vector2(48, 65), Vector2(0, 65)])
	layers[2].add_child(obstacle)
	await _wait_frames(2)
	await _expect_blocked(KEY_W, "A solid obstacle without a walkable surface is not treated as ground")
	obstacle.queue_free()

	var back_floor := _add_platform(3, Vector2(PLATFORM_X, BACK_Y), 400.0)
	var front_floor := _add_platform(1, Vector2(PLATFORM_X, FRONT_Y), 400.0)
	await _wait_frames(2)
	_press(KEY_W)
	await _wait_frames(3)
	_expect_layer(3, BACK_Y, "W lands on nearby walkable back ground")
	await _expect_blocked(KEY_W, "W observes the layer 3 boundary")
	_press(KEY_S)
	await _wait_frames(3)
	_expect_layer(2, MIDDLE_Y, "S returns to walkable middle ground")
	_press(KEY_S)
	await _wait_frames(3)
	_expect_layer(1, FRONT_Y, "S lands on walkable front ground")
	await _expect_blocked(KEY_S, "S observes the layer 1 boundary")

	back_floor.polygon = PackedVector2Array([Vector2(0, 20), Vector2(400, -20), Vector2(400, 100), Vector2(0, 100)])
	await _wait_frames(2)
	_press(KEY_W)
	await _wait_frames(3)
	_press(KEY_W)
	await _wait_frames(4)
	_expect_layer(3, BACK_Y + 10.0, "W fits the player's collision shape to a walkable slope")

	_spawn_on(2, Vector2(900, 482))
	await _wait_frames(4)
	_press(KEY_E)
	await _wait_frames(3)
	_expect(box.stored_orb, "The production box contains the orb")
	_spawn_on(2, Vector2(PLAYER_X, MIDDLE_Y))
	var box_start := box.global_transform
	box_start.origin = Vector2(BOX_X, MIDDLE_Y - 16.0)
	box.global_transform = box_start
	PhysicsServer2D.body_set_state(box.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, box_start)
	box.linear_velocity = Vector2.ZERO
	await _wait_frames(4)

	await _expect_blocked(KEY_W, "W keeps both bodies in place when only the box has a gap")
	front_floor.queue_free()
	_add_platform(1, Vector2(BOX_X - 55.0, FRONT_Y), 110.0)
	await _wait_frames(2)
	await _expect_blocked(KEY_S, "S keeps both bodies in place when only the player has a gap")

	_add_platform(3, Vector2(BOX_X - 55.0, BACK_Y + 11.0), 110.0)
	await _wait_frames(2)
	_press(KEY_W)
	await _wait_frames(5)
	_expect_layer(3, BACK_Y + 10.0, "W moves the player once both destinations have ground")
	_expect(box.current_layer == 3 and box.collision_layer == 4 and box.collision_mask == 4
		and box.global_position.distance_to(Vector2(BOX_X, BACK_Y + 11.0 - 16.0)) < 0.5
		and player.magic_orb.get_parent() == box,
		"The stored box aligns to its own platform while keeping its X position and orb")

	if failures.is_empty():
		print("Manual destination ground: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect_blocked(key: Key, message: String) -> void:
	var layer := player.current_layer
	var point := player.global_position
	var box_layer := box.current_layer
	var box_point := box.global_position
	_press(key)
	await _wait_frames(4)
	_expect(player.current_layer == layer and player.global_position.is_equal_approx(point)
		and player.collision_mask == (1 << (layer - 1))
		and box.current_layer == box_layer and box.global_position.is_equal_approx(box_point), message)

func _expect_layer(layer: int, y: float, message: String) -> void:
	_expect(player.current_layer == layer and player.collision_layer == (1 << (layer - 1))
		and player.collision_mask == player.collision_layer and player.is_on_floor()
		and absf(player.global_position.y - y) < 0.6, message + " at %s" % player.global_position)

func _add_platform(layer: int, point: Vector2, width: float) -> CollisionPolygon2D:
	var platform := CollisionPolygon2D.new()
	var parent := layers[layer - 1]
	platform.set_script(TERRAIN_SCRIPT)
	platform.set("supports_other_layers", true)
	platform.set("fill_color", Color("51475e"))
	platform.position = parent.to_local(point)
	platform.polygon = PackedVector2Array([Vector2.ZERO, Vector2(width, 0), Vector2(width, 100), Vector2(0, 100)])
	parent.add_child(platform)
	return platform

func _spawn_on(layer: int, point: Vector2) -> void:
	player.current_layer = layer
	player._apply_layer_mask()
	player.global_position = point
	player.velocity = Vector2.ZERO

func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)

func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

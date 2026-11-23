extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: PlayerController = main.get_node("Player")

	_set_player_layer(player, 1, Vector2(160, 520))
	player.current_layer = 0
	_expect(player.current_layer == 1, "Player layer index is clamped to the 1–3 range")
	player.current_layer = 4
	_expect(player.current_layer == 3, "Player layer index cannot exceed Layer 3")
	_set_player_layer(player, 1, Vector2(160, 520))
	player.try_change_layer(-1)
	_expect(player.current_layer == 1, "S at Layer 1 stays on Layer 1")
	player.try_change_layer(1)
	_expect(player.current_layer == 2, "W moves Layer 1 to Layer 2")
	_expect(is_equal_approx(player.global_position.y, 482.0) and player.collision_layer == 2, "Layer 2 transition synchronizes position and collision mask")
	await physics_frame
	player.try_change_layer(1)
	_expect(player.current_layer == 3, "W moves Layer 2 to Layer 3")
	_expect(is_equal_approx(player.global_position.y, 444.0) and player.collision_layer == 4, "Layer 3 transition synchronizes position and collision mask")
	await physics_frame
	player.try_change_layer(1)
	_expect(player.current_layer == 3, "W at Layer 3 stays on Layer 3")
	player.try_change_layer(-1)
	_expect(player.current_layer == 2, "S moves Layer 3 to Layer 2")
	await physics_frame
	player.try_change_layer(-1)
	_expect(player.current_layer == 1, "S moves Layer 2 to Layer 1")
	await physics_frame
	player.try_change_layer(-1)
	_expect(player.current_layer == 1, "S at Layer 1 stays on Layer 1")

	_set_player_layer(player, 1, Vector2(160, 520))
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.physical_keycode = KEY_W
	player._unhandled_input(key_event)
	_expect(player.current_layer == 2, "A W press changes one layer")
	key_event.echo = true
	player._unhandled_input(key_event)
	_expect(player.current_layer == 2, "Held W echo does not skip a layer")
	await physics_frame
	_set_player_layer(player, 3, Vector2(160, 444))
	await physics_frame
	key_event = InputEventKey.new()
	key_event.pressed = true
	key_event.physical_keycode = KEY_S
	player._unhandled_input(key_event)
	_expect(player.current_layer == 2, "A S press changes one layer")
	key_event.echo = true
	player._unhandled_input(key_event)
	_expect(player.current_layer == 2, "Held S echo does not skip a layer")
	await physics_frame

	var box: PushBox = main.get_node("Box")
	box.stored_orb = true
	_expect(box.try_shift_layer(3), "Orb-carrying box can shift to Layer 3")
	_expect(box.current_layer == 3 and box.collision_layer == 4, "Box layer shift synchronizes its collision mask")
	var box_moved_to_front := box.try_shift_layer(1)
	_expect(box_moved_to_front and absf(box.global_position.y - 504.0) < 2.0, "Box can move two adjacent steps while remaining within the layer range")

	var middle: GameplayLayer = main.get_node("MiddleLayer")
	var obstacle := CollisionPolygon2D.new()
	obstacle.position.x = 850.0
	obstacle.polygon = PackedVector2Array([Vector2(-27, -152), Vector2(27, -152), Vector2(27, 0), Vector2(-27, 0)])
	middle.add_child(obstacle)
	_set_player_layer(player, 1, Vector2(850, 520))
	await physics_frame
	player.try_change_layer(1)
	_expect(player.current_layer == 1, "An occupied destination blocks the transition")
	_expect(is_equal_approx(player.global_position.y, 520.0), "A blocked transition preserves player position")
	obstacle.queue_free()

	_set_player_layer(player, 1, Vector2(160, 520))
	await physics_frame
	await physics_frame
	var start_x := player.global_position.x
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	_expect(player.global_position.x > start_x, "D movement remains independent of layer movement")
	await physics_frame
	await physics_frame
	await physics_frame
	var jump_event := InputEventKey.new()
	jump_event.pressed = true
	jump_event.physical_keycode = KEY_SPACE
	Input.parse_input_event(jump_event)
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	_expect(player.velocity.y < 0.0, "Space jump remains independent of layer movement")

	if failures.is_empty():
		print("Layer controls: all validation checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _set_player_layer(player: PlayerController, layer_number: int, point: Vector2) -> void:
	player.current_layer = layer_number
	player._apply_layer_mask()
	player.global_position = point
	player.velocity = Vector2.ZERO

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

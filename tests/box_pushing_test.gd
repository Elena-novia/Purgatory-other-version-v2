extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const BOX_SCENE := preload("res://scenes/interactables/box.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: PlayerController = main.get_node("Player")
	var box: PushBox = main.get_node("Box") as PushBox
	player.current_layer = 2
	player._apply_layer_mask()
	# Start between the layer's tall pillar and the box, clear of both shapes.
	player.global_position = Vector2(900, 482)
	player.velocity = Vector2.ZERO
	box.linear_velocity = Vector2.ZERO
	await physics_frame
	player.magic_orb.toggle_release_or_retrieve()
	_expect(box.stored_orb, "The test box stores the orb before pushing")
	var initial_box_x := box.global_position.x
	Input.action_press("move_right")
	for _frame in range(45):
		await physics_frame
	Input.action_release("move_right")
	_expect(box.global_position.x > initial_box_x + 8.0, "D pushes the box smoothly to the right")
	_expect(player.global_position.x < box.global_position.x, "The player remains behind the box while pushing")
	_expect(player.facing_direction == 1.0, "Facing direction tracks the last horizontal input")
	_expect(player.magic_orb.global_position.distance_to(box.orb_anchor.global_position) < 0.01, "The stored orb follows the pushed box")
	var box_speed_after_push := absf(box.linear_velocity.x)
	_expect(box_speed_after_push > 0.0 and box_speed_after_push <= box.max_push_speed, "Push acceleration respects the configured box speed limit")
	var x_at_release := box.global_position.x
	for _frame in range(15):
		await physics_frame
	_expect(absf(box.global_position.x - x_at_release) < 20.0, "Idle braking stops the box shortly after input is released")
	_expect(absf(box.linear_velocity.x) <= box.stopping_velocity_threshold, "The stopping threshold removes residual horizontal velocity")
	var x_after_stopping := box.global_position.x
	for _frame in range(20):
		await physics_frame
	_expect(absf(box.global_position.x - x_after_stopping) < 0.1, "The stationary box does not jitter after braking")

	var wall := StaticBody2D.new()
	wall.collision_layer = box.collision_layer
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var wall_rectangle := RectangleShape2D.new()
	wall_rectangle.size = Vector2(24, 90)
	wall_shape.shape = wall_rectangle
	wall.add_child(wall_shape)
	wall.global_position = box.global_position + Vector2(100, 0)
	main.add_child(wall)
	await physics_frame
	var wall_left_edge := wall.global_position.x - wall_rectangle.size.x * 0.5
	Input.action_press("move_right")
	for _frame in range(90):
		await physics_frame
	Input.action_release("move_right")
	_expect(box.global_position.x + 17.0 <= wall_left_edge + 2.0, "The box stops at a solid wall")

	wall.queue_free()
	await physics_frame
	box.linear_velocity = Vector2.ZERO
	player.global_position = Vector2(box.global_position.x + 70.0, 482)
	player.velocity = Vector2.ZERO
	await physics_frame
	var initial_left_push_x := box.global_position.x
	Input.action_press("move_left")
	for _frame in range(45):
		await physics_frame
	Input.action_release("move_left")
	_expect(box.global_position.x < initial_left_push_x - 8.0, "A pushes the box smoothly to the left")
	_expect(player.facing_direction == -1.0, "Facing direction remains left after the player stops")
	var x_after_left_release := box.global_position.x
	for _frame in range(15):
		await physics_frame
	_expect(absf(box.global_position.x - x_after_left_release) < 20.0, "Idle braking also stops leftward movement quickly")

	for _frame in range(50):
		await physics_frame
	box.linear_velocity = Vector2.ZERO
	player.global_position = Vector2(box.global_position.x + 60.0, 482)
	player.velocity = Vector2.ZERO
	await physics_frame
	Input.action_press("move_right")
	for _frame in range(12):
		await physics_frame
	Input.action_release("move_right")
	_expect(absf(box.linear_velocity.x) < 1.0, "Moving away from the box does not push it")

	player.magic_orb.toggle_release_or_retrieve()
	player.current_layer = 1
	player._apply_layer_mask()
	player.global_position = Vector2(box.global_position.x - 60.0, 520)
	player.velocity = Vector2.ZERO
	box.linear_velocity = Vector2.ZERO
	await physics_frame
	Input.action_press("move_right")
	for _frame in range(12):
		await physics_frame
	Input.action_release("move_right")
	_expect(box.current_layer == 2 and absf(box.linear_velocity.x) < 1.0, "Player movement from another gameplay layer cannot push the box")

	var low_resistance_box := BOX_SCENE.instantiate() as PushBox
	low_resistance_box.position = Vector2(250, 466)
	low_resistance_box.current_layer = 2
	low_resistance_box.physics_damping = 0.0
	low_resistance_box.idle_braking_strength = 0.0
	low_resistance_box.push_resistance = 1.0
	var high_resistance_box := BOX_SCENE.instantiate() as PushBox
	high_resistance_box.position = Vector2(1200, 466)
	high_resistance_box.current_layer = 2
	high_resistance_box.physics_damping = 0.0
	high_resistance_box.idle_braking_strength = 0.0
	high_resistance_box.push_resistance = 2.0
	main.add_child(low_resistance_box)
	main.add_child(high_resistance_box)
	await physics_frame
	var active_push_box := BOX_SCENE.instantiate() as PushBox
	active_push_box.position = Vector2(500, 466)
	active_push_box.current_layer = 2
	active_push_box.physics_damping = 0.0
	active_push_box.idle_braking_strength = 1400.0
	main.add_child(active_push_box)
	await physics_frame
	active_push_box.receive_push(1.0)
	await physics_frame
	_expect(active_push_box.linear_velocity.x > 0.0, "Idle braking does not counteract a valid active push")
	for _frame in range(8):
		low_resistance_box.receive_push(1.0)
		high_resistance_box.receive_push(1.0)
		await physics_frame
	_expect(low_resistance_box.linear_velocity.x > high_resistance_box.linear_velocity.x, "Higher push resistance produces less acceleration")

	main.queue_free()
	if failures.is_empty():
		print("Directional box pushing: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

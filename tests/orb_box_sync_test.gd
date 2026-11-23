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
	var orb: MagicOrb = player.magic_orb
	var box: PushBox = main.get_node("Box") as PushBox
	player.current_layer = 2
	player._apply_layer_mask()
	player.global_position = Vector2(870, 482)
	player.velocity = Vector2.ZERO
	await physics_frame
	orb.toggle_release_or_retrieve()
	_expect(orb.state == MagicOrb.OrbState.STORED and box.stored_orb, "Placing the orb registers it inside the box")
	_expect(box.orb_anchor.position == Vector2.ZERO, "The box attachment point is centered inside the compartment")
	_expect(orb.scale == box.stored_orb_scale and orb.z_index == 1, "Stored orb is reduced and rendered inside the box layers")
	orb._process(1.0 / 60.0)
	_expect(orb.global_position == box.orb_anchor.global_position, "Stored orb snaps to the box attachment point")

	player.global_position = Vector2(500, 482)
	player.velocity = Vector2.ZERO
	await physics_frame
	player.try_change_layer(1)
	_expect(player.current_layer == 3 and box.current_layer == 3, "Distant box follows the player's upward layer transition")
	_expect(box.collision_layer == 4, "Box collision mask updates on the transition")
	_expect(orb.global_position.distance_to(box.orb_anchor.global_position) < 0.001, "Orb attachment updates on the transition")
	await physics_frame
	_expect(is_equal_approx(box.global_position.y, 428.0), "Physics simulation preserves the box's Layer 3 position after transition")
	_expect(box.current_layer == player.current_layer and box.collision_layer == player.collision_layer
		and (player.collision_mask & box.collision_mask) == box.collision_mask,
		"Physics tick keeps stored box and player synchronized on their common gameplay bit")
	player.try_change_layer(-1)
	_expect(player.current_layer == 2 and box.current_layer == 2, "Box follows the player's downward layer transition")
	player.try_change_layer(-1)
	_expect(player.current_layer == 1 and box.current_layer == 1, "Synchronization continues down to Layer 1")
	player.try_change_layer(-1)
	_expect(player.current_layer == 1 and box.current_layer == 1, "S cannot move either object below Layer 1")
	player.try_change_layer(1)
	_expect(player.current_layer == 2 and box.current_layer == 2, "W moves synchronized objects from Layer 1 to Layer 2")
	player.try_change_layer(1)
	_expect(player.current_layer == 3 and box.current_layer == 3, "W cannot move synchronized objects beyond Layer 3")
	player.try_change_layer(1)
	_expect(player.current_layer == 3 and box.current_layer == 3, "Layer 3 remains the upper boundary for both objects")

	player.try_change_layer(-1)
	player.try_change_layer(-1)
	_expect(player.current_layer == 1 and box.current_layer == 1, "Player and box return together to Layer 1")
	player.global_position = Vector2(870, 520)
	player.velocity = Vector2.ZERO
	orb.toggle_release_or_retrieve()
	_expect(orb.state == MagicOrb.OrbState.RETURNING and not box.stored_orb, "E detaches the orb and clears the box storage state")
	_expect(orb.scale == orb.default_scale and orb.z_index == 10, "Retrieved orb restores its normal visual scale and depth")
	player.global_position = Vector2(500, 520)
	player.try_change_layer(1)
	_expect(player.current_layer == 2 and box.current_layer == 1, "Box stops following layer changes immediately after retrieval")
	player.try_change_layer(-1)
	player.global_position = Vector2(870, 520)
	orb.state = MagicOrb.OrbState.FOLLOWING
	orb.toggle_release_or_retrieve()
	_expect(box.stored_orb, "Orb can be placed in the box again for blocked-transition validation")

	player.global_position = Vector2(500, 520)
	player.velocity = Vector2.ZERO
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 2
	blocker.collision_mask = 0
	var blocker_shape := CollisionShape2D.new()
	var blocker_rectangle := RectangleShape2D.new()
	blocker_rectangle.size = Vector2(48, 48)
	blocker_shape.shape = blocker_rectangle
	blocker.add_child(blocker_shape)
	blocker.global_position = box.global_position + Vector2(0, -box.layer_shift_offset)
	main.add_child(blocker)
	await physics_frame
	var player_position_before_blocked_transition := player.global_position
	var box_position_before_blocked_transition := box.global_position
	player.try_change_layer(1)
	_expect(player.current_layer == 1 and box.current_layer == 1, "A blocked box destination prevents both layer transitions")
	_expect(player.global_position == player_position_before_blocked_transition and box.global_position == box_position_before_blocked_transition, "Blocked synchronization preserves both positions")
	blocker.queue_free()
	await physics_frame

	# Supply the destination obstacle independently of edits to the level.
	var middle: GameplayLayer = main.get_node("MiddleLayer")
	var pillar := CollisionPolygon2D.new()
	pillar.position.x = 850.0
	pillar.polygon = PackedVector2Array([Vector2(-27, -152), Vector2(27, -152), Vector2(27, 0), Vector2(-27, 0)])
	middle.add_child(pillar)
	player.global_position = Vector2(1030, 520)
	player.velocity = Vector2.ZERO
	Input.action_press("move_left")
	for _frame in range(150):
		await physics_frame
		if box.global_position.x <= 850.0:
			break
	Input.action_release("move_left")
	_expect(box.global_position.x <= 850.0 and box.stored_orb, "The stored box can be pushed onto the lower layer's clear area")
	player.global_position = Vector2(500, 520)
	player.velocity = Vector2.ZERO
	await physics_frame
	var obstructed_box_x := box.global_position.x
	player.try_change_layer(1)
	_expect(player.current_layer == 1 and box.current_layer == 1, "A pushed box blocked by the destination obstacle keeps both on Layer 1")
	_expect(is_equal_approx(box.global_position.x, obstructed_box_x), "Blocked synchronization does not move the box")

	player.global_position = Vector2(box.global_position.x - 70.0, 520)
	player.velocity = Vector2.ZERO
	await physics_frame
	Input.action_press("move_right")
	for _frame in range(150):
		await physics_frame
		if box.global_position.x >= 905.0:
			break
	Input.action_release("move_right")
	_expect(box.global_position.x >= 905.0, "Pushing the box clear of the obstacle restores a valid destination")
	_expect(orb.global_position.distance_to(box.orb_anchor.global_position) < 0.01, "The orb remains attached throughout obstacle-side pushing")
	player.global_position = Vector2(500, 520)
	player.velocity = Vector2.ZERO
	await physics_frame
	player.try_change_layer(1)
	_expect(player.current_layer == 2 and box.current_layer == 2, "Player and pushed box synchronize again from a valid position")
	_expect(is_zero_approx(box.linear_velocity.x), "Successful layer transition clears horizontal box momentum")
	_expect(orb.global_position.distance_to(box.orb_anchor.global_position) < 0.01, "Orb remains inside after the synchronized transition")
	orb.toggle_release_or_retrieve()
	player.try_change_layer(-1)
	_expect(player.current_layer == 1 and box.current_layer == 2, "Retrieving the orb stops synchronization after the pushed transition")
	orb.reset_to_player()
	_expect(not box.stored_orb and orb.get_parent() == player, "Orb reset detaches it cleanly from the box")
	main.queue_free()

	if failures.is_empty():
		print("Orb and box synchronization: all checks passed.")
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

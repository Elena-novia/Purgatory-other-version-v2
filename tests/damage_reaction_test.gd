extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")

var failures: Array[String] = []
var damage_event_count := 0
var landing_event_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: PlayerController = main.get_node("Player")
	player.damaged.connect(_on_player_damaged)
	player.damage_landed.connect(_on_damage_landed)
	_set_player_at_front_floor(player)
	await physics_frame
	await physics_frame

	var starting_health := player.vitals.health
	var resting_camera_offset := player.camera.offset
	var starting_x := player.global_position.x
	player.take_hit(0.1, player.global_position + Vector2(-30, 0))
	_expect(player.velocity.x > 0.0 and player.velocity.x <= player.damage_knockback_launch_impulse, "The hit launches the player away from the enemy with a controlled initial speed")
	_expect(player.velocity.y <= -300.0, "Enemy damage applies a pronounced upward impulse")
	_expect(player._damage_landing_pending, "Damage jump arms exactly one landing reaction")
	_expect(is_equal_approx(player.vitals.health, starting_health - 0.1), "Enemy hit still reduces health")
	_expect(player._damage_flash_remaining > 0.0 and player.get_node("BloodParticles").emitting, "Existing hit flash and blood particles still trigger")
	_expect(damage_event_count == 1, "One hit emits one damage event")
	_expect(player.camera.offset == resting_camera_offset, "Landing shake waits until the damage jump lands")
	await physics_frame
	_expect(player.velocity.x > 0.0 and player.velocity.x < player.knockback_strength, "Unassisted knockback accelerates smoothly and carries momentum")

	var landing_frames := 0
	while player._damage_landing_pending and landing_frames < 60:
		await physics_frame
		landing_frames += 1
	_expect(not player._damage_landing_pending and landing_event_count == 1, "Landing after the damage jump triggers one shake")
	_expect(landing_frames >= 40, "The damage reaction remains airborne for a longer, natural arc")
	_expect(absf(player.global_position.x - starting_x) > 120.0, "The player travels noticeably backwards before landing")
	await process_frame
	_expect(player.camera.offset.distance_to(resting_camera_offset) > 3.0, "Landing shake is stronger to match the impact")
	await create_timer(player.landing_shake_duration + 0.08).timeout
	_expect(player.camera.offset == resting_camera_offset, "Camera offset returns to its original value")
	_expect(landing_event_count == 1, "A single damage jump cannot trigger multiple landing shakes")
	var health_before_repeat := player.vitals.health
	player.take_hit(0.1, player.global_position + Vector2(-30, 0))
	_expect(is_equal_approx(player.vitals.health, health_before_repeat - 0.1), "A subsequent valid damage event reduces health immediately")
	_expect(damage_event_count == 2 and player._damage_flash_remaining > 0.0, "Repeated damage retriggers the damage feedback")
	player.cancel_damage_reaction()
	var control_start_x := player.global_position.x
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	_expect(player.global_position.x > control_start_x, "Normal horizontal control returns after the reaction")

	player.cancel_damage_reaction()
	_set_player_at_front_floor(player)
	await physics_frame
	player.take_hit(0.1, player.global_position + Vector2(30, 0))
	_expect(player._damage_knockback_direction == -1.0, "An enemy to the right sets a leftward knockback direction")
	_expect(player.velocity.y < 0.0, "The right-side hit also applies an upward impulse")
	await physics_frame
	_expect(player.velocity.x < 0.0, "The right-side knockback accelerates smoothly to the left")
	_expect(damage_event_count == 3, "The third hit continues through the existing damage signal")
	player.cancel_damage_reaction()
	player.vitals.restore()
	_set_player_at_front_floor(player)
	await physics_frame
	await physics_frame

	var jump := InputEventKey.new()
	jump.pressed = true
	jump.physical_keycode = KEY_SPACE
	Input.parse_input_event(jump)
	await physics_frame
	await physics_frame
	_expect(player.velocity.y < 0.0, "Normal Space jump still works")
	var normal_landing_frames := 0
	while not player.is_on_floor() and normal_landing_frames < 60:
		await physics_frame
		normal_landing_frames += 1
	_expect(player.is_on_floor(), "Normal jump returns the player to the floor")
	_expect(landing_event_count == 1, "A normal jump does not trigger the damage landing shake")
	_expect(player.camera.offset == resting_camera_offset, "Normal landing leaves the camera at its base offset")

	var start_x := player.global_position.x
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	_expect(player.global_position.x > start_x, "Horizontal movement works after the landing reaction")

	player.cancel_damage_reaction()
	_set_player_at_front_floor(player)
	await physics_frame
	player.take_hit(0.1, player.global_position + Vector2(-30, 0))
	var launched_right_speed := player.velocity.x
	Input.action_press("move_left")
	for _frame in range(24):
		await physics_frame
	Input.action_release("move_left")
	var steered_left_speed := player.velocity.x
	_expect(steered_left_speed < 0.0 and player._damage_landing_pending, "A steers through and reverses the rightward knockback while airborne")
	var vertical_speed_after_release := player.velocity.y
	for _frame in range(6):
		await physics_frame
	_expect(player.velocity.x < 0.0 and absf(player.velocity.x) < absf(steered_left_speed), "Releasing A preserves momentum while horizontal damping eases it")
	_expect(player.velocity.y > vertical_speed_after_release, "Normal gravity continues through the damage jump")
	_expect(launched_right_speed > 0.0, "Initial knockback remains directed away from the enemy before steering")
	player.cancel_damage_reaction()
	_set_player_at_front_floor(player)
	await physics_frame
	player.take_hit(0.1, player.global_position + Vector2(30, 0))
	var launched_left_speed := player.velocity.x
	Input.action_press("move_right")
	for _frame in range(24):
		await physics_frame
	Input.action_release("move_right")
	_expect(player.velocity.x > 0.0 and player._damage_landing_pending, "D steers through and reverses the leftward knockback while airborne")
	_expect(launched_left_speed < 0.0, "The second impact initially launches left before rightward steering")

	if failures.is_empty():
		print("Damage reaction: all validation checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _set_player_at_front_floor(player: PlayerController) -> void:
	player.current_layer = 1
	player._apply_layer_mask()
	player.global_position = Vector2(160, 520)
	player.velocity = Vector2.ZERO

func _on_player_damaged() -> void:
	damage_event_count += 1

func _on_damage_landed() -> void:
	landing_event_count += 1

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const ENEMY := preload("res://scenes/world/enemy.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN.instantiate()
	root.add_child(main)
	var front := main.get_node("FrontLayer") as GameplayLayer
	var back := main.get_node("BackLayer") as GameplayLayer
	var back_two := main.get_node("BackLayer2") as GameplayLayer
	var middle_two := main.get_node("MiddleLayer2") as GameplayLayer
	var player := main.get_node("Player") as PlayerController
	back_two.depth_scale = 0.74
	back_two.tint_strength = 0.51
	var source := _branch(front, Vector2(4500, -250))
	var enemy := ENEMY.instantiate() as EnemyHazard
	enemy.position = Vector2(35, 0)
	source.add_child(enemy)
	await _frames(36)
	var before := enemy.global_transform
	var center := enemy.mount.origin
	var phase := _time(enemy)
	_expect(enemy.layer_context.gameplay_layer == front and _on_path(enemy, center)
		and _offset(enemy) > 20.0 and cos(phase * enemy.patrol_speed) > 0.0,
		"Front enemy is moving along its original patrol at the repro point")

	# Match the audit: both native reparent choices produce the same entry
	# pose, but the destination's horizontal scale would shift the old anchor.
	var scaled := back_two.global_transform.x.x
	var local := source.to_local(before.origin)
	var destination_origin := before.origin - Vector2(scaled * local.x, local.y)
	var destination := _branch(back_two, back_two.to_local(destination_origin))
	_expect(_pose_matches(_place(destination.global_transform, _relative(source.global_transform, before)), before),
		"The destination reproduces the coincident entry poses")
	enemy.reparent(destination, true)
	_expect(_pose_matches(enemy.global_transform, before) and _close(enemy.mount.origin, center)
		and is_equal_approx(_time(enemy), phase), "True reparent keeps the world pose, patrol centre and phase immediately")
	await _frames(2)
	var step := enemy.global_position.x - before.origin.x
	_expect(_on_path(enemy, center) and step > 0.0 and step < 2.3
		and _axes_match(enemy.global_transform, before),
		"Two patrol ticks after true reparent advance normally (%.3f px)" % step)
	await _frames(16)
	_expect(_matches_section(enemy, back_two) and _sensor_radius(enemy) > 16.999,
		"BackLayer2 owns the moving enemy and supplies its separate visual profile")

	var local_center := destination.to_local(center)
	var relative_axes := _relative(destination.global_transform, enemy.global_transform)
	destination.rotation += 0.42
	await _frames(3)
	center = destination.to_global(local_center)
	_expect(_on_path(enemy, center) and _axes_match(enemy.global_transform, _place(destination.global_transform, relative_axes)),
		"Rotating the branch rotates the enemy and keeps it on the horizontal path (Y error %.4f px)" %
		(enemy.global_position.y - enemy.mount.origin.y))
	destination.position += Vector2(78, -21)
	destination.scale *= Vector2(1.38, 0.66)
	await _frames(3)
	center = destination.to_global(local_center)
	_expect(_on_path(enemy, center) and is_equal_approx(_sensor_radius(enemy), 17.0),
		"Parent translation and nonuniform scale move the centre and preserve radius and world-space patrol")

	var same_layer := _branch(back, Vector2(5120, -210))
	same_layer.rotation = -0.31
	same_layer.scale = Vector2(1.14, 0.82)
	var local_pose := _relative(destination.global_transform, enemy.global_transform)
	var target := _place(same_layer.global_transform, local_pose)
	phase = _time(enemy)
	center = target.origin - Vector2(_offset(enemy), 0.0)
	enemy.reparent(same_layer, false)
	_expect(_pose_matches(enemy.global_transform, target) and _close(enemy.mount.origin, center)
		and is_equal_approx(_time(enemy), phase), "False reparent keeps the full relative pose and patrol phase")
	await _frames(18)
	_expect(_on_path(enemy, center) and _matches_section(enemy, back),
		"The active patrol continues after moving between the two physical Back sections")
	local_center = same_layer.to_local(center)
	same_layer.rotation -= 0.24
	same_layer.position += Vector2(23, 48)
	await _frames(3)
	center = same_layer.to_global(local_center)
	_expect(_on_path(enemy, center), "The destination still carries the patrol centre after false reparent")

	var other_layer := _branch(middle_two, Vector2(6200, -450))
	before = enemy.global_transform
	enemy.reparent(other_layer, true)
	_expect(_pose_matches(enemy.global_transform, before), "True reparent to a different logical layer preserves the world pose")
	await _frames(18)
	_expect(_on_path(enemy, center) and _matches_section(enemy, middle_two),
		"Changing to Middle restores its collision mask and visual profile without moving the patrol centre")
	await _check_full_cycle(enemy, center)
	await _check_contact(enemy, player)

	if failures.is_empty():
		print("Enemy patrol continuity: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_full_cycle(enemy: EnemyHazard, center: Vector2) -> void:
	var low := INF
	var high := -INF
	var max_error := 0.0
	var max_step := 0.0
	var previous := enemy.global_position.x
	var phase := _time(enemy)
	for _frame in range(504):
		await physics_frame
		var offset := enemy.global_position.x - center.x
		low = minf(low, offset)
		high = maxf(high, offset)
		max_error = maxf(max_error, enemy.global_position.distance_to(center + Vector2(_offset(enemy), 0)))
		max_step = maxf(max_step, absf(enemy.global_position.x - previous))
		previous = enemy.global_position.x
	_expect(absf(low + 90.0) < 0.02 and absf(high - 90.0) < 0.02 and max_error < 0.02,
		"One full cycle keeps the original 90 px amplitude (%.3f to %.3f px)" % [low, high])
	_expect(absf(_time(enemy) - phase - 8.4) < 0.0001 and absf(enemy.patrol_speed - 0.75) < 0.0001
		and max_step <= 1.13 and is_equal_approx(_sensor_radius(enemy), 17.0),
		"Patrol phase rate, speed and 17 px detection radius are unchanged")

func _check_contact(enemy: EnemyHazard, player: PlayerController) -> void:
	player.set_physics_process(false)
	player.vitals.restore()
	player.current_layer = 1
	player._apply_layer_mask()
	await _hold_contact(enemy, player, 12)
	_expect(is_equal_approx(player.vitals.health, player.vitals.max_health) and not enemy.overlaps_body(player),
		"The active Middle enemy does not detect or damage a Front player")
	player.current_layer = 2
	player._apply_layer_mask()
	await _hold_contact(enemy, player, 5)
	var one_hit := player.vitals.max_health - enemy.damage
	_expect(enemy.overlaps_body(player) and is_equal_approx(player.vitals.health, one_hit),
		"The same active enemy applies contact damage in Middle")
	await _hold_contact(enemy, player, 25)
	_expect(is_equal_approx(player.vitals.health, one_hit) and is_equal_approx(enemy.contact_damage_interval, 0.8),
		"Sustained contact waits for the unchanged 0.8 second interval")
	await _hold_contact(enemy, player, 25)
	_expect(is_equal_approx(player.vitals.health, one_hit - enemy.damage),
		"The enemy deals a second hit once the interval expires")

func _hold_contact(enemy: EnemyHazard, player: PlayerController, count: int) -> void:
	for _frame in range(count):
		player.global_position = enemy.global_position + Vector2(0, 24)
		await physics_frame

func _sensor_radius(enemy: EnemyHazard) -> float:
	var collider := enemy.get_node("CollisionShape2D") as CollisionShape2D
	var rid := enemy.get_rid()
	var pose := PhysicsServer2D.area_get_transform(rid) * PhysicsServer2D.area_get_shape_transform(rid, 0)
	return (collider.shape as CircleShape2D).radius * maxf(pose.x.length(), pose.y.length())

func _time(enemy: EnemyHazard) -> float:
	return float(enemy.get("_time"))

func _offset(enemy: EnemyHazard) -> float:
	return sin(_time(enemy) * enemy.patrol_speed) * enemy.patrol_distance

func _on_path(enemy: EnemyHazard, center: Vector2) -> bool:
	return _close(enemy.mount.origin, center) and _close(enemy.global_position, center + Vector2(_offset(enemy), 0.0))

func _matches_section(enemy: EnemyHazard, layer: GameplayLayer) -> bool:
	return enemy.layer_context.gameplay_layer == layer and enemy.layer_context.logical_layer == layer.current_layer \
		and enemy.collision_mask == GameplayLayer.solid_collision_bit(layer.current_layer) \
		and enemy.depth_visuals.global_scale.is_equal_approx(Vector2.ONE * layer.depth_scale) \
		and enemy.depth_visuals.modulate.is_equal_approx(layer.depth_modulation())

func _branch(parent: Node2D, point: Vector2) -> Node2D:
	var branch := Node2D.new()
	branch.position = point
	parent.add_child(branch)
	return branch

func _place(frame: Transform2D, local: Transform2D) -> Transform2D:
	var pose := Transform2D(frame.x.angle(), Vector2.ZERO) * local
	pose.origin = frame * local.origin
	return pose

func _relative(frame: Transform2D, global_pose: Transform2D) -> Transform2D:
	var pose := Transform2D(-frame.x.angle(), Vector2.ZERO) * global_pose
	pose.origin = frame.affine_inverse() * global_pose.origin
	return pose

func _pose_matches(a: Transform2D, b: Transform2D) -> bool:
	return _close(a.origin, b.origin) and _axes_match(a, b)

func _axes_match(a: Transform2D, b: Transform2D) -> bool:
	return a.x.distance_to(b.x) < 0.0002 and a.y.distance_to(b.y) < 0.0002

func _close(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.02

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

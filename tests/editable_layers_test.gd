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
	var front: GameplayLayer = main.get_node("FrontLayer")
	var middle: GameplayLayer = main.get_node("MiddleLayer")
	var back: GameplayLayer = main.get_node("BackLayer")
	var layers: Array[GameplayLayer] = [front, middle, back]
	var grounds: Array[CollisionPolygon2D] = []
	for layer in layers:
		grounds.append(layer.get_node("Ground"))
		var id := layer.current_layer
		_expect(not layer.scene_file_path.is_empty() and layer.collision_layer == 1 << (id - 1)
			and layer.collision_mask == 0, "%s is an instanced scene with the existing layer bit" % layer.name)
		_expect(_terrain_hit_y(layer, 160.0) == layer.global_position.y,
			"%s retains its original walkable height" % layer.name)

	player.set_physics_process(false)
	for moving_layer in layers:
		var original_position := moving_layer.position
		var original_parallax_position := moving_layer.parallax_decoration.global_position
		var ground_positions: Array[Vector2] = []
		for ground in grounds:
			ground_positions.append(ground.global_position)

		var offset := Vector2(80, -20)
		moving_layer.position += offset
		await physics_frame
		await physics_frame
		_expect(_terrain_hit_y(moving_layer, 160.0) == moving_layer.global_position.y,
			"%s collision follows its edited transform" % moving_layer.name)
		_expect(moving_layer.parallax_decoration.global_position.is_equal_approx(original_parallax_position + offset),
			"%s moves its authored decoration with the layer" % moving_layer.name)
		for index in range(layers.size()):
			var expected_offset := offset if layers[index] == moving_layer else Vector2.ZERO
			_expect(grounds[index].global_position == ground_positions[index] + expected_offset,
				"Moving %s preserves %s independence" % [moving_layer.name, layers[index].name])
		moving_layer.position = original_position

	var previous_parallax_x: Array[float] = []
	for layer in layers:
		previous_parallax_x.append(layer.parallax_decoration.global_position.x)
	player.global_position.x += 100.0
	await process_frame
	await process_frame
	var expected_parallax_delta := [-15.0, 0.0, 28.0]
	for index in range(layers.size()):
		var decor := layers[index].parallax_decoration
		_expect(is_equal_approx(decor.global_position.x - previous_parallax_x[index], expected_parallax_delta[index]),
			"%s keeps its parallax response to player movement" % layers[index].name)

	# Emulate editing the scenes: two front platforms with a slope and a gap,
	# a shorter back platform, and an untouched middle route.
	grounds[0].polygon = PackedVector2Array([Vector2(-850, 0), Vector2(-340, 0),
		Vector2(-340, 520), Vector2(-850, 520)])
	grounds[2].polygon = PackedVector2Array([Vector2(-850, 0), Vector2(-450, 0),
		Vector2(-450, 300), Vector2(-850, 300)])
	var right_platform := grounds[0].duplicate() as CollisionPolygon2D
	right_platform.position = Vector2(560, 0)
	right_platform.polygon = PackedVector2Array([Vector2.ZERO, Vector2(130, -26),
		Vector2(930, -26), Vector2(930, 200), Vector2(0, 200)])
	front.add_child(right_platform)
	await physics_frame
	await physics_frame

	_expect(_terrain_hit_y(front, 160.0) == 520.0, "Left platform remains walkable")
	_expect(is_equal_approx(_terrain_hit_y(front, 590.0), 514.0), "New platform has a collidable slope")
	_expect(is_inf(_terrain_hit_y(front, 500.0)), "The gap between front platforms has no collider")
	_expect(is_inf(_terrain_hit_y(back, 500.0)), "A shorter BackLayer has independent coverage")
	_expect(_terrain_hit_y(middle, 500.0) == 482.0, "Only the middle layer has ground at the gap")

	player.global_position = Vector2(500, 520)
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	player.try_change_layer(1)
	await physics_frame
	await physics_frame
	_expect(player.current_layer == 2 and player.is_on_floor(), "W reaches the middle route over the gap")

	var middle_position := player.global_position
	player.try_change_layer(-1)
	_expect(player.current_layer == 2 and player.global_position == middle_position,
		"S rejects the edited front-layer gap")
	player.current_layer = 1
	player._apply_layer_mask()
	player.global_position.y = 452.0
	player.velocity = Vector2.ZERO
	for _frame in range(30):
		await physics_frame
	_expect(player.current_layer == 2 and player.is_on_floor() and absf(player.global_position.y - 482.0) < 0.5,
		"Falling through a front-layer gap adopts the middle layer on landing")

	var starting_health := player.vitals.health
	player.global_position = Vector2(4000, 520)
	player.velocity = Vector2.ZERO
	for _frame in range(90):
		await physics_frame
		if player.vitals.health < starting_health:
			break
	_expect(player.vitals.health < starting_health, "A gap across all layers makes the player fall and take damage")
	_expect(player.global_position.is_equal_approx(player.checkpoint_position)
		and player.current_layer == player.checkpoint_layer, "Falling returns the player to the existing checkpoint")

	if failures.is_empty():
		print("Editable gameplay layers: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _terrain_hit_y(layer: GameplayLayer, x: float) -> float:
	var ray := PhysicsRayQueryParameters2D.create(Vector2(x, 350), Vector2(x, 650), layer.collision_layer)
	var player := layer.get_parent().get_node("Player") as PlayerController
	var box := layer.get_parent().get_node("Box") as PushBox
	ray.exclude = [player.get_rid(), box.get_rid()]
	var hit := layer.get_world_2d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return INF
	return hit.position.y

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

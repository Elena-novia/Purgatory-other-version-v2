extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const BOX_SCENE := preload("res://scenes/interactables/box.tscn")
const FLOOR_HEIGHTS := [520.0, 482.0, 444.0]

var failures: Array[String] = []
var main: Node2D
var player: PlayerController
var orb: MagicOrb
var box: PushBox
var profiles: Array[GameplayLayer]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	orb = player.magic_orb
	box = main.get_node("Box")
	profiles = main.get_depth_profiles()
	var boxes: Array[PushBox] = [_add_box(1, 380.0), _add_box(2, 520.0), _add_box(3, 280.0)]
	await _wait_frames(3)
	var player_collider := player.body_shape.transform
	var player_bounds := player.body_shape.shape.get_rect()

	_expect(_uses_layer(player.depth_visuals, 1) and _uses_layer(boxes[0].depth_visuals, 1)
		and _uses_layer(orb.depth_visuals, 1), "Front player, box and orb display original size and colors")
	_expect(_uses_layer(player.depth_visuals, 1) and _uses_layer(box.depth_visuals, 2),
		"Front player and Middle box coexist with independent appearances")

	orb.current_layer = 3
	await _wait_for_depth()
	_expect(player.current_layer == 1 and orb.current_layer == 3
		and _uses_layer(player.depth_visuals, 1) and _uses_layer(orb.depth_visuals, 3),
		"An independent Back orb displays its own depth beside a Front player")
	profiles[2].depth_scale = 0.76
	profiles[2].tint_strength = 0.50
	await _wait_for_depth()
	_expect(_uses_layer(orb.depth_visuals, 3) and _uses_layer(boxes[2].depth_visuals, 3),
		"An edited layer profile updates the independent orb and box")
	profiles[2].depth_scale = 0.70
	profiles[2].tint_strength = 0.68

	player.try_change_layer(1)
	await _wait_for_depth()
	_expect(_uses_layer(player.depth_visuals, 2) and _uses_layer(boxes[0].depth_visuals, 1),
		"A Front box stays full size beside the Middle player")
	_expect(_uses_layer(player.depth_visuals, 2) and _uses_layer(boxes[2].depth_visuals, 3),
		"A Back box stays at Back depth beside the Middle player")
	player.try_change_layer(1)
	await _wait_for_depth()
	_expect(_uses_layer(player.depth_visuals, 3) and _uses_layer(boxes[0].depth_visuals, 1),
		"A Front box stays full size beside the Back player")
	_expect(_uses_layer(player.depth_visuals, 3) and _uses_layer(box.depth_visuals, 2),
		"A Middle box keeps its own depth beside the Back player")
	_expect(_uses_layer(player.depth_visuals, 3) and _uses_layer(boxes[2].depth_visuals, 3)
		and _uses_layer(orb.depth_visuals, 3), "Back player, box and orb all use the Back profile")

	await _check_storage()
	for fixture in boxes:
		await _check_push_and_collision(fixture)
	_expect(player.scale == Vector2.ONE and player.body_shape.transform == player_collider
		and player.body_shape.shape.get_rect() == player_bounds,
		"The player retains its original physical transform and collider at every depth")

	if failures.is_empty():
		print("Object depth system: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_storage() -> void:
	orb.current_layer = 1
	_place_player(2, 895.0)
	await _wait_for_depth()
	orb.toggle_release_or_retrieve()
	_expect(box.stored_orb and orb.get_parent() == box and orb.current_layer == 2
		and _uses_layer(box.depth_visuals, 2) and _uses_layer(orb.depth_visuals, 2),
		"Storing an orb in a Middle box immediately uses the box's depth")
	_expect(_orb_matches_box(), "The stored orb is centered and scaled just once")

	_place_player(2, 560.0)
	var box_x := box.global_position.x
	player.try_change_layer(1)
	_expect(player.current_layer == 3 and box.current_layer == 3 and box.collision_mask == 4
		and orb.current_layer == 3 and is_equal_approx(box.global_position.x, box_x),
		"Synchronized W changes both logical layers before the visual animation finishes")
	await create_timer(box.depth_visuals.transition_duration * 0.4).timeout
	_expect(box.depth_visuals.scale.x < 0.85 and box.depth_visuals.scale.x > 0.70 and _orb_matches_box(),
		"The orb matches the interpolating box's scale, color and anchor")
	await _wait_for_depth()
	_expect(_uses_layer(box.depth_visuals, 3) and _uses_layer(orb.depth_visuals, 3) and _orb_matches_box(),
		"The orb and box settle together at Back depth")

	orb.toggle_release_or_retrieve()
	_expect(not box.stored_orb and orb.get_parent() == player and orb.current_layer == 1
		and orb.scale == orb.default_scale, "Retrieval restores the orb's original independent layer and size ratio")
	await _wait_for_depth()
	_expect(_uses_layer(orb.depth_visuals, 1) and _uses_layer(box.depth_visuals, 3),
		"The retrieved orb smoothly returns to Front depth while the box stays Back")

func _check_push_and_collision(fixture: PushBox) -> void:
	var layer := fixture.current_layer
	var shape_transform := fixture.body_shape.transform
	var shape_bounds := fixture.body_shape.shape.get_rect()
	var start_x := fixture.global_position.x
	var wall := StaticBody2D.new()
	wall.position = Vector2(start_x + 75.0, fixture.global_position.y)
	wall.collision_layer = fixture.collision_layer
	wall.collision_mask = 0
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 64)
	collider.shape = rectangle
	wall.add_child(collider)
	main.add_child(wall)
	_place_player(layer, start_x - 50.0)
	await _wait_frames(5)

	var probe_origin := fixture.global_position - Vector2(45, 0)
	var query := PhysicsRayQueryParameters2D.create(probe_origin, fixture.global_position, fixture.collision_layer,
		[player.get_rid()])
	var hit := fixture.get_world_2d().direct_space_state.intersect_ray(query)
	_expect(fixture.scale == Vector2.ONE and shape_bounds.size == Vector2(32, 32)
		and _uses_layer(fixture.depth_visuals, layer) and not hit.is_empty() and hit.collider == fixture
		and absf(hit.position.x - (start_x - 16.0)) < 0.1,
		"Layer %d box keeps a full 32 px physical collider at its visual depth (start=%s, current=%s, hit=%s, depth=%s)" % [
			layer, start_x, fixture.global_position, hit, fixture.depth_visuals.scale
		])

	Input.action_press("move_right")
	await _wait_frames(66)
	Input.action_release("move_right")
	var wall_limit := wall.global_position.x - 10.0 - 16.0
	_expect(fixture.global_position.x > start_x + 15.0 and fixture.global_position.x <= wall_limit + 0.6
		and player.global_position.x < fixture.global_position.x,
		"Layer %d box is physically pushed by the player and stops at obstacles (start=%s, end=%s, wall limit=%s, player=%s)" % [
			layer, start_x, fixture.global_position, wall_limit, player.global_position
		])
	await _wait_frames(12)
	_expect(absf(fixture.linear_velocity.x) <= fixture.stopping_velocity_threshold
		and fixture.body_shape.transform == shape_transform and fixture.body_shape.shape.get_rect() == shape_bounds,
		"Layer %d box retains braking and its original collider after pushing" % layer)
	wall.queue_free()
	await _wait_frames(2)

func _add_box(layer: int, x: float) -> PushBox:
	var instance := BOX_SCENE.instantiate() as PushBox
	instance.current_layer = layer
	instance.position = Vector2(x, FLOOR_HEIGHTS[layer - 1] - 16.0)
	main.add_child(instance)
	return instance

func _place_player(layer: int, x: float) -> void:
	player.current_layer = layer
	player.global_position = Vector2(x, FLOOR_HEIGHTS[layer - 1])
	player.velocity = Vector2.ZERO
	player._apply_layer_mask()

func _uses_layer(visuals: LayerDepthVisuals, number: int) -> bool:
	var profile := profiles[number - 1]
	return visuals.scale.is_equal_approx(Vector2.ONE * profile.depth_scale) \
		and visuals.modulate.is_equal_approx(profile.depth_modulation())

func _orb_matches_box() -> bool:
	return orb.depth_visuals.scale.is_equal_approx(box.depth_visuals.scale) \
		and orb.depth_visuals.modulate.is_equal_approx(box.depth_visuals.modulate) \
		and orb.depth_visuals.global_scale.is_equal_approx(box.depth_visuals.global_scale * box.stored_orb_scale) \
		and orb.global_position.is_equal_approx(box.orb_anchor.global_position)

func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _wait_for_depth() -> void:
	await create_timer(LayerDepthVisuals.DEFAULT_TRANSITION_DURATION + 0.05).timeout

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

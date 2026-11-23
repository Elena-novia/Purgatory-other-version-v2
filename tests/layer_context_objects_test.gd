extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const PEDESTAL_SCENE := preload("res://scenes/interactables/pedestal.tscn")
const ENEMY_SCENE := preload("res://scenes/world/enemy.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/world/checkpoint.tscn")
const SECTIONS := ["FrontLayer", "FrontLayer2", "MiddleLayer", "MiddleLayer2", "BackLayer", "BackLayer2"]

var failures: Array[String] = []
var main: Node2D
var player: PlayerController

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	var existing: OrbReceiver = main.get_node("Pedestal")
	_expect(existing.current_layer == 1 and existing.body.collision_layer == 1
		and existing.global_position == Vector2(630, 520), "Main preserves its existing Front pedestal")
	var existing_enemy: EnemyHazard = main.get_node("Enemy")
	_expect(existing_enemy.collision_mask == 2 and existing_enemy.layer_context.logical_layer == 2,
		"Main preserves its existing Middle enemy")
	var existing_checkpoint: Checkpoint = main.get_node("Checkpoint")
	_expect(existing_checkpoint.collision_mask == 2 and existing_checkpoint.layer_context.logical_layer == 2
		and existing_checkpoint.global_position + existing_checkpoint.respawn_offset == Vector2(216, 597),
		"Main preserves its existing Middle checkpoint and respawn position")
	# Give one section a distinct profile to catch accidental use of the canonical Back profile.
	var back_two: GameplayLayer = main.get_node("BackLayer2")
	back_two.depth_scale = 0.74
	back_two.tint_strength = 0.46
	for section_name in SECTIONS:
		var section: GameplayLayer = main.get_node(section_name)
		var branch := Node2D.new()
		branch.name = "NestedFixtures"
		branch.position.x = 470
		section.add_child(branch)
		await _check_pedestal(branch, section)
		await _check_enemy(branch, section)
		await _check_checkpoint(branch, section)
		branch.queue_free()
		await _wait_frames(2)
	await _check_mount_and_override()

	if failures.is_empty():
		print("LayerContext objects: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_pedestal(branch: Node2D, section: GameplayLayer) -> void:
	var label := str(section.name)
	var pedestal := PEDESTAL_SCENE.instantiate() as OrbReceiver
	branch.add_child(pedestal)
	var bit := GameplayLayer.solid_collision_bit(section.current_layer)
	var shape: CollisionShape2D = pedestal.get_node("Body/CollisionShape2D")
	_expect(pedestal.layer_context.gameplay_layer == section and pedestal.current_layer == section.current_layer
		and pedestal.body.collision_layer == bit and pedestal.body.collision_mask == 0,
		"%s pedestal inherits its layer and publishes only its solid bit" % label)
	_expect(_matches_depth(pedestal.depth_visuals, section)
		and shape.global_scale.is_equal_approx(Vector2.ONE) and shape.shape.get_rect().size == Vector2(46, 38),
		"%s pedestal artwork follows depth without scaling its body" % label)
	var foreign := _other_layer(section.current_layer)
	var near := pedestal.global_position + Vector2(-47, 0)
	player.set_physics_process(false)
	_place_player(foreign, near)
	await _wait_frames(3)
	_expect(_sees_pedestal(pedestal, shape, bit)
		and not _sees_pedestal(pedestal, shape, GameplayLayer.solid_collision_bit(foreign)),
		"%s pedestal collider is visible only to its own layer" % label)
	_press_orb_key()
	_expect(not pedestal.has_orb and player.magic_orb.stored_receiver != pedestal
		and not pedestal.receive_orb(player.magic_orb), "%s pedestal rejects a player from another layer" % label)
	_place_player(section.current_layer, near)
	_press_orb_key()
	_expect(pedestal.has_orb and player.magic_orb.get_parent() == pedestal
		and player.magic_orb.global_position.is_equal_approx(pedestal.orb_anchor.global_position)
		and player.magic_orb.global_scale.is_equal_approx(Vector2.ONE)
		and pedestal.indicator.color == Color("ffd66b"), "%s stores the orb at its art anchor and lights the indicator" % label)
	_press_orb_key()
	_expect(not pedestal.has_orb and player.magic_orb.get_parent() == player
		and pedestal.indicator.color == Color("85d8ea"), "%s returns the orb and clears the indicator" % label)
	for _frame in range(60):
		if player.magic_orb.state == MagicOrb.OrbState.FOLLOWING:
			break
		await process_frame
	pedestal.queue_free()
	await _wait_frames(2)

func _check_enemy(branch: Node2D, section: GameplayLayer) -> void:
	var label := str(section.name)
	var enemy := ENEMY_SCENE.instantiate() as EnemyHazard
	enemy.position.y = -24
	enemy.patrol_distance = 0.0
	enemy.contact_damage_interval = 0.25
	branch.add_child(enemy)
	var shape: CollisionShape2D = enemy.get_node("CollisionShape2D")
	_expect(enemy.layer_context.gameplay_layer == section and enemy.collision_layer == 0
		and enemy.collision_mask == GameplayLayer.solid_collision_bit(section.current_layer),
		"%s enemy resolves its layer and stays a non-solid hazard" % label)
	_expect(_matches_depth(enemy.depth_visuals, section) and shape.global_scale.is_equal_approx(Vector2.ONE)
		and (shape.shape as CircleShape2D).radius == 17.0, "%s enemy artwork leaves the hit area at its original size" % label)
	var overlap := enemy.global_position + Vector2(0, 24)
	player.vitals.restore()
	player.cancel_damage_reaction()
	_place_player(_other_layer(section.current_layer), overlap)
	await _wait_frames(20)
	_expect(is_equal_approx(player.vitals.health, player.vitals.max_health),
		"%s enemy ignores overlapping foreign-layer players" % label)
	_place_player(section.current_layer, overlap)
	await _wait_frames(5)
	var once := player.vitals.max_health - enemy.damage
	_expect(is_equal_approx(player.vitals.health, once), "%s enemy deals one hit on compatible contact" % label)
	await _wait_frames(7)
	_expect(is_equal_approx(player.vitals.health, once), "%s enemy waits for its contact interval" % label)
	await _wait_frames(9)
	_expect(is_equal_approx(player.vitals.health, once - enemy.damage),
		"%s enemy deals another hit after the interval" % label)
	enemy.queue_free()
	await _wait_frames(3)

func _check_checkpoint(branch: Node2D, section: GameplayLayer) -> void:
	var label := str(section.name)
	var checkpoint := CHECKPOINT_SCENE.instantiate() as Checkpoint
	checkpoint.position.y = -18
	checkpoint.respawn_offset = Vector2(40, 18)
	branch.add_child(checkpoint)
	var shape: CollisionShape2D = checkpoint.get_node("CollisionShape2D")
	_expect(checkpoint.layer_context.gameplay_layer == section
		and checkpoint.layer_context.logical_layer == section.current_layer and checkpoint.collision_layer == 0
		and checkpoint.collision_mask == GameplayLayer.solid_collision_bit(section.current_layer),
		"%s checkpoint inherits the layer and stays non-solid" % label)
	_expect(_matches_depth(checkpoint.depth_visuals, section) and not checkpoint.depth_visuals.visible
		and shape.global_scale.is_equal_approx(Vector2.ONE)
		and shape.shape.get_rect().size.is_equal_approx(Vector2(28, 484.77)),
		"%s checkpoint marker uses depth and its sensor keeps its original dimensions" % label)
	var original := Vector2(-300, 315)
	player.set_checkpoint(original, 3)
	var foreign := _other_layer(section.current_layer)
	var contact := checkpoint.global_position + Vector2(0, 18)
	_place_player(foreign, contact)
	await _wait_frames(5)
	_expect(player.checkpoint_position == original and player.checkpoint_layer == 3,
		"%s checkpoint ignores overlap from a foreign layer" % label)
	_place_player(section.current_layer, contact)
	await _wait_frames(5)
	var destination := checkpoint.global_position + checkpoint.respawn_offset
	_expect(player.checkpoint_position.is_equal_approx(destination) and player.checkpoint_layer == section.current_layer,
		"%s checkpoint saves its exact spawn position and logical layer" % label)
	_place_player(foreign, contact - Vector2(75, 0))
	player.vitals.take_damage(player.vitals.max_health)
	for _frame in range(230):
		if not bool(main.get("_respawn_in_progress")):
			break
		await physics_frame
	_expect(not bool(main.get("_respawn_in_progress")) and player.is_physics_processing()
		and player.current_layer == section.current_layer and player.collision_mask == checkpoint.collision_mask
		and player.global_position.distance_to(destination) < 0.5
		and is_equal_approx(player.vitals.health, player.vitals.max_health),
		"%s checkpoint respawns the player at the saved point with matching collision and health" % label)
	player.set_physics_process(false)
	checkpoint.queue_free()
	await _wait_frames(3)

func _check_mount_and_override() -> void:
	var section: GameplayLayer = main.get_node("FrontLayer2")
	var branch := Node2D.new()
	section.add_child(branch)
	var pedestal := PEDESTAL_SCENE.instantiate() as OrbReceiver
	branch.add_child(pedestal)
	var start := pedestal.global_position
	branch.position += Vector2(100, 20)
	await _wait_frames(3)
	_expect(pedestal.global_position.is_equal_approx(start + Vector2(32.5, 20))
		and pedestal.body.global_scale.is_equal_approx(Vector2.ONE),
		"Moving a placement branch moves the pedestal and its body at the original size")
	pedestal.layer_context.mode = LayerContext.Mode.DYNAMIC
	pedestal.layer_context.set_dynamic_layer(3)
	await _wait_frames(18)
	_expect(pedestal.layer_context.gameplay_layer == null and pedestal.current_layer == 3
		and pedestal.body.collision_layer == 4 and _matches_depth(pedestal.depth_visuals, main.get_node("BackLayer")),
		"A Dynamic override updates the pedestal collision and shared logical profile")
	branch.queue_free()

func _matches_depth(visuals: LayerDepthVisuals, section: GameplayLayer) -> bool:
	return visuals.global_scale.is_equal_approx(Vector2.ONE * section.depth_scale) \
		and visuals.modulate.is_equal_approx(section.depth_modulation())

func _sees_pedestal(pedestal: OrbReceiver, shape: CollisionShape2D, mask: int) -> bool:
	var sample := CircleShape2D.new()
	sample.radius = 2
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = sample
	query.transform.origin = shape.global_position
	query.collision_mask = mask
	for hit in pedestal.get_world_2d().direct_space_state.intersect_shape(query):
		if hit.collider == pedestal.body:
			return true
	return false

func _other_layer(layer: int) -> int:
	return layer % 3 + 1

func _place_player(layer: int, point: Vector2) -> void:
	player.current_layer = layer
	player._apply_layer_mask()
	player.global_position = point
	player.velocity = Vector2.ZERO

func _press_orb_key() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

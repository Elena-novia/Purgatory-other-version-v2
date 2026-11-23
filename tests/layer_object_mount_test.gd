extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const PEDESTAL := preload("res://scenes/interactables/pedestal.tscn")
const ENEMY := preload("res://scenes/world/enemy.tscn")
const CHECKPOINT := preload("res://scenes/world/checkpoint.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN.instantiate()
	root.add_child(main)
	var back: GameplayLayer = main.get_node("BackLayer")
	var back_two: GameplayLayer = main.get_node("BackLayer2")
	var front_two: GameplayLayer = main.get_node("FrontLayer2")
	back_two.depth_scale = 0.76
	back_two.tint_strength = 0.49
	var source := _branch(back, Vector2(4500, -220), 0.0, Vector2.ONE)
	var same_layer := _branch(back_two, Vector2(3900, -410), -0.53, Vector2(1.6, 0.78))
	var other_layer := _branch(front_two, Vector2(5700, -520), 0.36, Vector2(0.82, 1.21))

	await _check_object(PEDESTAL, "Pedestal", "Body/CollisionShape2D",
		Vector2(46, 38), source, same_layer, other_layer, back_two, front_two)
	await _check_object(ENEMY, "Enemy", "CollisionShape2D",
		Vector2(34, 34), source, same_layer, other_layer, back_two, front_two)
	await _check_object(CHECKPOINT, "Checkpoint", "CollisionShape2D",
		Vector2(28, 484.77), source, same_layer, other_layer, back_two, front_two)

	if failures.is_empty():
		print("Layer object mount: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_object(scene: PackedScene, label: String, shape_path: NodePath, dimensions: Vector2,
		source: Node2D, same_layer: Node2D, other_layer: Node2D,
		back_two: GameplayLayer, front_two: GameplayLayer) -> void:
	var object := scene.instantiate() as Node2D
	if object is EnemyHazard:
		object.patrol_distance = 0.0
	var local := Transform2D(0.27, Vector2(1.16, 0.88), 0.18, Vector2(46, -35))
	object.transform = local
	source.add_child(object)
	var shape := object.get_node(shape_path) as CollisionShape2D
	var context := object.get_node("LayerContext") as LayerContext
	var transitions: Array[int] = []
	context.context_changed.connect(func(): transitions.append(context.logical_layer))
	_expect(object.global_transform.is_equal_approx(_world(source.global_transform, local))
		and is_equal_approx(object.skew, 0.18), label + " preserves the complete authored pose")

	source.position += Vector2(56, 21)
	await _frames(2)
	_expect(object.global_transform.is_equal_approx(_world(source.global_transform, local)),
		label + " follows branch translation")
	source.rotation += 0.48
	await _frames(2)
	_expect(object.global_transform.is_equal_approx(_world(source.global_transform, local)),
		label + " follows branch rotation")
	source.scale = Vector2(1.48, 0.61)
	source.skew = 0.22
	await _frames(2)
	_expect(object.global_transform.is_equal_approx(_world(source.global_transform, local)),
		label + " follows combined parent translation, rotation, scale and skew")
	_expect(_physical_size(shape, dimensions, local), label + " retains authored physical dimensions")

	var before := object.global_transform
	object.reparent(same_layer, true)
	_expect(object.global_transform.is_equal_approx(before), label + " keeps its complete world pose immediately on true reparent")
	await _frames(18)
	_expect(object.global_transform.is_equal_approx(before), label + " keeps the same pose after reparent processing")
	_expect(context.gameplay_layer == back_two and context.logical_layer == 3
		and _uses_profile(object, back_two), label + " adopts the new section profile with the same logical layer")
	var relative := _relative(same_layer.global_transform, before)
	same_layer.position += Vector2(33, -14)
	same_layer.rotation += 0.21
	same_layer.scale *= Vector2(0.85, 1.28)
	await _frames(2)
	_expect(object.global_transform.is_equal_approx(_world(same_layer.global_transform, relative)),
		label + " follows its new parent after true reparent")
	_expect(_physical_size(shape, dimensions, local), label + " keeps its physical dimensions after true reparent")

	object.reparent(other_layer, false)
	_expect(object.global_transform.is_equal_approx(_world(other_layer.global_transform, relative)),
		label + " keeps its complete relative pose immediately on false reparent")
	await _frames(18)
	_expect(context.gameplay_layer == front_two and context.logical_layer == 1
		and _uses_profile(object, front_two) and transitions == [3, 1],
		label + " resolves the new logical layer and visual profile once per reparent")
	other_layer.position += Vector2(-23, 64)
	other_layer.rotation -= 0.31
	other_layer.scale *= Vector2(1.11, 0.91)
	await _frames(2)
	_expect(object.global_transform.is_equal_approx(_world(other_layer.global_transform, relative)),
		label + " follows its new parent after false reparent")
	_expect(_physical_size(shape, dimensions, local), label + " keeps its physical dimensions after false reparent")
	object.queue_free()
	await _frames(2)

func _branch(section: GameplayLayer, point: Vector2, angle: float, sizing: Vector2) -> Node2D:
	var branch := Node2D.new()
	branch.transform = Transform2D(angle, sizing, 0.0, point)
	section.add_child(branch)
	return branch

func _orientation(frame: Transform2D) -> Transform2D:
	var direction := frame.x.normalized()
	var perpendicular := Vector2(-direction.y, direction.x) * signf(frame.determinant())
	return Transform2D(direction, perpendicular, Vector2.ZERO)

func _world(frame: Transform2D, local: Transform2D) -> Transform2D:
	var expected := _orientation(frame) * local
	expected.origin = frame * local.origin
	return expected

func _relative(frame: Transform2D, world: Transform2D) -> Transform2D:
	var expected := _orientation(frame).affine_inverse() * world
	expected.origin = frame.affine_inverse() * world.origin
	return expected

func _physical_size(shape: CollisionShape2D, dimensions: Vector2, authored: Transform2D) -> bool:
	return shape.shape.get_rect().size.is_equal_approx(dimensions) \
		and is_equal_approx(shape.global_transform.x.length(), authored.x.length()) \
		and is_equal_approx(shape.global_transform.y.length(), authored.y.length())

func _uses_profile(object: Node2D, section: GameplayLayer) -> bool:
	var visuals := object.get_node("DepthVisuals") as LayerDepthVisuals
	return visuals.scale.is_equal_approx(Vector2.ONE * section.depth_scale) \
		and visuals.modulate.is_equal_approx(section.depth_modulation())

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

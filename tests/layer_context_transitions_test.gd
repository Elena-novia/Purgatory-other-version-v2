extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const PEDESTAL := preload("res://scenes/interactables/pedestal.tscn")
const ENEMY := preload("res://scenes/world/enemy.tscn")
const CHECKPOINT := preload("res://scenes/world/checkpoint.tscn")

var failures: Array[String] = []
var main: Node2D
var player: PlayerController

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = MAIN.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	player.set_physics_process(false)
	await _check_object(PEDESTAL, "Pedestal")
	await _check_object(ENEMY, "Enemy")
	await _check_object(CHECKPOINT, "Checkpoint")
	if failures.is_empty():
		print("Layer context transitions: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_object(scene: PackedScene, label: String) -> void:
	var middle := main.get_node("MiddleLayer") as GameplayLayer
	var back := main.get_node("BackLayer") as GameplayLayer
	var back_two := main.get_node("BackLayer2") as GameplayLayer
	var front := main.get_node("FrontLayer") as GameplayLayer
	var front_two := main.get_node("FrontLayer2") as GameplayLayer
	var branches: Array[Node2D] = [_branch(middle), _branch(main), _branch(back_two),
		_branch(back), _branch(front), _branch(front_two), _branch(front_two)]
	var object := scene.instantiate() as Node2D
	if object is EnemyHazard:
		object.patrol_distance = 0.0
	branches[0].add_child(object)
	var context := object.get_node("LayerContext") as LayerContext
	var visuals := object.get_node("DepthVisuals") as LayerDepthVisuals
	var events: Array[int] = []
	context.context_changed.connect(func(): events.append(context.logical_layer))
	_place_player(object, 2)
	await _frames(4)
	_expect(_matches(object, middle, middle, 2) and _detects(object, 2),
		label + " starts with an effective Middle collider or overlap and its Middle profile")

	var world := object.global_transform
	object.reparent(branches[1], true)
	_expect(object.global_transform.is_equal_approx(world) and _matches(object, null, null, 0),
		label + " resolves to neutral immediately and retains its pose on true reparent")
	_place_player(object, 2)
	await _frames(4)
	_expect(not _detects(object, 2) and events == [0],
		label + " no longer interacts with Middle in the physics space and publishes once")
	var saved_middle_scale := middle.depth_scale
	middle.depth_scale = 0.92
	await _frames(18)
	_expect(_matches(object, null, null, 0) and _connections(middle.depth_changed, visuals) == 0
		and _connections(middle.logical_layer_changed, context) == 0,
		label + " stays neutral when the former owner changes")

	object.reparent(branches[2], false)
	_place_player(object, 3)
	await _frames(18)
	_expect(_matches(object, back_two, back_two, 3) and _detects(object, 3) and events == [0, 3],
		label + " restores its collision and section profile in BackLayer2")
	var saved_back_scale := back_two.depth_scale
	middle.depth_scale = saved_middle_scale
	await _frames(18)
	_expect(_matches(object, back_two, back_two, 3) and _connections(middle.depth_changed, visuals) == 0,
		label + " ignores later changes to the old Middle owner")
	back_two.depth_scale = 0.76
	await _frames(18)
	_expect(_matches(object, back_two, back_two, 3) and _connections(back_two.depth_changed, visuals) == 1,
		label + " responds exactly once to its new Back profile")

	object.reparent(branches[1], false)
	_place_player(object, 3)
	await _frames(4)
	_expect(_matches(object, null, null, 0) and not _detects(object, 3) and events == [0, 3, 0],
		label + " clears Back on a second detach using false reparent")
	object.reparent(branches[3], false)
	await _frames(18)
	object.reparent(branches[2], true)
	await _frames(18)
	_expect(_matches(object, back_two, back_two, 3) and _connections(back.depth_changed, visuals) == 0
		and events == [0, 3, 0, 3, 3], label + " switches physical Back section without a duplicate event")
	back_two.depth_scale = saved_back_scale

	object.reparent(branches[4], false)
	await _frames(18)
	object.reparent(branches[5], true)
	await _frames(18)
	_expect(_matches(object, front_two, front_two, 1) and _connections(front.depth_changed, visuals) == 0
		and events == [0, 3, 0, 3, 3, 1, 1], label + " publishes the different-layer and same-layer Front moves")
	object.reparent(branches[6], true)
	await _frames(4)
	_expect(events.size() == 7 and _connections(front_two.depth_changed, visuals) == 1
		and _connections(front_two.logical_layer_changed, context) == 1,
		label + " keeps one subscription and publishes nothing when the section stays the same")

	branches[6].remove_child(object)
	_expect(context.logical_layer == 0 and context.gameplay_layer == null and events.size() == 7
		and _connections(front_two.depth_changed, visuals) == 0 and _connections(front_two.logical_layer_changed, context) == 0,
		label + " disconnects on tree exit without publishing an intermediate state")
	branches[6].add_child(object)
	await _frames(18)
	_expect(_matches(object, front_two, front_two, 1) and events.size() == 7
		and _connections(front_two.depth_changed, visuals) == 1,
		label + " restores its subscription after reentering the same section")
	context.fixed_layer = 2
	context.mode = LayerContext.Mode.FIXED
	await _frames(18)
	_expect(_matches(object, null, middle, 2) and events.back() == 2,
		label + " keeps a valid Fixed context and uses the shared Middle profile")
	context.fixed_layer = 0
	_expect(_matches(object, null, null, 0) and events.back() == 0,
		label + " clears its settings immediately when Fixed becomes unresolved")
	context.initial_dynamic_layer = 3
	context.mode = LayerContext.Mode.DYNAMIC
	await _frames(18)
	_expect(_matches(object, null, back, 3) and events == [0, 3, 0, 3, 3, 1, 1, 2, 0, 3],
		label + " still resolves a Dynamic layer without requiring an owner")

	for branch in branches:
		branch.queue_free()
	player.vitals.restore()
	player.cancel_damage_reaction()
	await _frames(3)

func _branch(parent: Node2D) -> Node2D:
	var branch := Node2D.new()
	branch.position = parent.to_local(Vector2(4200, 240))
	parent.add_child(branch)
	return branch

func _place_player(object: Node2D, layer: int) -> void:
	player.current_layer = layer
	player._apply_layer_mask()
	player.global_position = object.global_position + Vector2(0, 24)
	player.velocity = Vector2.ZERO

func _detects(object: Node2D, layer: int) -> bool:
	if object is OrbReceiver:
		var collider: CollisionShape2D = object.get_node("Body/CollisionShape2D")
		var sample := CircleShape2D.new()
		sample.radius = 2.0
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = sample
		query.transform.origin = collider.global_position
		query.collision_mask = GameplayLayer.solid_collision_bit(layer)
		return object.get_world_2d().direct_space_state.intersect_shape(query).any(
			func(hit: Dictionary): return hit.collider == object.body)
	return (object as Area2D).overlaps_body(player)

func _matches(object: Node2D, owner: GameplayLayer, profile: GameplayLayer, layer: int) -> bool:
	var context := object.get_node("LayerContext") as LayerContext
	var visuals := object.get_node("DepthVisuals") as LayerDepthVisuals
	var bit := GameplayLayer.solid_collision_bit(layer)
	var collider_matches: bool = object.body.collision_layer == bit and object.body.collision_mask == 0 if object is OrbReceiver \
		else (object as Area2D).collision_mask == bit and (object as Area2D).collision_layer == 0
	var scale_factor := profile.depth_scale if profile != null else 1.0
	var tint := profile.depth_modulation() if profile != null else Color.WHITE
	return context.logical_layer == layer and context.gameplay_layer == owner and context.depth_profile == profile \
		and collider_matches and visuals.global_scale.is_equal_approx(Vector2.ONE * scale_factor) \
		and visuals.modulate.is_equal_approx(tint)

func _connections(observed: Signal, target: Node) -> int:
	return observed.get_connections().filter(
		func(entry: Dictionary): return entry.callable.get_object() == target).size()

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

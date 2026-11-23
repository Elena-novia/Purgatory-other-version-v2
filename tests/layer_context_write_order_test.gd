extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const TERRAIN := preload("res://scripts/world/terrain_polygon.gd")

var world: Node2D
var player: PlayerController
var context: LayerContext
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_standalone_fifo(false)
	await _check_standalone_fifo(true)
	world = MAIN.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	context = player.layer_context
	await _check_explicit_support()
	await _check_coplanar_and_removed_support()
	await _check_deferred_support()
	await _check_foreign_landing()
	await _check_coordinated_request()
	world.queue_free()
	await _frames(2)
	quit(1 if failures else 0)

func _standalone_context() -> LayerContext:
	var standalone := LayerContext.new()
	standalone.mode = LayerContext.Mode.DYNAMIC
	standalone.initial_dynamic_layer = 1
	root.add_child(standalone)
	return standalone

func _check_standalone_fifo(multiple_writers: bool) -> void:
	var standalone := _standalone_context()
	var trace: Array[String] = []
	var admissions: Array[bool] = []
	var snapshots: Array[bool] = []
	var a := func():
		var layer := standalone.logical_layer
		trace.append("A%d" % layer)
		if trace.size() == 1:
			admissions.append(standalone.set_dynamic_layer(1))
			if multiple_writers:
				admissions.append(standalone.set_dynamic_layer(0))
				admissions.append(standalone.set_dynamic_layer(3))
				admissions.append(standalone.set_dynamic_layer(3))
		snapshots.append(_matches_layer(standalone, layer))
	var b := func():
		var layer := standalone.logical_layer
		trace.append("B%d" % layer)
		if multiple_writers and trace.size() == 2:
			admissions.append(standalone.set_dynamic_layer(2))
			admissions.append(standalone.set_dynamic_layer(4))
			admissions.append(standalone.set_dynamic_layer(1))
		snapshots.append(_matches_layer(standalone, layer))
	standalone.context_changed.connect(a)
	standalone.context_changed.connect(b)
	_expect(standalone.logical_layer == 1 and standalone.set_dynamic_layer(2), "Initial standalone write commits synchronously")
	if multiple_writers:
		admissions.append(standalone.set_dynamic_layer(-1))
		admissions.append(standalone.set_dynamic_layer(2))
	admissions.append(standalone.set_dynamic_layer(3))
	_expect(trace == ["A2", "B2"] and standalone.logical_layer == 2,
		"Later calls cannot pass older requests before the next physics frame")
	await _frames(3)
	var expected := ["A2", "B2", "A1", "B1", "A3", "B3"]
	var expected_admissions := [true, true]
	if multiple_writers:
		expected.append_array(["A2", "B2", "A1", "B1", "A2", "B2", "A3", "B3"])
		expected_admissions = [true, false, true, true, true, false, true, false, true, true]
	_expect(admissions == expected_admissions, "Valid writes are admitted and interleaved invalid indices are rejected")
	_expect(trace == expected and standalone.logical_layer == 3, "FIFO order, no duplicate signals, final layer 3: %s" % str(trace))
	_expect(snapshots.size() == trace.size() and not snapshots.has(false),
		"Both standalone observers see stable indices, bits and ownership")
	standalone.free()

func _check_explicit_support() -> void:
	var front: GameplayLayer = world.get_node("FrontLayer")
	var remote := _floor("UnrelatedFront", 1, Vector2(9000, 520))
	await _place(1, Vector2(160, 520), 6)
	var trace: Array[String] = []
	var a := func(): trace.append(_snapshot("A"))
	var b := func(): trace.append(_snapshot("B"))
	context.context_changed.connect(a)
	context.context_changed.connect(b)
	_expect(player.is_on_floor() and context.gameplay_layer == front, "FrontLayer is the actual owner at the original contact")
	var distance := player.global_position.distance_to(remote.global_position)
	var accepted := context.set_dynamic_layer(1, remote)
	await _frames(3)
	_expect(is_equal_approx(distance, 8840.0) and not accepted and context.gameplay_layer == front and trace.is_empty(),
		"UnrelatedFront at 8840 pixels is rejected without any owner notification")
	_expect(context.set_dynamic_layer(1, front) and trace.is_empty(), "A confirmed same-owner write is accepted without a duplicate signal")
	var standalone := _standalone_context()
	_expect(standalone.set_dynamic_layer(1, remote) and standalone.gameplay_layer == remote,
		"A standalone context still accepts an explicit owner without any player contact")
	standalone.free()
	await _place(1, Vector2(160, 450), 1)
	trace.clear()
	_expect(not player.is_on_floor() and not context.set_dynamic_layer(1, front) and _owner_name() == "null",
		"A valid floor below an airborne capsule cannot be claimed from the air")
	await _place(1, Vector2(8500, 600), 1)
	trace.clear()
	_expect(not player.is_on_floor() and not context.set_dynamic_layer(1, remote) and _owner_name() == "null"
		and trace.is_empty() and _matches_layer(context, 1), "A capsule above the void stays on a valid logical layer without a physical owner")
	context.context_changed.disconnect(a)
	context.context_changed.disconnect(b)
	remote.queue_free()

func _check_coplanar_and_removed_support() -> void:
	var first := _floor("CoincidentA", 1, Vector2(4800, 500))
	var second := _floor("CoincidentB", 1, Vector2(4800, 500))
	await _place(1, Vector2(4860, 480), 25)
	var trace: Array[String] = []
	var steps: Array[int] = []
	var removal: Array[bool] = []
	var a := func():
		trace.append(_snapshot("A"))
		if context.gameplay_layer == first:
			var path := context.owner_path
			var queued := context.set_dynamic_layer(1, first)
			world.remove_child(first)
			removal.append(queued and context.gameplay_layer == first and context.owner_path == path)
	var b := func(): trace.append(_snapshot("B"))
	var layer_event := func(layer: int): steps.append(layer)
	context.context_changed.connect(a)
	context.context_changed.connect(b)
	player.layer_changed.connect(layer_event)
	_expect(player.is_on_floor() and context.gameplay_layer == null and not context.set_dynamic_layer(1, first)
		and not context.set_dynamic_layer(1, second) and trace.is_empty(), "Coplanar support rejects both arbitrary owners")
	second.position.y += 3.0
	await _frames(18)
	_expect(removal == [true] and trace == ["A1/CoincidentA", "B1/CoincidentA", "A1/null", "B1/null",
		"A1/CoincidentB", "B1/CoincidentB"], "Both observers see the same publication, one removal and the new support: %s" % str(trace))
	_expect(context.gameplay_layer == second and steps.is_empty() and _matches_layer(context, 1),
		"Changing physical sections at the same index leaves layer_changed silent")
	context.context_changed.disconnect(a)
	context.context_changed.disconnect(b)
	player.layer_changed.disconnect(layer_event)
	first.free()
	second.queue_free()

func _check_deferred_support() -> void:
	var first := _floor("InitialSupport", 1, Vector2(5100, 500))
	var second := _floor("DeferredSupport", 1, Vector2(5400, 500))
	await _place(1, Vector2(5160, 450), 1)
	var trace: Array[String] = []
	var admissions: Array[bool] = []
	var a := func():
		trace.append(_snapshot("A"))
		if context.gameplay_layer == first:
			player.global_position.x = 5460.0
			admissions.append(context.set_dynamic_layer(1, second))
			player.global_position.y -= 60.0
	var b := func(): trace.append(_snapshot("B"))
	context.context_changed.connect(a)
	context.context_changed.connect(b)
	await _frames(23)
	_expect(admissions == [true] and trace == ["A1/InitialSupport", "B1/InitialSupport", "A1/null", "B1/null"]
		and second.is_available_as_owner() and not player.is_on_floor() and context.gameplay_layer == null,
		"A queued owner that loses capsule contact is revalidated before publication: %s" % str(trace))
	context.context_changed.disconnect(a)
	context.context_changed.disconnect(b)
	first.queue_free()
	second.queue_free()

func _check_foreign_landing() -> void:
	var middle := _floor("ForeignMiddle", 2, Vector2(7000, 520))
	await _place(1, Vector2(7060, 450), 1)
	var trace: Array[String] = []
	var a := func(): trace.append(_snapshot("A"))
	var b := func(): trace.append(_snapshot("B"))
	var layer_event := func(layer: int): trace.append("L%d/%s" % [layer, _owner_name()])
	context.context_changed.connect(a)
	context.context_changed.connect(b)
	player.layer_changed.connect(layer_event)
	_expect(not context.set_dynamic_layer(2, middle) and trace.is_empty() and _matches_layer(context, 1),
		"An explicit owner cannot force the player to another logical layer")
	await _frames(35)
	_expect(player.is_on_floor() and _matches_layer(context, 2) and context.gameplay_layer == middle
		and trace == ["A2/ForeignMiddle", "B2/ForeignMiddle", "L2/ForeignMiddle"],
		"Landing on real one-way support publishes the new owner and layer atomically: %s" % str(trace))
	context.context_changed.disconnect(a)
	context.context_changed.disconnect(b)
	player.layer_changed.disconnect(layer_event)
	middle.queue_free()

func _check_coordinated_request() -> void:
	await _place(2, Vector2(895, 482), 8)
	player.magic_orb.toggle_release_or_retrieve()
	await _place(2, Vector2(500, 482), 5)
	var box: PushBox = world.get_node("Box")
	var trace: Array[bool] = []
	var observe := func():
		trace.append(_matches_layer(context, 3) and box.current_layer == 3 and box.collision_mask == context.solid_bit
			and player.magic_orb.current_layer == 3 and player.magic_orb.stored_receiver == box)
	var layer_event := func(layer: int):
		if layer == 3:
			observe.call()
	context.context_changed.connect(observe)
	player.layer_changed.connect(layer_event)
	_expect(player.magic_orb.stored_receiver == box and context.set_dynamic_layer(3) and trace == [true, true],
		"A managed index request still commits through the coordinated player, box and orb path")
	context.context_changed.disconnect(observe)
	player.layer_changed.disconnect(layer_event)

func _floor(label: String, layer: int, at: Vector2) -> GameplayLayer:
	var section := GameplayLayer.new()
	section.name = label
	section.current_layer = layer
	section.position = at
	var art := Node2D.new()
	art.name = "ParallaxDecoration"
	var details := Node2D.new()
	details.name = "DepthDetails"
	art.add_child(details)
	section.add_child(art)
	var ground := CollisionPolygon2D.new()
	ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(180, 0), Vector2(180, 80), Vector2(0, 80)])
	ground.set_script(TERRAIN)
	ground.set("supports_other_layers", true)
	section.add_child(ground)
	world.add_child(section)
	return section

func _matches_layer(subject: LayerContext, layer: int) -> bool:
	var bit := GameplayLayer.solid_collision_bit(layer)
	if subject.logical_layer != layer or subject.solid_bit != bit \
			or subject.ground_support_bit != GameplayLayer.landing_surface_bit(layer):
		return false
	if subject == context:
		return player.current_layer == layer and player.collision_layer == bit and player.collision_mask == bit
	return subject.gameplay_layer == null and subject.owner_path.is_empty()

func _owner_name() -> String:
	return str(context.gameplay_layer.name) if context.gameplay_layer != null else "null"

func _snapshot(observer: String) -> String:
	return "%s%d/%s" % [observer, context.logical_layer, _owner_name()] if _matches_layer(context, context.logical_layer) else "inconsistent"

func _place(layer: int, at: Vector2, frames: int) -> void:
	player.set_checkpoint(at, layer)
	player.restore_checkpoint()
	await _frames(frames)

func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		failures += 1

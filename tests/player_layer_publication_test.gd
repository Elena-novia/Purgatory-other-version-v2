extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const TERRAIN := preload("res://scripts/world/terrain_polygon.gd")
const STEP_LIMIT := PlayerController.LAYER_STEPS_PER_PHYSICS_FRAME
const QUEUE_CAPACITY := PlayerController.MAX_PENDING_LAYER_STEPS

var world: Node2D
var player: PlayerController
var context: LayerContext
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = MAIN.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	context = player.layer_context
	if "--stress-only" in OS.get_cmdline_user_args():
		await _check_continuous_requests()
		await _check_overload()
	else:
		await _check_fifo()
		await _check_continuous_requests()
		await _check_overload()
		await _check_owner_notifications()
		await _check_restore_from_observer()
		await _check_cross_layer_landings()
	world.queue_free()
	await _frames(2)
	quit(1 if failed else 0)

func _check_fifo() -> void:
	await _place(2, Vector2(160, 482))
	var arrivals: Array[int] = [1, -1, 1, -1, -1, -1, 1, -1, 1, 1, -1, 1, -1, 1]
	var expected: Array[int] = [3, 2, 3, 2, 1, 2, 1, 2, 3, 2, 3, 2, 3]
	for _i in range(6):
		arrivals.append_array([-1, 1])
		expected.append_array([2, 3])
	var total_requested := arrivals.size() + 1
	var trace: Array[String] = []
	var last_index: Array[int] = [2]
	var admitted: Array[bool] = []
	var on_context := func():
		var index := context.logical_layer
		if index == last_index[0]:
			return
		last_index[0] = index
		trace.append("C%d" % index)
		if index == 3 and not arrivals.is_empty():
			admitted.append(not player.request_layer_step(0))
			for step in arrivals:
				admitted.append(player.request_layer_step(step))
			arrivals.clear()
	var on_layer := func(index: int): trace.append("L%d" % index)
	context.context_changed.connect(on_context)
	player.layer_changed.connect(on_layer)
	player.try_change_layer(1)
	_expect(admitted.size() == total_requested and not admitted.has(false),
		"All directional entries were admitted, and direction zero was rejected")
	_expect(trace == _pairs(expected.slice(0, STEP_LIMIT - 2)) and _pending() == total_requested - STEP_LIMIT,
		"First budget counts the invalid destinations and leaves the remaining entries pending")
	await _frames(4)
	_expect(trace == _pairs(expected) and _pending() == 0,
		"Deferred requests retain FIFO order, revalidate against the current layer and survive rejected entries")
	print("QUEUE_FIFO ", trace)
	context.context_changed.disconnect(on_context)
	player.layer_changed.disconnect(on_layer)

func _check_continuous_requests() -> void:
	await _place(2, Vector2(160, 482))
	var by_frame := {}
	var layers: Array[int] = []
	var running: Array[bool] = [true]
	var pending_peak: Array[int] = [0]
	var observe := func(index: int):
		layers.append(index)
		var frame := Engine.get_physics_frames()
		var count: int = by_frame.get(frame, 0) + 1
		by_frame[frame] = count
		# Tripwire for faulty builds. The runner also uses an external watchdog.
		if running[0] and count <= STEP_LIMIT * 3:
			player.try_change_layer(-1 if index == 3 else 1)
			pending_peak[0] = maxi(pending_peak[0], _pending())
	player.layer_changed.connect(observe)
	var first_frame := Engine.get_physics_frames()
	player.try_change_layer(1)
	await _frames(14)
	running[0] = false
	await _frames(2)
	player.layer_changed.disconnect(observe)
	var peak := _peak(by_frame.values())
	_expect(Engine.get_physics_frames() >= first_frame + 14 and by_frame.size() >= 14,
		"An observer requesting the reverse transition continuously cannot stall physics frames")
	_expect(peak <= STEP_LIMIT and layers.size() > STEP_LIMIT,
		"The per-frame limit applies even when all requests continue to validate")
	_expect(pending_peak[0] <= 1 and _pending() == 0 and _alternates(layers),
		"An inverse request per transition stays bounded, preserves order and drains after disconnecting the producer")
	print("QUEUE_CONTINUOUS frames=", by_frame.size(), " peak_per_frame=", peak,
		" transitions=", layers.size(), " peak_pending=", pending_peak[0])

func _check_overload() -> void:
	await _place(2, Vector2(160, 482))
	var expected: Array[int] = [3]
	var observed: Array[int] = []
	var next_step: Array[int] = [-1]
	var refused: Array[int] = [0]
	var peak: Array[int] = [0]
	var running: Array[bool] = [true]
	var receive := func(index: int):
		observed.append(index)
		if running[0]:
			for _i in range(2):
				if player.request_layer_step(next_step[0]):
					expected.append(2 if next_step[0] == -1 else 3)
					next_step[0] = -next_step[0]
				else:
					refused[0] += 1
				peak[0] = maxi(peak[0], _pending())
	player.layer_changed.connect(receive)
	player.try_change_layer(1)
	await _frames(15)
	running[0] = false
	await _frames(12)
	player.layer_changed.disconnect(receive)
	_expect(refused[0] > 0 and peak[0] == QUEUE_CAPACITY,
		"An overproducing observer receives explicit backpressure at finite capacity")
	_expect(observed == expected and _pending() == 0 and _alternates(observed),
		"All accepted requests, including successful retries, eventually complete in FIFO order")
	print("QUEUE_OVERLOAD capacity=", peak[0], " accepted=", expected.size(),
		" explicitly_refused=", refused[0], " completed=", observed.size())

func _check_owner_notifications() -> void:
	var front_a := _section("OwnerA", 1, Vector2(4380, 500), 120)
	var front_b := _section("OwnerB", 1, Vector2(4500, 500), 200)
	var middle := _section("OwnerMiddle", 2, Vector2(4380, 462), 320)
	await _place(1, Vector2(4480, 500))
	_expect(context.gameplay_layer == front_a, "Front A has confirmed support before crossing the seam")
	var logical_events: Array[int] = []
	var observe_layer := func(index: int): logical_events.append(index)
	player.layer_changed.connect(observe_layer)
	Input.action_press("move_right")
	await _frames(18)
	Input.action_release("move_right")
	await _frames(2)
	_expect(context.gameplay_layer == front_b and logical_events.is_empty(),
		"Walking Front A to B changes the physical owner without layer_changed")
	player.layer_changed.disconnect(observe_layer)

	await _place(1, Vector2(4480, 500))
	for _i in range(STEP_LIMIT):
		player.try_change_layer(-1)
	player.try_change_layer(1)
	_expect(_pending() == 1, "An older FIFO entry is already pending before the owner changes")

	var trace: Array[String] = []
	var observed_b: Array[bool] = []
	var first := func():
		trace.append(_state("A"))
		if context.gameplay_layer == front_b:
			player.try_change_layer(-1)
			player.try_change_layer(1)
			observed_b.append(context.gameplay_layer == front_b and _solid(1) and _pending() == 3)
	var second := func():
		trace.append(_state("B"))
		if context.gameplay_layer == front_b:
			observed_b.append(_solid(1) and _pending() == 3)
	var layer_listener := func(_index: int): trace.append(_state("L"))
	context.context_changed.connect(first)
	context.context_changed.connect(second)
	player.layer_changed.connect(layer_listener)
	player.global_position = Vector2(4560, 500)
	await _frames(3)
	context.context_changed.disconnect(first)
	context.context_changed.disconnect(second)
	player.layer_changed.disconnect(layer_listener)
	var expected: Array[String] = ["A1:OwnerB", "B1:OwnerB", "A2:null", "B2:null", "L2:null",
		"A1:null", "B1:null", "L1:null", "A2:null", "B2:null", "L2:null"]
	_expect(observed_b == [true, true] and trace.slice(0, expected.size()) == expected,
		"Both observers see Front B with all three requests pending, then the original FIFO order completes")
	_expect(context.gameplay_layer == middle and _solid(2) and _pending() == 0,
		"The last request completes on Middle and ownership confirms on contact")
	print("OWNER_PUBLICATION ", trace)

func _check_restore_from_observer() -> void:
	await _place(2, Vector2(160, 482))
	player.set_checkpoint(Vector2(160, 520), 1)
	var trace: Array[String] = []
	var requested: Array[bool] = [false]
	var request := func():
		if context.logical_layer == 3 and not requested[0]:
			requested[0] = true
			trace.append("request")
			player.restore_checkpoint()
			trace.append("still-%d" % context.logical_layer)
	var observe := func(): trace.append("C%d" % context.logical_layer)
	var layer_observer := func(index: int): trace.append("L%d" % index)
	context.context_changed.connect(request)
	context.context_changed.connect(observe)
	player.layer_changed.connect(layer_observer)
	player.try_change_layer(1)
	_expect(trace == ["request", "still-3", "C3", "L3"], "A restore requested by an observer cannot interrupt active publication")
	await _frames(3)
	context.context_changed.disconnect(request)
	context.context_changed.disconnect(observe)
	player.layer_changed.disconnect(layer_observer)
	_expect(trace.find("C1") > trace.find("L3") and trace.filter(func(event): return event.begins_with("L")) == ["L3"]
		and _solid(1),
		"The requested restore runs after the Back notification and retains checkpoint signal semantics")
	print("RESTORE_OBSERVER ", trace)

func _check_cross_layer_landings() -> void:
	var contacted := _section("CrossSingle", 2, Vector2(5000, 500), 180)
	await _fall(5070.0, contacted, null, "Single cross-layer floor", true)

	var a := _section("CoincidentA", 2, Vector2(5300, 500), 180)
	var b := _section("CoincidentB", 2, Vector2(5300, 500), 180)
	await _fall(5370.0, null, b, "Identical coplanar floors")
	_expect(context.gameplay_layer == a and _solid(2),
		"Removing one coplanar floor later establishes the surviving owner without changing the layer")

	var partial := _section("PartialA", 2, Vector2(5600, 500), 200)
	_section("PartialB", 2, Vector2(5680, 500), 200)
	await _fall(5730.0, null, null, "Partially overlapping floors at their overlap")
	await _fall(5630.0, partial, null, "Partially overlapping floors outside their overlap")

	var upper := _section("HigherMiddle", 2, Vector2(5980, 500), 180)
	_section("LowerMiddle", 2, Vector2(5980, 503), 180)
	await _fall(6050.0, upper, null, "Same-index floors at different heights")

	var destination := _section("ProfileMiddle", 2, Vector2(6280, 500), 180)
	_section("OtherIndexBack", 3, Vector2(6280, 503), 180)
	await _fall(6350.0, destination, null, "Floors belonging to different logical layers")

func _fall(x: float, owner: GameplayLayer, remove_after_landing: GameplayLayer, title: String,
		request_follow_up := false) -> void:
	await _place(1, Vector2(x, 420), 0)
	var trace: Array[String] = []
	var snapshots: Array[bool] = []
	var queued_counts: Array[int] = []
	var frames_ok := true
	var sample := func(label: String):
		trace.append(_state(label))
		snapshots.append(_solid(2) and player.is_on_floor() and absf(player.global_position.x - x) < 0.01
			and absf(player.global_position.y - 500.0) < 0.1
			and context.depth_profile == world.get_node("MiddleLayer"))
	var a := func():
		sample.call("A")
		if request_follow_up:
			player.try_change_layer(1)
			queued_counts.append(_pending())
	var b := func():
		sample.call("B")
		if request_follow_up:
			queued_counts.append(_pending())
	var layer_listener := func(_index: int):
		sample.call("L")
		if request_follow_up:
			queued_counts.append(_pending())
	context.context_changed.connect(a)
	context.context_changed.connect(b)
	player.layer_changed.connect(layer_listener)
	for _i in range(38):
		await physics_frame
		frames_ok = frames_ok and _solid(context.logical_layer)
	var section_name := str(owner.name) if owner != null else "null"
	var expected: Array[String] = ["A2:" + section_name, "B2:" + section_name, "L2:" + section_name]
	_expect(trace == expected and snapshots == [true, true, true] and frames_ok
		and context.gameplay_layer == owner and _solid(2),
		title + ": the first and only landing publication has the correct owner, masks and pose")
	if request_follow_up:
		_expect(queued_counts == [1, 1, 1] and _pending() == 0,
			"The follow-up stays pending during both natural landing signals before failing support validation")
	if remove_after_landing != null:
		remove_after_landing.queue_free()
		await _frames(6)
		_expect(trace.size() == 5 and trace[3] == "A2:CoincidentA" and trace[4] == "B2:CoincidentA",
			"The later unique contact publishes one owner change in both callbacks and no extra layer signal")
	context.context_changed.disconnect(a)
	context.context_changed.disconnect(b)
	player.layer_changed.disconnect(layer_listener)
	print("CROSS_LANDING ", title, " ", trace)

func _section(label: String, index: int, point: Vector2, width: float) -> GameplayLayer:
	var section := GameplayLayer.new()
	section.name = label
	section.current_layer = index
	section.position = point
	var decoration := Node2D.new()
	decoration.name = "ParallaxDecoration"
	var details := Node2D.new()
	details.name = "DepthDetails"
	decoration.add_child(details)
	section.add_child(decoration)
	var polygon := CollisionPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(width, 0), Vector2(width, 80), Vector2(0, 80)])
	polygon.set_script(TERRAIN)
	polygon.set("supports_other_layers", true)
	section.add_child(polygon)
	world.add_child(section)
	return section

func _state(observer: String) -> String:
	var owner := context.gameplay_layer
	return "%s%d:%s" % [observer, context.logical_layer, str(owner.name) if owner != null else "null"]

func _solid(index: int) -> bool:
	var bit := GameplayLayer.solid_collision_bit(index)
	return player.current_layer == index and context.logical_layer == index \
		and player.collision_layer == bit and player.collision_mask == bit

func _pending() -> int:
	var steps: Array[int] = player.get("_pending_layer_steps")
	return steps.size()

func _pairs(layers: Array[int]) -> Array[String]:
	var trace: Array[String] = []
	for index in layers:
		trace.append("C%d" % index)
		trace.append("L%d" % index)
	return trace

func _peak(values: Array) -> int:
	var peak := 0
	for entry in values:
		peak = maxi(peak, entry)
	return peak

func _alternates(layers: Array[int]) -> bool:
	for index in range(layers.size()):
		if layers[index] != (3 if index % 2 == 0 else 2):
			return false
	return not layers.is_empty()

func _place(index: int, point: Vector2, frames := 6) -> void:
	player.cancel_damage_reaction()
	player.set_checkpoint(point, index)
	player.restore_checkpoint()
	await _frames(frames)

func _frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		failed += 1

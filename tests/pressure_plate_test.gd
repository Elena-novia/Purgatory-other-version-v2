extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const PLATE_SCENE := preload("res://scenes/interactables/PressurePlate.tscn")
const BOX_SCENE := preload("res://scenes/interactables/box.tscn")
const BACK_SCENE := preload("res://scenes/world/layers/BackLayer.tscn")

var failures: Array[String] = []
var main: Node2D
var player: PlayerController

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	var front: PressurePlate = main.get_node("FrontLayer/PressurePlate")
	var back_two: PressurePlate = main.get_node("BackLayer2/PressurePlate")
	var middle_two: PressurePlate = main.get_node("MiddleLayer2/PressurePlate")
	var middle := _add_plate(main.get_node("MiddleLayer"), Vector2(510, 0))
	var wrapper := Node2D.new()
	main.get_node("BackLayer").add_child(wrapper)
	var nested := Node2D.new()
	wrapper.add_child(nested)
	var back := _add_plate(nested, Vector2(330, 0))
	await _wait_frames(3)

	await _check_layer_plate(front, 1, "FrontLayer")
	await _check_layer_plate(middle, 2, "MiddleLayer")
	await _check_layer_plate(back, 3, "BackLayer via nested node")
	await _check_layer_plate(back_two, 3, "BackLayer2")
	_expect(middle_two.position.y == -11.0 and middle_two.detection_area.global_position.y == 482.0,
		"MiddleLayer2 retains the audited plate placement with its sensor at floor height")
	await _check_layer_plate(middle_two, 2, "MiddleLayer2 raised artwork")
	_expect(back_two.detection_area.global_scale.is_equal_approx(Vector2.ONE),
		"Scaled BackLayer2 leaves the sensor at its authored width")
	await _check_section_profiles(back, back_two, wrapper)
	_check_standalone_layer()
	_check_explicit_modes()

	var point := Vector2(4000, 520)
	_add_flat_ground(point)
	var front_cross := _add_plate(main, point, 1)
	var back_cross := _add_plate(main, point + Vector2(300, 0), 3)
	await _check_player_crossing(back_cross, 1)
	await _check_player_crossing(front_cross, 3)
	await _check_box_crossing(front_cross, 2)
	await _check_box_crossing(back_cross, 1)
	await _check_multiple(front_cross)
	await _check_exclusions(front_cross)

	if failures.is_empty():
		print("Pressure plate layer integration: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_layer_plate(plate: PressurePlate, layer: int, label: String) -> void:
	var states: Array[bool] = []
	var edges: Array[String] = []
	plate.state_changed.connect(func(value: bool): states.append(value))
	plate.pressed.connect(func(): edges.append("pressed"))
	plate.released.connect(func(): edges.append("released"))
	var context := plate.layer_context
	var profile := context.depth_profile
	_expect(plate.current_layer == layer and profile == context.gameplay_layer
		and context.solid_bit == [1, 2, 4][layer - 1]
		and context.ground_support_bit == [8, 16, 32][layer - 1]
		and plate.detection_area.collision_mask == context.solid_bit,
		"%s resolves the layer and detects only its collision bit" % label)
	_expect(plate.depth_visuals.global_scale.is_equal_approx(Vector2.ONE * profile.depth_scale)
		and plate.depth_visuals.modulate.is_equal_approx(profile.depth_modulation()),
		"%s applies its own shared depth profile" % label)
	_place_player(layer, plate.global_position - Vector2(0, 54))
	await _wait_frames(36)
	_expect(player.is_on_floor() and plate.is_pressed, "%s activates on player landing" % label)
	_expect(absf(player.global_position.y - plate.detection_area.global_position.y) < 1.0,
		"%s stands on existing ground" % label)
	_expect(is_equal_approx(plate.button_top.position.y, -2.0 + plate.depression_distance),
		"%s depresses its lid" % label)
	await _walk_right(23)
	await _wait_frames(14)
	_expect(not plate.is_pressed and states == [true, false] and edges == ["pressed", "released"]
		and is_equal_approx(plate.button_top.position.y, -2.0), "%s releases once after walking off" % label)

func _check_section_profiles(back: PressurePlate, back_two: PressurePlate, wrapper: Node2D) -> void:
	var first: GameplayLayer = main.get_node("BackLayer")
	var second: GameplayLayer = main.get_node("BackLayer2")
	_expect(back.current_layer == 3 and back_two.current_layer == 3
		and back.layer_context.gameplay_layer == first and back_two.layer_context.gameplay_layer == second
		and back_two.layer_context.owner_path == str(second.get_path()),
		"Both Back sections resolve layer 3 and keep their distinct physical owners")
	second.depth_scale = 0.76
	second.tint_strength = 0.43
	await _wait_frames(18)
	_expect(back_two.depth_visuals.scale.is_equal_approx(Vector2.ONE * 0.76)
		and back_two.depth_visuals.modulate.is_equal_approx(second.depth_modulation())
		and back.depth_visuals.scale.is_equal_approx(Vector2.ONE * 0.70)
		and back_two.detection_area.global_scale.is_equal_approx(Vector2.ONE),
		"Changing BackLayer2 updates only its artwork, with no sensor scaling")
	wrapper.reparent(second)
	await _wait_frames(18)
	_expect(back.current_layer == 3 and back.layer_context.gameplay_layer == second
		and back.depth_visuals.scale.is_equal_approx(Vector2.ONE * 0.76)
		and back.detection_area.global_position.is_equal_approx(back.global_position),
		"Moving a whole nested branch refreshes the owner and profile even at the same logical index")
	wrapper.queue_free()

func _check_standalone_layer() -> void:
	var standalone := BACK_SCENE.instantiate() as GameplayLayer
	var plate := _add_plate(standalone, Vector2(200, 0))
	standalone.position.x = 6000
	root.add_child(standalone)
	_expect(plate.current_layer == 3
		and plate.depth_visuals.global_scale.is_equal_approx(Vector2.ONE * standalone.depth_scale)
		and plate.depth_visuals.modulate.is_equal_approx(standalone.depth_modulation()),
		"A layer scene run without Main supplies its own depth profile")
	standalone.current_layer = 2
	_expect(plate.current_layer == 2 and plate.detection_area.collision_mask == 2
		and plate.layer_context.gameplay_layer == standalone,
		"An inherited context refreshes when its owner's logical layer changes")
	standalone.queue_free()

func _check_explicit_modes() -> void:
	var missing := _add_plate(main, Vector2(6000, 520))
	var context := missing.layer_context
	var inspector_fields: Array[String] = []
	for property in context.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_READ_ONLY) != 0:
			inspector_fields.append(String(property.name))
	_expect(inspector_fields.has("logical_layer") and inspector_fields.has("owner_path")
		and inspector_fields.has("status"), "The Inspector exposes read-only resolved context")
	_expect(context.logical_layer == 0 and context.solid_bit == 0 and context.ground_support_bit == 0
		and context.gameplay_layer == null and missing.detection_area.collision_mask == 0
		and context._get_configuration_warnings()[0].contains("No GameplayLayer ancestor"),
		"An inherited context without an owner reports the problem and leaves detection inactive")
	context.mode = LayerContext.Mode.FIXED
	_expect(context.logical_layer == 0 and context.status.contains("Fixed Layer"),
		"Fixed mode requires an explicit layer")
	context.fixed_layer = 2
	_expect(context.logical_layer == 2 and context.gameplay_layer == null
		and context.depth_profile == main.get_node("MiddleLayer") and missing.detection_area.collision_mask == 2,
		"Fixed mode outside GameplayLayer uses the shared profile and correct mask")
	context.initial_dynamic_layer = 1
	context.mode = LayerContext.Mode.DYNAMIC
	_expect(context.logical_layer == 1 and context.set_dynamic_layer(3)
		and context.logical_layer == 3 and not context.set_dynamic_layer(4)
		and context.depth_profile == main.get_node("BackLayer") and context.ground_support_bit == 32,
		"Dynamic mode uses its initial layer, then updates atomically for valid runtime assignments")
	missing.queue_free()

func _check_player_crossing(plate: PressurePlate, layer: int) -> void:
	var states: Array[bool] = []
	plate.state_changed.connect(func(value: bool): states.append(value))
	_place_player(layer, plate.global_position - Vector2(75, 0))
	await _wait_frames(4)
	await _walk_right(38)
	_expect(player.global_position.x > plate.global_position.x + 60.0
		and not plate.is_pressed and states.is_empty(),
		"Player on layer %d walks through the layer %d plate at the same height" % [layer, plate.current_layer])

func _check_box_crossing(plate: PressurePlate, layer: int) -> void:
	var states: Array[bool] = []
	plate.state_changed.connect(func(value: bool): states.append(value))
	_place_player(3, Vector2(3900, 520))
	var box := _add_box(layer, plate.global_position - Vector2(75, 16))
	await _wait_frames(4)
	await _push_right(box, 105)
	_expect(box.global_position.x > plate.global_position.x + 55.0 and not plate.is_pressed and states.is_empty(),
		"PushBox on layer %d moves through the layer %d plate at the same height" % [layer, plate.current_layer])
	box.queue_free()
	await _wait_frames(3)

func _check_multiple(plate: PressurePlate) -> void:
	var states: Array[bool] = []
	plate.state_changed.connect(func(value: bool): states.append(value))
	_place_player(1, plate.global_position + Vector2(20, -40))
	await _wait_frames(30)
	_expect(plate.is_pressed, "Player alone presses the shared plate")
	var box := _add_box(1, plate.global_position - Vector2(21, 16))
	await _wait_frames(5)
	_expect(plate.is_pressed and plate.detection_area.overlaps_body(player)
		and plate.detection_area.overlaps_body(box), "Player and box both contact the shared plate")
	await _walk_right(24)
	_expect(plate.is_pressed and not plate.detection_area.overlaps_body(player) and states == [true],
		"The box keeps the plate pressed when the player leaves")
	box.queue_free()
	await _wait_frames(5)
	_expect(not plate.is_pressed and states == [true, false], "Removing the box releases the plate once")
	var pushed_box := _add_box(1, plate.global_position - Vector2(65, 16))
	await _wait_frames(4)
	await _push_right(pushed_box, 44)
	_expect(plate.is_pressed, "Pushing the box onto the plate activates it")
	await _push_right(pushed_box, 55)
	_expect(not plate.is_pressed and states == [true, false, true, false],
		"Pushing the box away releases the plate")
	pushed_box.queue_free()
	await _wait_frames(3)

func _check_exclusions(plate: PressurePlate) -> void:
	var states: Array[bool] = []
	plate.state_changed.connect(func(value: bool): states.append(value))
	_place_player(1, plate.global_position - Vector2(35, 0))
	await _wait_frames(8)
	_expect(not plate.is_pressed, "A collider grazing the side does not press the plate")
	var floating := _add_plate(main, plate.global_position - Vector2(0, 110), 1)
	var floating_states: Array[bool] = []
	floating.state_changed.connect(func(value: bool): floating_states.append(value))
	_place_player(1, plate.global_position)
	await _wait_frames(5)
	_expect(plate.is_pressed and not floating.is_pressed, "Horizontal overlap below another plate does not press it")
	player.magic_orb.toggle_release_or_retrieve()
	player.magic_orb.global_position = plate.global_position
	await _walk_right(22)
	await _wait_frames(5)
	_expect(not plate.is_pressed and states == [true, false], "The orb cannot keep an empty plate pressed")
	var suspended := _add_box(1, floating.global_position - Vector2(0, 16))
	await _wait_frames(6)
	_expect(floating.detection_area.overlaps_body(suspended) and floating_states.is_empty(),
		"A box at plate height without physical support does not press it")
	suspended.queue_free()

func _add_plate(parent: Node2D, point: Vector2, fixed_layer := 0) -> PressurePlate:
	var plate := PLATE_SCENE.instantiate() as PressurePlate
	plate.position = point
	if fixed_layer != 0:
		var context: LayerContext = plate.get_node("LayerContext")
		context.mode = LayerContext.Mode.FIXED
		context.fixed_layer = fixed_layer
	parent.add_child(plate)
	return plate

func _add_box(layer: int, point: Vector2) -> PushBox:
	var box := BOX_SCENE.instantiate() as PushBox
	box.position = point
	box.current_layer = layer
	main.add_child(box)
	return box

func _add_flat_ground(point: Vector2) -> void:
	# Put all three layer surfaces at the same height to exercise actual
	# traversal through the sensor instead of missing it vertically.
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 7
	floor_body.collision_mask = 0
	floor_body.position = point
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1000, 32)
	shape.shape = rectangle
	shape.position = Vector2(150, 16)
	floor_body.add_child(shape)
	main.add_child(floor_body)

func _place_player(layer: int, point: Vector2) -> void:
	player.current_layer = layer
	player._apply_layer_mask()
	player.global_position = point
	player.velocity = Vector2.ZERO

func _walk_right(frames: int) -> void:
	Input.action_press("move_right")
	await _wait_frames(frames)
	Input.action_release("move_right")

func _push_right(box: PushBox, frames: int) -> void:
	for _frame in range(frames):
		box.receive_push(1.0)
		await physics_frame

func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

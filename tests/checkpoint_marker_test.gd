extends SceneTree

const MAIN := preload("res://scenes/world/main.tscn")
const CHECKPOINT := preload("res://scenes/world/checkpoint.tscn")
const BACK := preload("res://scenes/world/layers/BackLayer.tscn")
const SECTIONS := ["FrontLayer", "FrontLayer2", "MiddleLayer", "MiddleLayer2", "BackLayer", "BackLayer2"]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN.instantiate()
	root.add_child(main)
	var editor := Engine.is_editor_hint()
	for label: String in SECTIONS:
		var section := main.get_node(label) as GameplayLayer
		var branch := Node2D.new()
		branch.transform = Transform2D(0.32, Vector2(1.24, 0.83), 0.13, Vector2(240, -40))
		section.add_child(branch)
		var checkpoint := CHECKPOINT.instantiate() as Checkpoint
		checkpoint.position = Vector2(42, -45)
		checkpoint.rotation = 0.26
		checkpoint.marker_offset = Vector2(15, -12)
		checkpoint.marker_rotation = 0.21
		branch.add_child(checkpoint)
		_check_marker(checkpoint, section, label)
		var anchor := branch.to_global(checkpoint.position) if editor else checkpoint.global_position
		var angle := branch.global_transform.x.angle() + 0.26
		var expected_point := anchor + checkpoint.marker_offset.rotated(angle)
		_expect(checkpoint.depth_visuals.global_position.is_equal_approx(expected_point)
			and is_zero_approx(angle_difference(angle + checkpoint.marker_rotation, checkpoint.depth_visuals.global_rotation)),
			label + " preserves the marker offset and orientation")
		branch.queue_free()
		await process_frame

	var middle := main.get_node("MiddleLayer") as GameplayLayer
	var fixed := main.get_node("Checkpoint") as Checkpoint
	_check_marker(fixed, middle, "Fixed Middle under Main")
	var sensor := fixed.get_node("CollisionShape2D") as CollisionShape2D
	var sensor_transform := sensor.global_transform
	var back_two := main.get_node("BackLayer2") as GameplayLayer
	back_two.depth_scale = 0.74
	back_two.tint_strength = 0.44
	fixed.reparent(back_two, true)
	fixed.layer_context.mode = LayerContext.Mode.INHERITED
	await _settle()
	_check_marker(fixed, back_two, "Fixed switched to Inherited under BackLayer2")
	if not editor:
		_expect(sensor.global_transform.is_equal_approx(sensor_transform),
			"The runtime sensor world transform is unchanged when keeping the checkpoint world pose")
	fixed.layer_context.mode = LayerContext.Mode.FIXED
	await _settle()
	_check_marker(fixed, middle, "Inherited switched back to Fixed")
	fixed.layer_context.mode = LayerContext.Mode.INHERITED
	fixed.reparent(main.get_node("FrontLayer2"), true)
	await _settle()
	var front_two := main.get_node("FrontLayer2") as GameplayLayer
	_check_marker(fixed, front_two, "Inherited moved to FrontLayer2")
	front_two.depth_scale = 0.92
	await _settle()
	_check_marker(fixed, front_two, "Updated owner depth")

	if DisplayServer.get_name() != "headless":
		await _check_rendered_marker()
	main.queue_free()
	await process_frame
	if editor:
		await create_timer(1.0).timeout
	if failures.is_empty():
		print("Checkpoint marker: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_marker(checkpoint: Checkpoint, profile: GameplayLayer, label: String) -> void:
	var shape := checkpoint.get_node("CollisionShape2D") as CollisionShape2D
	var visuals := checkpoint.depth_visuals
	_expect(checkpoint.layer_context.depth_profile == profile
		and visuals.global_scale.is_equal_approx(Vector2.ONE * profile.depth_scale)
		and visuals.modulate.is_equal_approx(profile.depth_modulation()),
		"%s has scale %s and the selected section tint" % [label, visuals.global_scale])
	_expect(shape.shape.get_rect().size.is_equal_approx(Vector2(28, 484.77))
		and (Engine.is_editor_hint() or shape.global_scale.is_equal_approx(Vector2.ONE)),
		label + " retains the original sensor dimensions")
	_expect(visuals.visible == Engine.is_editor_hint(), label + " retains editor-only marker visibility")

func _check_rendered_marker() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 260)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color.BLACK
	viewport.add_child(background)
	var section := BACK.instantiate() as GameplayLayer
	section.position = Vector2(70, 160)
	section.scale = Vector2(0.23, 1.0)
	viewport.add_child(section)
	(section.get_node("Ground") as CanvasItem).hide()
	(section.get_node("ParallaxDecoration") as CanvasItem).hide()
	var checkpoint := CHECKPOINT.instantiate() as Checkpoint
	checkpoint.position = Vector2(400, 0)
	section.add_child(checkpoint)
	(checkpoint.get_node("CollisionShape2D") as CanvasItem).hide()
	# Runtime hides this editor marker. Make the fixture visible for pixel sampling.
	checkpoint.depth_visuals.show()
	for _frame in range(4):
		await RenderingServer.frame_post_draw
	var screenshot := viewport.get_texture().get_image()
	var sample := screenshot.get_pixel(162, 100)
	var side := screenshot.get_pixel(168, 100)
	var outside := screenshot.get_pixel(175, 100)
	var expected := Color.BLACK.lerp(Color(0.2, 0.9, 0.9) * section.depth_modulation(), 0.3)
	_expect(_matches_rgb(sample, expected) and _matches_rgb(side, expected)
		and _matches_rgb(outside, Color.BLACK),
		"Rendered marker has its intended width and applies the Back tint once (%s / %s, outside %s, expected %s)" % [
			sample, side, outside, expected])
	viewport.queue_free()
	await process_frame

func _matches_rgb(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.018 and absf(a.g - b.g) < 0.018 and absf(a.b - b.b) < 0.018

func _settle() -> void:
	if Engine.is_editor_hint():
		await process_frame
	else:
		await create_timer(LayerDepthVisuals.DEFAULT_TRANSITION_DURATION + 0.1).timeout

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

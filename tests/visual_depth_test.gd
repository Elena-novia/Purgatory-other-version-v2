extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const TERRAIN := preload("res://scripts/world/terrain_polygon.gd")
const PROFILES := [Vector2(1.0, 0.0), Vector2(0.85, 0.32), Vector2(0.70, 0.68)]

var failures: Array[String] = []
var main: Node2D
var player: PlayerController
var layers: Array[GameplayLayer]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	layers = [main.get_node("FrontLayer"), main.get_node("MiddleLayer"), main.get_node("BackLayer")]
	await physics_frame
	await physics_frame

	_check_environment()
	if DisplayServer.get_name() != "headless":
		await _check_rendered_terrain()
	var shape_transform := player.body_shape.transform
	var shape_bounds := player.body_shape.shape.get_rect()
	var box: PushBox = main.get_node("Box")
	var enemy: Node2D = main.get_node("Enemy")
	var original_box_scale := box.scale
	var original_orb_scale := player.magic_orb.scale
	var camera_transform := player.camera.transform
	var hud: GameHUD = main.get_node("HUD")
	var health_artwork := hud.artwork.modulate

	_expect(_matches_depth(1), "Player begins at original scale and colors")
	player.try_change_layer(1)
	_expect(player.current_layer == 2 and player.depth_visuals.scale == Vector2.ONE,
		"W starts the depth transition from the current visual scale")
	await create_timer(player.depth_transition_duration * 0.4).timeout
	_expect(player.depth_visuals.scale.x < 1.0 and player.depth_visuals.scale.x > 0.85
		and player.depth_visuals.modulate.g < 1.0
		and player.depth_visuals.modulate.g > layers[1].depth_modulation().g,
		"Player size and tint interpolate during a layer change")
	await _settle_depth()
	_expect(_matches_depth(2), "Middle-layer player matches the layer's scale and purple tint")

	player.try_change_layer(1)
	await _settle_depth()
	_expect(player.current_layer == 3 and _matches_depth(3), "Back-layer player matches the strongest depth profile")
	var original_tint := layers[2].depth_tint
	layers[2].depth_scale = 0.76
	layers[2].depth_tint = Color("b887ff")
	layers[2].tint_strength = 0.5
	await _settle_depth()
	_expect(_matches_depth(3) and is_equal_approx(layers[2].depth_decoration.scale.x, 0.76)
		and layers[2].modulate.is_equal_approx(Color.WHITE.lerp(Color("b887ff"), 0.5)),
		"Changes to scale, tint and strength drive both the environment and the player")
	layers[2].depth_scale = 0.70
	layers[2].depth_tint = original_tint
	layers[2].tint_strength = 0.68
	player.try_change_layer(-1)
	player.try_change_layer(-1)
	await _settle_depth()
	_expect(player.current_layer == 1 and _matches_depth(1), "Rapid layer changes settle on the last layer's profile")

	await _check_airborne_change()
	await _check_natural_fall()
	_expect(player.scale == Vector2.ONE and player.body_shape.transform == shape_transform
		and player.body_shape.shape.get_rect() == shape_bounds,
		"Player body scale, collider transform and physics dimensions remain unchanged")
	_expect(player.camera.transform == camera_transform and player.magic_orb.scale == original_orb_scale
		and player.magic_orb.modulate == Color.WHITE and box.scale == original_box_scale
		and box.modulate == Color.WHITE and enemy.modulate == Color.WHITE,
		"Player depth does not change the camera, enemy or the orb and box root transforms")
	_expect(hud.artwork.modulate == health_artwork and hud.death_overlay.modulate == Color.WHITE
		and hud.death_splash.modulate == Color.WHITE, "Vitals artwork and death overlays keep their colors")

	await _check_respawn(hud)
	if failures.is_empty():
		print("Visual depth system: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_environment() -> void:
	for i in range(layers.size()):
		var layer := layers[i]
		var expected: Vector2 = PROFILES[i]
		var ground: CollisionPolygon2D = layer.get_node("Ground")
		var depth_details := layer.depth_decoration
		_expect(is_equal_approx(layer.depth_scale, expected.x) and is_equal_approx(layer.tint_strength, expected.y)
			and depth_details.scale.is_equal_approx(Vector2.ONE * expected.x) and layer.modulate == layer.depth_modulation(),
			"%s uses its configured environment depth" % layer.name)
		_expect(layer.scale == Vector2.ONE and ground.scale == Vector2.ONE
			and ground.polygon[0] == Vector2(-850, 0) and ground.global_position.y == layer.global_position.y,
			"%s preserves its physical terrain outline and height" % layer.name)
		var prop := Polygon2D.new()
		depth_details.add_child(prop)
		_expect(prop.global_scale.is_equal_approx(layer.parallax_decoration.global_scale * expected.x),
			"%s scales a decorative element inside the existing parallax transform" % layer.name)
		prop.queue_free()
	_expect(layers[0].modulate == Color.WHITE and layers[1].modulate.g > layers[2].modulate.g,
		"Purple grading progresses from neutral front to the strongest back tint")
	var extra_back: GameplayLayer = main.get_node("BackLayer2")
	_expect(extra_back.scale == Vector2(0.23, 1) and extra_back.modulate == layers[2].modulate,
		"Additional layer instances keep authored transforms and use the same depth profile")

func _check_rendered_terrain() -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var rim_widths: Array[int] = []
	for layer in layers:
		var ground: CollisionPolygon2D = layer.get_node("Ground")
		var xform := ground.get_global_transform_with_canvas()
		var rim_center := Vector2i(xform * Vector2(-260, 0))
		var fill_pixel := Vector2i(xform * Vector2(-260, 12))
		var expected_fill: Color = ground.get("fill_color") * layer.depth_modulation()
		var expected_rim: Color = ground.get("edge_color") * layer.depth_modulation()
		_expect(_color_near(frame.get_pixelv(fill_pixel), expected_fill),
			"%s renders the original fill with its intended tint" % layer.name)
		var width := 0
		for y in range(rim_center.y - 6, rim_center.y + 7):
			if _color_near(frame.get_pixel(rim_center.x, y), expected_rim):
				width += 1
		rim_widths.append(width)
	_expect(rim_widths[0] > rim_widths[1] and rim_widths[1] > rim_widths[2] and rim_widths[2] > 0,
		"Rendered platform trim gets progressively thinner (%s)" % str(rim_widths))

func _check_airborne_change() -> void:
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for _i in range(9):
		await physics_frame
	var airborne := not player.is_on_floor()
	player.try_change_layer(1)
	await _settle_depth()
	_expect(airborne and not player.is_on_floor() and player.current_layer == 2 and _matches_depth(2),
		"Airborne W updates the player profile while the original jump continues")

func _check_natural_fall() -> void:
	var front_edge := _add_platform(1, Vector2(4200, 520), 120.0)
	var middle_floor := _add_platform(2, Vector2(4345, 595), 450.0)
	await physics_frame
	await physics_frame
	player.current_layer = 1
	player._apply_layer_mask()
	player.global_position = Vector2(4303, 520)
	player.velocity = Vector2.ZERO
	for _i in range(4):
		await physics_frame
	Input.action_press("move_right")
	for _i in range(90):
		await physics_frame
		if player.current_layer == 2:
			break
	Input.action_release("move_right")
	await _settle_depth()
	_expect(player.current_layer == 2 and player.is_on_floor() and _matches_depth(2),
		"Natural falling switches to the new layer's visual depth on landing")
	front_edge.queue_free()
	middle_floor.queue_free()

func _check_respawn(hud: GameHUD) -> void:
	player.set_checkpoint(Vector2(160, 520), 1)
	player.vitals.take_damage(player.vitals.max_health)
	await create_timer(0.65).timeout
	_expect(hud.death_overlay.visible and hud.death_splash.visible, "The existing death sequence still displays")
	for _i in range(180):
		await physics_frame
		if not hud.death_overlay.visible:
			break
	_expect(player.current_layer == 1 and _matches_depth(1) and player.global_position.is_equal_approx(player.checkpoint_position)
		and not hud.death_overlay.visible and not hud.death_splash.visible,
		"Checkpoint respawn restores the front-layer appearance before showing the game")

func _add_platform(layer_id: int, point: Vector2, width: float) -> CollisionPolygon2D:
	var layer := layers[layer_id - 1]
	var platform := CollisionPolygon2D.new()
	platform.set_script(TERRAIN)
	platform.set("supports_other_layers", true)
	platform.position = layer.to_local(point)
	platform.polygon = PackedVector2Array([Vector2.ZERO, Vector2(width, 0), Vector2(width, 100), Vector2(0, 100)])
	layer.add_child(platform)
	return platform

func _matches_depth(layer_id: int) -> bool:
	var layer := layers[layer_id - 1]
	return player.depth_visuals.scale.is_equal_approx(Vector2.ONE * layer.depth_scale) \
		and player.depth_visuals.modulate.is_equal_approx(layer.depth_modulation())

func _settle_depth() -> void:
	await create_timer(player.depth_transition_duration + 0.05).timeout

func _color_near(pixel: Color, expected: Color) -> bool:
	return absf(pixel.r - expected.r) < 0.02 and absf(pixel.g - expected.g) < 0.02 and absf(pixel.b - expected.b) < 0.02

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

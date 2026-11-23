extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const FULL_TEXTURE := preload("res://assets/ui/Health_and_Sanity_Bar_UI.png")
const DEPLETED_TEXTURE := preload("res://assets/ui/Health_and_Sanity_Bar_UI_2.png")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var hud: GameHUD = main.get_node("HUD")
	var panel: Control = hud.get_node("VitalsPanel")
	var artwork: TextureRect = panel.get_node("Artwork")
	var material := artwork.material as ShaderMaterial

	_expect(artwork.texture == FULL_TEXTURE, "The original full PNG is the composite artwork source")
	_expect(material.get_shader_parameter("depleted_texture") == DEPLETED_TEXTURE, "The original empty PNG is the depleted composite source")
	_expect(artwork.size == Vector2(563, 141), "Artwork keeps the source PNG aspect ratio")
	_expect(panel.anchor_top == 1.0 and panel.anchor_bottom == 1.0, "Vitals artwork stays anchored to the bottom-left")
	_expect(panel.get_child_count() == 1, "The UI contains no duplicate bars or fill rectangles")

	var cases: Array[Vector2] = [
		Vector2(1.0, 1.0),
		Vector2(0.5, 1.0),
		Vector2(1.0, 0.5),
		Vector2(0.5, 0.5),
		Vector2(0.0, 1.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 0.0),
	]
	for values in cases:
		hud.update_vitals(values.x, values.y)
		_expect(is_equal_approx(float(material.get_shader_parameter("health_ratio")), values.x), "Health artwork follows the health value " + str(values.x) + "/" + str(values.y))
		_expect(is_equal_approx(float(material.get_shader_parameter("sanity_ratio")), values.y), "Sanity artwork follows the sanity value " + str(values.y) + "/" + str(values.x))

	if failures.is_empty():
		print("Health UI composition: all seven value combinations passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

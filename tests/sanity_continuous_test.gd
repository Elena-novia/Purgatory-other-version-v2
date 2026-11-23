extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var vitals_30 := _make_vitals()
	var vitals_144 := _make_vitals()
	vitals_30.orb_is_away = true
	vitals_144.orb_is_away = true
	var previous := vitals_30.sanity
	var decreases_smoothly := true
	for _frame in range(60):
		vitals_30._process(1.0 / 30.0)
		if vitals_30.sanity >= previous or not is_equal_approx(previous - vitals_30.sanity, vitals_30.sanity_drain_percent_per_second * 0.01 / 30.0):
			decreases_smoothly = false
		previous = vitals_30.sanity
	for _frame in range(288):
		vitals_144._process(1.0 / 144.0)
	_expect(decreases_smoothly, "Sanity decreases smoothly without timed steps")
	_expect(is_equal_approx(vitals_30.sanity, 0.85), "Two seconds of drain uses percentage-per-second tuning")
	_expect(absf(vitals_30.sanity - vitals_144.sanity) < 0.00001, "Drain is frame-rate independent at 30 and 144 FPS")

	var ui_values: Array[float] = []
	vitals_30.values_changed.connect(func(_health: float, sanity: float) -> void: ui_values.append(sanity))
	vitals_30.orb_is_away = false
	var before_regen := vitals_30.sanity
	vitals_30._process(0.5)
	_expect(vitals_30.sanity > before_regen, "Retrieving the orb switches immediately to smooth regeneration")
	_expect(not ui_values.is_empty() and is_equal_approx(ui_values.back(), vitals_30.sanity), "The UI signal receives the actual current sanity value")
	vitals_30.sanity = 0.999
	vitals_30._process(1.0)
	_expect(vitals_30.sanity <= vitals_30.max_sanity, "Regeneration clamps at maximum sanity")

	var death_vitals := _make_vitals()
	death_vitals.sanity = 0.001
	death_vitals.orb_is_away = true
	var death_causes: Array[String] = []
	death_vitals.died.connect(func(cause: String) -> void: death_causes.append(cause))
	death_vitals._process(1.0)
	_expect(is_zero_approx(death_vitals.sanity), "Sanity drain clamps at zero")
	_expect(death_causes == ["sanity"], "Reaching zero triggers the existing sanity death signal")

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var player_vitals: PlayerVitals = main.get_node("Player/Vitals")
	var sanity_material := main.get_node("HUD/VitalsPanel/Artwork").material as ShaderMaterial
	player_vitals.set_process(false)
	player_vitals.sanity = 0.6
	player_vitals.orb_is_away = true
	player_vitals._process(0.25)
	_expect(is_equal_approx(float(sanity_material.get_shader_parameter("sanity_ratio")), player_vitals.sanity), "The flower shader follows continuously drained gameplay sanity")
	main.queue_free()

	if failures.is_empty():
		print("Continuous sanity system: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _make_vitals() -> PlayerVitals:
	var vitals := PlayerVitals.new()
	root.add_child(vitals)
	vitals.set_process(false)
	return vitals

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

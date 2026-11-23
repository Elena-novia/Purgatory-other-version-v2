extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_responsive_layout()
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: PlayerController = main.get_node("Player")
	var hud: GameHUD = main.get_node("HUD")
	_expect(not hud.death_overlay.visible and not hud.death_splash.visible, "Death effects start hidden")
	_expect(is_zero_approx(hud.death_overlay.color.a) and is_zero_approx(hud.death_splash.color.a), "Death effect alpha starts reset")

	await _run_death_cycle(main, player, hud, "physical")
	await _run_death_cycle(main, player, hud, "sanity")
	await _run_death_cycle(main, player, hud, "physical")
	await _run_death_cycle(main, player, hud, "sanity")

	main.queue_free()
	if failures.is_empty():
		print("Death and respawn effects: all checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_responsive_layout() -> void:
	var test_viewport := SubViewport.new()
	test_viewport.size = Vector2i(1920, 1080)
	test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(test_viewport)
	var hud := HUD_SCENE.instantiate() as GameHUD
	test_viewport.add_child(hud)
	await process_frame
	var dimensions: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2048, 954), Vector2i(2048, 906), Vector2i(900, 1440)]
	for viewport_size in dimensions:
		test_viewport.size = viewport_size
		await process_frame
		await process_frame
		var canvas := hud.get_node("DeathCanvas") as Control
		var background := hud.get_node("DeathCanvas/DeathOverlay") as ColorRect
		var splash := hud.get_node("DeathCanvas/DeathSplash") as ColorRect
		var text := hud.get_node("DeathCanvas/DeathSplash/StatusTop") as Label
		_expect(canvas.size == Vector2(viewport_size), "Fullscreen root adapts to viewport %s" % str(viewport_size))
		_expect(background.position.is_zero_approx() and background.size == Vector2(viewport_size), "Death background covers all of viewport %s" % str(viewport_size))
		_expect(is_equal_approx(splash.size.x, splash.size.y), "Blood splash keeps square proportions at %s" % str(viewport_size))
		var splash_center := splash.position + splash.size * 0.5
		_expect(is_equal_approx(splash_center.x, viewport_size.x * 0.5) and is_equal_approx(splash_center.y, viewport_size.y * 0.5), "Blood splash remains centered at %s" % str(viewport_size))
		_expect(text.size == splash.size and text.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and text.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "Death text is centered inside the splash at %s" % str(viewport_size))
	test_viewport.queue_free()
	await process_frame

func _run_death_cycle(main: Node, player: PlayerController, hud: GameHUD, cause: String) -> void:
	if cause == "physical":
		player.vitals.take_damage(player.vitals.max_health)
	else:
		player.vitals.sanity = 0.0
		player.vitals._emit_values()
		player.vitals._check_death()

	_expect(bool(main.get("_respawn_in_progress")), cause + " death starts respawn lifecycle")
	_expect(hud.death_overlay.visible, cause + " death effect becomes visible")
	if cause == "physical":
		await create_timer(0.65).timeout
		_expect(hud.death_splash.color.a > 0.5, "Health death plays its blood splash")
	else:
		await create_timer(1.0).timeout
		_expect(hud.death_overlay.color.a > 0.0 and hud.death_overlay.color.a < 1.0, "Sanity death gradually extinguishes the screen illumination")

	var elapsed := 0.0
	while bool(main.get("_respawn_in_progress")) and elapsed < 7.0:
		await create_timer(0.05).timeout
		elapsed += 0.05
	_expect(not bool(main.get("_respawn_in_progress")), cause + " death completes the respawn")
	_expect(player.global_position == player.checkpoint_position, cause + " death returns the player to the checkpoint")
	_expect(player.vitals.health == player.vitals.max_health and player.vitals.sanity == player.vitals.max_sanity, cause + " respawn restores player vitals")
	_expect(player.is_physics_processing(), cause + " respawn restores player physics")
	_expect(not hud.death_overlay.visible and not hud.death_splash.visible, cause + " death effects hide after respawn")
	_expect(is_zero_approx(hud.death_overlay.color.a) and is_zero_approx(hud.death_splash.color.a), cause + " death effect alpha resets")
	_expect(is_zero_approx(hud.death_text.modulate.a) and hud.death_text.text.is_empty(), cause + " death text resets")
	await create_timer(0.1).timeout
	_expect(not hud.death_overlay.visible and is_zero_approx(hud.death_overlay.color.a), cause + " effect tween cannot reappear after the reset")

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)

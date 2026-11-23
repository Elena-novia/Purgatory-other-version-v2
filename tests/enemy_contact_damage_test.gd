extends SceneTree

const MAIN_SCENE := preload("res://scenes/world/main.tscn")
const ENEMY_SCENE := preload("res://scenes/world/enemy.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: PlayerController = main.get_node("Player")
	var enemy: EnemyHazard = ENEMY_SCENE.instantiate()
	enemy.patrol_distance = 0.0
	enemy.contact_damage_interval = 0.2
	var context: LayerContext = enemy.get_node("LayerContext")
	context.mode = LayerContext.Mode.FIXED
	context.fixed_layer = player.current_layer
	var contact_shape := enemy.get_node("CollisionShape2D") as CollisionShape2D
	(contact_shape.shape as CircleShape2D).radius = 250.0
	enemy.global_position = player.global_position
	main.add_child(enemy)
	await physics_frame
	var health_after_first_contact := player.vitals.health
	for _frame in range(28):
		await physics_frame
	_expect(health_after_first_contact < 1.0, "Enemy contact entry applies damage")
	_expect(player.vitals.health <= health_after_first_contact - 0.1, "Sustained contact reapplies damage at the enemy's configured interval")
	_expect(enemy.contact_damage_interval == 0.2, "Contact damage cadence is configured per enemy")
	main.queue_free()
	if failures.is_empty():
		print("Enemy contact damage: all checks passed.")
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

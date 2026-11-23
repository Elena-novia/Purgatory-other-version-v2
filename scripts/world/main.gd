@tool
extends Node2D

@onready var player: PlayerController = $Player
@onready var hud: GameHUD = $HUD
@onready var camera: Camera2D = $Player/Camera2D
var gameplay_layers: Array[GameplayLayer]
var checkpoint_instance: Checkpoint
var _respawn_in_progress := false

func _enter_tree() -> void:
	gameplay_layers = [$FrontLayer, $MiddleLayer, $BackLayer]

func get_depth_profiles() -> Array[GameplayLayer]:
	return gameplay_layers

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	checkpoint_instance = $Checkpoint
	player.global_position = Vector2(160, 520)
	player.set_checkpoint(Vector2(160, 520), 1)
	player.orb_toggle_requested.connect(player.magic_orb.toggle_release_or_retrieve)
	player.layer_input_backlog_full.connect(hud.show_layer_input_backlog_full)
	player.damaged.connect(hud.show_damage)
	player.vitals.values_changed.connect(hud.update_vitals)
	player.vitals.died.connect(_on_player_died)
	player.vitals._emit_values()
	_update_layer_parallax()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_update_layer_parallax()

func _update_layer_parallax() -> void:
	for gameplay_layer in gameplay_layers:
		gameplay_layer.update_parallax(player.global_position.x)

func _on_player_died(cause: String) -> void:
	if _respawn_in_progress:
		return
	_respawn_in_progress = true
	player.set_layer_transitions_suspended(true)
	player.cancel_damage_reaction()
	player.set_physics_process(false)
	await hud.show_death(cause)
	player.magic_orb.reset_to_player()
	player.restore_checkpoint_after_death()
	player.set_physics_process(true)
	# Let the repositioned player complete a physics tick before uncovering the
	# world, so the effect is never removed while respawn is still in progress.
	await get_tree().physics_frame
	hud.reset_death_effects()
	_respawn_in_progress = false
	player.set_layer_transitions_suspended(false)

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	draw_rect(Rect2(-4000, -2000, 8000, 2600), Color("171527"), true)
	for i in range(12):
		var x := float(i * 170)
		draw_colored_polygon(PackedVector2Array([Vector2(x, 360), Vector2(x + 95, 360), Vector2(x + 70, 120 + float(i % 3) * 34), Vector2(x + 28, 120 + float(i % 3) * 34)]), Color("211e36"))

extends Node2D
class_name MagicOrb

enum OrbState { FOLLOWING, STORED, RETURNING }

@export var follow_speed := 8.0
@export var interaction_distance := 100.0
@export var follow_offset := Vector2(34, -44)
@export var default_scale := Vector2.ONE
@export_range(1, 3, 1) var current_layer := 1:
	get:
		if state == OrbState.STORED and is_instance_valid(stored_receiver):
			if stored_receiver is PushBox:
				return (stored_receiver as PushBox).current_layer
			if stored_receiver is OrbReceiver:
				return (stored_receiver as OrbReceiver).current_layer
		return current_layer
	set(value):
		current_layer = clampi(value, 1, 3)
		if is_node_ready():
			depth_visuals.show_layer(current_layer)

@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals
@onready var vanish_effect: Node2D = $VanishEffect
@onready var vanish_glow: ColorRect = $VanishEffect/Glow
var state := OrbState.FOLLOWING
var player: Node2D
var stored_receiver: Node2D
var _phase := 0.0
var _vanish_tween: Tween

func _ready() -> void:
	player = get_parent()
	vanish_glow.material = (vanish_glow.material as ShaderMaterial).duplicate()
	add_to_group("magic_orb")
	if player is PlayerController:
		player.layer_changed.connect(_on_player_layer_changed)
		current_layer = player.current_layer
	depth_visuals.show_layer(current_layer, true)

func _process(delta: float) -> void:
	_phase += delta * 2.0
	if state == OrbState.FOLLOWING or state == OrbState.RETURNING:
		var target := player.global_position + follow_offset + Vector2(0, sin(_phase) * 5.0)
		global_position = global_position.lerp(target, clampf(follow_speed * delta, 0.0, 1.0))
		if global_position.distance_to(target) < 5.0:
			state = OrbState.FOLLOWING
	elif is_instance_valid(stored_receiver):
		global_position = stored_receiver.orb_anchor.global_position

func toggle_visibility() -> void:
	if depth_visuals.visible:
		_play_vanish_effect()
		depth_visuals.hide()
	else:
		if _vanish_tween and _vanish_tween.is_running():
			_vanish_tween.kill()
		vanish_effect.hide()
		depth_visuals.show()

func _play_vanish_effect() -> void:
	if _vanish_tween and _vanish_tween.is_running():
		_vanish_tween.kill()
	vanish_effect.global_position = global_position
	var material := vanish_glow.material as ShaderMaterial
	material.set_shader_parameter("fade", 1.0)
	vanish_effect.show()
	_vanish_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_vanish_tween.tween_method(_set_vanish_fade, 1.0, 0.0, 0.55)
	_vanish_tween.tween_callback(_hide_vanish_effect)

func _set_vanish_fade(value: float) -> void:
	(vanish_glow.material as ShaderMaterial).set_shader_parameter("fade", value)

func _hide_vanish_effect() -> void:
	vanish_effect.hide()

func toggle_release_or_retrieve() -> void:
	if state != OrbState.FOLLOWING:
		_retrieve()
		return
	var nearest: Node2D
	var nearest_distance := interaction_distance
	for candidate in get_tree().get_nodes_in_group("orb_receivers"):
		if not candidate.is_active_layer(player.current_layer):
			continue
		var distance := player.global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if nearest != null and nearest.receive_orb(self):
		stored_receiver = nearest
		reparent(nearest, true)
		state = OrbState.STORED
		if nearest is PushBox:
			var box_receiver := nearest as PushBox
			scale = box_receiver.stored_orb_scale
			z_index = 1
			depth_visuals.inherit_depth_from(box_receiver.depth_visuals)
		else:
			scale = default_scale
			z_index = 10
			if nearest is OrbReceiver:
				depth_visuals.inherit_depth_from((nearest as OrbReceiver).depth_visuals)
		global_position = nearest.orb_anchor.global_position
		player.vitals.orb_is_away = true

func _retrieve() -> void:
	if is_instance_valid(stored_receiver):
		stored_receiver.remove_orb(self)
	stored_receiver = null
	reparent(player, true)
	player.vitals.orb_is_away = false
	state = OrbState.RETURNING
	if player is PlayerController:
		current_layer = player.current_layer
	scale = default_scale
	z_index = 10
	depth_visuals.inherit_depth_from(null)

func reset_to_player() -> void:
	_retrieve()

func _on_player_layer_changed(layer_number: int) -> void:
	# Stored orbs use the receiver's depth profile; following or returning orbs
	# take the same logical layer profile as the player.
	if state != OrbState.STORED:
		current_layer = layer_number


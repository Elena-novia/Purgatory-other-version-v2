extends Node2D
class_name MagicOrb

enum OrbState { FOLLOWING, STORED, RETURNING }

@export var follow_speed := 8.0
@export var interaction_distance := 100.0
@export var follow_offset := Vector2(34, -44)
@export var default_scale := Vector2.ONE
@export_range(1, 3, 1) var current_layer := 1:
	get:
		if state == OrbState.STORED and is_instance_valid(stored_receiver) and stored_receiver is PushBox:
			return stored_receiver.current_layer
		return current_layer
	set(value):
		current_layer = clampi(value, 1, 3)
		if is_node_ready():
			depth_visuals.show_layer(current_layer)

@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals
var state := OrbState.FOLLOWING
var player: Node2D
var stored_receiver: Node2D
var _phase := 0.0

func _ready() -> void:
	player = get_parent()
	add_to_group("magic_orb")
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
		global_position = nearest.orb_anchor.global_position
		player.vitals.orb_is_away = true

func _retrieve() -> void:
	if is_instance_valid(stored_receiver):
		stored_receiver.remove_orb(self)
	stored_receiver = null
	reparent(player, true)
	player.vitals.orb_is_away = false
	state = OrbState.RETURNING
	scale = default_scale
	z_index = 10
	depth_visuals.inherit_depth_from(null)

func reset_to_player() -> void:
	_retrieve()


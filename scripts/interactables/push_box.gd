extends RigidBody2D
class_name PushBox

const MAX_LANDING_ANGLE := PI * 0.25

@export_range(1, 3, 1) var current_layer: int = 1:
	set(value):
		var next_layer := clampi(value, 1, 3)
		if current_layer == next_layer:
			return
		current_layer = next_layer
		if is_node_ready():
			depth_visuals.show_layer(current_layer)
@export var layer_shift_offset := 38.0
@export var transition_clearance := 4.0
@export var stored_orb_scale := Vector2(0.35, 0.35)
@export_range(100.0, 5000.0, 50.0) var push_force := 1500.0
@export_range(0.1, 10.0, 0.1) var push_resistance := 1.0
@export_range(0.5, 20.0, 0.5) var push_mass := 3.0
@export_range(0.0, 20.0, 0.1) var physics_damping := 0.8
@export_range(0.0, 5000.0, 50.0) var idle_braking_strength := 1400.0
@export_range(0.1, 20.0, 0.1) var stopping_velocity_threshold := 2.0
@export_range(20.0, 400.0, 5.0) var max_push_speed := 160.0
@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals
@onready var orb_anchor: Marker2D = $DepthVisuals/Artwork/OrbAnchor
@onready var body_shape: CollisionShape2D = $CollisionShape2D
var stored_orb := false
var stored_orb_instance: MagicOrb
var _push_force_received := false
var _push_suppressed_until_physics_frame := -1

func _ready() -> void:
	add_to_group("orb_receivers")
	collision_layer = 1 << (current_layer - 1)
	collision_mask = 1 << (current_layer - 1)
	gravity_scale = 0.0
	lock_rotation = true
	mass = push_mass
	linear_damp = physics_damping
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	depth_visuals.appearance_changed.connect(_place_stored_orb)
	depth_visuals.show_layer(current_layer, true)

func receive_push(direction: float) -> void:
	if not is_equal_approx(absf(direction), 1.0):
		return
	if Engine.get_physics_frames() <= _push_suppressed_until_physics_frame:
		return
	var resistance := maxf(push_resistance, 0.01)
	apply_central_force(Vector2(direction * push_force / resistance, 0.0))
	_push_force_received = true

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var body_velocity := state.linear_velocity
	body_velocity.x = clampf(body_velocity.x, -max_push_speed, max_push_speed)
	if not _push_force_received:
		body_velocity.x = move_toward(body_velocity.x, 0.0, idle_braking_strength * state.step)
		if absf(body_velocity.x) <= stopping_velocity_threshold:
			body_velocity.x = 0.0
	_push_force_received = false
	state.linear_velocity = body_velocity

func is_active_layer(layer_number: int) -> bool:
	return layer_number == current_layer

func receive_orb(orb: MagicOrb) -> bool:
	if stored_orb:
		return false
	stored_orb = true
	stored_orb_instance = orb
	return true

func remove_orb(_orb: MagicOrb) -> void:
	stored_orb = false
	stored_orb_instance = null

func can_shift_layer(target_layer: int, excluded_bodies: Array[RID] = [], landing_offset := 0.0) -> bool:
	if not stored_orb or target_layer < 1 or target_layer > 3:
		return false
	if target_layer == current_layer:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = layer_shift_transform(target_layer, landing_offset) * body_shape.transform
	query.transform.origin.y -= transition_clearance
	query.collision_mask = 1 << (target_layer - 1)
	query.exclude = [get_rid()]
	query.exclude.append_array(excluded_bodies)
	return get_world_2d().direct_space_state.intersect_shape(query, 8).is_empty()

func try_shift_layer(target_layer: int, excluded_bodies: Array[RID] = []) -> bool:
	var landing_offset := manual_landing_offset(target_layer)
	if not is_finite(landing_offset) or not can_shift_layer(target_layer, excluded_bodies, landing_offset):
		return false
	shift_to_layer(target_layer, landing_offset)
	return true

func manual_landing_offset(target_layer: int) -> float:
	if not stored_orb or target_layer < 1 or target_layer > 3:
		return INF
	if target_layer == current_layer:
		return 0.0
	return GameplayLayer.find_landing_offset(get_world_2d().direct_space_state,
		body_shape.shape, layer_shift_transform(target_layer) * body_shape.transform,
		target_layer, layer_shift_offset * 0.5, MAX_LANDING_ANGLE)

func layer_shift_transform(target_layer: int, landing_offset := 0.0) -> Transform2D:
	var destination := global_transform
	destination.origin.y += landing_offset - layer_shift_offset * float(target_layer - current_layer)
	return destination

func shift_to_layer(target_layer: int, landing_offset := 0.0) -> void:
	if not stored_orb or target_layer < 1 or target_layer > 3:
		return
	if target_layer == current_layer:
		return
	# RigidBody2D transforms are owned by the physics server. Set both the
	# scene transform and the body state so the next simulation tick cannot
	# restore the pre-transition transform.
	var destination_transform := layer_shift_transform(target_layer, landing_offset)
	current_layer = target_layer
	global_transform = destination_transform
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, destination_transform)
	var body_velocity := linear_velocity
	body_velocity.x = 0.0
	linear_velocity = body_velocity
	_push_force_received = false
	_push_suppressed_until_physics_frame = Engine.get_physics_frames() + 1
	collision_layer = 1 << (target_layer - 1)
	collision_mask = 1 << (target_layer - 1)
	_place_stored_orb()

func _place_stored_orb() -> void:
	if is_instance_valid(stored_orb_instance):
		stored_orb_instance.global_position = orb_anchor.global_position

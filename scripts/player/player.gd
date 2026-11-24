extends CharacterBody2D
class_name PlayerController

signal orb_toggle_requested
signal layer_changed(layer_index: int)
signal damaged
signal damage_landed
signal layer_input_backlog_full

const VOID_Y := 1000.0
const LAYER_STEPS_PER_PHYSICS_FRAME := 16
const MAX_PENDING_LAYER_STEPS := 64
const MAX_BUFFERED_KEYBOARD_STEPS := 16
# Relative steps use -1 and 1. Absolute requests are stored as the index plus this offset.
const ABSOLUTE_LAYER_REQUEST_OFFSET := 2

enum CheckpointRecovery { POSITION_ONLY, VOID_SURVIVAL, DEATH }

@export var move_speed := 240.0
@export var jump_velocity := -430.0
@export var layer_transition_offset := 38.0
@export var transition_clearance := 4.0
@export_range(300.0, 520.0, 1.0) var knockback_strength := 390.0
@export_range(0.0, 2000.0, 10.0) var knockback_acceleration := 480.0
@export_range(0.0, 400.0, 5.0) var damage_knockback_launch_impulse := 90.0
@export_range(200.0, 420.0, 1.0) var damage_jump_impulse := 250.0
@export_range(0.05, 1.0, 0.01) var damage_knockback_duration := 0.22
@export_range(0.0, 1.0, 0.01) var damage_knockback_gravity_scale := 0.78
@export_range(0.0, 2000.0, 10.0) var damage_knockback_air_control_acceleration := 1200.0
@export_range(200.0, 600.0, 10.0) var damage_knockback_max_horizontal_speed := 320.0
@export_range(0.0, 1000.0, 5.0) var damage_knockback_horizontal_damping := 80.0
@export_range(0.0, 1.0, 0.01) var damage_knockback_recovery_duration := 0.30
@export_range(0.0, 3000.0, 10.0) var damage_knockback_recovery_acceleration := 720.0
@export_range(0.16, 0.24, 0.01) var landing_shake_duration := 0.20
@export_range(3.0, 5.0, 0.1) var landing_shake_intensity := 4.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var depth_transition_duration := LayerDepthVisuals.DEFAULT_TRANSITION_DURATION:
	set(value):
		depth_transition_duration = value
		if is_node_ready():
			depth_visuals.transition_duration = value

@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals
@onready var visuals: AnimatedSprite2D = $DepthVisuals/PlayerSprite
@onready var vitals: PlayerVitals = $Vitals
@onready var camera: Camera2D = $Camera2D
@onready var magic_orb: MagicOrb = $Orb
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var walking_particles: CPUParticles2D = $WalkingParticles
var layer_context: LayerContext:
	get:
		return $LayerContext
var current_layer: int:
	get:
		var context := layer_context
		return context.logical_layer if context.is_inside_tree() else context.configured_dynamic_layer
	set(value):
		var next_layer := clampi(value, 1, 3)
		if is_inside_tree() and (_is_publishing_layer_state() or _layer_transitions_suspended \
				or (is_node_ready() and _get_stored_box() != null)):
			if not _request_context_layer(next_layer):
				push_warning("The requested player layer was not queued.")
		elif current_layer != next_layer:
			# Keep direct positioning/setup assignments outside gameplay publications.
			layer_context._commit_dynamic_layer(next_layer)
var checkpoint_position := Vector2(160, 520)
var checkpoint_layer := 1
var checkpoint_progression := 0
var facing_direction := 1.0
var _damage_flash_remaining := 0.0
var _base_color := Color.WHITE
var _damage_knockback_remaining := 0.0
var _damage_knockback_recovery_remaining := 0.0
var _damage_knockback_direction := 0.0
var _damage_landing_pending := false
var _intentional_jump := false
var _camera_base_offset := Vector2.ZERO
var _camera_shake_elapsed := 0.0
var _camera_shake_remaining := 0.0
var _reported_layer_mismatch := ""
var _visual_profile: GameplayLayer
var _ground_support := KinematicCollision2D.new()
var _other_support_query := PhysicsTestMotionParameters2D.new()
var _other_support := PhysicsTestMotionResult2D.new()
var _pending_layer_steps: Array[int] = []
var _buffered_keyboard_steps: Array[int] = []
var _processing_layer_steps := false
var _layer_transitions_suspended := false
var _layer_steps_frame := -1
var _layer_steps_processed := 0
var _checkpoint_visual_pending := false

func _enter_tree() -> void:
	layer_context._bind_dynamic_controller(_request_context_layer, _is_processing_layer_steps, _confirms_ground_owner)

func _ready() -> void:
	add_to_group("player")
	_camera_base_offset = camera.offset
	_apply_layer_mask()
	depth_visuals.transition_duration = depth_transition_duration
	refresh_visual_depth(true)

func refresh_visual_depth(immediate := false) -> void:
	if is_node_ready():
		_visual_profile = layer_context.depth_profile
		depth_visuals.show_profile(_visual_profile, immediate)

func _on_layer_context_changed() -> void:
	# The scene connects this handler before runtime observers subscribe.
	_apply_layer_mask()
	var immediate := _checkpoint_visual_pending
	_checkpoint_visual_pending = false
	if immediate or _visual_profile != layer_context.depth_profile:
		refresh_visual_depth(immediate)

func _process(delta: float) -> void:
	if _camera_shake_remaining > 0.0:
		_camera_shake_elapsed += delta
		_camera_shake_remaining = maxf(0.0, _camera_shake_remaining - delta)
		var progress := _camera_shake_remaining / landing_shake_duration
		var envelope := progress * progress
		var phase := _camera_shake_elapsed * TAU * 18.0
		camera.offset = _camera_base_offset + Vector2(
			sin(phase) * landing_shake_intensity * envelope,
			cos(phase * 1.31) * landing_shake_intensity * 0.65 * envelope
		)
	else:
		camera.offset = _camera_base_offset

func _physics_process(delta: float) -> void:
	_check_stored_box_layer_consistency()
	var was_on_floor := is_on_floor()
	if not is_on_floor():
		var gravity_scale := damage_knockback_gravity_scale if _damage_landing_pending else 1.0
		velocity.y += get_gravity().y * gravity_scale * delta
	var direction := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(direction):
		facing_direction = signf(direction)
	if _damage_landing_pending:
		if _damage_knockback_remaining > 0.0:
			_damage_knockback_remaining = maxf(0.0, _damage_knockback_remaining - delta)
			velocity.x += _damage_knockback_direction * knockback_acceleration * delta
			if _damage_knockback_remaining <= 0.0:
				_damage_knockback_recovery_remaining = damage_knockback_recovery_duration
		if not is_zero_approx(direction):
			velocity.x += direction * damage_knockback_air_control_acceleration * delta
		else:
			velocity.x = move_toward(velocity.x, 0.0, damage_knockback_horizontal_damping * delta)
		velocity.x = clampf(velocity.x, -damage_knockback_max_horizontal_speed, damage_knockback_max_horizontal_speed)
	elif _damage_knockback_recovery_remaining > 0.0:
		_damage_knockback_recovery_remaining = maxf(0.0, _damage_knockback_recovery_remaining - delta)
		velocity.x = move_toward(velocity.x, direction * move_speed, damage_knockback_recovery_acceleration * delta)
	else:
		velocity.x = direction * move_speed
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_intentional_jump = true
	if _damage_flash_remaining > 0.0:
		_damage_flash_remaining -= delta
		visuals.modulate = Color(1.0, 0.48, 0.48).lerp(_base_color, 1.0 - _damage_flash_remaining / 0.22)
	else:
		visuals.modulate = _base_color

	var synchronized_box := _get_stored_box()
	var fallback_layer := 0
	if not _layer_transitions_suspended and not was_on_floor and not _intentional_jump and velocity.y > 0.0:
		fallback_layer = _find_fallback_layer(velocity * delta, synchronized_box)
	if fallback_layer != 0:
		collision_mask |= GameplayLayer.landing_surface_bit(fallback_layer)
	move_and_slide()
	collision_mask = collision_layer
	var fallback_contact: KinematicCollision2D
	if is_on_floor():
		_intentional_jump = false
		if fallback_layer != 0:
			fallback_contact = _fallback_floor_contact(fallback_layer)
	if fallback_contact != null:
		var owner := _fallback_ground_owner(fallback_contact, fallback_layer)
		_commit_layer_change(fallback_layer, global_position, synchronized_box, 0.0,
			owner)
	else:
		_update_ground_owner()
	_try_push_box(direction)
	if not was_on_floor and is_on_floor() and _damage_landing_pending:
		_damage_landing_pending = false
		_damage_knockback_remaining = 0.0
		if _damage_knockback_recovery_remaining <= 0.0:
			_damage_knockback_recovery_remaining = damage_knockback_recovery_duration
		_start_landing_shake()
	_update_player_animation(direction, was_on_floor)
	_update_walking_particles(direction)
	if global_position.y > VOID_Y:
		fall_into_void()
	_process_layer_steps()

func _update_walking_particles(direction: float) -> void:
	var is_walking := is_on_floor() and visuals.animation == &"Walking" and not is_zero_approx(direction)
	walking_particles.emitting = is_walking
	if is_walking:
		walking_particles.position.x = -facing_direction * 6.0

func _update_player_animation(direction: float, was_on_floor: bool) -> void:
	visuals.flip_h = facing_direction < 0.0
	if not is_on_floor():
		if visuals.animation != &"Jump":
			visuals.play(&"Jump")
		return
	if not was_on_floor:
		visuals.play(&"Jump-To-Land")
		return
	if visuals.animation == &"Jump-To-Land" and visuals.is_playing():
		return
	if not is_zero_approx(direction):
		if visuals.animation != &"Walking":
			visuals.play(&"Walking")
		return
	if visuals.animation == &"Walking":
		visuals.play(&"Walking-To-Idle")
		return
	if visuals.animation == &"Walking-To-Idle" and visuals.is_playing():
		return
	if visuals.animation != &"Idle":
		visuals.play(&"Idle")

func _find_fallback_layer(motion: Vector2, synchronized_box: PushBox) -> int:
	# Prefer the active layer anywhere under the player's next position,
	# even if a foreign surface is higher than that layer's floor.
	var probe_origin := global_transform
	probe_origin.origin.x += motion.x
	var drop := VOID_Y - global_position.y
	var support := KinematicCollision2D.new()
	if drop <= 0.0 or (test_move(probe_origin, Vector2(0, drop), support, safe_margin, true)
		and support.get_angle(up_direction) <= floor_max_angle):
		return 0

	var surfaces := GameplayLayer.LANDING_SURFACE_MASK & ~GameplayLayer.landing_surface_bit(current_layer)
	while surfaces != 0:
		collision_mask = surfaces
		var will_land := test_move(global_transform, motion, support, safe_margin)
		collision_mask = collision_layer
		if not will_land or support.get_angle(up_direction) > floor_max_angle:
			return 0
		var body := support.get_collider() as StaticBody2D
		if body == null or (body.collision_layer & surfaces) == 0:
			return 0
		var target := GameplayLayer.landing_surface_layer(body.collision_layer)
		if target == 0:
			return 0
		var contact := global_position + support.get_travel()
		var remaining_x := global_position.x + motion.x - contact.x
		var floor_normal := support.get_normal()
		var end_position := contact + Vector2(remaining_x, -remaining_x * floor_normal.x / floor_normal.y)
		if _can_occupy_layer(target, contact, safe_margin) and _can_occupy_layer(target, end_position, safe_margin):
			if _can_sync_box(synchronized_box, target, contact, end_position):
				return target
		surfaces &= ~GameplayLayer.landing_surface_bit(target)
	return 0

func _fallback_floor_contact(target: int) -> KinematicCollision2D:
	var bit := GameplayLayer.landing_surface_bit(target)
	for i in range(get_slide_collision_count()):
		var contact := get_slide_collision(i)
		var body := contact.get_collider() as StaticBody2D
		if body != null and body.collision_layer == bit and contact.get_angle(up_direction) <= floor_max_angle:
			return contact
	return null

func _fallback_ground_owner(contact: KinematicCollision2D, target: int) -> GameplayLayer:
	# Query competing sections using only the confirmed layer's one-way support.
	# Begin above contact so the one-way solver can admit the short downward sweep.
	collision_mask = GameplayLayer.landing_surface_bit(target)
	var owner := _unambiguous_ground_owner(contact, target, safe_margin, safe_margin)
	collision_mask = collision_layer
	return owner

func _update_ground_owner() -> void:
	var context := layer_context
	var previous_owner := context.gameplay_layer
	var owner := _ground_contact_owner(context.logical_layer) if is_on_floor() else null
	if owner != previous_owner:
		context._commit_dynamic_layer(context.logical_layer, owner)

func _ground_contact_owner(layer: int) -> GameplayLayer:
	var floor_contact: KinematicCollision2D
	for index in range(get_slide_collision_count()):
		var contact := get_slide_collision(index)
		if contact.get_angle(up_direction) > floor_max_angle:
			continue
		if floor_contact != null and _section_for_contact(floor_contact, layer) != _section_for_contact(contact, layer):
			return null
		floor_contact = contact
	if floor_contact != null:
		return _unambiguous_ground_owner(floor_contact, layer, safe_margin)

	# A snapped body can be grounded without a recorded slide. The first sweep
	# confirms support, but it cannot distinguish coincident sections on its own.
	return _probe_ground_owner(layer, maxf(floor_snap_length, safe_margin))

func _confirms_ground_owner(section: GameplayLayer, layer: int) -> bool:
	if not is_node_ready() or _layer_transitions_suspended or velocity.dot(up_direction) > 0.0:
		return false
	# A sweep can find a future contact inside safe_margin. Publish only a
	# current floor contact, resolved against competing supports.
	return is_on_floor() and _ground_contact_owner(layer) == section

func _probe_ground_owner(layer: int, reach: float) -> GameplayLayer:
	var down := -up_direction
	if test_move(global_transform, down * reach, _ground_support, safe_margin, true) \
			and _ground_support.get_angle(up_direction) <= floor_max_angle:
		var distance := clampf(_ground_support.get_travel().dot(down), 0.0, reach)
		return _unambiguous_ground_owner(_ground_support, layer, distance + safe_margin)
	return null

func _unambiguous_ground_owner(contact: KinematicCollision2D, layer: int, reach: float,
		lift := 0.0) -> GameplayLayer:
	var section := _section_for_contact(contact, layer)
	if section == null:
		return null
	var excluded: Array[RID] = [contact.get_collider_rid()]
	_other_support_query.from = global_transform.translated(up_direction * lift)
	_other_support_query.motion = -up_direction * (reach + lift)
	_other_support_query.margin = safe_margin
	_other_support_query.recovery_as_collision = true
	_other_support_query.exclude_bodies = excluded
	# Search only at the original contact's height, skipping non-floor hits.
	while PhysicsServer2D.body_test_motion(get_rid(), _other_support_query, _other_support):
		if _other_support.get_collision_normal().dot(up_direction) >= cos(floor_max_angle) \
				and _section_for_support(_other_support.get_collider(), layer) != section:
			return null
		excluded.append(_other_support.get_collider_rid())
		_other_support_query.exclude_bodies = excluded
	return section

func _section_for_contact(contact: KinematicCollision2D, layer: int) -> GameplayLayer:
	return _section_for_support(contact.get_collider(), layer)

func _section_for_support(collider: Object, layer: int) -> GameplayLayer:
	var body := collider as StaticBody2D
	var section := body as GameplayLayer
	if section == null and body != null and body.collision_layer == GameplayLayer.landing_surface_bit(layer):
		section = LayerContext.find_gameplay_layer(body)
	return section if section != null and section.current_layer == layer else null

func _try_push_box(direction: float) -> void:
	if is_zero_approx(direction) or signf(direction) != facing_direction:
		return
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		var box := collision.get_collider() as PushBox
		if box == null or box.current_layer != current_layer:
			continue
		if collision.get_normal().x * direction < -0.5:
			box.receive_push(direction)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_W:
			_queue_keyboard_layer_step(1)
		elif event.physical_keycode == KEY_S:
			_queue_keyboard_layer_step(-1)
		elif event.physical_keycode == KEY_E:
			orb_toggle_requested.emit()
		elif event.physical_keycode == KEY_R:
			magic_orb.toggle_visibility()

func try_change_layer(direction: int) -> void:
	if absi(direction) == 1 and not request_layer_step(direction):
		push_warning("Layer step %d was not queued because the transition queue is full." % direction)

## Returns whether the request was admitted, not whether its transition is valid.
## A producer can retry a full queue on a later physics frame.
func request_layer_step(direction: int) -> bool:
	return absi(direction) == 1 and _queue_layer_request(direction)

func _request_context_layer(layer_number: int) -> bool:
	return _queue_layer_request(layer_number + ABSOLUTE_LAYER_REQUEST_OFFSET)

func _queue_keyboard_layer_step(direction: int) -> void:
	if request_layer_step(direction):
		return
	if _buffered_keyboard_steps.size() < MAX_BUFFERED_KEYBOARD_STEPS:
		_buffered_keyboard_steps.append(direction)
	else:
		layer_input_backlog_full.emit()

func _admit_buffered_keyboard_steps() -> void:
	while not _buffered_keyboard_steps.is_empty() and _pending_layer_steps.size() < MAX_PENDING_LAYER_STEPS:
		_pending_layer_steps.append(_buffered_keyboard_steps.pop_front())

func _queue_layer_request(request: int) -> bool:
	_admit_buffered_keyboard_steps()
	if _pending_layer_steps.size() >= MAX_PENDING_LAYER_STEPS:
		return false
	_pending_layer_steps.append(request)
	_process_layer_steps()
	return true

func set_layer_transitions_suspended(suspended: bool) -> void:
	_layer_transitions_suspended = suspended

func _is_processing_layer_steps() -> bool:
	return _processing_layer_steps

func _is_publishing_layer_state() -> bool:
	return _processing_layer_steps or layer_context.is_publishing_context()

func _process_layer_steps() -> void:
	if _pending_layer_steps.is_empty() or _is_publishing_layer_state() or not _can_process_layer_steps():
		return
	var frame := Engine.get_physics_frames()
	if frame != _layer_steps_frame:
		_layer_steps_frame = frame
		_layer_steps_processed = 0
	_processing_layer_steps = true
	while _layer_steps_processed < LAYER_STEPS_PER_PHYSICS_FRAME and not _pending_layer_steps.is_empty() \
			and _can_process_layer_steps():
		_layer_steps_processed += 1
		var request: int = _pending_layer_steps.pop_front()
		# Give this slot to the oldest buffered key before callbacks can submit more work.
		_admit_buffered_keyboard_steps()
		var direction := request if absi(request) == 1 else request - ABSOLUTE_LAYER_REQUEST_OFFSET - current_layer
		if absi(direction) == 1:
			_try_layer_step(direction)
	_processing_layer_steps = false

func _can_process_layer_steps() -> bool:
	return is_node_ready() and is_physics_processing() and not _layer_transitions_suspended

func _try_layer_step(direction: int) -> void:
	var target := current_layer + direction
	if target < 1 or target > 3:
		return
	var step := Vector2(0, -direction * layer_transition_offset)
	var airborne := not is_on_floor() or velocity.y < 0.0
	var layer_adjustment := _validated_layer_adjustment(target, step, airborne)
	if not is_finite(layer_adjustment):
		_log_layer_transition("No walkable ground for the player on layer %d." % target)
		return
	var destination := global_position + step + Vector2(0, layer_adjustment)
	if destination.y > VOID_Y:
		_log_layer_transition("Player destination is below the void boundary on layer %d." % target)
		return
	if not _can_occupy_layer(target, destination, 0.0 if airborne else transition_clearance):
		_log_layer_transition("Player destination blocked on layer %d." % target)
		return
	var synchronized_box := _get_stored_box()
	var box_offset := 0.0
	if synchronized_box != null:
		box_offset = synchronized_box.manual_landing_offset(target)
		if not is_finite(box_offset):
			_log_layer_transition("No walkable ground for the box on layer %d." % target)
			return
		if not _can_sync_box(synchronized_box, target, destination, destination, box_offset):
			_log_layer_transition("Box destination blocked on layer %d at %s." % [target, str(synchronized_box.global_position)])
			return
	_commit_layer_change(target, destination, synchronized_box, box_offset)

func _validated_layer_adjustment(target: int, step: Vector2, airborne: bool) -> float:
	var space := get_world_2d().direct_space_state
	var source := body_shape.global_transform
	var destination := source.translated(step)
	var nearby := layer_transition_offset * 0.5
	if not airborne:
		return GameplayLayer.find_landing_offset(space, body_shape.shape, destination, target, nearby, floor_max_angle)

	var gravity := maxf(get_gravity().y, 1.0)
	var jump_height := jump_velocity * jump_velocity / (2.0 * gravity)
	if _damage_landing_pending:
		var knockback_gravity := maxf(gravity * damage_knockback_gravity_scale, 1.0)
		var knockback_height := damage_jump_impulse * damage_jump_impulse / (2.0 * knockback_gravity)
		jump_height = maxf(jump_height, knockback_height)
	var reach := jump_height + nearby

	# Where both layers have nearby floor heights, translate by their difference
	# and preserve the player's current height above the floor.
	var source_drop := GameplayLayer.find_landing_offset(space, body_shape.shape, source, current_layer,
		safe_margin, floor_max_angle, reach)
	if is_finite(source_drop):
		var target_floor_probe := destination.translated(Vector2(0, source_drop))
		var adjustment := GameplayLayer.find_landing_offset(space, body_shape.shape, target_floor_probe,
			target, nearby, floor_max_angle)
		if is_finite(adjustment) and global_position.y + step.y + source_drop + adjustment <= VOID_Y:
			return adjustment

	# If the player is over a gap in the source layer, keep the normal layer step
	# and confirm there is somewhere to land below the airborne destination.
	var target_drop := GameplayLayer.find_landing_offset(space, body_shape.shape, destination, target,
		safe_margin, floor_max_angle, reach)
	if is_finite(target_drop) and global_position.y + step.y + target_drop <= VOID_Y:
		return 0.0
	return INF

func _can_occupy_layer(target: int, destination: Vector2, clearance: float) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = body_shape.global_transform
	query.transform.origin += destination - global_position + up_direction * clearance
	query.collision_mask = GameplayLayer.solid_collision_bit(target)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _can_sync_box(box: PushBox, target: int, contact: Vector2, end_position: Vector2, box_offset := 0.0) -> bool:
	if box == null:
		return true
	if not box.can_shift_layer(target, [get_rid()], box_offset):
		return false
	var box_shape := box.layer_shift_transform(target, box_offset) * box.body_shape.transform
	var player_shape := body_shape.global_transform
	player_shape.origin += contact - global_position
	if body_shape.shape.collide(player_shape, box.body_shape.shape, box_shape):
		return false
	player_shape.origin += end_position - contact
	return not body_shape.shape.collide(player_shape, box.body_shape.shape, box_shape)

func _get_stored_box() -> PushBox:
	if magic_orb.state == MagicOrb.OrbState.STORED and is_instance_valid(magic_orb.stored_receiver):
		return magic_orb.stored_receiver as PushBox
	return null

func _commit_layer_change(target: int, destination: Vector2, synchronized_box: PushBox,
		box_offset := 0.0, owner: GameplayLayer = null) -> void:
	var source := current_layer
	var was_processing := _processing_layer_steps
	_processing_layer_steps = true
	if synchronized_box != null:
		synchronized_box.shift_to_layer(target, box_offset)
	global_position = destination
	layer_context._commit_dynamic_layer(target, owner)
	layer_changed.emit(target)
	if synchronized_box != null:
		_log_layer_transition("Synchronized runtime state: player_layer=%d player_position=%s player_collision=(%d,%d), box_layer=%d box_position=%s box_collision=(%d,%d), orb_state=%s receiver=%s, source_layer=%d" % [
			target, str(global_position), collision_layer, collision_mask,
			synchronized_box.current_layer, str(synchronized_box.global_position),
			synchronized_box.collision_layer, synchronized_box.collision_mask,
			str(magic_orb.state), str(magic_orb.stored_receiver), source
		])
	_processing_layer_steps = was_processing
	_process_layer_steps()

func _log_layer_transition(message: String) -> void:
	if OS.is_debug_build():
		print_debug("[LayerTransition] ", message)

func _check_stored_box_layer_consistency() -> void:
	if magic_orb.state != MagicOrb.OrbState.STORED or not is_instance_valid(magic_orb.stored_receiver):
		_reported_layer_mismatch = ""
		return
	var box := magic_orb.stored_receiver as PushBox
	if box == null:
		_reported_layer_mismatch = ""
		return
	if current_layer == box.current_layer:
		_reported_layer_mismatch = ""
		return
	var mismatch := "%d/%d" % [current_layer, box.current_layer]
	if mismatch == _reported_layer_mismatch:
		return
	_reported_layer_mismatch = mismatch
	_log_layer_transition("CONSISTENCY ERROR: stored box differs from player; player_layer=%d player_position=%s player_collision=(%d,%d), box_layer=%d box_position=%s box_collision=(%d,%d), orb_state=%s receiver=%s" % [
		current_layer, str(global_position), collision_layer, collision_mask,
		box.current_layer, str(box.global_position), box.collision_layer, box.collision_mask,
		str(magic_orb.state), str(magic_orb.stored_receiver)
	])

func _apply_layer_mask() -> void:
	collision_layer = layer_context.solid_bit
	collision_mask = collision_layer

func take_hit(amount: float = -1.0, source_position: Vector2 = Vector2.ZERO) -> void:
	vitals.take_damage(amount)
	_damage_flash_remaining = 0.22
	if source_position != Vector2.ZERO and vitals.health > 0.0 and vitals.sanity > 0.0:
		var knockback_direction := signf(global_position.x - source_position.x)
		if is_zero_approx(knockback_direction):
			knockback_direction = -signf(velocity.x)
			if is_zero_approx(knockback_direction):
				knockback_direction = 1.0
		_damage_knockback_direction = knockback_direction
		velocity.x = knockback_direction * minf(knockback_strength, damage_knockback_launch_impulse)
		velocity.y = -damage_jump_impulse
		_damage_knockback_remaining = damage_knockback_duration
		_damage_knockback_recovery_remaining = 0.0
		_damage_landing_pending = true
		_intentional_jump = false
	$BloodParticles.restart()
	$BloodParticles.emitting = true
	damaged.emit()

func _start_landing_shake() -> void:
	_camera_shake_elapsed = 0.0
	_camera_shake_remaining = landing_shake_duration
	camera.offset = _camera_base_offset
	damage_landed.emit()

func cancel_damage_reaction() -> void:
	_damage_knockback_remaining = 0.0
	_damage_knockback_recovery_remaining = 0.0
	_damage_landing_pending = false
	_intentional_jump = false
	_camera_shake_remaining = 0.0
	camera.offset = _camera_base_offset

func set_checkpoint(point: Vector2, layer_number: int = 1, progression_order: int = 0) -> void:
	if progression_order < checkpoint_progression:
		return
	checkpoint_position = point
	checkpoint_layer = clampi(layer_number, 1, 3)
	checkpoint_progression = progression_order

func restore_checkpoint() -> void:
	_restore_checkpoint(CheckpointRecovery.POSITION_ONLY)

func restore_checkpoint_after_death() -> void:
	_restore_checkpoint(CheckpointRecovery.DEATH)

func _restore_checkpoint(recovery: CheckpointRecovery) -> void:
	# Explicit restore requests from signal observers must wait until publication ends.
	if _is_publishing_layer_state():
		await get_tree().physics_frame
	var was_processing := _processing_layer_steps
	_processing_layer_steps = true
	global_position = checkpoint_position
	velocity = Vector2.ZERO
	_intentional_jump = false
	_damage_knockback_remaining = 0.0
	_damage_knockback_recovery_remaining = 0.0
	_damage_landing_pending = false
	match recovery:
		CheckpointRecovery.DEATH:
			vitals._restore_values()
		CheckpointRecovery.VOID_SURVIVAL:
			vitals.sanity = vitals.max_sanity
	_checkpoint_visual_pending = true
	layer_context._commit_dynamic_layer(checkpoint_layer)
	if _checkpoint_visual_pending:
		# A same-layer return without an owner may not emit context_changed.
		_on_layer_context_changed()
	if recovery != CheckpointRecovery.POSITION_ONLY:
		vitals._emit_values()
	_processing_layer_steps = was_processing
	_process_layer_steps()

func fall_into_void() -> void:
	if global_position.y < VOID_Y:
		return
	take_hit()
	var synchronized_box := _get_stored_box()
	if synchronized_box != null and synchronized_box.current_layer != checkpoint_layer:
		magic_orb.reset_to_player()
	# A lethal fall already started Main's physical-death sequence.
	if vitals.health > 0.0:
		_restore_checkpoint(CheckpointRecovery.VOID_SURVIVAL)

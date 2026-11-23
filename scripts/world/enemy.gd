extends Area2D
class_name EnemyHazard

@export var damage := 0.1
@export var patrol_distance := 90.0
@export var patrol_speed := 0.75
@export_range(0.05, 5.0, 0.05) var contact_damage_interval := 0.8

@onready var layer_context: LayerContext = $LayerContext
@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals
@onready var mount: LayerObjectMount = $Mount

var _time := 0.0
var _contact_damage_remaining: Dictionary = {}

func _ready() -> void:
	layer_context.context_changed.connect(_apply_context)
	_apply_context(true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _apply_context(immediate := false) -> void:
	var mask := layer_context.solid_bit
	if collision_mask != mask:
		collision_mask = mask
		_contact_damage_remaining.clear()
	depth_visuals.show_profile(layer_context.depth_profile, immediate)

func _physics_process(delta: float) -> void:
	_time += delta
	# Patrol remains horizontal in world space, with its original range and phase.
	mount.set_world_offset(Vector2(sin(_time * patrol_speed) * patrol_distance, 0.0))
	for body in get_overlapping_bodies():
		if _can_damage(body):
			var key := body.get_instance_id()
			_contact_damage_remaining[key] = float(_contact_damage_remaining.get(key, 0.0)) - delta
			if _contact_damage_remaining[key] <= 0.0:
				_apply_contact_damage(body)

func _on_body_entered(body: Node2D) -> void:
	if _can_damage(body):
		var key := body.get_instance_id()
		if not _contact_damage_remaining.has(key):
			_apply_contact_damage(body)

func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		_contact_damage_remaining.erase(body.get_instance_id())

func _can_damage(body: Node2D) -> bool:
	return body is PlayerController and body.current_layer == layer_context.logical_layer

func _apply_contact_damage(body: PlayerController) -> void:
	body.take_hit(damage, global_position)
	_contact_damage_remaining[body.get_instance_id()] = contact_damage_interval

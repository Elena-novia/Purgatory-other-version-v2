extends Node2D
class_name PressurePlate

signal pressed
signal released
signal state_changed(is_pressed: bool)

const CONTACT_DISTANCE := 2.0
const BOX_RISE_TOLERANCE := 1.0

@export_group("Activation")
@export var player_can_activate := true
@export var box_can_activate := true

@export_group("Dimensions")
## Vertical distance from the plate artwork's origin to its supporting floor, in world pixels.
@export_range(0.0, 64.0, 0.5, "or_greater", "suffix:px") var floor_contact_offset := 0.0:
	set(value):
		floor_contact_offset = value
		if is_node_ready():
			_position_components()
@export_range(32.0, 160.0, 1.0) var plate_width := 64.0:
	set(value):
		plate_width = maxf(value, 32.0)
		_update_geometry()
@export_range(6.0, 24.0, 1.0) var plate_height := 8.0:
	set(value):
		plate_height = maxf(value, 6.0)
		_update_geometry()

@export_group("Animation")
@export_range(1.0, 16.0, 0.5) var depression_distance := 4.0:
	set(value):
		depression_distance = maxf(value, 1.0)
		if is_node_ready() and not is_pressed:
			button_top.position.y = -2.0
@export_range(0.01, 0.5, 0.01, "suffix:s") var press_duration := 0.10
@export_range(0.01, 0.8, 0.01, "suffix:s") var release_duration := 0.16

var is_pressed := false:
	set(value):
		if is_pressed == value:
			return
		is_pressed = value
		state_changed.emit(is_pressed)
		if is_pressed:
			pressed.emit()
		else:
			released.emit()
		_animate_button()

var current_layer: int:
	get:
		return layer_context.logical_layer

@onready var layer_context: LayerContext = $LayerContext
@onready var depth_visuals: LayerDepthVisuals = $Visuals
@onready var base_visual: Polygon2D = $Visuals/Base
@onready var button_top: Polygon2D = $Visuals/ButtonTop
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D

var _animation: Tween
var _support_query := PhysicsTestMotionParameters2D.new()
var _support_result := PhysicsTestMotionResult2D.new()

func _ready() -> void:
	# Keep the mount position from the layer scene. Its tint and nonuniform
	# terrain scale must not compound the artwork or resize the sensor.
	depth_visuals.top_level = true
	depth_visuals.z_index = 2
	detection_area.top_level = true
	_position_components()
	set_notify_transform(true)
	visibility_changed.connect(func(): depth_visuals.visible = is_visible_in_tree())
	depth_visuals.visible = is_visible_in_tree()
	_update_geometry()
	layer_context.context_changed.connect(_sync_layer)
	_sync_layer(true)
	_support_query.motion = Vector2.DOWN * CONTACT_DISTANCE

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_position_components()

func _position_components() -> void:
	depth_visuals.global_position = global_position
	detection_area.global_position = global_position + Vector2.DOWN * floor_contact_offset

func _sync_layer(immediate := false) -> void:
	detection_area.collision_mask = layer_context.solid_bit
	depth_visuals.show_profile(layer_context.depth_profile, immediate)

func _physics_process(_delta: float) -> void:
	for body in detection_area.get_overlapping_bodies():
		if _is_valid_press(body):
			is_pressed = true
			return
	is_pressed = false

func _is_valid_press(body: Node2D) -> bool:
	var layer := 0
	var shape_node: CollisionShape2D
	var physics_body: PhysicsBody2D
	if body is PlayerController and player_can_activate:
		var player := body as PlayerController
		layer = player.current_layer
		shape_node = player.body_shape
		physics_body = player
		if player.velocity.y < 0.0:
			return false
	elif body is PushBox and box_can_activate:
		var box := body as PushBox
		layer = box.current_layer
		shape_node = box.body_shape
		physics_body = box
		if box.linear_velocity.y < -BOX_RISE_TOLERANCE:
			return false
	else:
		return false
	if layer != current_layer or shape_node == null or shape_node.disabled or shape_node.shape == null:
		return false
	var object_bounds := shape_node.global_transform * shape_node.shape.get_rect()
	# The sensor is aligned to the load-bearing surface independently of the artwork.
	if absf(object_bounds.end.y - detection_area.global_position.y) > CONTACT_DISTANCE:
		return false
	var left := global_position.x - plate_width * 0.5
	var right := global_position.x + plate_width * 0.5
	var horizontal_overlap := minf(object_bounds.end.x, right) - maxf(object_bounds.position.x, left)
	var required_overlap := minf(object_bounds.size.x * 0.5, plate_width * 0.25)
	if horizontal_overlap < required_overlap:
		return false
	_support_query.from = physics_body.global_transform
	if not PhysicsServer2D.body_test_motion(physics_body.get_rid(), _support_query, _support_result):
		return false
	var support := _support_result.get_collider() as PhysicsBody2D
	return support != null and (support.collision_layer & detection_area.collision_mask) != 0 \
		and _support_result.get_collision_normal().dot(Vector2.UP) >= 0.707107

func _update_geometry() -> void:
	if not is_node_ready():
		return
	var base_half := plate_width * 0.5
	base_visual.polygon = PackedVector2Array([
		Vector2(-base_half, 0), Vector2(base_half, 0),
		Vector2(base_half, plate_height), Vector2(-base_half, plate_height),
	])
	var top_half := plate_width * 0.38
	button_top.polygon = PackedVector2Array([
		Vector2(-top_half, -8), Vector2(top_half, -8),
		Vector2(top_half, 0), Vector2(-top_half, 0),
	])
	var sensor_rectangle := detection_shape.shape as RectangleShape2D
	sensor_rectangle.size.x = plate_width

func _animate_button() -> void:
	if not is_node_ready():
		return
	if _animation and _animation.is_running():
		_animation.kill()
	_animation = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var target_y := -2.0 + (depression_distance if is_pressed else 0.0)
	_animation.tween_property(button_top, "position:y", target_y, press_duration if is_pressed else release_duration)

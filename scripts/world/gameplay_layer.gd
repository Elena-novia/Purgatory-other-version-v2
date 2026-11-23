@tool
extends StaticBody2D
class_name GameplayLayer

signal depth_changed
signal logical_layer_changed

const LANDING_SURFACE_MASK := 0b111000

@export_range(1, 3, 1) var current_layer := 1:
	set(value):
		var next_layer := clampi(value, 1, 3)
		if next_layer == current_layer:
			return
		current_layer = next_layer
		collision_layer = solid_collision_bit(current_layer)
		logical_layer_changed.emit()
@export var parallax_scroll_factor := 1.0

@export_group("Visual Depth")
@export_range(0.1, 2.0, 0.01) var depth_scale := 1.0:
	set(value):
		depth_scale = value
		_apply_visual_depth()
@export var depth_tint := Color.WHITE:
	set(value):
		depth_tint = value
		_apply_visual_depth()
@export_range(0.0, 1.0, 0.01) var tint_strength := 0.0:
	set(value):
		tint_strength = value
		_apply_visual_depth()

@onready var parallax_decoration: Node2D = $ParallaxDecoration
@onready var depth_decoration: Node2D = $ParallaxDecoration/DepthDetails
@onready var _parallax_origin: Vector2 = parallax_decoration.position

var _exiting_tree := false

func _enter_tree() -> void:
	_exiting_tree = false

func _exit_tree() -> void:
	# Godot emits tree_exiting after this callback, while the node is still in the tree.
	_exiting_tree = true

func is_available_as_owner() -> bool:
	return is_inside_tree() and not _exiting_tree and not is_queued_for_deletion()

func _ready() -> void:
	collision_layer = solid_collision_bit(current_layer)
	_apply_visual_depth()

func depth_modulation() -> Color:
	return Color.WHITE.lerp(Color(depth_tint, 1.0), tint_strength)

func _apply_visual_depth() -> void:
	if not is_node_ready():
		return
	modulate = depth_modulation()
	depth_decoration.scale = Vector2.ONE * depth_scale
	for child in get_children():
		if child is CollisionPolygon2D:
			child.queue_redraw()
	depth_changed.emit()

static func is_valid_layer(layer_number: int) -> bool:
	return layer_number >= 1 and layer_number <= 3

static func solid_collision_bit(layer_number: int) -> int:
	return 1 << (layer_number - 1) if is_valid_layer(layer_number) else 0

static func landing_surface_bit(layer_number: int) -> int:
	return 1 << (layer_number + 2) if is_valid_layer(layer_number) else 0

static func landing_surface_layer(bit: int) -> int:
	match bit:
		0b001000: return 1
		0b010000: return 2
		0b100000: return 3
		_: return 0

# Return the vertical adjustment from the nominal destination, or INF if unsupported.
static func find_landing_offset(space: PhysicsDirectSpaceState2D, shape: Shape2D,
		destination: Transform2D, target: int, search_above: float, floor_angle: float,
		search_below := -1.0) -> float:
	var drop := search_above if search_below < 0.0 else search_below
	var bounds := destination * shape.get_rect()
	var center_x := bounds.get_center().x
	var feet_y := bounds.end.y
	var support_span := bounds.size.x * 0.25
	var surface_mask := landing_surface_bit(target)
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = surface_mask
	var ground_y := INF
	var needs_shape_cast := false
	# Require support across the central half of the collider's footprint.
	for x_offset: float in [0.0, -support_span, support_span]:
		var sample := Vector2(center_x + x_offset, feet_y)
		query.from = sample - Vector2(0, search_above)
		query.to = sample + Vector2(0, drop)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or Vector2.UP.dot(hit.normal) < cos(floor_angle):
			return INF
		var sample_y: float = hit.position.y
		if x_offset == 0.0:
			ground_y = sample_y
		elif absf(sample_y - ground_y) > support_span * tan(floor_angle) + 1.0:
			return INF
		needs_shape_cast = needs_shape_cast or not is_equal_approx(sample_y, ground_y) or not is_zero_approx(hit.normal.x)

	if not needs_shape_cast:
		return ground_y - feet_y

	# On a slope, fit the full shape so its uphill side clears the surface.
	var sweep := PhysicsShapeQueryParameters2D.new()
	sweep.shape = shape
	sweep.collision_mask = surface_mask
	var rise := search_above + bounds.size.x * 0.5 * tan(floor_angle)
	sweep.transform = destination.translated(Vector2(0, -rise))
	sweep.motion = Vector2(0, rise + drop)
	var fractions := space.cast_motion(sweep)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return INF
	var adjustment := fractions[0] * sweep.motion.y - rise
	return adjustment if adjustment >= -search_above and adjustment <= drop else INF

func update_parallax(tracked_x: float) -> void:
	var world_offset := Vector2(tracked_x * (1.0 - parallax_scroll_factor), 0.0)
	parallax_decoration.position = _parallax_origin + to_local(global_position + world_offset)

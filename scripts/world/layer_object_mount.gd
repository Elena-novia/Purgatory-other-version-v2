extends Node
class_name LayerObjectMount

## World position of the object's scene placement, before movement such as patrol.
var origin: Vector2:
	get:
		if _check_reparent:
			return _object.global_position - _world_offset
		return _parent_frame * _local_origin

var _object: Node2D
var _parent_frame: Transform2D
var _local_origin: Vector2
var _entry_world: Transform2D
var _world_offset := Vector2.ZERO
var _has_mounted := false
var _check_reparent := false

func _enter_tree() -> void:
	_object = get_parent() as Node2D
	var local_pose := _object.transform
	if not _has_mounted:
		_local_origin = local_pose.origin
	_parent_frame = _get_parent_frame()
	_entry_world = world_pose(_parent_frame, local_pose)
	_check_reparent = _has_mounted
	_has_mounted = true
	if _check_reparent:
		_object.transform = _entry_world
	process_physics_priority = -10

func _ready() -> void:
	# The receiver and the orb it carries must be isolated from section tint
	# and scale. The object's artwork applies its own depth below this root.
	# Wait until descendants have entered the canvas before changing roots.
	_object.top_level = true
	_object.transform = _entry_world

func _exit_tree() -> void:
	_accept_reparented_pose()
	var local_pose := _local_pose(_parent_frame, _object.global_transform)
	# Godot reads the old world pose before removing the node. Give the
	# destination its placement-local pose, which the native false mode keeps.
	# Leave canvas isolation in place while the children exit their viewport.
	_object.transform = local_pose

func _physics_process(_delta: float) -> void:
	_accept_reparented_pose()
	var next_frame := _get_parent_frame()
	if next_frame == _parent_frame:
		return
	var placement := _object.global_transform
	placement.origin -= _world_offset
	var local_pose := _local_pose(_parent_frame, placement)
	_parent_frame = next_frame
	var world := world_pose(_parent_frame, local_pose)
	world.origin += _world_offset
	_object.transform = world

## Motion in world pixels, independent of the parent's rotation and scale.
func set_world_offset(offset: Vector2) -> void:
	_accept_reparented_pose()
	_world_offset = offset
	_object.global_position = origin + offset

func _accept_reparented_pose() -> void:
	if not _check_reparent:
		return
	# Both native reparent modes leave the selected pose on the object. Recover
	# its anchor from that pose and the unchanged world-space motion offset.
	_local_origin = _parent_frame.affine_inverse() * origin
	_check_reparent = false

func _get_parent_frame() -> Transform2D:
	var parent := _object.get_parent() as CanvasItem
	var frame := parent.get_global_transform() if parent != null else Transform2D.IDENTITY
	# A collapsed parent has no inverse. Use the last valid placement frame
	# until its scale is restored.
	return _parent_frame if is_zero_approx(frame.determinant()) else frame

## The full parent transform positions the object. Its orthonormal basis
## carries orientation without stretching or shearing the authored object.
static func world_pose(frame: Transform2D, local_pose: Transform2D) -> Transform2D:
	var world := frame.orthonormalized() * local_pose
	world.origin = frame * local_pose.origin
	return world

static func _local_pose(frame: Transform2D, world: Transform2D) -> Transform2D:
	var local := frame.orthonormalized().affine_inverse() * world
	local.origin = frame.affine_inverse() * world.origin
	return local

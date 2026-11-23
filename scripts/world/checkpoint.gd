@tool
extends Area2D
class_name Checkpoint

@export var respawn_offset := Vector2(0, -18)

@export_enum("Use parent layer", "Front (1)", "Middle (2)", "Back (3)", "All layers") var selected_layer := 0:
	set(value):
		selected_layer = clampi(value, 0, 4)
		if is_node_ready():
			_sync_layer_selection()

@export_range(0, 999, 1) var progression_order := 1

@export_group("Marker")
## Authored offset in checkpoint coordinates. The marker itself uses uniform depth scale.
@export var marker_offset := Vector2.ZERO:
	set(value):
		marker_offset = value
		if is_node_ready():
			_sync_marker_pose()
@export_range(-PI, PI, 0.01, "radians_as_degrees") var marker_rotation := 0.0:
	set(value):
		marker_rotation = value
		if is_node_ready():
			_sync_marker_pose()

@onready var layer_context: LayerContext = $LayerContext
@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals

func _ready() -> void:
	_sync_layer_selection()
	layer_context.context_changed.connect(_apply_context)
	set_notify_transform(true)
	_sync_marker_pose()
	_apply_context(true)
	if Engine.is_editor_hint():
		return
	add_to_group("checkpoints")
	monitoring = true
	depth_visuals.hide()
	body_entered.connect(_on_body_entered)

func _apply_context(immediate := false) -> void:
	if not Engine.is_editor_hint():
		collision_mask = 0b111 if selected_layer == 4 else layer_context.solid_bit
	depth_visuals.show_profile(layer_context.depth_profile, immediate)

func _sync_layer_selection() -> void:
	if not is_node_ready():
		return
	if selected_layer == 0 or selected_layer == 4:
		layer_context.mode = LayerContext.Mode.INHERITED
	else:
		layer_context.mode = LayerContext.Mode.FIXED
		layer_context.fixed_layer = selected_layer
	_apply_context(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_sync_marker_pose()

func _sync_marker_pose() -> void:
	var placement := global_transform
	if Engine.is_editor_hint():
		var parent := get_parent() as CanvasItem
		if parent != null:
			placement = LayerObjectMount.world_pose(parent.get_global_transform(), transform)
	depth_visuals.global_position = placement * marker_offset
	depth_visuals.global_rotation = (placement * Transform2D(marker_rotation, Vector2.ZERO)).get_rotation()

func _on_body_entered(body: Node2D) -> void:
	if not body is PlayerController:
		return
	var saved_layer: int = body.current_layer
	if selected_layer != 4 and saved_layer != layer_context.logical_layer:
		return
	body.set_checkpoint(global_position + respawn_offset, saved_layer, progression_order)

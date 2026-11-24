extends Node2D
class_name OrbReceiver

signal orb_placed(receiver: OrbReceiver)
signal orb_removed(receiver: OrbReceiver)

@export var accepts_orb := true
@export_enum("Inherit from parent", "Front", "Middle", "Back") var configured_layer := 0
var current_layer: int:
	get:
		return layer_context.logical_layer

@onready var layer_context: LayerContext = $LayerContext
@onready var body: StaticBody2D = $Body
@onready var depth_visuals: LayerDepthVisuals = $DepthVisuals
@onready var orb_anchor: Marker2D = $DepthVisuals/OrbAnchor
@onready var indicator: Polygon2D = $DepthVisuals/Indicator
var has_orb := false

func _enter_tree() -> void:
	# Configure the child before LayerContext enters the tree and resolves its
	# initial context. Zero preserves the existing inherited-layer behavior.
	var context := get_node_or_null("LayerContext") as LayerContext
	if context == null:
		return
	if configured_layer == 0:
		context.mode = LayerContext.Mode.INHERITED
	else:
		context.mode = LayerContext.Mode.FIXED
		context.fixed_layer = configured_layer

func _ready() -> void:
	add_to_group("orb_receivers")
	layer_context.context_changed.connect(_apply_context)
	_apply_context(true)

func _apply_context(immediate := false) -> void:
	body.collision_layer = layer_context.solid_bit
	depth_visuals.show_profile(layer_context.depth_profile, immediate)

func is_active_layer(layer_number: int) -> bool:
	return current_layer != 0 and layer_number == current_layer

func receive_orb(orb: MagicOrb) -> bool:
	var player := orb.player as PlayerController
	if has_orb or not accepts_orb or player == null or not is_active_layer(player.current_layer):
		return false
	has_orb = true
	indicator.color = Color("ffd66b")
	orb_placed.emit(self)
	return true

func remove_orb(_orb: MagicOrb) -> void:
	has_orb = false
	indicator.color = Color("85d8ea")
	orb_removed.emit(self)


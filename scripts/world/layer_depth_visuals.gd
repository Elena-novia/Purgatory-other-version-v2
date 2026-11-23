@tool
extends Node2D
class_name LayerDepthVisuals

signal appearance_changed

const DEFAULT_TRANSITION_DURATION := 0.20

@export_range(0.0, 1.0, 0.01, "suffix:s") var transition_duration := DEFAULT_TRANSITION_DURATION

var _profiles: Array[GameplayLayer] = []
var _local_profile: GameplayLayer
var _active_profile: GameplayLayer
var _depth_source: LayerDepthVisuals
var _tween: Tween

func _enter_tree() -> void:
	if is_instance_valid(_active_profile):
		_connect_profile()
		_refresh_depth()

func _exit_tree() -> void:
	_disconnect_profile()

func _ready() -> void:
	_local_profile = LayerContext.find_gameplay_layer(self)
	_profiles = LayerContext.find_shared_profiles(self)

## Independently managed objects use the shared profile for their logical layer.
func show_layer(layer_number: int, immediate := false) -> void:
	if not GameplayLayer.is_valid_layer(layer_number):
		return
	if _profiles.size() >= layer_number:
		show_profile(_profiles[layer_number - 1], immediate)
	elif is_instance_valid(_local_profile) and _local_profile.current_layer == layer_number:
		show_profile(_local_profile, immediate)

## A context supplies the exact section profile for inherited objects.
func show_profile(profile: GameplayLayer, immediate := false) -> void:
	if _active_profile != profile:
		_disconnect_profile()
		_active_profile = profile
		_connect_profile()
	_refresh_depth(immediate or profile == null)

func _connect_profile() -> void:
	if is_inside_tree() and is_instance_valid(_active_profile) and not _active_profile.depth_changed.is_connected(_refresh_depth):
		_active_profile.depth_changed.connect(_refresh_depth)

func _disconnect_profile() -> void:
	if is_instance_valid(_active_profile) and _active_profile.depth_changed.is_connected(_refresh_depth):
		_active_profile.depth_changed.disconnect(_refresh_depth)

func inherit_depth_from(source: LayerDepthVisuals) -> void:
	if is_instance_valid(_depth_source):
		_depth_source.appearance_changed.disconnect(_copy_source_depth)
	_depth_source = source
	if _depth_source == null:
		_refresh_depth()
		return
	_cancel_tween()
	_depth_source.appearance_changed.connect(_copy_source_depth)
	_copy_source_depth()

func _refresh_depth(immediate := false) -> void:
	if is_instance_valid(_depth_source):
		return
	var target_scale := Vector2.ONE
	var target_tint := Color.WHITE
	if is_instance_valid(_active_profile):
		target_scale *= _active_profile.depth_scale
		target_tint = _active_profile.depth_modulation()
	_cancel_tween()
	if immediate or Engine.is_editor_hint() or transition_duration <= 0.0 or not is_inside_tree():
		_apply_depth(target_scale, target_tint)
		return
	if scale.is_equal_approx(target_scale) and modulate.is_equal_approx(target_tint):
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_interpolate_depth.bind(scale, modulate, target_scale, target_tint),
		0.0, 1.0, transition_duration)

func _cancel_tween() -> void:
	if _tween:
		_tween.kill()

func _interpolate_depth(weight: float, start_scale: Vector2, start_tint: Color,
		target_scale: Vector2, target_tint: Color) -> void:
	_apply_depth(start_scale.lerp(target_scale, weight), start_tint.lerp(target_tint, weight))

func _copy_source_depth() -> void:
	_apply_depth(_depth_source.scale, _depth_source.modulate)

func _apply_depth(visual_scale: Vector2, tint: Color) -> void:
	scale = visual_scale
	modulate = tint
	appearance_changed.emit()

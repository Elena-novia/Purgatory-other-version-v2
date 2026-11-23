@tool
extends Node
class_name LayerContext

signal context_changed

enum Mode { INHERITED, FIXED, DYNAMIC }

const MAX_WRITES_PER_DRAIN := 16

class DynamicWrite:
	var layer: int
	var owner: WeakRef
	var owner_only: bool

	func _init(index: int, section: GameplayLayer, managed: bool) -> void:
		layer = index
		owner = weakref(section) if section != null else null
		owner_only = managed

## Inherited follows the nearest GameplayLayer. Fixed and Dynamic are independent of ancestry.
@export var mode: Mode = Mode.INHERITED:
	set(value):
		if _has_live_controller() and value != Mode.DYNAMIC:
			push_warning("The player LayerContext must stay in Dynamic mode.")
			return
		mode = value
		if mode != Mode.DYNAMIC:
			_runtime_owner = null
		_refresh_if_inside_tree()

## Zero leaves Fixed mode unresolved until an explicit layer is chosen.
@export_range(0, 3, 1) var fixed_layer := 0:
	set(value):
		fixed_layer = value
		_refresh_if_inside_tree()

## Optional initial value. A runtime assignment takes precedence.
@export_range(0, 3, 1) var initial_dynamic_layer := 0:
	set(value):
		if _has_live_controller():
			push_warning("The player's initial layer can only be configured before entering the tree.")
			return
		if is_inside_tree():
			if not GameplayLayer.is_valid_layer(value) or mode != Mode.DYNAMIC:
				return
			if not set_dynamic_layer(value):
				return
		initial_dynamic_layer = value

@export_group("Resolved Context")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var logical_layer: int:
	get:
		return _logical_layer

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var owner_path: String:
	get:
		if _publication_locked() and is_instance_valid(_gameplay_layer):
			return _published_owner_path
		var section := gameplay_layer
		if is_instance_valid(section) and section.is_inside_tree():
			return str(section.get_path())
		return ""

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var status: String:
	get:
		if logical_layer != 0:
			return "Resolved"
		match mode:
			Mode.FIXED:
				return "Set Fixed Layer to 1, 2 or 3."
			Mode.DYNAMIC:
				return "Set an initial layer or assign a layer during gameplay."
			_:
				return "No GameplayLayer ancestor. Place this object inside a layer or select Fixed."

var gameplay_layer: GameplayLayer:
	get:
		if _publication_locked():
			return _gameplay_layer if is_instance_valid(_gameplay_layer) else null
		if mode == Mode.DYNAMIC and not _is_available_owner(_gameplay_layer, _logical_layer):
			return null
		return _gameplay_layer

var solid_bit: int:
	get:
		return GameplayLayer.solid_collision_bit(logical_layer)

var ground_support_bit: int:
	get:
		return GameplayLayer.landing_surface_bit(logical_layer)

## The exact section in Inherited mode, or the shared logical profile in Fixed and Dynamic.
var depth_profile: GameplayLayer:
	get:
		return _depth_profile

## Configured index before the context enters the tree. The resolved index is logical_layer.
var configured_dynamic_layer: int:
	get:
		return _runtime_layer if _runtime_layer != 0 else initial_dynamic_layer

var _logical_layer := 0
var _gameplay_layer: GameplayLayer
var _depth_profile: GameplayLayer
var _runtime_layer := 0
var _runtime_owner: GameplayLayer
# Compare settled contexts across reparenting without retaining the nodes
# that just left the tree. An exit alone does not publish a new context.
var _published_context := PackedInt64Array([0, 0, 0])
var _published_owner_path := ""
var _publishing_context := false
var _refresh_pending := false
var _request_controller_layer: Callable
var _controller_is_publishing: Callable
var _confirm_controller_owner: Callable
var _pending_dynamic_writes: Array[DynamicWrite] = []
var _dynamic_drain_scheduled := false
var _draining_dynamic_writes := false

func is_publishing_context() -> bool:
	return _publishing_context

func _bind_dynamic_controller(request_layer: Callable, is_publishing: Callable, confirm_owner: Callable) -> void:
	_request_controller_layer = request_layer
	_controller_is_publishing = is_publishing
	_confirm_controller_owner = confirm_owner

func _has_live_controller() -> bool:
	return is_inside_tree() and _request_controller_layer.is_valid()

func _publication_locked() -> bool:
	return _publishing_context or (_controller_is_publishing.is_valid() and _controller_is_publishing.call())

func _enter_tree() -> void:
	_refresh()
	_schedule_dynamic_drain()

func _exit_tree() -> void:
	_bind_owner(null)
	_runtime_owner = null
	_depth_profile = null
	_published_owner_path = ""
	_logical_layer = 0

func _get_configuration_warnings() -> PackedStringArray:
	if logical_layer == 0:
		return PackedStringArray([status])
	return PackedStringArray()

## Standalone contexts accept an index and optional section. For a managed
## context, true on an index request means admitted for the controller's normal
## adjacency, ground and collision checks. An explicit section requires confirmed support.
func set_dynamic_layer(layer_number: int, physical_owner: GameplayLayer = null) -> bool:
	if mode != Mode.DYNAMIC or not GameplayLayer.is_valid_layer(layer_number):
		return false
	var managed := _has_live_controller()
	if managed:
		if physical_owner == null:
			return _request_controller_layer.call(layer_number)
		if layer_number != logical_layer:
			return false
		if not _is_available_owner(physical_owner, layer_number):
			# A departing section cannot replace or clear a subsequently confirmed owner.
			return true
		if not _confirm_controller_owner.call(physical_owner, layer_number):
			return false
	var section := physical_owner if _is_available_owner(physical_owner, layer_number) else null
	var has_older_write := not _pending_dynamic_writes.is_empty()
	_pending_dynamic_writes.append(DynamicWrite.new(layer_number, section, managed))
	if has_older_write or _publication_locked() or _draining_dynamic_writes:
		_schedule_dynamic_drain()
	else:
		_drain_dynamic_writes(1)
	return true

func _schedule_dynamic_drain() -> void:
	if _dynamic_drain_scheduled or not is_inside_tree() or _pending_dynamic_writes.is_empty():
		return
	_dynamic_drain_scheduled = true
	await get_tree().physics_frame
	_dynamic_drain_scheduled = false
	if is_inside_tree():
		_drain_dynamic_writes(MAX_WRITES_PER_DRAIN)

func _drain_dynamic_writes(limit: int) -> void:
	if _publication_locked() or _draining_dynamic_writes:
		_schedule_dynamic_drain()
		return
	_draining_dynamic_writes = true
	var was_in_tree := is_inside_tree()
	# Handle only the writes already admitted. Signal callbacks append to the tail.
	for index in range(mini(limit, _pending_dynamic_writes.size())):
		if was_in_tree and not is_inside_tree():
			break
		var write: DynamicWrite = _pending_dynamic_writes.pop_front()
		_apply_dynamic_write(write)
	_draining_dynamic_writes = false
	_schedule_dynamic_drain()

func _apply_dynamic_write(write: DynamicWrite) -> void:
	if mode != Mode.DYNAMIC:
		return
	var section := write.owner.get_ref() as GameplayLayer if write.owner != null else null
	if write.owner_only:
		if not _has_live_controller() or write.layer != logical_layer or not _is_available_owner(section, write.layer):
			return
		if not _confirm_controller_owner.call(section, write.layer):
			return
	_commit_dynamic_layer(write.layer, section)

## A coordinated commit has already prepared the actor's position and dependents.
func _commit_dynamic_layer(layer_number: int, physical_owner: GameplayLayer = null) -> void:
	_runtime_layer = layer_number
	_runtime_owner = null
	if _is_available_owner(physical_owner, layer_number):
		_runtime_owner = physical_owner
	if is_inside_tree():
		_publish_resolved_context()

func _is_available_owner(section: GameplayLayer, layer_number: int) -> bool:
	return is_instance_valid(section) and is_inside_tree() and section.is_available_as_owner() \
		and section.get_tree() == get_tree() and section.current_layer == layer_number

static func find_gameplay_layer(from: Node) -> GameplayLayer:
	var ancestor := from.get_parent()
	while ancestor != null:
		if ancestor is GameplayLayer:
			return ancestor
		ancestor = ancestor.get_parent()
	return null

static func find_shared_profiles(from: Node) -> Array[GameplayLayer]:
	var ancestor := from.get_parent()
	while ancestor != null:
		var provider_script := ancestor.get_script() as Script
		var can_call := not Engine.is_editor_hint() or (provider_script != null and provider_script.is_tool())
		if can_call and ancestor.has_method("get_depth_profiles"):
			return ancestor.get_depth_profiles()
		ancestor = ancestor.get_parent()
	return []

func _refresh_if_inside_tree() -> void:
	if is_inside_tree():
		_refresh()

func _refresh() -> void:
	if _publication_locked():
		if not _refresh_pending:
			_refresh_pending = true
			_refresh_after_publication()
		return
	_publish_resolved_context()

func _refresh_after_publication() -> void:
	await get_tree().physics_frame
	_refresh_pending = false
	_refresh_if_inside_tree()

func _publish_resolved_context() -> void:
	var owner_layer: GameplayLayer
	var layer_number := 0
	if mode == Mode.INHERITED:
		owner_layer = find_gameplay_layer(self)
		if owner_layer != null:
			layer_number = owner_layer.current_layer
	elif mode == Mode.FIXED:
		layer_number = fixed_layer
	else:
		layer_number = configured_dynamic_layer
		if _is_available_owner(_runtime_owner, layer_number):
			owner_layer = _runtime_owner
		else:
			_runtime_owner = null

	if not GameplayLayer.is_valid_layer(layer_number):
		layer_number = 0
	var profile := owner_layer if mode == Mode.INHERITED else null
	if profile == null and layer_number != 0:
		var profiles := find_shared_profiles(self)
		if profiles.size() >= layer_number:
			profile = profiles[layer_number - 1]

	var owner_id := owner_layer.get_instance_id() if is_instance_valid(owner_layer) else 0
	var profile_id := profile.get_instance_id() if is_instance_valid(profile) else 0
	var next_context := PackedInt64Array([layer_number, owner_id, profile_id])
	var changed := _published_context != next_context
	_bind_owner(owner_layer)
	_logical_layer = layer_number
	_depth_profile = profile
	_published_context = next_context
	_published_owner_path = str(owner_layer.get_path()) if is_instance_valid(owner_layer) else ""
	if Engine.is_editor_hint():
		update_configuration_warnings()
		notify_property_list_changed()
	if changed:
		var was_publishing := _publishing_context
		_publishing_context = true
		context_changed.emit()
		_publishing_context = was_publishing

func _bind_owner(next_owner: GameplayLayer) -> void:
	if _gameplay_layer == next_owner:
		return
	if is_instance_valid(_gameplay_layer):
		_gameplay_layer.logical_layer_changed.disconnect(_refresh)
		_gameplay_layer.tree_exiting.disconnect(_on_owner_exiting)
	_gameplay_layer = next_owner
	if _gameplay_layer != null:
		_gameplay_layer.logical_layer_changed.connect(_refresh)
		_gameplay_layer.tree_exiting.connect(_on_owner_exiting)

func _on_owner_exiting() -> void:
	if mode == Mode.DYNAMIC:
		_runtime_owner = null
		_refresh()

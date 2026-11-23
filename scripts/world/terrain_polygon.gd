@tool
extends CollisionPolygon2D

const LANDING_THICKNESS := 1.0

@export var supports_other_layers := false
@export var fill_color := Color.WHITE:
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color.TRANSPARENT:
	set(value):
		edge_color = value
		queue_redraw()
@export_range(0.0, 20.0, 0.5, "or_greater", "suffix:px") var edge_width := 8.0:
	set(value):
		edge_width = value
		queue_redraw()

var _landing_body: StaticBody2D
var _landing_polygon: PackedVector2Array
var _landing_disabled := false

func _ready() -> void:
	var layer := get_parent() as GameplayLayer
	if Engine.is_editor_hint() or not supports_other_layers or layer == null:
		set_physics_process(false)
		return
	_landing_body = StaticBody2D.new()
	_landing_body.name = "CrossLayerLanding"
	_landing_body.collision_layer = GameplayLayer.landing_surface_bit(layer.current_layer)
	_landing_body.collision_mask = 0
	_landing_body.input_pickable = false
	add_child(_landing_body, false, Node.INTERNAL_MODE_BACK)
	_update_landing_surfaces()

func _physics_process(_delta: float) -> void:
	_update_landing_surfaces()

func _update_landing_surfaces() -> void:
	var landing_disabled := disabled or not supports_other_layers
	if _landing_disabled != landing_disabled:
		_landing_disabled = landing_disabled
		for surface: CollisionShape2D in _landing_body.get_children():
			surface.disabled = landing_disabled
	var points := polygon
	if points == _landing_polygon:
		return
	_landing_polygon = points
	for surface in _landing_body.get_children():
		_landing_body.remove_child(surface)
		surface.queue_free()
	var edges := _upper_edges(_landing_polygon)
	for i in range(0, edges.size(), 2):
		var start := edges[i]
		var end := edges[i + 1]
		var slope := end - start
		# Steeper edges act as walls under the player's default floor angle.
		if absf(slope.y) > absf(slope.x):
			continue
		var tangent := slope.normalized() * signf(slope.x)
		var down := Vector2(-tangent.y, tangent.x)
		# Give Godot's one-way solver a top and bottom face. Keep the top
		# flush with the source edge so both collider types land at the same height.
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(slope.length(), LANDING_THICKNESS)
		var surface := CollisionShape2D.new()
		surface.shape = rectangle
		surface.position = (start + end) * 0.5 + down * LANDING_THICKNESS * 0.5
		surface.rotation = tangent.angle()
		surface.one_way_collision = true
		surface.disabled = landing_disabled
		_landing_body.add_child(surface)

func _draw() -> void:
	if disabled or polygon.size() < 3:
		return
	draw_colored_polygon(polygon, fill_color)
	if edge_color.a <= 0.0 or edge_width <= 0.0:
		return
	# Scale the decorative trim without moving the walkable edge.
	var layer := get_parent() as GameplayLayer
	var detail_scale := layer.depth_scale if layer != null else 1.0
	var trim_width := edge_width * detail_scale
	var edges := _upper_edges(polygon)
	for i in range(0, edges.size(), 2):
		var start := edges[i]
		var end := edges[i + 1]
		var tangent := (end - start).normalized()
		var up := Vector2(tangent.y, -tangent.x) * signf(tangent.x)
		# Keep the outside of the rim aligned. Centering both sides on a
		# snapped edge can make different thicknesses render the same.
		var offset := up * minf(edge_width - trim_width, trim_width) * 0.5
		draw_line(start + offset, end + offset, edge_color, trim_width)

func _upper_edges(points: PackedVector2Array) -> PackedVector2Array:
	var edges := PackedVector2Array()
	if points.size() < 3:
		return edges
	var upper_edge_direction := -1.0 if Geometry2D.is_polygon_clockwise(points) else 1.0
	for i in range(points.size()):
		var start := points[i]
		var end := points[(i + 1) % points.size()]
		if (end.x - start.x) * upper_edge_direction > 0.0:
			edges.append(start)
			edges.append(end)
	return edges

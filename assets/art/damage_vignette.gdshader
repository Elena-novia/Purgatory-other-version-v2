shader_type canvas_item;

void fragment() {
	vec2 edge_distance = min(UV, vec2(1.0) - UV);
	float distance_to_edge = min(edge_distance.x, edge_distance.y);
	float outline = 1.0 - smoothstep(0.015, 0.075, distance_to_edge);
	COLOR = vec4(COLOR.rgb, COLOR.a * outline);
}

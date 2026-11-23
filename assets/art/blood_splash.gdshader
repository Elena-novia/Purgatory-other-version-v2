shader_type canvas_item;

void fragment() {
	vec2 centered = UV - vec2(0.5, 0.5);
	float angle = atan(centered.y, centered.x);
	float radius = 0.24 + 0.035 * sin(angle * 7.0) + 0.025 * sin(angle * 13.0);
	float distance_from_center = length(centered);
	float splash = 1.0 - smoothstep(radius - 0.012, radius + 0.012, distance_from_center);
	vec2 droplets[5] = vec2[](vec2(0.24, 0.35), vec2(0.7, 0.28), vec2(0.28, 0.7), vec2(0.76, 0.68), vec2(0.52, 0.18));
	for (int i = 0; i < 5; i++) {
		float dot_mask = 1.0 - smoothstep(0.012, 0.025, distance(UV, droplets[i]));
		splash = max(splash, dot_mask);
	}
	COLOR = vec4(COLOR.rgb, COLOR.a * splash);
}

shader_type canvas_item;

uniform sampler2D depleted_texture : source_color, filter_linear;
uniform float health_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float sanity_ratio : hint_range(0.0, 1.0) = 1.0;

float full_share(float ratio, float horizontal_progress) {
	if (ratio <= 0.0) {
		return 0.0;
	}
	if (ratio >= 1.0) {
		return 1.0;
	}
	return 1.0 - smoothstep(ratio - 0.0015, ratio + 0.0015, horizontal_progress);
}

void fragment() {
	vec4 full_art = texture(TEXTURE, UV);
	vec4 depleted_art = texture(depleted_texture, UV);
	float full_visibility = 1.0;

	// The two source PNGs differ in this flower strip only for sanity.
	const vec2 flowers_min = vec2(404.0 / 1024.0, 77.0 / 256.0);
	const vec2 flowers_max = vec2(760.0 / 1024.0, 155.0 / 256.0);
	if (UV.x >= flowers_min.x && UV.x <= flowers_max.x && UV.y >= flowers_min.y && UV.y <= flowers_max.y) {
		float progress = (UV.x - flowers_min.x) / (flowers_max.x - flowers_min.x);
		full_visibility = full_share(sanity_ratio, progress);
	}

	// The lower health bar has its own independent depleted-to-full reveal.
	const vec2 health_min = vec2(424.0 / 1024.0, 177.0 / 256.0);
	const vec2 health_max = vec2(844.0 / 1024.0, 206.0 / 256.0);
	if (UV.x >= health_min.x && UV.x <= health_max.x && UV.y >= health_min.y && UV.y <= health_max.y) {
		float progress = (UV.x - health_min.x) / (health_max.x - health_min.x);
		full_visibility = full_share(health_ratio, progress);
	}

	COLOR = mix(depleted_art, full_art, full_visibility);
}

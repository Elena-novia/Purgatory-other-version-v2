shader_type canvas_item;

uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.56, 0.82);
uniform float pixel_count : hint_range(4.0, 32.0, 1.0) = 12.0;

void fragment() {
	vec2 pixel_uv = (floor(UV * pixel_count) + vec2(0.5)) / pixel_count;
	vec2 centered = (pixel_uv - vec2(0.5)) * 2.0;
	float radius = length(centered);
	float glow = exp(-radius * radius * 4.0);
	float core = exp(-radius * radius * 28.0) * 0.45;
	float alpha = max(glow, core) * glow_color.a * fade;
	COLOR = vec4(glow_color.rgb, alpha);
}

shader_type canvas_item;

void fragment() {
	vec2 edge = abs(UV - vec2(0.5, 0.5)) * 2.0;
	float amount = smoothstep(0.45, 1.35, length(edge));
	COLOR = vec4(COLOR.rgb, COLOR.a * amount);
}

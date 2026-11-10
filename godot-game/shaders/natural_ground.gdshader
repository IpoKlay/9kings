shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ground_source : source_color, filter_nearest, repeat_enable;

vec3 sample_ground(vec2 uv) {
	return texture(ground_source, uv).rgb;
}

void fragment() {
	// Preserve the full composition, but render grain on the battlefield's 2-unit pixel grid.
	vec2 uv = (floor(UV * 2048.0) + 0.5) / 2048.0;
	vec2 size = vec2(textureSize(ground_source, 0));
	vec2 pixel = uv * size - 0.5;
	vec2 cell = (floor(pixel) + 0.5) / size;
	vec2 blend = fract(pixel);
	vec2 dx = vec2(1.0 / size.x, 0.0);
	vec2 dy = vec2(0.0, 1.0 / size.y);
	vec3 base = mix(mix(sample_ground(cell), sample_ground(cell + dx), blend.x),
		mix(sample_ground(cell + dy), sample_ground(cell + dx + dy), blend.x), blend.y);
	// Retain only fine source detail here, so the recognizable grass patches never repeat.
	vec2 grain_uv = fract(uv * 4.0 + vec2(0.193, 0.367));
	vec3 local_mean = (sample_ground(grain_uv + dx * 2.0) + sample_ground(grain_uv - dx * 2.0)
		+ sample_ground(grain_uv + dy * 2.0) + sample_ground(grain_uv - dy * 2.0)) * 0.25;
	vec3 ground = clamp(base + (sample_ground(grain_uv) - local_mean) * 0.55, vec3(0.0), vec3(1.0));
	COLOR = vec4(floor(ground * 63.0 + 0.5) / 63.0, 1.0);
}

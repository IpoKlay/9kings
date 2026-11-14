shader_type canvas_item;
render_mode unshaded;

uniform sampler2D water_mask : filter_nearest, repeat_disable;
uniform vec4 west : source_color;
uniform vec4 north : source_color;
uniform vec4 south : source_color;
uniform vec4 east : source_color;

// Blend only near territory boundaries. The atlas's existing shade and water pixels stay legible.
void fragment() {
	vec4 terrain = texture(TEXTURE, UV);
	vec2 point = floor(UV / TEXTURE_PIXEL_SIZE) * TEXTURE_PIXEL_SIZE;
	float w = distance(point, vec2(0.17, 0.36));
	float n = distance(point, vec2(0.52, 0.12));
	float s = distance(point, vec2(0.375, 0.70));
	float e = distance(point, vec2(0.83, 0.45));
	float nearest = min(min(w, n), min(s, e));
	vec4 weights = 1.0 - smoothstep(vec4(0.0), vec4(0.021), vec4(w, n, s, e) - nearest);
	vec3 hue = (west.rgb * weights.x + north.rgb * weights.y + south.rgb * weights.z + east.rgb * weights.w)
		/ dot(weights, vec4(1.0));
	float value = dot(terrain.rgb, vec3(0.299, 0.587, 0.114));
	float hue_value = dot(hue, vec3(0.299, 0.587, 0.114));
	vec3 tinted = clamp(hue * (0.32 + 0.83 * value / max(hue_value, 0.1)), 0.0, 1.0);
	float land = 1.0 - texture(water_mask, UV).g;
	COLOR = vec4(mix(terrain.rgb, tinted, land * 0.80), terrain.a);
}
